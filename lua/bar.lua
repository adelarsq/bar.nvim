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
    git = 3000,         -- 3s - Git
    file_git = 1000,    -- 1s - Git status do arquivo
    lsp = 500,          -- 500ms - LSP
    lsp_progress = 200, -- 200ms - Progresso (para animação suave)
    overseer = 1000,    -- 1s - tarefas
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

    -- Verifica status git apenas para o buffer atual
    local filepath = vim.api.nvim_buf_get_name(bufnr)
    if filepath and filepath ~= '' then
        local git_dir = uv.cwd() .. '/.git'
        if uv.fs_stat(git_dir) then
            local handle = io.popen('git status --porcelain -- ' .. vim.fn.shellescape(filepath) .. ' 2>/dev/null')
            if handle then
                local status = handle:read('*a')
                handle:close()
                git_sig = #status > 0 and 1 or 0
            end
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

local function jump_status()
  local jumplist = vim.fn.getjumplist()
  local jumps = jumplist[1]   -- lista de saltos
  local cur_idx = jumplist[2] -- índice atual no jumplist

  -- Índices começam em 1 em Lua, então ajustamos para algo mais intuitivo
  local current_jump = cur_idx

  -- Quantidade de saltos anteriores disponíveis (equivale ao que <C-o> pode voltar)
  local prev_count = cur_idx - 1

  -- Quantidade de saltos que pode avançar (equivale ao que <C-i> pode avançar)
  local next_count = #jumps - cur_idx

  return string.format("%d-%d-%d", prev_count, current_jump, next_count)
end

local function undo_status()
  local ut = vim.fn.undotree()
  local seq_cur = ut.seq_cur
  local seq_last = ut.seq_last

  -- Índice da ação atual
  local current_action = seq_cur

  -- Quantidade de ações anteriores que podem ser desfeitas (u)
  local prev_count = seq_cur - 1

  -- Quantidade de ações que podem ser refeitas (C-r)
  local next_count = seq_last - seq_cur

  return string.format("%d-%d-%d", prev_count, current_action, next_count)
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
    [''] = 'Visual Block',
    [''] = 'Select Block',
    ['n'] = 'Normal',
    ['no'] = 'Operator Pending',
    ['nov'] = 'Operator Pending',
    ['noV'] = 'Operator Pending',
    ['niI'] = 'Normal',
    ['niR'] = 'Normal',
    ['niV'] = 'Normal',
    ['nt'] = 'Normal',
    ['v'] = 'Visual',
    ['vs'] = 'Visual',
    ['V'] = 'Visual Line',
    ['Vs'] = 'Visual Line',
    ['s'] = 'Select',
    ['S'] = 'Select Line',
    [''] = 'Select',
    ['i'] = 'Insert',
    ['ic'] = 'Insert',
    ['ix'] = 'Insert',
    ['R'] = 'Replace',
    ['Rc'] = 'Replace',
    ['Rx'] = 'Replace',
    ['Rv'] = 'Replace',
    ['Rvc'] = 'Replace',
    ['Rvx'] = 'Replace',
    ['c'] = 'Command',
    ['cv'] = 'Ex',
    ['ce'] = 'Ex',
    ['r'] = 'Prompt',
    ['rm'] = 'More',
    ['r?'] = 'Confirm',
    ['!'] = 'Shell',
    ['t'] = 'Terminal',
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

-- Cache específico para ahead/behind (parte pesada: commits)
local ahead_behind_cache = {}

local function get_ahead_behind()
    local now = uv.now()
    local cache_key = 'ahead_behind'

    if ahead_behind_cache[cache_key] and ahead_behind_cache[cache_key].expiry > now then
        return ahead_behind_cache[cache_key].ahead, ahead_behind_cache[cache_key].behind
    end

    local ahead, behind = 0, 0
    local upstream = exec_git_command('git rev-parse --abbrev-ref @{upstream} 2>/dev/null')
    if upstream and upstream ~= '' then
        local ahead_str = exec_git_command('git rev-list --count @{upstream}..HEAD 2>/dev/null')
        local behind_str = exec_git_command('git rev-list --count HEAD..@{upstream} 2>/dev/null')
        ahead = tonumber(ahead_str) or 0
        behind = tonumber(behind_str) or 0
    end

    ahead_behind_cache[cache_key] = {
        ahead = ahead,
        behind = behind,
        expiry = now + 60000 -- 60 segundos
    }

    return ahead, behind
end

