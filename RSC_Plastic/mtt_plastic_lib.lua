-- mtt_plastic_lib.lua
-- Libreria condivisa per l'integrazione Plastic SCM (Unity VCS) in REAPER.
-- NON è un'azione: viene caricata via dofile() dagli altri script mtt_plastic_*.
--
-- Responsabilità:
--   * auto-detect dell'eseguibile cm (mac + win + PATH), override da settings
--   * esecuzione comandi sync/async cross-platform senza congelare la UI
--   * parsing output cm in formato macchina (--format), niente frasi in inglese
--   * settings persistenti (ExtState) + stato runtime condiviso tra script

local M = {}

M.EXT      = 'MTT_PLASTIC'      -- settings persistenti
M.EXT_RT   = 'MTT_PLASTIC_RT'   -- stato runtime (non persistito)

M.OS         = reaper.GetOS()
M.is_windows = M.OS:find('Win') ~= nil
M.SEP        = M.is_windows and '\\' or '/'

-- ---------------------------------------------------------------- settings --

function M.getSetting(key, default)
  local v = reaper.GetExtState(M.EXT, key)
  if v == nil or v == '' then return default end
  return v
end

function M.setSetting(key, value)
  reaper.SetExtState(M.EXT, key, tostring(value), true)
end

function M.setRT(key, value)
  reaper.SetExtState(M.EXT_RT, key, tostring(value), false)
end

function M.getRT(key)
  return reaper.GetExtState(M.EXT_RT, key)
end

-- Segnala al monitor che lo stato è cambiato (dopo checkin/checkout/ecc.)
-- Invalida anche lo stato pubblicato: il fast path del save non deve fidarsi
-- di uno stato vecchio finché il monitor non ha rinfrescato.
function M.markDirty()
  M.setRT('dirty', '1')
  M.setRT('state', '')
end

-- ------------------------------------------------------------------- utils --

function M.q(s) return '"' .. tostring(s) .. '"' end

function M.fileExists(p)
  if not p or p == '' then return false end
  local f = io.open(p, 'r')
  if f then f:close() return true end
  return false
end

function M.dirname(path)
  if type(path) ~= 'string' or path == '' then return nil end
  local i = path:find('[/\\][^/\\]*$')
  if i then return path:sub(1, i - 1) end
  return path
end

function M.trim(s)
  return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', ''))
end

local function readAll(path)
  local f = io.open(path, 'r')
  if not f then return nil end
  local c = f:read('*a')
  f:close()
  return c
end

function M.tempDir()
  local d = os.getenv(M.is_windows and 'TEMP' or 'TMPDIR')
  if not d or d == '' then d = reaper.GetResourcePath() end
  return (d:gsub('[/\\]+$', ''))
end

-- ------------------------------------------------------------ cm detection --

local CM_CANDIDATES_MAC = {
  '/Applications/PlasticSCM.app/Contents/Applications/cm.app/Contents/MacOS/cm',
  '/Applications/Gluon.app/Contents/Applications/cm.app/Contents/MacOS/cm',
  '/usr/local/bin/cm',
  '/opt/homebrew/bin/cm',
}

local CM_CANDIDATES_WIN = {
  'C:\\Program Files\\PlasticSCM5\\client\\cm.exe',
  'C:\\Program Files (x86)\\PlasticSCM5\\client\\cm.exe',
}

local cm_cache = nil

function M.findCm()
  if cm_cache then return cm_cache end

  -- 1. override manuale dalle impostazioni
  local override = M.getSetting('cm_path', '')
  if override ~= '' and M.fileExists(override) then
    cm_cache = override
    return cm_cache
  end

  -- 2. path standard per OS
  local list = M.is_windows and CM_CANDIDATES_WIN or CM_CANDIDATES_MAC
  for _, p in ipairs(list) do
    if M.fileExists(p) then
      cm_cache = p
      return cm_cache
    end
  end

  -- 3. speriamo sia nel PATH
  cm_cache = M.is_windows and 'cm.exe' or 'cm'
  return cm_cache
end

function M.cmq()
  local cm = M.findCm()
  if cm:find('%s') then return M.q(cm) end
  return cm
end

-- --------------------------------------------------- esecuzione comandi ----
-- Strategia: il comando viene scritto in uno script temporaneo (.sh / .bat)
-- che redirige stdout+stderr su file e scrive l'exit code in un file .done.
-- Sync : ExecProcess con attesa, poi lettura dei file.
-- Async: ExecProcess -2 (background, nessuna finestra), poll dei file .done
--        dentro il defer loop del monitor -> UI mai congelata.

