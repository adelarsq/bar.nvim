local api = vim.api
local uv = vim.uv

local M = {}

------------------------------------------------------------------------
-- Colors & Configs
------------------------------------------------------------------------

local function set_default(var, value)
    if vim.g[var] == nil then
        vim.g[var] = value
    end
end

set_default('bar_blank', ' ')
set_default('bar_none', 'none')
set_default('bar_red', '#ff5349')
set_default('bar_orange', '#fe6e00')
set_default('bar_green', '#4CBB17')
set_default('bar_turquoise', '#3FE0D0')
set_default('bar_aqua', '#18ffe0')
set_default('bar_blue', '#31baff')
set_default('bar_purple', '#9d8cff')
set_default('bar_green_light', '#D5F5E3')
set_default('bar_purple_light', '#E8DAEF')
set_default('bar_blue_light', '#D6EAF8')
set_default('bar_red_light', '#FADBD8')
set_default('bar_black', '#282c34')
set_default('bar_black2', '#4d4d4d')
set_default('bar_gray', '#cccccc')
set_default('bar_gray2', '#e6e6e6')
set_default('bar_white', '#ffffff')

------------------------------------------------------------------------
-- Icons
------------------------------------------------------------------------

set_default('bar_iconCwd', '🏡')
set_default('bar_lsp_running', '🔥')
set_default('bar_dap_running', '🐞')
set_default('bar_symbol_error', '💥')
set_default('bar_symbol_warning', '💩')
set_default('bar_symbol_information', '⚠️')
set_default('bar_symbol_hint', '💡')
set_default('bar_symbol_canceled', '⛔')
set_default('bar_symbol_failure', '💥')
set_default('bar_symbol_success', '✅')
set_default('bar_symbol_running', '🚀')

local excluded_buftypes = { 'nofile', 'prompt', 'terminal' }
local excluded_filetypes = { 'dap-view', 'dap-repl', 'help', 'qf' }

------------------------------------------------------------------------
-- Performance: Cache & Debounce
------------------------------------------------------------------------

local cache = {
    git = { value = '', expiry = 0 },
    lsp = { bufnr = nil, value = '', diagnostics = nil, expiry = 0 },
    overseer = { value = '', expiry = 0 },
    mode_colors = {},
}

local CACHE_TTL = {
    git = 3000,      -- 3s - Git
    lsp = 500,       -- 500ms - LSP
    overseer = 1000, -- 1s - tarefas
}

local debounce_timer = nil
local last_render_hash = nil

local function is_cache_valid(key)
    return cache[key].expiry and uv.now() < cache[key].expiry
end

local function set_cache(key, value, extra)
    cache[key].value = value
    cache[key].expiry = uv.now() + CACHE_TTL[key]
    if extra then
        for k, v in pairs(extra) do
            cache[key][k] = v
        end
    end
end

local function debounced_update(delay, callback)
    if debounce_timer and not debounce_timer:is_closing() then
        debounce_timer:stop()
    end
    debounce_timer = uv.new_timer()
    debounce_timer:start(delay, 0, vim.schedule_wrap(callback))
end

-- Dirty checking
local function get_render_signature(bufnr)
    local bo = vim.bo[bufnr]
    local git_head = vim.b[bufnr].gitsigns_head or ''
    local git_stats = vim.b[bufnr].gitsigns_status_dict
    local git_sig = ''
    if git_stats then
        git_sig = (git_stats.added or 0) .. (git_stats.removed or 0)
    end

    local mode = api.nvim_get_mode().mode
    local recording = vim.fn.reg_recording()

    return table.concat({
        bufnr,
        bo.modified and 'M' or '_',
        bo.filetype,
        git_head,
        git_sig,
        mode,
        recording,
    }, ':')
end

------------------------------------------------------------------------
-- Utils
------------------------------------------------------------------------

local function is_suffix(suffix, str)
    local suffix_len = #suffix
    if suffix_len > #str then return false end
    return string.sub(str, -suffix_len) == suffix
end

