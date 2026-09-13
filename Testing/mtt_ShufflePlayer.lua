--[[
  SFX Preview
  Renderizza gli item selezionati in file audio temporanei e li riproduce
  in loop randomizzato tramite un JSFX generato al volo sulla master track.

  Requisiti: REAPER 6.x+ , ReaImGui (ReaPack).
--]]

local r = reaper

--------------------------------------------------------------------------------
-- Dipendenze
--------------------------------------------------------------------------------

if not r.APIExists('ImGui_GetBuiltinPath') then
  r.MB('ReaImGui non e installato.\nInstallalo da ReaPack (ReaTeam Extensions).',
       'SFX Preview', 0)
  return
end

package.path = r.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.10'

--------------------------------------------------------------------------------
-- Costanti / percorsi
--------------------------------------------------------------------------------

local IS_WIN     = r.GetOS():find('Win') ~= nil
local SEP        = IS_WIN and '\\' or '/'
local RES        = r.GetResourcePath()

local TMP_DIR    = RES .. SEP .. 'SFX_Preview_tmp'
local EFFECTS_DIR= RES .. SEP .. 'Effects'
local JSFX_FILE  = 'SFX_Preview_Player_SFP.jsfx'   -- nome file dentro Effects/
local JSFX_PATH  = EFFECTS_DIR .. SEP .. JSFX_FILE
local JSFX_DESC  = 'SFX Preview Player SFP'
local PREFIX     = 'SFXPRV_'                        -- prefisso dei render temporanei
local GMEM_NAME  = 'SFP_RATE'
local MAX_ITEMS  = 256                              -- limite imposto dal layout memoria JSFX
local RENDER_ACT = 42230 -- File: Render project, using most recent settings, auto-close dialog

--------------------------------------------------------------------------------
-- Stato
--------------------------------------------------------------------------------

local state = {
  rate_ms    = 500,
  file_count = 0,
  gmem_ok    = false,
  msg        = '',
}

local rs = {
  phase   = 'idle',   -- idle | rendering
  items   = {},
  idx     = 0,
  files   = {},       -- percorsi assoluti dei file renderizzati
  pending = nil,      -- basename atteso dal render corrente
  wait    = 0,        -- contatore di timeout
}

local saved_render = nil  -- impostazioni di render salvate

--------------------------------------------------------------------------------
-- Utility filesystem (via API REAPER: niente io.popen, funziona anche su Windows)
--------------------------------------------------------------------------------