local job_seq = 0
local jobs = {}

local function makeJobFiles(cmd, workdir)
  job_seq = job_seq + 1
  local base   = M.tempDir() .. M.SEP .. 'mtt_cm_' .. tostring(os.time()) .. '_' .. tostring(job_seq)
  local out_f  = base .. '.out'
  local done_f = base .. '.done'
  local script = base .. (M.is_windows and '.bat' or '.sh')

  local f = io.open(script, 'w')
  if not f then return nil end

  if M.is_windows then
    f:write('@echo off\r\n')
    if workdir then f:write('cd /d "' .. workdir .. '"\r\n') end
    f:write(cmd .. ' > "' .. out_f .. '" 2>&1\r\n')
    f:write('echo %ERRORLEVEL% > "' .. done_f .. '"\r\n')
  else
    f:write('#!/bin/sh\n')
    if workdir then f:write('cd "' .. workdir .. '" || exit 1\n') end
    f:write(cmd .. ' > "' .. out_f .. '" 2>&1\n')
    f:write('echo $? > "' .. done_f .. '"\n')
  end
  f:close()

  local runner
  if M.is_windows then
    runner = 'cmd.exe /S /C ""' .. script .. '""'
  else
    runner = '/bin/sh "' .. script .. '"'
  end

  return { out = out_f, done = done_f, script = script, runner = runner }
end

local function collectJob(j)
  local code = tonumber((readAll(j.done) or ''):match('%-?%d+') or '') or -1
  local out  = readAll(j.out) or ''
  os.remove(j.done); os.remove(j.out); os.remove(j.script)
  return code, out
end

-- Esecuzione sincrona. Ritorna exit_code, output (stdout+stderr).
-- timeout 0 = attesa illimitata (default).
function M.run(cmd, workdir, timeout_ms)
  local j = makeJobFiles(cmd, workdir)
  if not j then return -1, 'unable to create temporary script' end
  reaper.ExecProcess(j.runner, timeout_ms or 0)
  return collectJob(j)
end

