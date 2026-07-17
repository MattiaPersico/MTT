--[[
  QuickLoopPreview_Selection.lua  (versione JSFX, nessuna dipendenza SWS)

  Toggle:
  - ON : renderizza gli item selezionati (mix via track FX + master) in un WAV
         temporaneo col channel count più alto tra le track coinvolte
         (6 -> 5.1, 2 -> stereo, ...), genera un JSFX player dedicato,
         lo appende in coda alla chain del Master e parte il loop.
  - OFF: rimuove il JSFX dal Master, cancella WAV + JSFX, ripristina tutto.

  Il JSFX è puramente additivo: non tocca i canali esistenti (spl(n) += file),
  non cambia il layout del Master. Se il file ha più canali del Master,
  I_NCHAN viene alzato temporaneamente e ripristinato allo stop.

  File temporanei:
  - WAV : <resource>/Data/qlp_tmp/          (file_open del JSFX legge da Data)
  - JSFX: <resource>/Effects/qlp_tmp/
  Entrambi ripuliti allo stop; eventuali orfani (crash / chiusura REAPER)
  vengono ripuliti al lancio successivo, incluse istanze JSFX orfane sul Master.

  Limite: il JSFX carica il file in RAM (@init), max ~128M sample.
  A 48 kHz / 6 canali ≈ 7,7 minuti di selezione. Oltre, viene troncato.
]]

local r = reaper

local MARKER = "QLP_TEMP"  -- appare nel desc del JSFX: usato per trovare/rimuovere orfani

------------------------------------------------------------------- toggle
local EXT = "QLP_SELECTION_PREVIEW"
local has_sao = r.set_action_options ~= nil

if has_sao then
  r.set_action_options(1 | 4)  -- ri-lancio = termina istanza attiva, toggle ON
else
  if r.GetExtState(EXT, "running") == "1" then
    r.SetExtState(EXT, "stop", "1", false)
    return
  end
  r.SetExtState(EXT, "running", "1", false)
  r.SetExtState(EXT, "stop", "0", false)
end

local _, _, sectionID, cmdID = r.get_action_context()
r.SetToggleCommandState(sectionID, cmdID, 1)
r.RefreshToolbar2(sectionID, cmdID)

------------------------------------------------------------------- percorsi
local sep     = package.config:sub(1, 1)
local res     = r.GetResourcePath()
local datadir = res .. sep .. "Data"    .. sep .. "qlp_tmp"
local fxdir   = res .. sep .. "Effects" .. sep .. "qlp_tmp"
r.RecursiveCreateDirectory(datadir, 0)
r.RecursiveCreateDirectory(fxdir, 0)

local master = r.GetMasterTrack(0)