local function list_files(dir)
  local out = {}
  if dir == '' then return out end
  local i = 0
  while true do
    local f = r.EnumerateFiles(dir, i)
    if not f then break end
    out[#out + 1] = f
    i = i + 1
  end
  return out
end

-- Cancella SOLO i file temporanei creati da questo script (mai wildcard generiche)
local function delete_temp_files()
  local files = list_files(TMP_DIR)   -- prima raccolgo, poi cancello
  for _, f in ipairs(files) do
    if f:sub(1, #PREFIX) == PREFIX then
      os.remove(TMP_DIR .. SEP .. f)
    end
  end
end

local function find_rendered(basename)
  for _, f in ipairs(list_files(TMP_DIR)) do
    if f:sub(1, #basename) == basename then
      return TMP_DIR .. SEP .. f
    end
  end
  return nil
end

--------------------------------------------------------------------------------
-- Gestione JSFX sulla master
--------------------------------------------------------------------------------

local function fx_name_at(track, i)
  local a, b = r.TrackFX_GetFXName(track, i, '')
  if type(a) == 'string' then return a end
  return b or ''
end

local function remove_jsfx()
  local master = r.GetMasterTrack(0)
  if not master then return end
  local count = r.TrackFX_GetCount(master)
  for i = count - 1, 0, -1 do   -- a ritroso: cancellare sposta gli indici
    if fx_name_at(master, i):find('SFP', 1, true) then
      r.TrackFX_Delete(master, i)
    end
  end
end

--------------------------------------------------------------------------------
-- Cleanup completo
--------------------------------------------------------------------------------

local function full_cleanup()
  remove_jsfx()
  if state.gmem_ok then
    r.gmem_attach('')       -- stringa vuota = detach
    state.gmem_ok = false
  end
  delete_temp_files()
  os.remove(JSFX_PATH)      -- cancello solo IL MIO file, non tutta la cartella
  state.file_count = 0
end

--------------------------------------------------------------------------------
-- Impostazioni di render: salvataggio e ripristino
--------------------------------------------------------------------------------

local function save_render_settings()
  if saved_render then return end
  local s = {}
  s.bounds   = r.GetSetProjectInfo(0, 'RENDER_BOUNDSFLAG', 0, false)
  s.settings = r.GetSetProjectInfo(0, 'RENDER_SETTINGS',   0, false)
  s.tail     = r.GetSetProjectInfo(0, 'RENDER_TAILFLAG',   0, false)
  local _, f = r.GetSetProjectInfo_String(0, 'RENDER_FILE',    '', false)
  local _, p = r.GetSetProjectInfo_String(0, 'RENDER_PATTERN', '', false)
  s.file, s.pattern = f, p
  s.ts_start, s.ts_end = r.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
  saved_render = s
end

local function restore_render_settings()
  local s = saved_render
  if not s then return end
  r.GetSetProjectInfo(0, 'RENDER_BOUNDSFLAG', s.bounds,   true)
  r.GetSetProjectInfo(0, 'RENDER_SETTINGS',   s.settings, true)
  r.GetSetProjectInfo(0, 'RENDER_TAILFLAG',   s.tail,     true)
  r.GetSetProjectInfo_String(0, 'RENDER_FILE',    s.file,    true)
  r.GetSetProjectInfo_String(0, 'RENDER_PATTERN', s.pattern, true)
  r.GetSet_LoopTimeRange2(0, true, false, s.ts_start, s.ts_end, false)
  saved_render = nil
end

--------------------------------------------------------------------------------
-- Selezione item
--------------------------------------------------------------------------------

local function get_selected_items()
  local items = {}
  for i = 0, r.CountSelectedMediaItems(0) - 1 do
    local it = r.GetSelectedMediaItem(0, i)
    items[#items + 1] = {
      handle   = it,
      position = r.GetMediaItemInfo_Value(it, 'D_POSITION'),
      length   = r.GetMediaItemInfo_Value(it, 'D_LENGTH'),
    }
  end
  return items
end

--------------------------------------------------------------------------------
-- Generazione del JSFX
--------------------------------------------------------------------------------

local function generate_jsfx(paths)
  local n = #paths

  local loads = {}
  for i, p in ipairs(paths) do
    -- EEL usa "\" come escape: normalizzo a "/" (accettato anche su Windows)
    local jp = (p:gsub('\\', '/'))
    loads[#loads + 1] = ([[
fh = file_open("%s");
fh >= 0 ? (
  file_riff(fh, nch, fsr);
  nch > 0 ? (
    avail = file_avail(fh);
    avail > memtop - ptr ? avail = memtop - ptr;
    avail >= nch ? (
      file_mem(fh, ptr, avail);
      base_arr[%d] = ptr;
      nch_arr[%d]  = nch;
      sr_arr[%d]   = fsr;
      frm_arr[%d]  = floor(avail / nch);
      ptr += avail;
    );
  );
  file_close(fh);
);]]):format(jp, i - 1, i - 1, i - 1, i - 1)
  end

  return ([[
desc:%s (auto-generato dallo script SFX Preview - non modificare)
options:gmem=%s maxmem=32000000

in_pin:Left
in_pin:Right
out_pin:Left
out_pin:Right

@init
N = %d;

// layout memoria: 6 array da 256 slot, poi i campioni audio
base_arr = 0;
nch_arr  = 256;
sr_arr   = 512;
frm_arr  = 768;
pos_arr  = 1024;
order    = 1280;
ptr      = 2048;
memtop   = __memtop();

i = 0;
loop(N,
  base_arr[i] = 0;
  nch_arr[i]  = 0;
  sr_arr[i]   = srate;
  frm_arr[i]  = 0;
  pos_arr[i]  = -1;   // -1 = non in riproduzione
  order[i]    = i;
  i += 1;
);

%s

shuffle_pos = 0;
timer_cnt   = 0;
rate_smp    = srate / 2;

@block
// gmem[0] e' il rate in ms scritto dallo script Lua
rate_ms = gmem[0];
rate_ms < 20    ? rate_ms = 20;
rate_ms > 10000 ? rate_ms = 10000;
rate_smp = rate_ms * srate / 1000;

@sample
timer_cnt += 1;
timer_cnt >= rate_smp ? (
  timer_cnt = 0;
  N > 0 ? (
    cur = order[shuffle_pos];
    frm_arr[cur] > 0 ? pos_arr[cur] = 0;
    shuffle_pos += 1;
    shuffle_pos >= N ? (
      shuffle_pos = 0;
      // rimescolo (Fisher-Yates) quando la lista e' esaurita
      i = N - 1;
      loop(N - 1,
        j = rand(i + 1) | 0;
        tmp = order[i]; order[i] = order[j]; order[j] = tmp;
        i -= 1;
      );
    );
  );
);

// somma di tutte le voci attive
i = 0;
loop(N,
  p = pos_arr[i];
  p >= 0 ? (
    b  = base_arr[i];
    nc = nch_arr[i];
    fr = frm_arr[i];
    ip = p | 0;
    fc = p - ip;
    i2 = ip + 1;
    i2 >= fr ? i2 = ip;
    a1 = b + ip * nc;
    a2 = b + i2 * nc;
    lv = a1[0] * (1 - fc) + a2[0] * fc;
    nc > 1 ? (
      rv = a1[1] * (1 - fc) + a2[1] * fc;
    ) : (
      rv = lv;
    );
    spl0 += lv;
    spl1 += rv;
    p += sr_arr[i] / srate;   // resampling lineare se sr file != sr progetto
    p >= fr ? p = -1;
    pos_arr[i] = p;
  );
  i += 1;
);
]]):format(JSFX_DESC, GMEM_NAME, n, table.concat(loads, '\n'))
end

local function install_jsfx(src)
  r.RecursiveCreateDirectory(EFFECTS_DIR, 0)

  local f = io.open(JSFX_PATH, 'w')
  if not f then return false, 'Impossibile scrivere ' .. JSFX_PATH end
  f:write(src)
  f:close()

  local master = r.GetMasterTrack(0)
  remove_jsfx()   -- evita duplicati e forza il ricaricamento del file

  local idx = r.TrackFX_AddByName(master, JSFX_FILE, false, -1)
  if idx < 0 then
    idx = r.TrackFX_AddByName(master, 'JS: ' .. JSFX_DESC, false, -1)
  end
  if idx < 0 then return false, 'Impossibile inserire il JSFX sulla master' end

  r.gmem_attach(GMEM_NAME)
  state.gmem_ok = true
  r.gmem_write(0, state.rate_ms)
  return true
end

--------------------------------------------------------------------------------
-- Render asincrono
--------------------------------------------------------------------------------

local function render_current()
  local it = rs.items[rs.idx]
  if not it then return end
  r.GetSet_LoopTimeRange2(0, true, false, it.position, it.position + it.length, false)
  local name = ('%s%03d'):format(PREFIX, rs.idx)
  r.GetSetProjectInfo_String(0, 'RENDER_PATTERN', name, true)
  rs.pending = name
  rs.wait    = 0
  r.Main_OnCommand(RENDER_ACT, 0)
end

local function start_render(items)
  save_render_settings()
  r.RecursiveCreateDirectory(TMP_DIR, 0)
  full_cleanup()

  r.GetSetProjectInfo(0, 'RENDER_BOUNDSFLAG', 2, true)  -- 2 = time selection
  r.GetSetProjectInfo(0, 'RENDER_SETTINGS',   0, true)  -- 0 = master mix
  r.GetSetProjectInfo(0, 'RENDER_TAILFLAG',   0, true)  -- niente coda
  r.GetSetProjectInfo_String(0, 'RENDER_FILE', TMP_DIR, true)

  rs.items = items
  rs.idx   = 1
  rs.files = {}
  rs.phase = 'rendering'
  state.msg = ''
  render_current()
end

local function finish_render()
  rs.phase = 'idle'
  restore_render_settings()

  if #rs.files == 0 then
    state.msg = 'Nessun file renderizzato.'
    return
  end
  local ok, err = install_jsfx(generate_jsfx(rs.files))
  if ok then
    state.file_count = #rs.files
    state.msg = ''
  else
    state.msg = err or 'Errore installazione JSFX'
  end
end

local function check_render()
  if rs.phase ~= 'rendering' or not rs.pending then return end

  local path = find_rendered(rs.pending)
  if not path then
    rs.wait = rs.wait + 1
    if rs.wait > 600 then   -- ~20 s a 30 fps
      rs.phase = 'idle'
      restore_render_settings()
      state.msg = 'Timeout durante il render.'
    end
    return
  end

  rs.files[#rs.files + 1] = path
  rs.pending = nil
  rs.idx = rs.idx + 1

  if rs.items[rs.idx] then
    render_current()
  else
    finish_render()
  end
end

--------------------------------------------------------------------------------
-- Cleanup all'uscita (finestra chiusa, script fermato, REAPER chiuso)
--------------------------------------------------------------------------------

r.atexit(function()
  restore_render_settings()
  full_cleanup()
end)

--------------------------------------------------------------------------------
-- Interfaccia
--------------------------------------------------------------------------------

local ctx = ImGui.CreateContext('SFX Preview')

-- pulizia di eventuali residui di una sessione precedente
full_cleanup()

--------------------------------------------------------------------------------
-- Stile (ripreso da mtt_Shelf.lua: push prima di Begin, pop dopo End)
--------------------------------------------------------------------------------

local function apply_style()
  local col = r.ImGui_ColorConvertDouble4ToU32

  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), col(0.1, 0.1, 0.1, 1))
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), col(0.45, 0.45, 0.45, 2))
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_BorderShadow(), col(0, 0, 0, 2))

  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), col(0.1, 0.1, 0.1, 2))
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), col(0.1, 0.1, 0.1, 2))
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), col(0.18, 0.18, 0.18, 2))
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_MenuBarBg(), col(0.1, 0.1, 0.1, 2))

  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), col(0.18, 0.18, 0.18, 2))
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), col(0.3, 0.3, 0.3, 2))
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), col(0.18, 0.18, 0.18, 2))

  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ResizeGrip(), col(0.1, 0.1, 0.1, 2))
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ResizeGripActive(), col(0.3, 0.3, 0.3, 2))
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ResizeGripHovered(), col(0.18, 0.18, 0.18, 2))

  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBg(), col(0.14, 0.14, 0.14, 2))
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgActive(), col(0.18, 0.18, 0.18, 2))
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgCollapsed(), col(0.18, 0.18, 0.18, 2))

  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), col(0.2, 0.2, 0.2, 2))
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), col(0.4, 0.4, 0.4, 2))
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), col(0.25, 0.25, 0.25, 2))
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), col(0.5, 0.5, 0.5, 2))
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), col(0.13, 0.13, 0.13, 2))

  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), col(0.8, 0.8, 0.8, 2))
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(), col(0.35, 0.35, 0.35, 2))

  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ScrollbarSize(), 10)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ScrollbarBg(), col(0.09, 0.09, 0.09, 1))
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ScrollbarGrab(), col(0.3, 0.3, 0.3, 1))
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ScrollbarGrabActive(), col(0.2, 0.2, 0.2, 1))
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ScrollbarGrabHovered(), col(0.5, 0.5, 0.5, 1))

  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 7)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ScrollbarRounding(), 7)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), 7)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ChildRounding(), 7)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 5)