-- Esecuzione asincrona: callback(exit_code, output) quando finisce.
-- Serve chiamare M.poll() periodicamente (defer loop del monitor).
function M.runAsync(cmd, workdir, callback)
  local j = makeJobFiles(cmd, workdir)
  if not j then callback(-1, 'unable to create temporary script') return end
  j.cb = callback
  j.t0 = reaper.time_precise()
  reaper.ExecProcess(j.runner, -2)
  jobs[#jobs + 1] = j
end

function M.poll()
  for i = #jobs, 1, -1 do
    local j = jobs[i]
    if M.fileExists(j.done) then
      table.remove(jobs, i)
      local code, out = collectJob(j)
      j.cb(code, out)
    elseif reaper.time_precise() - j.t0 > 120 then
      -- job hanging for 2 minutes: abandoned
      table.remove(jobs, i)
      j.cb(-1, 'timeout')
    end
  end
end

function M.pendingJobs() return #jobs end

-- ----------------------------------------------------------- parsing cm ----

M.FILEINFO_FORMAT = '{Status};{RevisionChangeset};{LockedBy};{LockedWhere}'

-- Parsa l'output di `cm fileinfo --format=FILEINFO_FORMAT`.
-- Ritorna tabella oppure nil se l'output non è nel formato atteso.
function M.parseFileInfo(out)
  local line = M.trim(out):match('[^\r\n]+')
  if not line then return nil end
  local status, cs, lockedby, lockedwhere = line:match('^(.-);(.-);(.-);(.-)$')
  if not status then return nil end
  local t = {
    status       = M.trim(status),
    local_cs     = tonumber(M.trim(cs)),
    locked_by    = M.trim(lockedby),
    locked_where = M.trim(lockedwhere),
  }
  t.checked_out = t.status:lower():find('checked%-?out') ~= nil
  return t
end

-- Estrae il changeset massimo da un output che contiene id numerici (history).
function M.parseMaxChangeset(out)
  local maxcs = nil
  for n in tostring(out or ''):gmatch('%d+') do
    n = tonumber(n)
    if not maxcs or n > maxcs then maxcs = n end
  end
  return maxcs
end

function M.containsExclusiveCheckout(text)
  return tostring(text or ''):find('exclusively checked out by') ~= nil
end

function M.extractLockOwner(text)
  -- riga tipo: "path ... exclusively checked out by user@server (wk ...)"
  local who = tostring(text or ''):match('checked out by%s+([^%s%(]+)')
  return who
end

-- ------------------------------------------------------------ comandi cm ---

-- Comandi in versione sync (usati dagli script one-shot) e stringhe di comando
-- riusabili in async dal monitor (M.cmd_*).

function M.cmd_getWorkspace(path)  return M.cmq() .. ' getworkspacefrompath ' .. M.q(path) end
function M.cmd_fileInfo(path)      return M.cmq() .. ' fileinfo ' .. M.q(path) .. ' --format="' .. M.FILEINFO_FORMAT .. '"' end
function M.cmd_history(path)       return M.cmq() .. ' history ' .. M.q(path) .. ' --format="{changesetid}"' end
function M.cmd_whoami()            return M.cmq() .. ' whoami' end

function M.isInWorkspace(path)
  local code = M.run(M.cmd_getWorkspace(path))
  return code == 0
end

function M.getWorkspaceRoot(dir)
  local code, out = M.run(M.cmq() .. ' wk', dir)
  if code ~= 0 then return nil end
  -- output: "wkname@machine root_path" -> secondo blocco
  local root = M.trim(out):match('%S+%s+(%S.*)$')
  return root and M.trim(root) or nil
end

function M.fileInfo(path)
  local code, out = M.run(M.cmd_fileInfo(path))
  if code ~= 0 then return nil, out end
  local info = M.parseFileInfo(out)
  if not info then return nil, out end
  return info
end

-- Best effort: ultimo changeset del file sul server. nil se non determinabile.
function M.serverHead(path)
  local code, out = M.run(M.cmd_history(path))
  if code ~= 0 then return nil end
  return M.parseMaxChangeset(out)
end

function M.getUser()
  local cached = M.getRT('whoami')
  if cached ~= '' then return cached end
  local code, out = M.run(M.cmd_whoami())
  if code ~= 0 then return nil end
  local user = M.trim(out):match('[^\r\n]+')
  if user then M.setRT('whoami', user) end
  return user
end

function M.update(dir)
  return M.run(M.cmq() .. ' partial update', dir)
end

function M.undoChanges(dir)
  return M.run(M.cmq() .. ' undo -R ' .. M.q(dir))
end

function M.undoCheckout(dir)
  return M.run(M.cmq() .. ' partial undocheckout ' .. M.q(dir))
end

function M.checkout(dir)
  local code, out = M.run(M.cmq() .. ' co -R ' .. M.q(dir))
  if M.containsExclusiveCheckout(out) then
    return false, M.extractLockOwner(out) or '?', out
  end
  if code ~= 0 then return false, nil, out end
  return true, nil, out
end

function M.add(dir)
  -- aggiunge i file nuovi; errori su file già tracciati sono attesi e ignorati
  return M.run(M.cmq() .. ' add -R ' .. M.q(dir))
end

local function sanitizeComment(comment)
  comment = tostring(comment or ''):gsub('"', "'")
  if M.is_windows then
    -- caratteri speciali di cmd/bat
    comment = comment:gsub('[%%%^&<>|]', ' ')
  end
  return comment
end

-- Ritorna ok(bool), messaggio errore
function M.checkin(dir, comment)
  comment = sanitizeComment(comment)

  -- 1. Pre-pulizia: marca per delete i file già "Removed locally"
  --    (tracciati ma cancellati dal disco) prima di pagare un checkin completo.
  local scode, sout = M.run(M.cmq() .. ' partial status ' .. M.q(dir))
  if scode == 0 then
    for line in (sout .. '\n'):gmatch('(.-)\n') do
      -- Status "Removed locally", poi size (numero+virgole, unità), poi il path.
      -- Il path può contenere spazi: lo prendiamo "dal size in poi".
      local path = line:match('^%s*Removed locally%s+[%d,]+%s+%a+%s+(.+)$')
      if path then
        M.run(M.cmq() .. ' remove ' .. M.q(M.trim(path)))
      end
    end
  end

  -- 2. Checkin. Il ciclo resta solo come rete di sicurezza per i file
  --    checked-out spariti dal disco che lo status non segnala ancora.
  for attempt = 1, 5 do
    local code, out = M.run(
      M.cmq() .. ' partial checkin ' .. M.q(dir) .. ' -c="' .. comment .. '" --applychanged')

    local has_error = (code ~= 0) or out:find('\nError:') or out:match('^Error:')
    if not has_error then return true end

    -- recupero: rimuovi TUTTI i file cancellati riportati nell'errore (non uno solo)
    local removed = 0
    for missing in out:gmatch('The changed (.-) is not on disk') do
      M.run(M.cmq() .. ' remove ' .. M.q(M.trim(missing)))
      removed = removed + 1
    end

    if removed == 0 then
      return false, out  -- errore non recuperabile
    end
  end

  return false, 'too many recovery attempts during check-in'
end

-- ------------------------------------------------- flusso checkout completo --
-- Chiude il progetto, scarta modifiche locali, aggiorna alla versione server,
-- fa checkout esclusivo (lock) e riapre il progetto.
-- Usato sia da mtt_plastic_checkout che da mtt_plastic_save.
-- Ritorna ok(bool), messaggio.

function M.doCheckoutFlow(proj_path, opts)
  opts = opts or {}
  local dir = M.dirname(proj_path)
  if not dir then return false, 'invalid project path' end

  if not M.isInWorkspace(proj_path) then
    return false, 'Project is not inside a Plastic workspace.'
  end

  -- chiudi la tab del progetto per liberare i file
  reaper.Main_OnCommand(40860, 0) -- Close current project tab

  if not opts.keep_local then
    M.undoChanges(dir)
  end

  M.update(dir)

  local ok, who, out = M.checkout(dir)

  -- riapri il progetto (versione appena aggiornata)
  reaper.Main_openProject('noprompt:' .. proj_path)

  M.markDirty()

  if not ok then
    if who then
      return false, 'Project locked by: ' .. who .. '\nUpdated to server version, but without lock.'
    end
    return false, 'Checkout failed:\n' .. tostring(out)
  end
  return true, 'Project updated and checked out (lock acquired).'
end

-- ------------------------------------------------- flussi interattivi ------
-- Flussi completi con message box: usati sia dagli script one-shot che dal
-- menu del monitor. Caricando solo il monitor si ha accesso a tutto.

function M.doCheckinFlow(proj_path)
  local title = 'MTT Plastic Check-in'

  if not proj_path or proj_path == '' then
    reaper.ShowMessageBox('The project has never been saved.', title, 0)
    return
  end

  local dir = M.dirname(proj_path)

  if not M.isInWorkspace(proj_path) then
    reaper.ShowMessageBox('The project is not inside a Plastic workspace.', title, 0)
    return
  end

  local info = M.fileInfo(proj_path)
  if info and not info.checked_out then
    reaper.ShowMessageBox(
      'The project is not checked out: nothing to commit.\nPlease checkout first.', title, 0)
    return
  end

  local proj_name = reaper.GetProjectName(0, ''):gsub('%.[Rr][Pp][Pp]$', '')
  local template  = M.getSetting('comment_template', '$PROJECT Update')
  local default   = template:gsub('%$PROJECT', proj_name)

  local ok, comment = reaper.GetUserInputs(title, 1, 'Comment:,extrawidth=250', default)
  if not ok then return end
  if M.trim(comment) == '' then comment = default end

  reaper.Main_OnCommand(40026, 0) -- File: Save project
  M.add(dir)

  local success, err = M.checkin(dir, comment)
  M.markDirty()

  if success then
    reaper.ShowMessageBox('Check-in completed. Lock released.', title, 0)
  else
    reaper.ShowMessageBox('Check-in FAILED:\n\n' .. tostring(err), title, 0)
  end
end

function M.doCheckoutInteractive(proj_path)
  local title = 'MTT Plastic Check-out'

  if not proj_path or proj_path == '' then
    reaper.ShowMessageBox('The project has never been saved.', title, 0)
    return
  end

  if not M.isInWorkspace(proj_path) then
    reaper.ShowMessageBox('The project is not inside a Plastic workspace.', title, 0)
    return
  end

  local info = M.fileInfo(proj_path)

  if info and info.checked_out then
    reaper.ShowMessageBox('The project is already checked out.', title, 0)
    return
  end

  -- lock in un altro workspace (anche stesso account su altra macchina)
  if info and info.locked_by ~= '' then
    local where = info.locked_where ~= '' and (' @ ' .. info.locked_where) or ''
    reaper.ShowMessageBox('Project locked by: ' .. info.locked_by .. where, title, 0)
    return
  end

  local answer = reaper.ShowMessageBox(
    'This operation will:\n' ..
    '  1. discard uncommitted local changes\n' ..
    '  2. update the project to the server version\n' ..
    '  3. perform checkout + lock\n' ..
    '  4. reopen the project\n\n' ..
    'Continue?', title, 1) -- OK / Cancel
  if answer ~= 1 then return end

  local _, msg = M.doCheckoutFlow(proj_path)
  reaper.ShowMessageBox(msg, title, 0)
end

function M.doRevertFlow(proj_path)
  local title = 'MTT Plastic Revert'

  if not proj_path or proj_path == '' then
    reaper.ShowMessageBox('The project has never been saved.', title, 0)
    return
  end

  if not M.isInWorkspace(proj_path) then
    reaper.ShowMessageBox('The project is not inside a Plastic workspace.', title, 0)
    return
  end

  local answer = reaper.ShowMessageBox(
    'Are you sure you want to revert to the server version?\n\n' ..
    'This operation will:\n' ..
    '  1. discard ALL local changes\n' ..
    '  2. release any checkout/lock\n' ..
    '  3. restore the project to the server version\n' ..
    '  4. reopen the project\n\n' ..
    'Continue?', title, 1) -- OK / Cancel
  if answer ~= 1 then return end

  local dir = M.dirname(proj_path)

  reaper.Main_OnCommand(40860, 0) -- Close current project tab
  M.undoChanges(dir)
  M.undoCheckout(dir)
  M.update(dir)
  reaper.Main_openProject('noprompt:' .. proj_path)
  M.markDirty()

  reaper.ShowMessageBox('Project restored to server version.', title, 0)
end

function M.doSettingsFlow()
  local title = 'MTT Plastic - Settings'

  local cur_cm       = M.getSetting('cm_path', '')
  local cur_interval = M.getSetting('poll_interval', '5')
  local cur_template = M.getSetting('comment_template', '$PROJECT Update')
  local detected     = M.findCm()

  local captions =
    'cm path (empty = auto),' ..
    'Monitor refresh interval (s),' ..
    'Check-in comment template,' ..
    'extrawidth=280'
  local defaults = cur_cm .. ',' .. cur_interval .. ',' .. cur_template

  local ok, csv = reaper.GetUserInputs(title, 3, captions, defaults)
  if not ok then return end

  -- il template è l'ultimo campo: cattura anche eventuali virgole residue
  local cm_path, interval, template = csv:match('^(.-),(.-),(.*)$')

  cm_path  = M.trim(cm_path or '')
  interval = tostring(tonumber(M.trim(interval or '')) or 5)
  template = M.trim(template or '')
  if template == '' then template = '$PROJECT Update' end

  if cm_path ~= '' and not M.fileExists(cm_path) then
    reaper.ShowMessageBox(
      'Warning: the specified cm path does not exist:\n' .. cm_path ..
      '\n\nSaved anyway, but auto-detect will be used.', title, 0)
  end

  M.setSetting('cm_path', cm_path)
  M.setSetting('poll_interval', interval)
  M.setSetting('comment_template', template)

  local code, out = M.run(M.cmq() .. ' version')
  local first = M.trim(out):match('[^\r\n]+') or ''

  if code == 0 then
    reaper.ShowMessageBox(
      'Settings saved.\n\ncm in use: ' .. (cm_path ~= '' and cm_path or detected) ..
      '\ncm version: ' .. first, title, 0)
  else
    reaper.ShowMessageBox(
      'Settings saved, but cm does not respond.\n\nPath tried: ' ..
      (cm_path ~= '' and cm_path or detected) .. '\nError: ' .. first ..
      '\n\nCheck that Plastic SCM / Unity VCS is installed.', title, 0)
  end

  M.markDirty()
end

-- --------------------------------------------------------- stati condivisi --

M.STATE = {
  UNSAVED     = 'unsaved',        -- project never saved
  NOT_IN_REPO = 'not_in_repo',    -- outside a Plastic workspace
  OUT_OF_DATE = 'out_of_date',    -- in repo but not on latest version
  AVAILABLE   = 'available',      -- up to date, no lock, checkout available
  LOCKED      = 'locked',         -- locked by another user
  CHECKED_OUT = 'checked_out',    -- in our checkout+lock
  UNKNOWN     = 'unknown',
}

M.STATE_LABEL = {
  [M.STATE.UNSAVED]     = 'Project not saved',
  [M.STATE.NOT_IN_REPO] = 'Outside a Plastic workspace',
  [M.STATE.OUT_OF_DATE] = 'In repo - NOT up to date',
  [M.STATE.AVAILABLE]   = 'In repo - up to date, checkout available',
  [M.STATE.LOCKED]      = 'Locked by another user',
  [M.STATE.CHECKED_OUT] = 'Checked out',
  [M.STATE.UNKNOWN]     = 'Unknown state',
}

return M

