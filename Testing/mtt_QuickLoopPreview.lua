--[[
  QuickLoopPreview_Selection.lua  (JSFX, no SWS, con cache)

  Toggle:
  - ON : se la selezione è identica all'ultimo render (item, edit, FX,
         master, sample rate) riusa il WAV in cache senza ri-renderizzare;
         altrimenti renderizza. Poi genera il JSFX player, lo appende in
         coda alla chain del Master e parte il loop.
  - OFF: rimuove il JSFX dal Master e ripristina i canali del Master.
         Il WAV resta in cache per un eventuale riuso al prossimo ON.

  Il confronto usa un hash dei chunk di stato: item selezionati, track
  coinvolte (inclusi FX e parametri), master, span temporale, sample rate.
  Qualsiasi modifica rilevante forza il re-render.

  Cache: un solo file, nomi fissi, sovrascritto a ogni nuovo render.
  - WAV : <resource>/Data/qlp_tmp/qlp_cache.wav
  - JSFX: <resource>/Effects/qlp_tmp/qlp_cache_fx
  La firma della cache vive in ExtState non persistente: alla chiusura di
  REAPER si invalida da sola (il file verrà comunque sovrascritto).

  JSFX puramente additivo: spl(n) += file. Non tocca i canali esistenti,
  non cambia il layout del Master. ext_noinit=1: play/stop del transport
  non fanno ripartire il loop.

  Limite: file caricato in RAM in @init, max ~128M sample
  (48 kHz / 6 ch ≈ 7,7 min; oltre, troncato). REAPER 6.44+.
]]

local r = reaper

local MARKER    = "QLP_TEMP"
local EXT       = "QLP_SELECTION_PREVIEW"
local WAV_BASE  = "qlp_cache"        -- nome fisso: la cache è un solo file
local JS_BASE   = "qlp_cache_fx"

------------------------------------------------------------------- toggle
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

local wavpath = datadir .. sep .. WAV_BASE .. ".wav"
local jspath  = fxdir   .. sep .. JS_BASE

local master = r.GetMasterTrack(0)

