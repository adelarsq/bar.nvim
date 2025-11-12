local api = vim.api

local M = {}

------------------------------------------------------------------------
-- Colors
------------------------------------------------------------------------

vim.g.bar_none = 'none'
vim.g.bar_red = '#ff5349'    -- red orange
vim.g.bar_orange = '#fe6e00' -- blaze orange
vim.g.bar_green = '#4CBB17'  -- color Kelly
vim.g.bar_turquoise = '#3FE0D0'
vim.g.bar_aqua = '#18ffe0'
vim.g.bar_blue = '#31baff'
vim.g.bar_purple = '#9d8cff'
vim.g.bar_green_light = '#D5F5E3'
vim.g.bar_purple_light = '#E8DAEF'
vim.g.bar_blue_light = '#D6EAF8'
vim.g.bar_red_light = '#FADBD8'
vim.g.bar_black = '#282c34'
vim.g.bar_black2 = '#4d4d4d'
vim.g.bar_gray = '#cccccc'
vim.g.bar_gray2 = '#e6e6e6'
vim.g.bar_white = '#ffffff'

------------------------------------------------------------------------
-- Icons
------------------------------------------------------------------------

vim.g.bar_iconCwd = '🏡'

-- LSP
vim.g.bar_lsp_running = '🔥'

-- DAP
vim.g.bar_dap_running = '🐞'

vim.g.bar_symbol_error = '💥'
vim.g.bar_symbol_warning = '💩'
vim.g.bar_symbol_information = '⚠️'
vim.g.bar_symbol_hint = '💡'

vim.g.bar_symbol_canceled = '⛔'
vim.g.bar_symbol_failure = '💥'
vim.g.bar_symbol_success = '✅'
vim.g.bar_symbol_running = '🚀'

------------------------------------------------------------------------
-- Utils
------------------------------------------------------------------------

local Exists = function(variable)
    local loaded = api.nvim_call_function('exists', { variable })
    return loaded ~= 0
end

local Call = function(arg0, arg1)
    return api.nvim_call_function(arg0, arg1)
end

-- Verify if a string is a suffix from another
local function is_suffix(suffix, str)
    -- Get the length of the suffix and the string
    local suffix_len = #suffix
    local str_len = #str

    -- If the suffix is longer than the string, it can't be a suffix
    if suffix_len > str_len then
        return false
    end

    -- Extract the last `suffix_len` characters of the string
    local str_suffix = string.sub(str, 1, suffix_len)

    -- Compare the extracted suffix with the given suffix
    return str_suffix == suffix
end

-- Get path relative to cwd() for the current file.
local function get_relative_path(bufnr, filetype)
    local file_dir = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ':p:h')
    file_dir = vim.fn.substitute(file_dir, '\\', '/', 'g')

    if filetype == 'oil' then
        file_dir = file_dir:sub(7)
    end

    local cwd = vim.uv.cwd()

    if cwd == nil then
        return ''
    end

    cwd = vim.fn.substitute(cwd, '\\', '/', 'g')

    if file_dir:sub(-1) ~= '/' then
        file_dir = file_dir .. '/'
    end
    if cwd:sub(-1) ~= '/' then
        cwd = cwd .. '/'
    end

    if is_suffix(cwd, file_dir) then
        return file_dir:sub(cwd:len() + 1)
    else
        return file_dir
    end
end

------------------------------------------------------------------------
-- Features
------------------------------------------------------------------------

local TsStatus = function()
    if vim.g.bar_enable_plugins then
        if vim.g.loaded_nvim_treesitter then
            local use, imported = pcall(require, "nvim-treesitter.statusline")
            if use then
                return imported.statusline()
            else
                return ''
            end
        end
        return ''
    else
        return ''
    end
end

local CurrentScope = function()
    return TsStatus()
end