local function get_relative_path(bufnr, filetype)
    local file_dir = vim.fn.fnamemodify(api.nvim_buf_get_name(bufnr), ':p:h')
    file_dir = vim.fn.substitute(file_dir, '\\', '/', 'g')
    if filetype == 'oil' then file_dir = file_dir:sub(7) end

    local cwd = uv.cwd()
    if not cwd then return '' end
    cwd = vim.fn.substitute(cwd, '\\', '/', 'g')

    if file_dir:sub(-1) ~= '/' then file_dir = file_dir .. '/' end
    if cwd:sub(-1) ~= '/' then cwd = cwd .. '/' end

    return is_suffix(cwd, file_dir) and file_dir:sub(#cwd + 1) or file_dir
end

------------------------------------------------------------------------
-- Features (Lazy Loading)
------------------------------------------------------------------------

local ts_available, ts_status = pcall(require, 'nvim-treesitter.statusline')
local dap_available, dap = pcall(require, 'dap')
local dapui_available, dapui_controls = pcall(require, 'dapui.controls')
local overseer_available = pcall(require, 'overseer')

local TsStatus = function()
    if not (vim.g.bar_enable_plugins and vim.g.loaded_nvim_treesitter and ts_available) then
        return ''
    end
    return ts_status.statusline()
end

local DebugStatus = function()
    if not (vim.g.bar_enable_plugins and dap_available and dap.session()) then
        return ''
    end
    return dap.status()
end

local DebugControls = function()
    if not (vim.g.bar_enable_plugins and dap_available and dapui_available and DebugStatus() ~= '') then
        return ''
    end
    return dapui_controls.controls()
end

------------------------------------------------------------------------
-- Plugins: Overseer
------------------------------------------------------------------------

local TasksStatus = function()
    if not (vim.g.bar_enable_plugin_overseer and overseer_available) then
        return ''
    end

    if is_cache_valid('overseer') then
        return cache.overseer.value
    end

    local task_list = require("overseer.task_list")
    local util = require("overseer.util")

    local tasks = task_list.list_tasks({ unique = true })
    local by_status = util.tbl_group_by(tasks, "status")

    local symbols = {
        CANCELED = vim.g.bar_symbol_canceled,
        FAILURE = vim.g.bar_symbol_failure,
        SUCCESS = vim.g.bar_symbol_success,
        RUNNING = vim.g.bar_symbol_running,
    }

    local parts = {}
    for _, status_key in ipairs({ "CANCELED", "FAILURE", "SUCCESS", "RUNNING" }) do
        if by_status[status_key] then
            table.insert(parts, symbols[status_key] .. #by_status[status_key])
        end
    end

    local result = table.concat(parts, '')
    set_cache('overseer', result)
    return result
end

------------------------------------------------------------------------
-- StatusLine Helpers
------------------------------------------------------------------------

local current_mode = setmetatable({
    [''] = 'V·Block',
    [''] = 'S·Block',
    ['n'] = 'N',
    ['no'] = 'O',
    ['nov'] = 'O',
    ['noV'] = 'O',
    ['niI'] = 'N',
    ['niR'] = 'N',
    ['niV'] = 'N',
    ['nt'] = 'N',
    ['v'] = 'V',
    ['vs'] = 'V',
    ['V'] = 'V',
    ['Vs'] = 'V',
    ['s'] = 'S',
    ['S'] = 'S',
    [''] = 'S',
    ['i'] = 'I',
    ['ic'] = 'I',
    ['ix'] = 'I',
    ['R'] = 'R',
    ['Rc'] = 'R',
    ['Rx'] = 'R',
    ['Rv'] = 'R',
    ['Rvc'] = 'R',
    ['Rvx'] = 'R',
    ['c'] = 'C',
    ['cv'] = 'EX',
    ['ce'] = 'EX',
    ['r'] = 'R',
    ['rm'] = 'M',
    ['r?'] = 'C',
    ['!'] = 'S',
    ['t'] = 'T',
}, {})

local function RedrawColors(mode)
    if cache.mode_colors[mode] then return end

    local colors = {
        n = { vim.g.bar_blue, vim.g.bar_white },
        i = { vim.g.bar_green, vim.g.bar_white },
        v = { vim.g.bar_purple, vim.g.bar_white },
        V = { vim.g.bar_purple, vim.g.bar_white },
        [''] = { vim.g.bar_purple, vim.g.bar_white },
        c = { vim.g.bar_orange, vim.g.bar_white },
        Rv = { vim.g.bar_red, vim.g.bar_white },
        t = { vim.g.bar_turquoise, vim.g.bar_white },
    }

    local cfg = colors[mode]
    if cfg then
        api.nvim_command(string.format('hi BarMode guibg=%s guifg=%s', cfg[1], cfg[2]))
        cache.mode_colors[mode] = true
    end
end

local function count_diagnostics(bufnr)
    local counts = { [1] = 0, [2] = 0, [3] = 0, [4] = 0 }
    for _, d in ipairs(vim.diagnostic.get(bufnr)) do
        counts[d.severity] = (counts[d.severity] or 0) + 1
    end
    return counts
end

------------------------------------------------------------------------
-- Git Status
------------------------------------------------------------------------

local GitStatus = function()
    if is_cache_valid('git') then
        return cache.git.value
    end

    if vim.b.gitsigns_status_dict then
        local d = vim.b.gitsigns_status_dict
        local parts = { d.head or '' }
        if d.added and d.added > 0 then table.insert(parts, '↑' .. d.added) end
        if d.removed and d.removed > 0 then table.insert(parts, '↓' .. d.removed) end
        if d.changed and d.changed > 0 then table.insert(parts, '~' .. d.changed) end

        local result = table.concat(parts, ' ')
        set_cache('git', result)
        return result
    end

    local function safe_popen(cmd)
        local handle = io.popen(cmd)
        if not handle then return nil end
        local result = handle:read('*a'):gsub('%s+', '')
        handle:close()
        return result
    end

    local is_git = safe_popen(vim.fn.has('win32') == 1
        and 'git rev-parse --is-inside-work-tree 2>nul'
        or 'git rev-parse --is-inside-work-tree 2>/dev/null')

    if is_git ~= 'true' then
        set_cache('git', '', { expiry = uv.now() + 10000 })
        return ''
    end

    local branch = safe_popen(vim.fn.has('win32') == 1
        and 'git branch --show-current 2>nul'
        or 'git branch --show-current 2>/dev/null')

    if not branch or branch == '' then
        set_cache('git', '', { expiry = uv.now() + 5000 })
        return ''
    end

    local result = branch
    set_cache('git', result)
    return result
end

------------------------------------------------------------------------
-- LSP Status
------------------------------------------------------------------------

local ClientsLsp = function(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()

    if cache.lsp.bufnr == bufnr and is_cache_valid('lsp') then
        return cache.lsp.value
    end

    local clients = vim.lsp.get_clients({ bufnr = bufnr })
    if not next(clients) then
        set_cache('lsp', '', { bufnr = bufnr })
        return ''
    end

    local result = vim.g.bar_disable_lsp_names
        and vim.g.bar_lsp_running
        or (vim.g.bar_lsp_running .. ' ' .. table.concat(
            vim.tbl_map(function(c) return c.name end, clients), '|'))

    set_cache('lsp', result, { bufnr = bufnr })
    return result
end

local BuiltinLsp = function(bufnr)
    if vim.g.bar_disable_diagnostics then return "%#Normal#" end

    local counts = count_diagnostics(bufnr)
    local parts = {}

    if counts[1] > 0 then table.insert(parts, vim.g.bar_symbol_error .. counts[1]) end
    if counts[2] > 0 then table.insert(parts, vim.g.bar_symbol_warning .. counts[2]) end
    if counts[3] > 0 then table.insert(parts, vim.g.bar_symbol_information .. counts[3]) end
    if counts[4] > 0 then table.insert(parts, vim.g.bar_symbol_hint .. counts[4]) end

    return "%#Normal#" .. (next(parts) and ' ' .. table.concat(parts, ' ') or '') .. "%#Normal#"
end

local LspStatus = function(bufnr)
    return ClientsLsp(bufnr) .. BuiltinLsp(bufnr)
end

local DapRunning = function()
    return (dap_available and dap.session()) and vim.g.bar_dap_running or ''
end

------------------------------------------------------------------------
-- StatusLine Builders
------------------------------------------------------------------------

local ShowMacroRecording = function()
    local reg = vim.fn.reg_recording()
    return reg == '' and '' or (' Recording @' .. reg .. ' ')
end

function M.activeLine(bufnr)
    local bo = vim.bo[bufnr]
    local mode = api.nvim_get_mode().mode

    RedrawColors(mode)

    local blank = vim.g.bar_blank or ' '

    local sl = "%#Normal%#"
    sl = sl .. "%#BarMode#" .. (current_mode[mode] or '?') .. "%#Normal%#" .. blank

    -- Git/VCS
    if vim.g.loaded_signify then
        local stats = api.nvim_call_function('sy#repo#get_stats', {})
        if stats[1] > -1 then
            sl = sl .. "%#BarVCSAdd#+" .. stats[1] .. "%#BarVCSDelete#-" .. stats[2] .. "%#BarVCSChange#~" .. stats[3]
            local vcs = api.nvim_call_function('VcsName', {})
            sl = sl .. blank .. vcs
        end
    end

    if vim.b[bufnr].gitsigns_head then
        sl = sl .. (vim.b.gitsigns_status or '') .. ' ' .. GitStatus()
    end

    if bo.modified then sl = sl .. '+' end

    sl = sl .. ShowMacroRecording() .. "%="
    sl = sl .. DebugStatus() .. "%=%#Normal%#"

    if vim.g.bar_enable_plugin_overseer then
        sl = sl .. TasksStatus()
    end

    if vim.g.asyncrun_status then
        sl = sl .. vim.g.asyncrun_status
    end

    sl = sl .. LspStatus(bufnr) .. DapRunning()
    sl = sl .. "%#Normal# " .. bo.filetype .. blank
    sl = sl .. "%#Normal#%{&fileencoding} " .. blank
    sl = sl .. "%l:%c"

    return sl
end

function M.inActiveLine(bufnr)
    return "%#Normal# %#Normal# %f%=%#Normal# "
end

function M.UpdateInactiveWindows()
    if vim.bo.buftype == 'popup' then return end
    local total_wins = vim.fn.winnr('$')
    for n = 1, total_wins do
        if api.nvim_win_is_valid(n) then
            local bufid = vim.fn.winbufnr(n)
            api.nvim_win_set_option(n, 'statusline', M.inActiveLine(bufid))
        end
    end
end

------------------------------------------------------------------------
-- TabLine & Winbar
------------------------------------------------------------------------

local abbreviate_path = function(path)
    if not path then return '' end
    local last = string.match(path, "[^/\\]+$") or ''
    local prev = string.match(path, "^.+[\\/]") or ''
    local abbr = prev:gsub("[^/\\]+", function(f) return f:sub(1, 1) end)
    return abbr .. last
end

function M.tabLine()
    local current = api.nvim_get_current_tabpage()
    local parts = {}

    for _, tab in ipairs(api.nvim_list_tabpages()) do
        local num = api.nvim_tabpage_get_number(tab)
        local hl = (tab == current) and "%#BarMode#" or "%#Normal#"
        table.insert(parts, hl .. num .. "%#Normal# ")
    end

    local blank = vim.g.bar_blank or ' '
    return "%#Normal# " .. table.concat(parts, '') .. "%=" ..
        blank .. DebugControls() .. blank ..
        "%#Normal# " .. vim.g.bar_iconCwd .. blank .. abbreviate_path(uv.cwd())
end

function M.winbar(bufnr)
    local bo = vim.bo[bufnr]
    local filename = vim.fn.fnamemodify(api.nvim_buf_get_name(bufnr), ':t')
    if filename == '' then filename = '[No Name]' end

    local file_dir = get_relative_path(bufnr, bo.filetype)
    local abbr = abbreviate_path(file_dir .. filename)

    local diag_parts = {}
    for sev, icon in pairs({ error = 'e', warn = '', info = '', hint = '' }) do
        local n = #vim.diagnostic.get(bufnr, { severity = vim.diagnostic.severity[sev:upper()] })
        if n > 0 then
            table.insert(diag_parts, "%#DiagnosticSign" .. sev .. "#" .. icon .. n)
        end
    end

    local function get_scrollbar()
        for _, win in ipairs(api.nvim_list_wins()) do
            if api.nvim_win_get_buf(win) == bufnr then
                local cur = api.nvim_win_get_cursor(win)[1]
                local total = api.nvim_buf_line_count(bufnr)
                if total == 0 then return '' end
                local chars = { '▔', '🮂', '🮃', '▀', '▬', '▄', '▃', '▂', '▁' }
                local i = math.floor((cur - 1) / total * #chars) + 1
                return string.rep(chars[i], 2)
            end
        end
        return ''
    end

    return '%#Normal#' .. abbr .. ' ' .. table.concat(diag_parts, ' ') .. ' %#Normal#' .. get_scrollbar()
end

------------------------------------------------------------------------
-- Setup
------------------------------------------------------------------------

function M.setup(opts)
    opts = opts or {}

    if vim.o.updatetime > 100 then
        vim.o.updatetime = 100
    end

    local bar_augroup = api.nvim_create_augroup('BarPlugin', { clear = true })

    local function update_bar()
        local bufnr = api.nvim_get_current_buf()
        local winid = api.nvim_get_current_win()
        local bo = vim.bo[bufnr]

        local sig = get_render_signature(bufnr)

        if sig == last_render_hash then return end
        last_render_hash = sig

        if vim.o.laststatus ~= 0 then
            vim.wo[winid].statusline = M.activeLine(bufnr)
            if vim.o.laststatus < 3 then
                M.UpdateInactiveWindows()
            end
        end

        if vim.g.bar_disable_tabline ~= 0 then
            vim.o.tabline = M.tabLine()
        end

        if not vim.g.bar_disable_winbar and
            not vim.tbl_contains(excluded_buftypes, bo.buftype) and
            not vim.tbl_contains(excluded_filetypes, bo.filetype) then
            vim.wo[winid].winbar = M.winbar(bufnr)
        end
    end

    api.nvim_create_autocmd({ 'RecordingEnter', 'RecordingLeave', 'ModeChanged' }, {
        group = bar_augroup,
        callback = function()
            debounced_update(10, update_bar)
        end,
    })

    api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
        group = bar_augroup,
        callback = function()
            vim.schedule(update_bar)
        end,
    })

    api.nvim_create_autocmd({ 'BufEnter', 'WinEnter', 'TabEnter', 'VimResized', 'BufWritePost' }, {
        group = bar_augroup,
        callback = function()
            last_render_hash = nil
            update_bar()
        end,
    })

    api.nvim_create_autocmd('BufLeave', {
        group = bar_augroup,
        callback = function()
            cache.lsp.bufnr = nil
        end,
    })

    vim.schedule(update_bar)
end

return M