-- Status específico do arquivo atual e repositório (formato ~C+A-R^AvBuUsSt)
local FileGitStatus = function(bufnr)
    local filepath = api.nvim_buf_get_name(bufnr)
    if not filepath or filepath == '' then
        return ''
    end

    -- Cache específico para o arquivo (status geral)
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

    -- Função auxiliar para executar git diff e retornar added, removed
    local function get_diff_stats(cmd)
        local output = exec_git_command(cmd)
        if not output or output == '' then
            return 0, 0
        end

        local total_added = 0
        local total_removed = 0

        for line in output:gmatch('[^\r\n]+') do
            local added, removed = line:match('^(%d+)%s+(%d+)')
            if added and removed then
                total_added = total_added + tonumber(added)
                total_removed = total_removed + tonumber(removed)
            end
        end

        return total_added, total_removed
    end

    -- Obtém stats do arquivo
    local shell_filepath = vim.fn.shellescape(filepath)
    local unstaged_added, unstaged_removed = get_diff_stats('git diff --numstat ' .. shell_filepath .. ' 2>/dev/null')
    local staged_added, staged_removed = get_diff_stats('git diff --cached --numstat ' ..
    shell_filepath .. ' 2>/dev/null')

    local total_added = unstaged_added + staged_added
    local total_removed = unstaged_removed + staged_removed

    local modified = math.min(total_added, total_removed)
    local net_added = math.max(0, total_added - total_removed)
    local net_removed = math.max(0, total_removed - total_added)

    -- Obtém quantidade de arquivos unstaged
    local unstaged_files = 0
    local unstaged_status = exec_git_command('git ls-files --modified --exclude-standard 2>/dev/null')
    if unstaged_status and unstaged_status ~= '' then
        unstaged_files = #vim.split(unstaged_status:gsub('\n$', ''), '\n')
    end

    -- Obtém quantidade de arquivos staged
    local staged_files = 0
    local staged_status = exec_git_command('git diff --cached --name-only 2>/dev/null')
    if staged_status and staged_status ~= '' then
        staged_files = #vim.split(staged_status:gsub('\n$', ''), '\n')
    end

    -- Obtém ahead/behind (parte pesada, com cache de 1 minuto)
    local ahead, behind = get_ahead_behind()

    -- Se não há nenhuma alteração, retorna vazio
    if modified == 0 and net_added == 0 and net_removed == 0 and ahead == 0 and behind == 0 and unstaged_files == 0 and staged_files == 0 then
        set_cache(cache[cache_key], '', { ttl_key = 'file_git' })
        return ''
    end

    -- Constrói o resultado no formato: ~C+A-R^AvBuUsSt
    local result_parts = {}

    -- Parte do arquivo atual: ~C+A-R
    if modified > 0 or net_added > 0 or net_removed > 0 then
        table.insert(result_parts, string.format('%%#Changed#~%d%%#Added#+%d%%#Removed#-%d%%#Normal#', modified, net_added, net_removed))
    end

    -- Parte de commits: ↑A↓B (agora vem do cache separado)
    if ahead > 0 or behind > 0 then
        local commit_parts = {}
        if ahead > 0 then
            table.insert(commit_parts, '%#Directory#↑' .. ahead .. '%#Normal#')
        end
        if behind > 0 then
            table.insert(commit_parts, '%#Directory#↓' .. behind .. '%#Normal#')
        end
        if #commit_parts > 0 then
            table.insert(result_parts, table.concat(commit_parts, ''))
        end
    end

    -- Parte de arquivos: UsSt
    if unstaged_files > 0 or staged_files > 0 then
        local file_parts = {}
        if unstaged_files > 0 then
            table.insert(file_parts, '%#Special#󰡯' .. unstaged_files .. '%#Normal#')
        end
        if staged_files > 0 then
            table.insert(file_parts, '%#Added#󰈖' .. staged_files .. '%#Normal#')
        end
        table.insert(result_parts, table.concat(file_parts, ''))
    end

    local result = table.concat(result_parts, '')
    set_cache(cache[cache_key], result, { ttl_key = 'file_git' })
    return result
end

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

    local sl = "%#BarMode#" .. (current_mode[mode] or '?') .. "%#Normal#" .. blank

    sl = sl .. ' ' .. jump_status() .. blank

    if not vim.tbl_contains(excluded_buftypes, bo.buftype) then
        sl = sl .. '󰕌 ' .. undo_status() .. blank
        if bo.modified then sl = sl .. '%#ErrorMsg#' .. ' ' .. '%#Normal#' .. blank end
    end

    -- Status do arquivo atual (~C+A-R^AvBuUsSt)
    if vim.g.bar_enable_git_status then
        local file_git = FileGitStatus(bufnr)
        if file_git ~= '' then
            sl = sl .. '%#Special# %#Normal#' .. file_git .. blank
        end
    end

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
    sl = sl .. "%#Normal#%{&fileencoding}" .. blank
    sl = sl .. "%l:%L/%c:%v"

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

local function normalize_path(path)
  return path:gsub("\\", "/")
end

local function get_relative_path_from_cwd(full_path)
  if not full_path or full_path == "" then
    return ""
  end

  local dir = vim.fn.fnamemodify(full_path, ":h")
  local filename = vim.fn.fnamemodify(full_path, ":t")

  local cwd = uv.cwd()
  local cwd_norm = normalize_path(cwd)
  local dir_norm = normalize_path(dir)

  -- Garante que ambos terminem com "/"
  cwd_norm = cwd_norm:gsub("/*$", "") .. "/"
  dir_norm = dir_norm:gsub("/*$", "") .. "/"

  -- Se o diretório começar com o cwd, remove essa parte
  if dir_norm:sub(1, #cwd_norm) == cwd_norm then
    local relative_dir = dir_norm:sub(#cwd_norm + 1)
    relative_dir = relative_dir:gsub("^/", "")  -- remove barra inicial se houver
    relative_dir = relative_dir:gsub("/*$", "") -- remove barras finais

    -- Se o diretório relativo ficar vazio, retorna só o nome do arquivo
    if relative_dir == "" then
      return filename
    end
    -- Junta diretório relativo + nome do arquivo
    return relative_dir .. "/" .. filename
  end

  -- Caso contrário, retorna o caminho completo normalizado
  return dir_norm:gsub("/*$", "") .. "/" .. filename
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
    local full_path = api.nvim_buf_get_name(bufnr)
    local filename = vim.fn.fnamemodify(full_path, ':t')
    if filename == '' then filename = '[No Name]' end

    local relative_part = get_relative_path_from_cwd(full_path)
    local abbr = abbreviate_path(relative_part)

    local diag_parts = {}
    for sev, icon in pairs({ error = vim.g.bar_symbol_error, warn = vim.g.bar_symbol_warning, info = vim.g.bar_symbol_information, hint = vim.g.bar_symbol_hint}) do
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
