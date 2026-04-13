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
    lsp_progress = { value = '', expiry = 0, spinner_index = 0 },
    overseer = { value = '', expiry = 0 },
    mode_colors = {},
}

-- Cache para nomes customizados das tabs
local tab_names = {}

local CACHE_TTL = {
    git = 3000,      -- 3s - Git
    file_git = 1000, -- 1s - Git status do arquivo
    lsp = 500,       -- 500ms - LSP
    lsp_progress = 200, -- 200ms - Progresso (para animação suave)
    overseer = 1000, -- 1s - tarefas
}

local debounce_timer = nil
local spinner_timer = nil
local last_render_hash = nil

local function is_cache_valid(cache_entry)
    if not cache_entry then
        return false
    end
    if not cache_entry.expiry then
        return false
    end
    return uv.now() < cache_entry.expiry
end

local function set_cache(cache_entry, value, extra)
    if not cache_entry then return end
    cache_entry.value = value

    local ttl_key = (extra and extra.ttl_key) or 'git'
    local ttl = CACHE_TTL[ttl_key] or CACHE_TTL.git

    cache_entry.expiry = uv.now() + ttl

    if extra then
        for k, v in pairs(extra) do
            if k ~= 'ttl_key' then
                cache_entry[k] = v
            end
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
    local git_sig = ''

    -- Verifica status git via comando nativo
    local git_dir = uv.cwd() .. '/.git'
    if uv.fs_stat(git_dir) then
        local handle = io.popen('git status --porcelain 2>/dev/null')
        if handle then
            local status = handle:read('*a')
            handle:close()
            git_sig = #status
        end
    end

    local mode = api.nvim_get_mode().mode
    local recording = vim.fn.reg_recording()

    return table.concat({
        bufnr,
        bo.modified and 'M' or '_',
        bo.filetype,
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

    if filetype == 'oil' and type(file_dir) == 'string' then
        file_dir = file_dir:sub(7)
    end

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

local dap_available, dap = pcall(require, 'dap')
local dapui_available, dapui_controls = pcall(require, 'dapui.controls')
local overseer_available = pcall(require, 'overseer')

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

    if is_cache_valid(cache.overseer) then
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
    set_cache(cache.overseer, result, { ttl_key = 'overseer' })
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
    local colors = {
        n = { vim.g.bar_blue, vim.g.bar_white },
        i = { vim.g.bar_green, vim.g.bar_white },
        v = { vim.g.bar_purple, vim.g.bar_white },
        V = { vim.g.bar_purple, vim.g.bar_white },
        [''] = { vim.g.bar_purple, vim.g.bar_white },
        c = { vim.g.bar_orange, vim.g.bar_white },
        R = { vim.g.bar_red, vim.g.bar_white },
        t = { vim.g.bar_turquoise, vim.g.bar_white },
    }

    local cfg = colors[mode] or colors.n

    api.nvim_set_hl(0, 'BarMode', {
        bg = cfg[1],
        fg = cfg[2],
        bold = true,
    })
end

local function count_diagnostics(bufnr)
    local counts = { [1] = 0, [2] = 0, [3] = 0, [4] = 0 }
    for _, d in ipairs(vim.diagnostic.get(bufnr)) do
        counts[d.severity] = (counts[d.severity] or 0) + 1
    end
    return counts
end

------------------------------------------------------------------------
-- Git Status (Nativo - sem plugins)
------------------------------------------------------------------------

local function exec_git_command(cmd)
    local handle = io.popen(cmd)
    if not handle then return nil end
    local result = handle:read('*a'):gsub('%s+$', '')
    handle:close()
    return result
end

-- Obtém o status do branch (commits ahead/behind)
local function get_branch_status()
    local branch = exec_git_command('git branch --show-current 2>/dev/null')
    if not branch or branch == '' then
        return nil, nil, nil
    end

    -- Verifica se tem upstream configurado
    local upstream = exec_git_command('git rev-parse --abbrev-ref @{upstream} 2>/dev/null')
    if not upstream or upstream == '' then
        return branch, 0, 0
    end

    -- Conta commits ahead e behind
    local ahead = exec_git_command('git rev-list --count @{upstream}..HEAD 2>/dev/null')
    local behind = exec_git_command('git rev-list --count HEAD..@{upstream} 2>/dev/null')

    local ahead_count = tonumber(ahead) or 0
    local behind_count = tonumber(behind) or 0

    return branch, ahead_count, behind_count
end

-- Obtém o status do arquivo atual (linhas alteradas)
local function get_file_git_status(filepath)
    if not filepath or filepath == '' then
        return 0, 0, 0
    end

    -- Obtém diff do arquivo
    local diff = exec_git_command('git diff --numstat ' .. vim.fn.shellescape(filepath) .. ' 2>/dev/null')
    local added, removed = 0, 0

    if diff and diff ~= '' then
        -- Parse do numstat: "added\tremoved\tfilename"
        local num_added, num_removed = diff:match('^(%d+)%s+(%d+)')
        added = tonumber(num_added) or 0
        removed = tonumber(num_removed) or 0
    end

    -- Obtém diff de arquivos unstaged
    local staged_diff = exec_git_command('git diff --cached --numstat ' .. vim.fn.shellescape(filepath) .. ' 2>/dev/null')
    local staged_added, staged_removed = 0, 0

    if staged_diff and staged_diff ~= '' then
        local num_added, num_removed = staged_diff:match('^(%d+)%s+(%d+)')
        staged_added = tonumber(num_added) or 0
        staged_removed = tonumber(num_removed) or 0
    end

    -- Total de alterações
    local total_added = added + staged_added
    local total_removed = removed + staged_removed
    local total_changed = total_added + total_removed

    return total_changed, total_added, total_removed
end

local GitStatus = function()
    if is_cache_valid(cache.git) then
        return cache.git.value
    end

    -- Verifica se está em um repositório git
    local is_git = exec_git_command('git rev-parse --is-inside-work-tree 2>/dev/null')
    if is_git ~= 'true' then
        set_cache(cache.git, '', { ttl_key = 'git', expiry = uv.now() + 10000 })
        return ''
    end

    -- Obtém status do branch
    local branch, ahead, behind = get_branch_status()
    if not branch or branch == '' then
        -- Tenta obter o commit hash se estiver em detached HEAD
        branch = exec_git_command('git rev-parse --short HEAD 2>/dev/null')
        if not branch or branch == '' then
            set_cache(cache.git, '', { ttl_key = 'git', expiry = uv.now() + 5000 })
            return ''
        end
        ahead, behind = 0, 0
    end

    -- Constrói o resultado
    local parts = { branch }

    -- Adiciona indicadores de ahead/behind
    if ahead > 0 then
        table.insert(parts, '↑' .. ahead)
    end
    if behind > 0 then
        table.insert(parts, '↓' .. behind)
    end

    local result = table.concat(parts, ' ')
    set_cache(cache.git, result, { ttl_key = 'git' })
    return result
end

-- Status específico do arquivo atual
local FileGitStatus = function(bufnr)
    local filepath = api.nvim_buf_get_name(bufnr)
    if not filepath or filepath == '' then
        return ''
    end

    -- Cache específico para o arquivo
    local cache_key = 'file_git_' .. bufnr
    if not cache[cache_key] then
        cache[cache_key] = { value = '', expiry = 0 }
    end

    if is_cache_valid(cache[cache_key]) then
        return cache[cache_key].value
    end

    -- Verifica se está em um repositório git
    local is_git = exec_git_command('git rev-parse --is-inside-work-tree 2>/dev/null')
    if is_git ~= 'true' then
        set_cache(cache[cache_key], '', { ttl_key = 'file_git', expiry = uv.now() + 10000 })
        return ''
    end

    local changed, added, removed = get_file_git_status(filepath)

    if changed == 0 then
        set_cache(cache[cache_key], '', { ttl_key = 'file_git' })
        return ''
    end

    -- Formato: ~C+A-C (C = total de alterações, A = adicionadas, R = removidas)
    local result = string.format('~%d+%d-%d', changed, added, removed)
    set_cache(cache[cache_key], result, { ttl_key = 'file_git' })
    return result
end

------------------------------------------------------------------------
-- LSP Status & Progress
------------------------------------------------------------------------

------------------------------------------------------------------------
-- LSP Status & Progress
------------------------------------------------------------------------

-- Spinner characters para animação
local SPINNER_CHARS = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }
local LSP_DONE_ICON = '✓'

-- Estado para progresso LSP via eventos
local lsp_progress_state = {
    active = false,
    message = nil,
    client_name = nil,
    percentage = nil,
}

-- Estado para manter o ícone de done
local lsp_done_state = {
    active = false,
    client_name = nil,
    expiry = 0,
}

local function get_lsp_progress()
    -- Mantém o ícone de done se ainda estiver no tempo
    if lsp_done_state.active then
        if uv.now() < lsp_done_state.expiry then
            return LSP_DONE_ICON .. (lsp_done_state.client_name and ' ' .. lsp_done_state.client_name or '')
        else
            lsp_done_state.active = false
        end
    end

    -- Se não há progresso ativo, retorna vazio
    if not lsp_progress_state.active then
        return ''
    end

    -- Atualiza índice do spinner
    cache.lsp_progress.spinner_index = (cache.lsp_progress.spinner_index % #SPINNER_CHARS) + 1
    local spinner = SPINNER_CHARS[cache.lsp_progress.spinner_index]

    local msg = lsp_progress_state.message
    local percentage = lsp_progress_state.percentage

    -- Se tem porcentagem, mostra
    if percentage then
        if percentage >= 100 then
            -- Progresso completo - ativa done state
            lsp_done_state.active = true
            lsp_done_state.client_name = lsp_progress_state.client_name
            lsp_done_state.expiry = uv.now() + 3000
            lsp_progress_state.active = false
            return LSP_DONE_ICON .. (lsp_progress_state.client_name and ' ' .. lsp_progress_state.client_name or '')
        end
        msg = (msg and msg ~= '') and msg or (percentage .. '%%')
    end

    -- Se não houver mensagem, mostra só o spinner
    if not msg or msg == '' then
        return spinner
    end

    -- Remove caracteres de controle e limpa a mensagem
    msg = msg:gsub('%%', '%%%%'):gsub('\n', ' '):gsub('\r', '')

    -- Trunca mensagem se for muito longa
    if #msg > 20 then
        msg = msg:sub(1, 20) .. '...'
    end

    return spinner .. ' ' .. msg
end

local function LspProgress()
    if is_cache_valid(cache.lsp_progress) then
        return cache.lsp_progress.value
    end

    local progress = get_lsp_progress()
    set_cache(cache.lsp_progress, progress, { ttl_key = 'lsp_progress' })
    return progress
end

local ClientsLsp = function(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()

    if cache.lsp.bufnr == bufnr and is_cache_valid(cache.lsp) then
        return cache.lsp.value
    end

    local clients = vim.lsp.get_clients({ bufnr = bufnr })
    if not next(clients) then
        set_cache(cache.lsp, '', { ttl_key = 'lsp', bufnr = bufnr })
        return ''
    end

    local result = vim.g.bar_disable_lsp_names
        and vim.g.bar_lsp_running
        or (vim.g.bar_lsp_running .. ' ' .. table.concat(
            vim.tbl_map(function(c) return c.name end, clients), '|'))

    set_cache(cache.lsp, result, { ttl_key = 'lsp', bufnr = bufnr })
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
    local clients = ClientsLsp(bufnr)
    local progress = LspProgress()

    -- Se houver progresso, mostra ao lado do ícone
    if progress ~= '' then
        return clients .. ' ' .. progress .. BuiltinLsp(bufnr)
    end

    return clients .. BuiltinLsp(bufnr)
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

    -- CORREÇÃO: Removido "%#Normal#%#" extra que estava causando o problema
    local sl = "%#BarMode#" .. (current_mode[mode] or '?') .. "%#Normal#" .. blank

    -- Git branch com ahead/behind
    local git_status = GitStatus()
    if git_status ~= '' then
        sl = sl .. git_status .. blank
    end

    -- Status do arquivo atual (~C+A-B)
    local file_git = FileGitStatus(bufnr)
    if file_git ~= '' then
        sl = sl .. file_git .. blank
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
            vim.wo[n].statusline = M.inActiveLine(bufid)
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

-- Função para obter o nome da tab (customizado ou padrão)
local function get_tab_name(tab)
    local tab_id = tostring(tab)
    local custom_name = tab_names[tab_id]

    if custom_name then
        return custom_name
    end

    -- Nome padrão: número da tab
    return tostring(api.nvim_tabpage_get_number(tab))
end

function M.tabLine()
    local current = api.nvim_get_current_tabpage()
    local parts = {}

    for _, tab in ipairs(api.nvim_list_tabpages()) do
        local name = get_tab_name(tab)
        local hl = (tab == current) and "%#BarMode#" or "%#Normal#"
        table.insert(parts, hl .. " " .. name .. " " .. "%#Normal#")
    end

    local blank = vim.g.bar_blank or ' '
    return "%#Normal# " .. table.concat(parts, '') .. "%=" ..
        blank .. DebugControls() .. blank ..
        "%#Normal# " .. vim.g.bar_iconCwd .. blank .. abbreviate_path(uv.cwd())
end

-- Função para renomear a tab atual
function M.rename_tab()
    local current_tab = api.nvim_get_current_tabpage()
    local tab_id = tostring(current_tab)
    local current_name = tab_names[tab_id] or tostring(api.nvim_tabpage_get_number(current_tab))

    vim.ui.input({
        prompt = "New tab name: ",
        default = current_name,
    }, function(input)
        if input and input ~= "" then
            tab_names[tab_id] = input
        else
            tab_names[tab_id] = nil
        end
        -- Atualiza a tabline
        if vim.g.bar_disable_tabline ~= 0 then
            vim.o.tabline = M.tabLine()
        end
    end)
end

-- Função para limpar o nome customizado da tab atual
function M.reset_tab_name()
    local current_tab = api.nvim_get_current_tabpage()
    local tab_id = tostring(current_tab)
    tab_names[tab_id] = nil
    -- Atualiza a tabline
    if vim.g.bar_disable_tabline ~= 0 then
        vim.o.tabline = M.tabLine()
    end
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

    -- Captura eventos de progresso LSP
    api.nvim_create_autocmd('LspProgress', {
        group = bar_augroup,
        callback = function(args)
            local data = args.data
            if not data or not data.params then
                return
            end

            local value = data.params.value
            if not value then
                return
            end

            local client = vim.lsp.get_client_by_id(data.client_id)
            local client_name = client and client.name or 'LSP'

            if value.kind == 'begin' then
                -- Progresso iniciou
                lsp_progress_state.active = true
                lsp_progress_state.client_name = client_name
                lsp_progress_state.message = value.message or value.title
                lsp_progress_state.percentage = value.percentage
            elseif value.kind == 'report' then
                -- Progresso em andamento
                lsp_progress_state.active = true
                lsp_progress_state.client_name = client_name
                lsp_progress_state.message = value.message or value.title
                lsp_progress_state.percentage = value.percentage
            elseif value.kind == 'end' then
                -- Progresso terminou
                lsp_done_state.active = true
                lsp_done_state.client_name = client_name
                lsp_done_state.expiry = uv.now() + 3000
                lsp_progress_state.active = false
            end

            -- Força atualização da barra
            local bufnr = api.nvim_get_current_buf()
            local winid = api.nvim_get_current_win()
            if vim.o.laststatus ~= 0 then
                vim.wo[winid].statusline = M.activeLine(bufnr)
            end
        end,
    })

    -- Inicia timer do spinner para animação
    local function start_spinner_timer()
        if spinner_timer and not spinner_timer:is_closing() then
            spinner_timer:stop()
        end
        spinner_timer = uv.new_timer()
        spinner_timer:start(0, 100, vim.schedule_wrap(function()
            cache.lsp_progress.expiry = 0
            -- Atualiza a barra se houver progresso ativo ou done state
            if lsp_progress_state.active or lsp_done_state.active then
                local bufnr = api.nvim_get_current_buf()
                local winid = api.nvim_get_current_win()
                if vim.o.laststatus ~= 0 then
                    vim.wo[winid].statusline = M.activeLine(bufnr)
                end
            end
        end))
    end

    api.nvim_create_autocmd('ModeChanged', {
        group = bar_augroup,
        callback = function()
            last_render_hash = nil
            update_bar()
        end,
    })

    api.nvim_create_autocmd({ 'RecordingEnter', 'RecordingLeave' }, {
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
            -- Invalida cache do arquivo ao trocar de buffer
            for k, _ in pairs(cache) do
                if k:match('^file_git_') then
                    cache[k] = nil
                end
            end
            update_bar()
        end,
    })

    api.nvim_create_autocmd('BufLeave', {
        group = bar_augroup,
        callback = function()
            cache.lsp.bufnr = nil
        end,
    })

    -- Atualiza tabline quando uma tab é fechada
    api.nvim_create_autocmd('TabClosed', {
        group = bar_augroup,
        callback = function(args)
            local closed_tab = args.tabpage
            if closed_tab then
                tab_names[tostring(closed_tab)] = nil
            end
            if vim.g.bar_disable_tabline ~= 0 then
                vim.o.tabline = M.tabLine()
            end
        end,
    })

    -- Comandos para renomear tabs
    vim.api.nvim_create_user_command('TabRename', function()
        M.rename_tab()
    end, {})

    vim.api.nvim_create_user_command('TabRenameReset', function()
        M.reset_tab_name()
    end, {})

    -- Inicia timer do spinner se LSP estiver disponível
    if vim.lsp and vim.lsp.get_clients then
        start_spinner_timer()
    end

    vim.schedule(update_bar)
end

return M
