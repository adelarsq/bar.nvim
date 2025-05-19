local api = vim.api

local M = {}

------------------------------------------------------------------------
-- Colors
------------------------------------------------------------------------

vim.g.bar_none = 'none'
vim.g.bar_red = '#ff5349'        -- red orange
vim.g.bar_orange = '#fe6e00'     -- blaze orange
vim.g.bar_green = '#4CBB17'      -- color Kelly
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
vim.g.bar_lsp_stoped = '🧊'

vim.g.bar_symbol_error = '💥'
vim.g.bar_symbol_warning = '💩'
vim.g.bar_symbol_information = '⚠️'
vim.g.bar_symbol_hint = '💡'

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
    for _, client in pairs(clients) do
        table.insert(c, client.name)
    end

    return vim.g.bar_lsp_running .. " " .. table.concat(c, "|")
end

local BuiltinLsp = function(idBuffer)
    local sl = "%#Normal#"

    if not vim.tbl_isempty(vim.lsp.get_clients({ bufnr = idBuffer })) then

        if vim.g.bar_disable_diagnostics ~= 0 then
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
    else
        sl = sl .. vim.g.bar_lsp_stoped
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
        statusline = statusline .. vim.b.gitsigns_status .. ' ' .. vim.b.gitsigns_head
    end

    statusline = statusline .. "%{&modified?'+':''}"

    statusline = statusline .. ShowMacroRecording()

    statusline = statusline .. "%="

    statusline = statusline .. DebugStatus()

    -- Alignment to left
    statusline = statusline .. "%#Normal#"
    statusline = statusline .. "%="
    statusline = statusline .. "%#Normal#"

    statusline = statusline .. RunStatus()
    statusline = statusline .. LspStatus(idBuffer)

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

function M.TabLine()
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

function M.setup(opts)
    opts = opts or {}

    local timer = vim.uv.new_timer()

    timer:start(100, 1000, vim.schedule_wrap(function()
        local bufnr = vim.api.nvim_get_current_buf()

        if vim.o.laststatus == 1 or vim.o.laststatus == 2 then
            vim.wo.statusline = require 'bar'.activeLine(bufnr)
            require 'bar'.UpdateInactiveWindows(bufnr)
        end

        if vim.o.laststatus == 3 then
            vim.wo.statusline = require 'bar'.activeLine(bufnr)
        end

        if vim.g.bar_disable_tabline ~= 0 then
            vim.o.tabline = require 'bar'.TabLine()
        end
    end))

    -- winbar
    if not vim.g.bar_disable_winbar then
        vim.o.winbar = '%#Normal#%F'
    end
end

return M
