-- mtt_plastic_monitor.lua
-- Monitor sempre attivo: SOLO un pallino colorato sopra la GUI di REAPER.
--
--   click sinistro  -> menu con azioni (Check-In / Check-Out / Revert / ...)
--   trascina        -> riposiziona (posizione ricordata)
--   hover           -> tooltip con stato
--
-- Ancoraggio: se js_ReaScriptAPI è installata, la posizione è salvata come
-- OFFSET dall'angolo alto-destra della finestra REAPER: trascina il pallino
-- una volta accanto al bottone "Monitoring FX" e resterà incollato lì anche
-- spostando/ridimensionando la finestra. Senza estensione JS: posizione
-- assoluta salvata (non segue la finestra).
--
-- Caricando SOLO questo script si ha accesso a tutte le azioni (i flussi
-- stanno in mtt_plastic_lib.lua, gli altri script sono wrapper opzionali).
--
-- Colori:
--   grigio  : progetto non salvato
--   rosso   : fuori da un workspace Plastic
--   arancio : lockato in un altro workspace
--   blu     : in repo ma NON aggiornato all'ultima versione
--   verde   : in repo, aggiornato, checkout disponibile
--   giallo  : in checkout + lock (tuo)

local script_dir = debug.getinfo(1, 'S').source:match('@(.*)[/\\]')
local LIB = dofile(script_dir .. '/mtt_plastic_lib.lua')

-- ---------------------------------------------------------------- ReaImGui --

local imgui_ok = pcall(function()
  dofile(reaper.GetResourcePath() .. '/Scripts/ReaTeam Extensions/API/imgui.lua')('0.10')
end)

if not imgui_ok or not reaper.ImGui_CreateContext then
  reaper.ShowMessageBox(
    'ReaImGui not found.\nGet it from ReaPack (ReaTeam Extensions).',
    'MTT Plastic Monitor', 0)
  return
end

local ctx = reaper.ImGui_CreateContext('MTT Plastic Monitor')

local has_js    = reaper.JS_Window_GetRect ~= nil
local main_hwnd = reaper.GetMainHwnd()

-- ------------------------------------------------------------------- stato --

local S = LIB.STATE

local state          = S.UNKNOWN
local state_detail   = ''
local busy           = false
local busy_since     = 0
local last_path      = nil
local last_refresh   = 0
local first_run      = true
local refresh_path   = ''
local need_refresh   = false
local refresh_gen    = 0    -- invalida i callback dei refresh superati

local want_quit      = false
local pending_action = nil
local drag_candidate = false
local press_x, press_y = nil, nil

local DOT_SIZE = 10

local function pollInterval()
  return tonumber(LIB.getSetting('poll_interval', '5')) or 5
end

local function publish()
  LIB.setRT('state', state)
  LIB.setRT('state_detail', state_detail)
  LIB.setRT('state_path', refresh_path) -- a quale progetto si riferisce lo stato
end

-- --------------------------------------------------------- refresh (async) --

local function finish(new_state, detail)
  state        = new_state
  state_detail = detail or ''
  busy         = false
  publish()
end

local function startRefresh()
  local _, proj_path = reaper.EnumProjects(-1, '')
  refresh_path = proj_path

  refresh_gen = refresh_gen + 1
  local gen = refresh_gen

  -- i callback di un refresh superato (progetto cambiato nel frattempo)
  -- non devono pubblicare nulla
  local function alive() return gen == refresh_gen end

  if proj_path == '' then
    finish(S.UNSAVED)
    return
  end

  busy       = true
  busy_since = reaper.time_precise()

  -- 1) siamo in un workspace?
  LIB.runAsync(LIB.cmd_getWorkspace(proj_path), nil, function(code)
    if not alive() then return end
    if code ~= 0 then
      finish(S.NOT_IN_REPO)
      return
    end

    -- 2) stato del file di progetto
    LIB.runAsync(LIB.cmd_fileInfo(proj_path), nil, function(code2, out2)
      if not alive() then return end
      if code2 ~= 0 then
        finish(S.UNKNOWN, 'fileinfo failed')
        return
      end
      local info = LIB.parseFileInfo(out2)
      if not info then
        finish(S.UNKNOWN, 'unrecognized fileinfo output')
        return
      end

      if info.checked_out then
        finish(S.CHECKED_OUT)
        return
      end

      -- Non in checkout locale ma lock presente: il lock sta in un ALTRO
      -- workspace. Vale anche con lo stesso account su due macchine
      -- (il lock di Plastic e' per workspace, non per utente).
      if info.locked_by ~= '' then
        local where = info.locked_where ~= '' and (' @ ' .. info.locked_where) or ''
        finish(S.LOCKED, info.locked_by .. where)
        return
      end

      -- 3) siamo aggiornati? (best effort, confronto changeset)
      LIB.runAsync(LIB.cmd_history(proj_path), nil, function(code3, out3)
        if not alive() then return end
        if code3 ~= 0 then
          finish(S.AVAILABLE, 'stato aggiornamento non verificabile')
          return
        end
        local head = LIB.parseMaxChangeset(out3)
        if head and info.local_cs and head > info.local_cs then
          finish(S.OUT_OF_DATE, 'locale cs:' .. info.local_cs .. ' / server cs:' .. head)
        else
          finish(S.AVAILABLE)
        end
      end)
    end)
  end)
