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
  files      = {},    -- ultimo render completo, anche dopo Stop
  gmem_ok    = false,
  previous_gmem = '',
  msg        = '',
}

local rs = {
  phase   = 'idle',   -- idle | rendering
  items   = {},
  idx     = 0,
  files   = {},       -- percorsi assoluti dei file renderizzati
  pending = nil,      -- basename atteso dal render corrente
  wait    = 0,        -- contatore di timeout
  serial  = 0,
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

local function delete_render_files(paths)
  for _, path in ipairs(paths) do os.remove(path) end
end

local function find_rendered(basename)
  for _, f in ipairs(list_files(TMP_DIR)) do
    if f:sub(1, #basename + 1) == basename .. '.' then
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

local function stop_playback()
  if not state.gmem_ok then return end
  remove_jsfx()
  r.gmem_attach(state.previous_gmem)
  state.gmem_ok = false
end

local function discard_pending_render()
  if rs.pending then
    local path = find_rendered(rs.pending)
    if path then rs.files[#rs.files + 1] = path end
    rs.pending = nil
  end
  delete_render_files(rs.files)
  rs.files = {}
end

local function full_cleanup()
  stop_playback()
  discard_pending_render()
  delete_render_files(state.files)
  os.remove(JSFX_PATH)
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

  state.previous_gmem = r.gmem_attach(GMEM_NAME) or ''
  state.gmem_ok = true
  r.gmem_write(0, state.rate_ms)
  return true
end

--------------------------------------------------------------------------------
-- Render asincrono
--------------------------------------------------------------------------------

local function play_last_render()
  local ok, err = install_jsfx(generate_jsfx(state.files))
  state.msg = ok and '' or (err or 'Errore installazione JSFX')
end

local function render_current()
  local it = rs.items[rs.idx]
  if not it then return end
  r.GetSet_LoopTimeRange2(0, true, false, it.position, it.position + it.length, false)
  local name
  repeat
    rs.serial = rs.serial + 1
    name = ('%s%d_%d'):format(PREFIX, os.time(), rs.serial)
  until not find_rendered(name)
  r.GetSetProjectInfo_String(0, 'RENDER_PATTERN', name, true)
  rs.pending = name
  rs.wait    = 0
  r.Main_OnCommand(RENDER_ACT, 0)
end

local function start_render(items)
  save_render_settings()
  r.RecursiveCreateDirectory(TMP_DIR, 0)
  stop_playback()
  discard_pending_render()

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
  delete_render_files(state.files)
  state.files = rs.files
  rs.files = {}
  play_last_render()
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


--------------------------------------------------------------------------------
-- Stile della finestra principale di FmodSync, limitato ai controlli presenti.
--------------------------------------------------------------------------------

local palette = {
  { ImGui.Col_WindowBg, 0x191A1BFF }, { ImGui.Col_TitleBg, 0x202223FF },
  { ImGui.Col_TitleBgActive, 0x292B2CFF }, { ImGui.Col_Text, 0xECEEEBFF },
  { ImGui.Col_TextDisabled, 0xA6AAA8FF },
  { ImGui.Col_FrameBg, 0x2D3031FF }, { ImGui.Col_FrameBgHovered, 0x373B3CFF },
  { ImGui.Col_FrameBgActive, 0x3C4142FF }, { ImGui.Col_Button, 0x303435FF },
  { ImGui.Col_ButtonHovered, 0x414948FF }, { ImGui.Col_ButtonActive, 0x4D5956FF },
  { ImGui.Col_SliderGrab, 0xE89B3CFF }, { ImGui.Col_SliderGrabActive, 0xF0B462FF },
  { ImGui.Col_ResizeGrip, 0xE89B3C33 }, { ImGui.Col_ResizeGripHovered, 0xE89B3C99 },
  { ImGui.Col_ResizeGripActive, 0xE89B3CFF },
}
local style_vars = {
  { ImGui.StyleVar_WindowRounding, 0 }, { ImGui.StyleVar_FrameRounding, 0 },
  { ImGui.StyleVar_GrabRounding, 0 },
  { ImGui.StyleVar_WindowPadding, 16, 14 },
  { ImGui.StyleVar_ItemSpacing, 8, 7 },
  { ImGui.StyleVar_FramePadding, 9, 5 },
}

local FONT_SIZE = 15
local ok_font, font = pcall(function()
  local f = ImGui.CreateFont("sans-serif")
  ImGui.Attach(ctx, f)
  return f
end)
if not ok_font then font = nil end

local function apply_style()
  if font then ImGui.PushFont(ctx, font, FONT_SIZE) end
  for _, pair in ipairs(palette) do ImGui.PushStyleColor(ctx, pair[1], pair[2]) end
  for _, v in ipairs(style_vars) do ImGui.PushStyleVar(ctx, table.unpack(v)) end
end

local function pop_style()
  ImGui.PopStyleVar(ctx, #style_vars)
  ImGui.PopStyleColor(ctx, #palette)
  if font then ImGui.PopFont(ctx) end
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
  elseif #state.files > 0 then
    status = ('%d file renderizzati - %s'):format(#state.files,
      state.gmem_ok and 'in riproduzione' or 'fermo')
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
  ImGui.BeginDisabled(ctx, rs.phase == 'rendering' or #state.files == 0 or state.gmem_ok)
  if ImGui.Button(ctx, 'Play', 70, 0) then play_last_render() end
  ImGui.EndDisabled(ctx)

  ImGui.SameLine(ctx)
  ImGui.BeginDisabled(ctx, not state.gmem_ok)
  if ImGui.Button(ctx, 'Stop', 70, 0) then stop_playback() end
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