end

local function pop_style()
  for _ = 1, 6 do
    r.ImGui_PopStyleVar(ctx)
  end
  for _ = 1, 27 do
    r.ImGui_PopStyleColor(ctx)
  end
end

local LOG_MIN, LOG_MAX = math.log(30), math.log(4000)

local function draw()
  -- Fader rate 40 - 4000 ms, scala logaritmica
  local rv, new_log = ImGui.SliderDouble(ctx, 'Rate', math.log(state.rate_ms),
                                         LOG_MIN, LOG_MAX,
                                         ('%d ms'):format(state.rate_ms))
  if rv then
    state.rate_ms = math.floor(math.exp(new_log) + 0.5)
    if state.gmem_ok then r.gmem_write(0, state.rate_ms) end
  end

  -- Stato
  local status
  if rs.phase == 'rendering' then
    status = ('Render %d/%d...'):format(rs.idx, #rs.items)
  elseif state.file_count > 0 then
    status = ('%d file caricati - in riproduzione'):format(state.file_count)
  else
    status = 'Seleziona degli item e premi Render & Start'
  end
  ImGui.Text(ctx, status)
  if state.msg ~= '' then ImGui.Text(ctx, state.msg) end

  -- Pulsanti
  ImGui.BeginDisabled(ctx, rs.phase == 'rendering')
  if ImGui.Button(ctx, 'Render & Start', 150, 0) then
    local items = get_selected_items()
    if #items == 0 then
      state.msg = 'Nessun item selezionato.'
    else
      if #items > MAX_ITEMS then
        for i = #items, MAX_ITEMS + 1, -1 do items[i] = nil end
        state.msg = ('Limite di %d item: gli altri sono stati ignorati.'):format(MAX_ITEMS)
      end
      start_render(items)
    end
  end
  ImGui.EndDisabled(ctx)

  ImGui.SameLine(ctx)
  ImGui.BeginDisabled(ctx, state.file_count == 0 and rs.phase == 'idle')
  if ImGui.Button(ctx, 'Stop & Clear', 150, 0) then
    rs.phase = 'idle'
    rs.pending = nil
    restore_render_settings()
    full_cleanup()
  end
  ImGui.EndDisabled(ctx)
end

local function loop()
  check_render()

  apply_style()   -- push prima di Begin (cosi copre anche la title bar)
  ImGui.SetNextWindowSize(ctx, 420, 170, ImGui.Cond_FirstUseEver)
  local visible, open = ImGui.Begin(ctx, 'SFX Preview', true)
  if visible then
    draw()
    ImGui.End(ctx)
  end
  pop_style()     -- pop dopo End: sempre, anche a finestra collassata

  if open then r.defer(loop) end   -- chiudendo la finestra lo script termina
end

r.defer(loop)