-- pulizia: file estranei alla cache + istanze JSFX orfane sul Master
local function wipe_dir(dir, keep)
  local list, i = {}, 0
  while true do
    local f = r.EnumerateFiles(dir, i)
    if not f then break end
    if f ~= keep then list[#list + 1] = dir .. sep .. f end
    i = i + 1
  end
  for _, f in ipairs(list) do os.remove(f) end
end
wipe_dir(datadir, WAV_BASE .. ".wav")
wipe_dir(fxdir, JS_BASE)

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

-- legge il channel count dall'header WAV: permette di riusare la cache
-- anche dopo un riavvio di REAPER (l'ExtState non sopravvive)
local function wav_channels(path)
  local fh = io.open(path, "rb")
  if not fh then return nil end
  local hdr = fh:read(12)
  if not hdr or #hdr < 12 or hdr:sub(1, 4) ~= "RIFF" or hdr:sub(9, 12) ~= "WAVE" then
    fh:close() return nil
  end
  while true do
    local ck = fh:read(8)
    if not ck or #ck < 8 then break end
    local sz = ck:byte(5) + ck:byte(6) * 256 + ck:byte(7) * 65536 + ck:byte(8) * 16777216
    if ck:sub(1, 4) == "fmt " then
      local fmt = fh:read(sz)
      fh:close()
      if fmt and #fmt >= 4 then return fmt:byte(3) + fmt:byte(4) * 256 end
      return nil
    end
    fh:seek("cur", sz + (sz % 2)) -- chunk allineati a 2 byte
  end
  fh:close()
  return nil
end

local nsel = r.CountSelectedMediaItems(0)

local t0, t1 = math.huge, -math.huge
local maxch = 2
local selItems, selTracks, trackSeen = {}, {}, {}
for i = 0, nsel - 1 do
  local it  = r.GetSelectedMediaItem(0, i)
  local pos = r.GetMediaItemInfo_Value(it, "D_POSITION")
  local len = r.GetMediaItemInfo_Value(it, "D_LENGTH")
  if pos < t0 then t0 = pos end
  if pos + len > t1 then t1 = pos + len end
  local tr = r.GetMediaItem_Track(it)
  local nch = r.GetMediaTrackInfo_Value(tr, "I_NCHAN")
  if nch > maxch then maxch = nch end
  selItems[#selItems + 1] = it
  if not trackSeen[tr] then
    trackSeen[tr] = true
    selTracks[#selTracks + 1] = tr
  end
end
maxch = math.floor(maxch)

-- selezione vuota o span nullo: risuona l'ultima cache invece di abortire
local reuse_only = false
if nsel == 0 or t1 <= t0 then
  local cch = wav_channels(wavpath)
  if cch and cch > 0 then
    maxch = cch
    reuse_only = true
  else
    abort("Nessun item selezionato e nessuna cache da risuonare.")
    return
  end
end

------------------------------------------------------------------- firma cache
-- djb2 su stringhe, a blocchi (i chunk possono essere grandi)
local function hash_str(h, s)
  for i = 1, #s, 256 do
    local bytes = { s:byte(i, math.min(i + 255, #s)) }
    for j = 1, #bytes do
      h = (h * 33 + bytes[j]) % 4294967296
    end
  end
  return h
end

local function build_signature()
  local h = 5381
  h = hash_str(h, string.format("%.9f|%.9f|%d|%.1f", t0, t1, maxch,
        r.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)))
  for _, it in ipairs(selItems) do
    local ok, chunk = r.GetItemStateChunk(it, "", false)
    if ok then h = hash_str(h, chunk) end
  end
  for _, tr in ipairs(selTracks) do
    local ok, chunk = r.GetTrackStateChunk(tr, "", false)
    if ok then h = hash_str(h, chunk) end
  end
  local ok, mchunk = r.GetTrackStateChunk(master, "", false)
  if ok then h = hash_str(h, mchunk) end
  return string.format("%d", h)
end

local sig = (not reuse_only) and build_signature() or ""

local function cache_valid()
  if reuse_only then return true end -- suona la cache così com'è
  if r.GetExtState(EXT, "cache_sig") ~= sig then return false end
  local fh = io.open(wavpath, "rb")
  if not fh then return false end
  fh:close()
  return true
end

------------------------------------------------------------------- render (solo se cache non valida)
if not cache_valid() then
  -- muta gli item non selezionati che si sovrappongono all'intervallo
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
  setS("RENDER_PATTERN",    WAV_BASE)
  setS("RENDER_FORMAT",     "evaw") -- WAV

  os.remove(wavpath)  -- evita il prompt "overwrite?" del render

  r.Main_OnCommand(42230, 0) -- Render project using most recent settings (auto-close)

  for _, k in ipairs(numKeys) do setN(k, savedN[k]) end
  for _, k in ipairs(strKeys) do setS(k, savedS[k]) end
  for _, it in ipairs(unmute_later) do r.SetMediaItemInfo_Value(it, "B_MUTE", 0) end
  r.UpdateArrange()

  local fh = io.open(wavpath, "rb")
  if not fh then
    r.DeleteExtState(EXT, "cache_sig", false)
    abort("Render non riuscito (file non trovato).")
    return
  end
  fh:close()

  r.SetExtState(EXT, "cache_sig", sig, false) -- non persistente: muore con REAPER
end

------------------------------------------------------------------- genera JSFX
-- Player additivo. file_open legge relativo a <resource>/Data.
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
]]):format(MARKER, table.concat(pins, "\n"), WAV_BASE)

do
  local fh, err = io.open(jspath, "w")
  if not fh then abort("Impossibile scrivere il JSFX: " .. tostring(err)) return end
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
local fxIdx = r.TrackFX_AddByName(master, "JS:qlp_tmp/" .. JS_BASE, false, -1)
if fxIdx < 0 then
  fxIdx = r.TrackFX_AddByName(master, "qlp_tmp/" .. JS_BASE, false, -1)
end
if fxIdx < 0 then
  if masterChChanged then r.SetMediaTrackInfo_Value(master, "I_NCHAN", savedMasterCh) end
  abort("Impossibile inserire il JSFX sul Master.")
  return
end
local fxGUID = r.TrackFX_GetFXGUID(master, fxIdx)

------------------------------------------------------------------- cleanup + loop
local function cleanup()
  -- rimuovi il JSFX (per GUID: l'indice può essere cambiato)
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
  -- NB: WAV e JSFX restano su disco come cache per il prossimo ON
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