-- pulizia orfani: file da sessioni precedenti + istanze JSFX rimaste sul Master
local function wipe_dir(dir)
  local list, i = {}, 0
  while true do
    local f = r.EnumerateFiles(dir, i)
    if not f then break end
    list[#list + 1] = dir .. sep .. f
    i = i + 1
  end
  for _, f in ipairs(list) do os.remove(f) end
end
wipe_dir(datadir)
wipe_dir(fxdir)

for i = r.TrackFX_GetCount(master) - 1, 0, -1 do
  local _, name = r.TrackFX_GetFXName(master, i, "")
  if name:find(MARKER, 1, true) then r.TrackFX_Delete(master, i) end
end

------------------------------------------------------------------- selezione
local function abort(msg)
  if msg then r.MB(msg, "QuickLoopPreview", 0) end
  r.SetToggleCommandState(sectionID, cmdID, 0)
  r.RefreshToolbar2(sectionID, cmdID)
  if not has_sao then r.DeleteExtState(EXT, "running", false) end
end

local nsel = r.CountSelectedMediaItems(0)
if nsel == 0 then abort("Nessun item selezionato.") return end

local t0, t1 = math.huge, -math.huge
local maxch = 2
for i = 0, nsel - 1 do
  local it  = r.GetSelectedMediaItem(0, i)
  local pos = r.GetMediaItemInfo_Value(it, "D_POSITION")
  local len = r.GetMediaItemInfo_Value(it, "D_LENGTH")
  if pos < t0 then t0 = pos end
  if pos + len > t1 then t1 = pos + len end
  local nch = r.GetMediaTrackInfo_Value(r.GetMediaItem_Track(it), "I_NCHAN")
  if nch > maxch then maxch = nch end
end
maxch = math.floor(maxch)

------------------------------------------------------------------- muta item estranei
local unmute_later = {}
for ti = 0, r.CountTracks(0) - 1 do
  local tr = r.GetTrack(0, ti)
  for ii = 0, r.CountTrackMediaItems(tr) - 1 do
    local it = r.GetTrackMediaItem(tr, ii)
    if r.GetMediaItemInfo_Value(it, "B_UISEL") == 0 then
      local pos = r.GetMediaItemInfo_Value(it, "D_POSITION")
      local len = r.GetMediaItemInfo_Value(it, "D_LENGTH")
      if pos + len > t0 and pos < t1
         and r.GetMediaItemInfo_Value(it, "B_MUTE") == 0 then
        r.SetMediaItemInfo_Value(it, "B_MUTE", 1)
        unmute_later[#unmute_later + 1] = it
      end
    end
  end
end

------------------------------------------------------------------- render settings
local function getN(k)    return r.GetSetProjectInfo(0, k, 0, false) end
local function setN(k, v) r.GetSetProjectInfo(0, k, v, true) end
local function getS(k) local _, s = r.GetSetProjectInfo_String(0, k, "", false) return s end
local function setS(k, v) r.GetSetProjectInfo_String(0, k, v, true) end

local numKeys = { "RENDER_SETTINGS", "RENDER_BOUNDSFLAG", "RENDER_CHANNELS",
                  "RENDER_SRATE", "RENDER_STARTPOS", "RENDER_ENDPOS",
                  "RENDER_TAILFLAG", "RENDER_ADDTOPROJ", "RENDER_DITHER" }
local strKeys = { "RENDER_FILE", "RENDER_PATTERN", "RENDER_FORMAT" }

local savedN, savedS = {}, {}
for _, k in ipairs(numKeys) do savedN[k] = getN(k) end
for _, k in ipairs(strKeys) do savedS[k] = getS(k) end

math.randomseed(os.time() + math.floor(r.time_precise() * 1000))
local uid   = string.format("%d_%04d", os.time(), math.random(0, 9999))
local wname = "qlp_" .. uid            -- basename WAV
local jname = "qlp_fx_" .. uid         -- basename JSFX

setN("RENDER_SETTINGS",   0)      -- master mix
setN("RENDER_BOUNDSFLAG", 0)      -- bounds custom
setN("RENDER_STARTPOS",   t0)
setN("RENDER_ENDPOS",     t1)
setN("RENDER_CHANNELS",   maxch)
setN("RENDER_SRATE",      0)      -- sample rate del progetto
setN("RENDER_TAILFLAG",   0)      -- nessuna coda: loop pulito
setN("RENDER_ADDTOPROJ",  0)
setN("RENDER_DITHER",     0)
setS("RENDER_FILE",       datadir)
setS("RENDER_PATTERN",    wname)
setS("RENDER_FORMAT",     "evaw") -- WAV

------------------------------------------------------------------- render
r.Main_OnCommand(42230, 0) -- Render project using most recent settings (auto-close)

-- ripristina tutto subito dopo il render
for _, k in ipairs(numKeys) do setN(k, savedN[k]) end
for _, k in ipairs(strKeys) do setS(k, savedS[k]) end
for _, it in ipairs(unmute_later) do r.SetMediaItemInfo_Value(it, "B_MUTE", 0) end
r.UpdateArrange()

local wavpath = datadir .. sep .. wname .. ".wav"
do
  local fh = io.open(wavpath, "rb")
  if not fh then abort("Render non riuscito (file non trovato).") return end
  fh:close()
end

------------------------------------------------------------------- genera JSFX
-- Player additivo: somma il file sui canali del Master, non tocca nient'altro.
-- file_open legge relativo a <resource>/Data -> "qlp_tmp/<wname>.wav"
local pins = {}
for c = 1, maxch do
  pins[#pins + 1] = ("in_pin:Ch%d\nout_pin:Ch%d"):format(c, c)
end

local jsfx = ([[
desc:%s preview player (auto-generato, non salvare nel progetto)
options:maxmem=134217728
%s

@init
ext_noinit = 1; // niente re-init su play/stop del transport: il loop non riparte
frames = 0;
fh = file_open("qlp_tmp/%s.wav");
fh > 0 ? (
  file_riff(fh, fnch, fsr);
  fnch > 0 ? (
    avail = file_avail(fh);
    avail > __memtop() ? avail = __memtop() - (__memtop() %% fnch);
    file_mem(fh, 0, avail);
    frames = floor(avail / fnch);
  );
  file_close(fh);
);
pos = 0;

@sample
frames > 0 ? (
  ip = floor(pos);
  fr = pos - ip;
  i2 = ip + 1;
  i2 >= frames ? i2 = 0;
  c = 0;
  loop(fnch,
    spl(c) += ((ip * fnch + c)[0]) * (1 - fr) + ((i2 * fnch + c)[0]) * fr;
    c += 1;
  );
  pos += fsr / srate;
  pos >= frames ? pos -= frames;
);
]]):format(MARKER, table.concat(pins, "\n"), wname)

local jspath = fxdir .. sep .. jname
do
  local fh, err = io.open(jspath, "w")
  if not fh then os.remove(wavpath) abort("Impossibile scrivere il JSFX: " .. tostring(err)) return end
  fh:write(jsfx)
  fh:close()
end

------------------------------------------------------------------- master: canali + inserimento FX
local savedMasterCh = r.GetMediaTrackInfo_Value(master, "I_NCHAN")
local masterChChanged = false
if maxch > savedMasterCh then
  r.SetMediaTrackInfo_Value(master, "I_NCHAN", maxch)
  masterChChanged = true
end

-- TrackFX_AddByName appende in coda alla chain
local fxIdx = r.TrackFX_AddByName(master, "JS:qlp_tmp/" .. jname, false, -1)
if fxIdx < 0 then
  fxIdx = r.TrackFX_AddByName(master, "qlp_tmp/" .. jname, false, -1)
end
if fxIdx < 0 then
  os.remove(wavpath)
  os.remove(jspath)
  if masterChChanged then r.SetMediaTrackInfo_Value(master, "I_NCHAN", savedMasterCh) end
  abort("Impossibile inserire il JSFX sul Master.")
  return
end
local fxGUID = r.TrackFX_GetFXGUID(master, fxIdx)

------------------------------------------------------------------- cleanup + loop
local function cleanup()
  -- rimuovi il JSFX (cerca per GUID: l'indice può essere cambiato)
  for i = r.TrackFX_GetCount(master) - 1, 0, -1 do
    if r.TrackFX_GetFXGUID(master, i) == fxGUID then
      r.TrackFX_Delete(master, i)
      break
    end
  end
  -- safety net: qualsiasi altra istanza marcata
  for i = r.TrackFX_GetCount(master) - 1, 0, -1 do
    local _, name = r.TrackFX_GetFXName(master, i, "")
    if name:find(MARKER, 1, true) then r.TrackFX_Delete(master, i) end
  end
  os.remove(wavpath)
  os.remove(jspath)
  if masterChChanged then
    r.SetMediaTrackInfo_Value(master, "I_NCHAN", savedMasterCh)
  end
  r.SetToggleCommandState(sectionID, cmdID, 0)
  r.RefreshToolbar2(sectionID, cmdID)
  if not has_sao then
    r.DeleteExtState(EXT, "running", false)
    r.DeleteExtState(EXT, "stop", false)
  end
end
r.atexit(cleanup)

local function mainloop()
  if not has_sao and r.GetExtState(EXT, "stop") == "1" then return end
  r.defer(mainloop)
end
mainloop()