end

-- ------------------------------------------------------------------ colori --

local COL = {
  [S.UNSAVED]     = { 0.6, 0.6, 0.6 },
  [S.NOT_IN_REPO] = { 1.0, 0.2, 0.2 },
  [S.LOCKED]      = { 1.0, 0.55, 0.1 },
  [S.OUT_OF_DATE] = { 0.3, 0.6, 1.0 },
  [S.AVAILABLE]   = { 0.2, 1.0, 0.2 },
  [S.CHECKED_OUT] = { 1.0, 1.0, 0.2 },
  [S.UNKNOWN]     = { 0.8, 0.8, 0.8 },
}

local function stateColor()
  local c = COL[state] or COL[S.UNKNOWN]
  return reaper.ImGui_ColorConvertDouble4ToU32(c[1], c[2], c[3], 1)
end

local function stateLabel()
  local label = LIB.STATE_LABEL[state] or state
  --if busy then label = label .. '  (aggiorno...)' end
  return label
end

-- -------------------------------------------------------------- ancoraggio --
-- Ritorna la posizione (x, y) dell'angolo alto-destra della finestra REAPER
-- in coordinate ImGui, oppure nil se js_ReaScriptAPI non è disponibile.

local function anchorCorner()
  if not has_js then return nil end
  local ok, l, t, r, b = reaper.JS_Window_GetRect(main_hwnd)
  if not ok then return nil end
  -- su mac le coordinate native hanno la y invertita: converto entrambi gli
  -- angoli e prendo la y più in alto e la x più a destra
  local x1, y1 = reaper.ImGui_PointConvertNative(ctx, l, t, false)
  local x2, y2 = reaper.ImGui_PointConvertNative(ctx, r, b, false)
  return math.max(x1, x2), math.min(y1, y2)
end

local function desiredDotPos()
  local ax, ay = anchorCorner()
  if ax then
    local off_x = tonumber(LIB.getSetting('dot_off_x', '260')) or 260
    local off_y = tonumber(LIB.getSetting('dot_off_y', '6'))   or 6
    return ax - off_x, ay + off_y
  end
  local px = tonumber(LIB.getSetting('dot_x', ''))
  local py = tonumber(LIB.getSetting('dot_y', ''))
  return px, py -- può essere nil, nil al primo avvio
end

local function saveDotPos()
  local wx, wy = reaper.ImGui_GetWindowPos(ctx)
  local ax, ay = anchorCorner()
  if ax then
    LIB.setSetting('dot_off_x', math.floor(ax - wx))
    LIB.setSetting('dot_off_y', math.floor(wy - ay))
  else
    LIB.setSetting('dot_x', math.floor(wx))
    LIB.setSetting('dot_y', math.floor(wy))
  end
end

-- -------------------------------------------------------------------- menu --

local function drawMenu(proj_path)
  reaper.ImGui_TextDisabled(ctx, stateLabel())
  if state_detail ~= '' then
    reaper.ImGui_TextDisabled(ctx, state_detail)
  end
  reaper.ImGui_Separator(ctx)

  local in_repo      = state == S.AVAILABLE or state == S.OUT_OF_DATE
                    or state == S.CHECKED_OUT or state == S.LOCKED
  local can_checkout = state == S.AVAILABLE or state == S.OUT_OF_DATE
  local can_checkin  = state == S.CHECKED_OUT
  local can_revert   = in_repo

  if reaper.ImGui_MenuItem(ctx, 'Check-Out', nil, false, can_checkout) then
    pending_action = 'checkout'
  end
  if reaper.ImGui_MenuItem(ctx, 'Check-In', nil, false, can_checkin) then
    pending_action = 'checkin'
  end
  if reaper.ImGui_MenuItem(ctx, 'Revert', nil, false, can_revert) then
    pending_action = 'revert'
  end

  reaper.ImGui_Separator(ctx)

--[[   if reaper.ImGui_MenuItem(ctx, 'Refresh', nil, false, not busy) then
    startRefresh()
  end ]]
  if reaper.ImGui_MenuItem(ctx, 'Settings') then
    pending_action = 'settings'
  end

  reaper.ImGui_Separator(ctx)

  if reaper.ImGui_MenuItem(ctx, 'Quit') then
    want_quit = true
  end
end

-- --------------------------------------------------------------------- dot --