local DebugStatus = function()
    if vim.g.bar_enable_plugins then
        local use, imported = pcall(require, "dap")
        if use then
            return imported.status()
        else
            return ''
        end
    else
        return ''
    end
end

local DebugControls = function()
    if vim.g.bar_enable_plugins then
        if DebugStatus() == '' then
            return ''
        end

        local use, imported = pcall(require, "dapui.controls")
        if use then
            return imported.controls()
        else
            return ''
        end
    else
        return ''
    end
end

------------------------------------------------------------------------
-- Configs
------------------------------------------------------------------------
-- Space between components
vim.g.bar_blank = ' '

------------------------------------------------------------------------
-- Plugins
------------------------------------------------------------------------


local TasksStatus = function()
    local tasks = require("overseer.task_list").list_tasks({ unique = true })
    local tasks_by_status = require("overseer.util").tbl_group_by(tasks, "status")

    local symbols = {
        ["CANCELED"] = vim.g.bar_symbol_canceled,
        ["FAILURE"] = vim.g.bar_symbol_failure,
        ["SUCCESS"] = vim.g.bar_symbol_success,
        ["RUNNING"] = vim.g.bar_symbol_running,
    }

    local status = ''
    if tasks_by_status["CANCELED"] then
        status = string.format("%s%d", symbols["CANCELED"], #tasks_by_status["CANCELED"])
    end
    if tasks_by_status["FAILURE"] then
        status = status .. string.format("%s%d", symbols["FAILURE"], #tasks_by_status["FAILURE"])
    end
    if tasks_by_status["SUCCESS"] then
        status = status .. string.format("%s%d", symbols["SUCCESS"], #tasks_by_status["SUCCESS"])
    end
    if tasks_by_status["RUNNING"] then
        status = status .. string.format("%s%d", symbols["RUNNING"], #tasks_by_status["RUNNING"])
    end

    return status
end

------------------------------------------------------------------------
-- StatusLine
------------------------------------------------------------------------

-- Mode Prompt Table
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
}, {}
)

-- Redraw different colors for different mode
local RedrawColors = function(mode)
    if mode == 'n' then
        api.nvim_command('hi BarMode guibg=' .. vim.g.bar_blue .. ' guifg=' .. vim.g.bar_white)
    elseif mode == 'i' then
        api.nvim_command('hi BarMode guibg=' .. vim.g.bar_green .. ' guifg=' .. vim.g.bar_white)
    elseif mode == 'v' or mode == 'V' or mode == '' then
        api.nvim_command('hi BarMode guibg=' .. vim.g.bar_purple .. ' guifg=' .. vim.g.bar_white)
    elseif mode == 'c' then
        api.nvim_command('hi BarMode guibg=' .. vim.g.bar_orange .. ' guifg=' .. vim.g.bar_white)
    elseif mode == 'Rv' then
        api.nvim_command('hi BarMode guibg=' .. vim.g.bar_red .. ' guifg=' .. vim.g.bar_white)
    elseif mode == 't' then
        api.nvim_command('hi BarMode guibg=' .. vim.g.bar_turquoise .. ' guifg=' .. vim.g.bar_white)
    end
end

local DiagnosticStatus = function(idBuffer)
    local diagnostics = vim.diagnostic.get(idBuffer)
    local count = { 0, 0, 0, 0 }
    for _, diagnostic in ipairs(diagnostics) do
        count[diagnostic.severity] = count[diagnostic.severity] + 1
    end
    return count[vim.diagnostic.severity.ERROR],
        count[vim.diagnostic.severity.WARN],
        count[vim.diagnostic.severity.INFO],
        count[vim.diagnostic.severity.HINT]
end

-- Builtin Neovim LSP

local ClientsLsp = function()
    local bufnr = vim.api.nvim_get_current_buf()
    local clients = vim.lsp.get_clients({ bufnr = bufnr })
    if next(clients) == nil then
        return ""
    end

    local c = {}
    if not vim.g.bar_disable_lsp_names then
        for _, client in pairs(clients) do
            table.insert(c, client.name)
        end

        return vim.g.bar_lsp_running .. " " .. table.concat(c, "|")
    end

    return vim.g.bar_lsp_running
end

local DapRunning = function()
    local dap = require("dap")
    if dap.session() then
        return vim.g.bar_dap_running
    else
        return ''
    end
end

local BuiltinLsp = function(idBuffer)
    local sl = "%#Normal#"

    if not vim.tbl_isempty(vim.lsp.get_clients({ bufnr = idBuffer })) then
        if not vim.g.bar_disable_diagnostics then
            local error, warning, information, hint = DiagnosticStatus(idBuffer)

            if error > 0 then
                sl = sl .. ' ' .. vim.g.bar_symbol_error
                sl = sl .. error
            end
            if warning > 0 then
                sl = sl .. ' ' .. vim.g.bar_symbol_warning
                sl = sl .. warning
            end
            if information > 0 then
                sl = sl .. ' ' .. vim.g.bar_symbol_information
                sl = sl .. information
            end
            if hint > 0 then
                sl = sl .. ' ' .. vim.g.bar_symbol_hint
                sl = sl .. hint
            end
        end
    end
    sl = sl .. "%#Normal#"
    return sl
end

local LspStatus = function(idBuffer)
    local sl = ""
    sl = sl .. ClientsLsp()
    sl = sl .. BuiltinLsp(idBuffer)
    return sl
end

local FilePath = function()
    return '%f'
end

local RunStatus = function()
    if vim.g.asyncrun_status then
        local result = vim.g.asyncrun_status
        if result ~= nil then
            return result
        end
    end
    return ''
end

local ShowMacroRecording = function()
    local recording_register = vim.fn.reg_recording()
    if recording_register == "" then
        return ""
    else
        return " Recording @" .. recording_register .. " "
    end
end


local GitStatus = function()
    local is_windows = vim.fn.has('win32') == 1 or vim.fn.has('win64') == 1

    local cmd_dir = nil
    if is_windows then
        cmd_dir = 'git rev-parse --is-inside-work-tree 2>nul'
    else
        cmd_dir = 'git rev-parse --is-inside-work-tree 2>/dev/null'
    end
    local handle = io.popen(cmd_dir)
    if not handle then return '' end
    local git_dir = handle:read('*a'):gsub('%s+', '')
    handle:close()

    if git_dir ~= 'true' then
        return ''
    end

    local branch_cmd = nil
    if is_windows then
        branch_cmd = 'git branch --show-current 2>nul'
    else
        branch_cmd = 'git branch --show-current 2>/dev/null'
    end
    local branch_handle = io.popen(branch_cmd)
    if not branch_handle then return '' end
    local branch = branch_handle:read('*a'):gsub('%s+', '')
    branch_handle:close()

    if branch == '' then
        return ''
    end

    local cmd = nil
    if is_windows then
        cmd = 'git rev-list --count --left-right @{upstream}...HEAD 2>nul'
    else
        cmd = 'git rev-list --count --left-right @{upstream}...HEAD 2>/dev/null'
    end
    local rev_list_handle = io.popen(cmd)
    if not rev_list_handle then return branch end
    local result = rev_list_handle:read('*a'):gsub('%s+$', '')
    rev_list_handle:close()

    if result == '' then
        return branch
    end

    local behind, ahead = result:match('(%d+)%s+(%d+)')
    ahead = tonumber(ahead) or 0
    behind = tonumber(behind) or 0

    local status = branch
    if ahead > 0 then
        status = status .. ' ↑' .. ahead
    end
    if behind > 0 then
        status = status .. ' ↓' .. behind
    end

    return status
end

function M.activeLine(idBuffer)
    local statusline = "%#Normal#"

    local filetype = api.nvim_buf_get_option(idBuffer, 'filetype')
    local laststatus = api.nvim_get_option('laststatus')

    local mode = api.nvim_get_mode()['mode']

    RedrawColors(mode)

    statusline = statusline .. "%#BarMode#" .. current_mode[mode]
    statusline = statusline .. "%#Normal#"
    statusline = statusline .. vim.g.bar_blank

    -- Repository Status
    -- TODO move this on another module
    if vim.g.loaded_signify then
        local repostats = Call('sy#repo#get_stats', {})

        if repostats[1] > -1 then
            statusline = statusline .. "%#BarVCSAdd#"
            statusline = statusline .. "+" .. repostats[1]
            statusline = statusline .. "%#BarVCSDelete#"
            statusline = statusline .. "-" .. repostats[2]
            statusline = statusline .. "%#BarVCSChange#"
            statusline = statusline .. "~" .. repostats[3]

            -- TODO verificar se plugin esta ativo
            local vcsName = Call('VcsName', {})
            statusline = statusline .. vim.g.bar_blank .. vcsName
        end
    end

    -- TODO move this on another module
    if Exists('b:gitsigns_head') then
        local bar_git_status = GitStatus()
        statusline = statusline .. vim.b.gitsigns_status .. ' ' .. bar_git_status
    end

    statusline = statusline .. "%{&modified?'+':''}"

    statusline = statusline .. ShowMacroRecording()

    statusline = statusline .. "%="

    statusline = statusline .. DebugStatus()

    -- Alignment to left
    statusline = statusline .. "%#Normal#"
    statusline = statusline .. "%="
    statusline = statusline .. "%#Normal#"

    if vim.g.bar_enable_plugin_overseer then
        statusline = statusline .. TasksStatus()
    end
    statusline = statusline .. RunStatus()
    statusline = statusline .. LspStatus(idBuffer)
    statusline = statusline .. DapRunning()

    -- Component: FileType
    statusline = statusline .. "%#Normal# " .. filetype
    statusline = statusline .. vim.g.bar_blank

    -- Component: row and col
    local line = Call('line', { "." })
    local column = Call('col', { "." })
    statusline = statusline .. "%#Normal#%{&fileencoding} "
    statusline = statusline .. vim.g.bar_blank
    statusline = statusline .. line .. ":" .. column

    return statusline
end

function M.inActiveLine(idBuffer)
    local statusline = ""

    statusline = "%#Normal#" .. " "

    local filetype = api.nvim_buf_get_option(idBuffer, 'filetype')

    statusline = statusline .. "%#Normal# " .. FilePath()

    statusline = statusline .. "%="
    statusline = statusline .. "%#Normal#" .. " "

    return statusline
end

function M.UpdateInactiveWindows()
    if vim.bo.buftype == 'popup' then
        return
    end

    for n = 1, vim.fn.winnr('$') do
        if not vim.api.nvim_win_is_valid(0) then
            local bufferId = vim.fn.winbufnr(n)
            local statusLine = M.inActiveLine(bufferId)
            vim.api.nvim_win_set_var(n, '&statusline', statusLine)
        end
    end
end

------------------------------------------------------------------------
--                              TabLine                               --
------------------------------------------------------------------------

local abbreviate_path = function(path)
    if path == nil then
        return ''
    end

    local last_name = string.match(path, "[^/\\]+$")

    if last_name == nil then
        return ''
    end

    local previous_folders = string.match(path, "^.+[\\/]")

    local abbreviated_folders = ""

    if previous_folders ~= nil then
        for folder in string.gmatch(previous_folders, "[^/\\]+") do
            abbreviated_folders = abbreviated_folders .. string.sub(folder, 1, 1) .. "/"
        end
    end

    return abbreviated_folders .. last_name
end

function M.tabLine()
    local tabline = ''
    local tab_list = api.nvim_list_tabpages()
    local current_tab = api.nvim_get_current_tabpage()
    for _, val in ipairs(tab_list) do
        local number = api.nvim_tabpage_get_number(val)
        tabline = tabline .. "%#Normal# "
        if val == current_tab then
            tabline = tabline .. "%#BarMode#"
        else
            tabline = tabline .. "%#Normal#"
        end
        tabline = tabline .. number
        tabline = tabline .. "%#Normal#" .. " "
    end
    tabline = tabline .. "%="

    tabline = tabline .. " " .. DebugControls() .. " "

    tabline = tabline .. "%#Normal# " .. vim.g.bar_iconCwd .. ' ' .. abbreviate_path(vim.uv.cwd())

    return tabline
end

function M.winbar(bufnr)
    local winbar = '%#Normal#'

    -- local bufnr = vim.api.nvim_win_get_buf(0)
    local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ':t')
    local filetype = vim.bo[bufnr]['filetype']

    if filename == '' then
        filename = '[No Name]'
    end

    local file_dir = get_relative_path(bufnr, filetype)

    local modified = vim.bo[bufnr].modified

    local function get_diagnostic_label(bufnr)
        local icons = { error = 'e', warn = '', info = '', hint = '' }
        local label = ''

        for severity, icon in pairs(icons) do
            local n = #vim.diagnostic.get(bufnr,
                { severity = vim.diagnostic.severity[string.upper(severity)] })
            if n > 0 then
                label = label .. '%#DiagnosticSign'.. severity ..'#'
                label = label .. icon .. n .. ''
            end
        end
        return label
    end

    -- Get window id for the buffer id passed as parameter
    local function find_window_by_bufid(bufnr)
        for _, win in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_get_buf(win) == bufnr then
                return win
            end
        end
        return nil
    end

    -- Based on https://www.reddit.com/r/neovim/comments/1jogp6e/comment/mkrywdw/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button
    local function get_scrollbar(bufnr)
        local window_id = find_window_by_bufid(bufnr)
        if window_id == nil then
            return ''
        end

        local sbar_chars = { '▔', '🮂', '🮃', '▀', '▬', '▄', '▃', '▂', '▁', }

        local cur_line = vim.api.nvim_win_get_cursor(window_id)[1]
        local lines = vim.api.nvim_buf_line_count(bufnr)

        local i = math.floor((cur_line - 1) / lines * #sbar_chars) + 1
        local sbar = string.rep(sbar_chars[i], 2)

        return sbar
    end

    local diagnostic_label = get_diagnostic_label(bufnr)
    local scroolbar = '%#Normal#' .. get_scrollbar(bufnr)
    local file_dir_abbreviate = abbreviate_path(file_dir .. filename)

    return winbar .. file_dir_abbreviate .. ' ' ..diagnostic_label .. ' ' .. scroolbar
end

function M.setup(opts)
    opts = opts or {}

    local timer = vim.uv.new_timer()

    timer:start(100, 1000, vim.schedule_wrap(function()
        local bufnr = vim.api.nvim_get_current_buf()
        local winid = vim.api.nvim_get_current_win()
        local buftype = vim.bo[bufnr].buftype
        local filetype = vim.bo[bufnr].filetype

        if vim.o.laststatus == 1 or vim.o.laststatus == 2 then
            vim.wo.statusline = require 'bar'.activeLine(bufnr)
            require 'bar'.UpdateInactiveWindows(bufnr)
        end

        if vim.o.laststatus == 3 then
            vim.wo.statusline = require 'bar'.activeLine(bufnr)
        end

        if vim.g.bar_disable_tabline ~= 0 then
            vim.o.tabline = require 'bar'.tabLine()
        end

        if not vim.g.bar_disable_winbar then
            -- if buftype ~= '' and buftype ~= 'nofile' and
            --    filetype ~= 'dap-view' and filetype ~= 'dap-repl' then
               vim.wo[winid].winbar = require 'bar'.winbar(bufnr)
            -- end
        end
    end))
end

return M