local function drawDot()
  local wx, wy = reaper.ImGui_GetWindowPos(ctx)
  local cx, cy = wx + DOT_SIZE, wy + DOT_SIZE
  local dl = reaper.ImGui_GetWindowDrawList(ctx)

  -- anello scuro per visibilita' su qualsiasi tema, poi pallino colorato
  reaper.ImGui_DrawList_AddCircleFilled(dl, cx, cy, 6,
    reaper.ImGui_ColorConvertDouble4ToU32(0.08, 0.08, 0.08, 0.9), 0)
  reaper.ImGui_DrawList_AddCircleFilled(dl, cx, cy, 4, stateColor(), 0)

  local hovered = reaper.ImGui_IsWindowHovered(ctx)

  if hovered and not reaper.ImGui_IsPopupOpen(ctx, 'mtt_plastic_menu') then
    local tip = stateLabel()
    if state_detail ~= '' then tip = tip .. '\n' .. state_detail end
    reaper.ImGui_SetTooltip(ctx, tip)
  end

  -- click sinistro senza trascinamento = apri menu; con trascinamento = sposta
  if hovered and reaper.ImGui_IsMouseClicked(ctx, 0) then
    drag_candidate = true
    press_x, press_y = reaper.ImGui_GetMousePos(ctx)
  end

  if drag_candidate and not reaper.ImGui_IsMouseDown(ctx, 0) then
    local mx, my = reaper.ImGui_GetMousePos(ctx)
    if press_x and math.abs(mx - press_x) < 4 and math.abs(my - press_y) < 4 then
      reaper.ImGui_OpenPopup(ctx, 'mtt_plastic_menu')
    else
      saveDotPos() -- fine trascinamento
    end
    drag_candidate = false
    press_x, press_y = nil, nil
  end

  if reaper.ImGui_BeginPopup(ctx, 'mtt_plastic_menu') then
    local _, proj_path = reaper.EnumProjects(-1, '')
    drawMenu(proj_path)
    reaper.ImGui_EndPopup(ctx)
  end
end

-- -------------------------------------------------------------------- loop --

local function loop()
  LIB.poll()  -- fa avanzare i job async

  local _, proj_path = reaper.EnumProjects(-1, '')
  local now = reaper.time_precise()

  -- watchdog: refresh appeso
  if busy and now - busy_since > 60 then busy = false end

  -- need_refresh è PERSISTENTE: se la richiesta arriva mentre un refresh è
  -- in corso (busy) non si perde, parte appena il precedente finisce.
  if first_run then need_refresh = true first_run = false end
  if proj_path ~= last_path then
    -- progetto cambiato/aperto: check immediato, e il refresh in corso
    -- (relativo al progetto vecchio) viene invalidato
    need_refresh = true
    busy = false
  end
  if LIB.getRT('dirty') == '1' then
    LIB.setRT('dirty', '0')
    need_refresh = true
  end
  if now - last_refresh > pollInterval() then need_refresh = true end

  last_path = proj_path

  if need_refresh and not busy then
    need_refresh = false
    last_refresh = now
    startRefresh()
  end

  -- posizionamento: forzato all'ancora, MA sospeso durante il trascinamento
  local dx, dy = desiredDotPos()
  if dx and dy and not drag_candidate then
    local cond = has_js and reaper.ImGui_Cond_Always() or reaper.ImGui_Cond_Once()
    reaper.ImGui_SetNextWindowPos(ctx, dx, dy, cond)
  end
  reaper.ImGui_SetNextWindowSize(ctx, DOT_SIZE, DOT_SIZE, reaper.ImGui_Cond_Always())

  local flags =
      reaper.ImGui_WindowFlags_NoTitleBar()
    | reaper.ImGui_WindowFlags_NoResize()
    | reaper.ImGui_WindowFlags_NoScrollbar()
    | reaper.ImGui_WindowFlags_NoScrollWithMouse()
    | reaper.ImGui_WindowFlags_NoCollapse()
    | reaper.ImGui_WindowFlags_NoDocking()
    | reaper.ImGui_WindowFlags_NoBackground()

  local visible = reaper.ImGui_Begin(ctx, 'MTT Plastic Dot', nil, flags)
  if visible then
    drawDot()
    reaper.ImGui_End(ctx)
  end

  -- azioni eseguite FUORI dal frame ImGui (aprono dialoghi modali)
  if pending_action then
    local act = pending_action
    pending_action = nil
    if     act == 'checkout' then LIB.doCheckoutInteractive(proj_path)
    elseif act == 'checkin'  then LIB.doCheckinFlow(proj_path)
    elseif act == 'revert'   then LIB.doRevertFlow(proj_path)
    elseif act == 'settings' then LIB.doSettingsFlow()
    end
  end

  if not want_quit then
    reaper.defer(loop)
  else
    LIB.setRT('state', '')
  end
end

reaper.defer(loop)

