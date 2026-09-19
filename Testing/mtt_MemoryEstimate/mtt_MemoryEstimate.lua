-- @description mtt_MemoryEstimate - render memory estimate of empty items on top-level tracks
-- @author mattia
-- @version 2.0
-- @about
--   For each top-level track (no parent) containing empty items (no PCM source,
--   not muted), estimates the rendered file size using item length and the
--   track channel count.
--   Formats: PCM (16/24/32 bit), FADPCM (~4.4 bit/sample), Vorbis (quality 1-100%).
--   Items longer than a threshold can be excluded (streaming instead of RAM).
--   Docked mode: compact stacked bar by track name category
--   (Point_ / Zone_ / Int_ / Event_ / Scat_ / Other) + total, with a detached
--   settings window.

if not reaper.ImGui_CreateContext then
  reaper.MB('ReaImGui not installed. Install it via ReaPack.', 'mtt_MemoryEstimate', 0)
  return
end

local ctx = reaper.ImGui_CreateContext('mtt_MemoryEstimate', reaper.ImGui_ConfigFlags_DockingEnable())

--------------------------------------------------------------------------
-- VORBIS TUNING (edit here if estimates drift from FMOD)
-- VORBIS_CALIBRATION: ratio between real FMOD bank size and the nominal
--   libvorbis bitrate model. Re-measure with real assets
--   (FMOD MB / estimate at 1.0) and adjust.
-- VORBIS_FILE_OVERHEAD: fixed per-file cost in bytes (Ogg/codebook headers).
--   Matters on short files.
-- VORBIS_SILENCE_WEIGHT: bit cost of silent blocks (<-60 dBFS) relative to
--   non-silent ones in the content analysis. Non-silent audio always weighs
--   1.0: Vorbis VBR spends bits on spectral complexity, NOT on level, so
--   quiet-but-complex material must not be discounted.
--------------------------------------------------------------------------
-- 0.72 fitted on two real FMOD banks (est/real ratios 0.794 and 0.742 at
-- calibration 0.94 -> both land within +-4% at 0.72)
local VORBIS_CALIBRATION    = 0.72
local VORBIS_FILE_OVERHEAD  = 4096
local VORBIS_SILENCE_WEIGHT = 0.1
-- Block cost model: below SILENCE_DB (dBFS RMS) a block weighs SILENCE_WEIGHT,
-- above FULL_DB it weighs 1.0. In the quiet zone in between, cost is decided
-- by SPECTRAL analysis (native reaper.array FFT): fraction of spectrum bins
-- with amplitude above BIN_FLOOR_DB (dB re full-scale sine). Broadband
-- ambience lights up many bins -> full cost; tonal tails/rumble light few
-- -> cheap. ACTIVE_REF = bin fraction at which cost saturates to 1.0.
-- If FFT is unavailable, falls back to a linear-in-dB ramp.
local VORBIS_SILENCE_DB     = -80
local VORBIS_FULL_DB        = -50
local VORBIS_BIN_FLOOR_DB   = -110
-- occupancy response: w = SW + (1-SW) * min(1, frac/ACTIVE_REF)^OCC_GAMMA
-- lower REF = broadband saturates to full cost sooner (raises ambience banks)
-- gamma > 1 = low-occupancy (tonal) blocks discounted harder
local VORBIS_ACTIVE_REF     = 0.15
local VORBIS_OCC_GAMMA      = 2.0

--------------------------------------------------------------------------
-- SETTINGS
--------------------------------------------------------------------------
local SAMPLE_RATES   = { 44100, 48000, 88200, 96000 }
local SR_COMBO       = '44100\0' .. '48000\0' .. '88200\0' .. '96000\0'
local FORMAT_COMBO   = 'PCM\0' .. 'FADPCM\0' .. 'Vorbis\0'
local BITDEPTHS      = { 16, 24, 32 }
local BD_COMBO       = '16 bit\0' .. '24 bit\0' .. '32 bit\0'

-- category colors (cycled over user-defined patterns); 'Other' always appended
local PALETTE = {
  0x5B8FD4FF, 0x6BBF7BFF, 0xD4A65BFF, 0xC96A6AFF,
  0x9B6BD4FF, 0x4EC9C9FF, 0xC9C94EFF, 0xD46BB0FF,
}
local OTHER_COLOR = 0x8A8A8AFF
local CATEGORIES = {} -- rebuilt from settings.categories

local settings = {
  format_idx      = 2,     -- 0=PCM 1=FADPCM 2=Vorbis (default Vorbis)
  sr_idx          = 1,     -- default 48000
  bd_idx          = 0,     -- 16 bit
  vorbis_quality  = 100,    -- 1..100 %
  exclude_enabled = false,
  exclude_seconds = 15.0,
  budget_mb       = 200,   -- memory budget
  mono_check      = true,  -- stereo tracks: detect mono-only content, estimate as 1ch
  use_rendered    = true,  -- use files in the render folder for precise sizes
  categories      = { 'Point_', 'Zone_', 'Int_', 'Event_', 'Scat_' },
}

local function rebuild_categories()
  CATEGORIES = {}
  for i, pat in ipairs(settings.categories) do
    CATEGORIES[i] = {
      key   = pat,
      label = (pat:gsub('_+$', '')),
      color = PALETTE[(i - 1) % #PALETTE + 1],
    }
  end
  CATEGORIES[#CATEGORIES + 1] = { key = nil, label = 'Other', color = OTHER_COLOR }
end
rebuild_categories()

local state = {
  show_settings = false,
  sort_col      = 4,     -- default: Size
  sort_asc      = false, -- default: descending
  new_cat       = '',    -- input buffer for new category pattern
  proj_id       = nil,   -- active project, to reload settings on switch
  show_details  = false, -- detached file details window (dock mode)
}

-- last computed results
local results = {
  rows           = {},    -- { track, name, len, ch, bytes, stream }
  cat_bytes      = {},    -- per CATEGORIES index, RAM bytes
  cat_excluded   = {},    -- per CATEGORIES index, excluded (streaming) bytes
  total_bytes    = 0,
  included_count = 0,
  excluded_count = 0,
  excluded_bytes = 0,
  computed       = false,
}

--------------------------------------------------------------------------
-- PER-PROJECT SETTINGS PERSISTENCE (ProjExtState: saved inside the .rpp)
--------------------------------------------------------------------------
local EXT_SECTION = 'mtt_MemoryEstimate'

local function save_settings()
  local s = settings
  reaper.SetProjExtState(0, EXT_SECTION, 'settings', table.concat({
    s.format_idx, s.sr_idx, s.bd_idx, s.vorbis_quality,
    s.exclude_enabled and 1 or 0, s.exclude_seconds,
    s.budget_mb, 0, -- slot 8 unused (was auto_update)
    s.mono_check and 1 or 0, s.use_rendered and 1 or 0,
  }, ';'))
  reaper.SetProjExtState(0, EXT_SECTION, 'categories', table.concat(s.categories, ','))
end

local function load_settings()
  local ok, ser = reaper.GetProjExtState(0, EXT_SECTION, 'settings')
  if ok == 1 and ser ~= '' then
    local v = {}
    for tok in ser:gmatch('[^;]+') do v[#v + 1] = tok end
    settings.format_idx      = math.floor(tonumber(v[1]) or settings.format_idx)
    settings.sr_idx          = math.floor(tonumber(v[2]) or settings.sr_idx)
    settings.bd_idx          = math.floor(tonumber(v[3]) or settings.bd_idx)
    settings.vorbis_quality  = math.floor(tonumber(v[4]) or settings.vorbis_quality)
    settings.exclude_enabled = v[5] == '1'
    settings.exclude_seconds = tonumber(v[6]) or settings.exclude_seconds
    settings.budget_mb       = math.floor(tonumber(v[7]) or settings.budget_mb)
    -- v[8] unused (was auto_update)
    settings.mono_check      = v[9] ~= '0'  -- default true for older saves
    settings.use_rendered    = v[10] ~= '0' -- default true for older saves
  end
  local ok2, cats = reaper.GetProjExtState(0, EXT_SECTION, 'categories')
  if ok2 == 1 then -- key present: honor it even if empty (user removed all)
    settings.categories = {}
    for tok in cats:gmatch('[^,]+') do settings.categories[#settings.categories + 1] = tok end
  end
  rebuild_categories()
end

--------------------------------------------------------------------------
-- ESTIMATE
--------------------------------------------------------------------------
-- FADPCM: ~4.4 bits per sample per channel (FMOD, ~3.6:1 vs PCM16)
--
-- Vorbis: FMOD quality % maps to libvorbis quality (-1..10).
-- Nominal total bitrates for STEREO (kbps) per libvorbis quality level:
local VORBIS_Q_KBPS = {
  [-1] = 45, [0] = 64, [1] = 80, [2] = 96, [3] = 112, [4] = 128,
  [5] = 160, [6] = 192, [7] = 224, [8] = 256, [9] = 320, [10] = 500,
}

local function vorbis_nominal_stereo_kbps(percent)
  local q = -1 + (percent / 100) * 11
  if q <= -1 then return VORBIS_Q_KBPS[-1] end
  if q >= 10 then return VORBIS_Q_KBPS[10] end
  local lo = math.floor(q)
  local hi = lo + 1
  local t = q - lo
  return VORBIS_Q_KBPS[lo] + (VORBIS_Q_KBPS[hi] - VORBIS_Q_KBPS[lo]) * t
end

-- Vorbis is VBR: nominal bitrate is an upper-ish bound, real size depends on
-- content. Use 'Vorbis calibration' to match measured FMOD bank sizes.
local function estimate_bytes(len_sec, channels, sr)
  local fmt = settings.format_idx
  if fmt == 0 then -- PCM
    local bytes_per_sample = BITDEPTHS[settings.bd_idx + 1] / 8
    return len_sec * sr * channels * bytes_per_sample
  elseif fmt == 1 then -- FADPCM
    return len_sec * sr * channels * (4.4 / 8)
  else -- Vorbis
    local kbps_stereo = vorbis_nominal_stereo_kbps(settings.vorbis_quality)
    local kbps = kbps_stereo * (channels / 2) -- scale by channel count (coupled stereo baseline)
    return len_sec * kbps * 1000 / 8 * VORBIS_CALIBRATION + VORBIS_FILE_OVERHEAD
  end
end

-- empty item = no valid PCM source (no take, no source, or source without filename)
local function is_empty_item(item)
  local take = reaper.GetActiveTake(item)
  if not take then return true end
  local src = reaper.GetMediaItemTake_Source(take)
  if not src then return true end
  local filename = reaper.GetMediaSourceFileName(src, '')
  return filename == nil or filename == ''
end

local function get_item_name(item)
  local _, notes = reaper.GetSetMediaItemInfo_String(item, 'P_NOTES', '', false)
  notes = (notes or ''):match('([^\r\n]*)') or ''
  if notes == '' then return '(unnamed)' end
  return notes
end

-- columns: 0=Track 1=Item 2=Length 3=Ch 4=Size
function sort_rows()
  local col, asc = state.sort_col, state.sort_asc
  table.sort(results.rows, function(a, b)
    local av, bv
    if     col == 0 then av, bv = a.track:lower(), b.track:lower()
    elseif col == 1 then av, bv = a.name:lower(), b.name:lower()
    elseif col == 2 then av, bv = a.len, b.len
    elseif col == 3 then av, bv = a.ch, b.ch
    else                 av, bv = a.bytes, b.bytes end
    if av == bv then return a.bytes > b.bytes end
    if asc then return av < bv else return av > bv end
  end)
end

local function cat_index(track_name)
  for i, c in ipairs(CATEGORIES) do
    if c.key and track_name:find(c.key, 1, true) then return i end
  end
  return #CATEGORIES -- Other
end

--------------------------------------------------------------------------
-- RENDERED FILES LOOKUP
-- If a file with a similar name exists in the render folder, its real
-- properties are used instead of the theoretical model:
--   * target Vorbis + file is .ogg  -> actual file size on disk
--   * otherwise -> real length/channels from the file, fed to the model
--------------------------------------------------------------------------
local AUDIO_EXT = { wav=true, flac=true, aif=true, aiff=true, ogg=true, mp3=true, opus=true, wv=true }
local render_cache = { files = nil, dir = nil, t = 0, meta = {} }

-- renders live in <project folder>/Render.
-- GetProjectPath returns <project folder>/Audio Files: go up one level.
local function get_render_dir()
  local audio_dir = reaper.GetProjectPath('')
  local parent = audio_dir:match('^(.*)[/\\][^/\\]+$') or audio_dir
  local sep = package.config:sub(1, 1)
  return parent .. sep .. 'Render'
end

local function get_render_files()
  local now = reaper.time_precise()
  local dir = get_render_dir()
  if render_cache.files and render_cache.dir == dir and now - render_cache.t < 3.0 then
    return render_cache.files, dir
  end
  local files, i = {}, 0
  while true do
    local fn = reaper.EnumerateFiles(dir, i)
    if not fn or fn == '' then break end
    local ext = fn:match('%.([^.]+)$')
    if ext and AUDIO_EXT[ext:lower()] then files[#files + 1] = fn end
    i = i + 1
  end
  render_cache.files, render_cache.dir, render_cache.t = files, dir, now
  return files, dir
end

local function name_score(a, b)
  a, b = a:lower(), b:lower()
  if a == b then return 1000 end
  if a:find(b, 1, true) or b:find(a, 1, true) then return 100 + math.min(#a, #b) end
  local n, p = math.min(#a, #b), 0
  for i = 1, n do
    if a:byte(i) == b:byte(i) then p = p + 1 else break end
  end
  return p
end

-- best match against item name and track name; nil if nothing plausible
local function find_rendered_file(item_name, track_name)
  local files, dir = get_render_files()
  local best, best_score = nil, 3 -- require at least 4 chars of affinity
  for _, fn in ipairs(files) do
    local base = fn:gsub('%.[^.]+$', '')
    local s = name_score(base, track_name)
    if item_name then s = math.max(s, name_score(base, item_name)) end
    if s > best_score then best, best_score = fn, s end
  end
  if best then
    return dir .. '/' .. best, best:match('%.([^.]+)$'):lower()
  end
end

local function file_size(path)
  local f = io.open(path, 'rb')
  if not f then return nil end
  local sz = f:seek('end')
  f:close()
  return sz
end

-- real length/channels of a media file, cached (invalidated on size change)
local function get_source_meta(path)
  local sz = file_size(path)
  if not sz then return nil end
  local m = render_cache.meta[path]
  if m and m.fsize == sz then return m end
  local src = reaper.PCM_Source_CreateFromFile(path)
  if not src then return nil end
  local slen = reaper.GetMediaSourceLength(src)
  local snch = reaper.GetMediaSourceNumChannels(src)
  reaper.PCM_Source_Destroy(src)
  m = { fsize = sz, len = slen, nch = snch }
  render_cache.meta[path] = m
  return m
end

-- Content factor (0..1) for Vorbis VBR prediction, measured by actually
-- reading the audio through an AudioAccessor on a temporary track.
-- Per 4096-sample block (25% coverage): silence weighs VORBIS_SILENCE_WEIGHT,
-- loud blocks weigh 1.0, quiet blocks are weighted by spectral occupancy via
-- native reaper.array FFT (see VORBIS_* macros at the top). Result multiplies
-- the nominal bitrate model. Cached per file (invalidated on size change).
local function analyze_content_factor(path)
  local src = reaper.PCM_Source_CreateFromFile(path)
  if not src then return nil end
  local len   = reaper.GetMediaSourceLength(src)
  local nch   = math.max(1, math.floor(reaper.GetMediaSourceNumChannels(src)))
  local srate = reaper.GetMediaSourceSampleRate(src)
  if len <= 0 or srate <= 0 then reaper.PCM_Source_Destroy(src); return nil end

  reaper.PreventUIRefresh(1)

  -- temp track/item/take to host the accessor (source ownership moves to take)
  local idx = reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(idx, false)
  local tr = reaper.GetTrack(0, idx)
  local it = reaper.AddMediaItemToTrack(tr)
  local tk = reaper.AddTakeToMediaItem(it)
  reaper.SetMediaItemTake_Source(tk, src)
  reaper.SetMediaItemInfo_Value(it, 'D_LENGTH', len)

  local acc = reaper.CreateTakeAudioAccessor(tk)
  local block, stride = 4096, 4096 * 4
  local total_samples = math.floor(len * srate)
  local buf = reaper.new_array(block * nch)
  local total_w, nblocks = 0, 0
  local pos = 0

  -- FFT workspace for the quiet zone (native reaper.array, no dependencies)
  local half = block / 2
  local fbuf = reaper.new_array(block)
  local hann = {}
  for i = 1, block do
    hann[i] = 0.5 * (1 - math.cos(2 * math.pi * (i - 1) / (block - 1)))
  end
  -- per-bin amplitude floor: full-scale Hann-windowed sine peaks at ~N/4
  local bin_floor = (block / 4) * 10 ^ (VORBIS_BIN_FLOOR_DB / 20)
  local bin_floor2 = bin_floor * bin_floor
  local fft_ok = true

  while pos < total_samples do
    local n = math.min(block, total_samples - pos)
    buf.clear()
    reaper.GetAudioAccessorSamples(acc, srate, nch, pos / srate, n, buf)
    local t = buf.table(1, n * nch)
    local sum = 0
    for i = 1, n * nch do local s = t[i]; sum = sum + s * s end
    local rms = math.sqrt(sum / (n * nch))
    local db = 20 * math.log(rms > 0 and rms or 1e-12, 10)
    local w
    if db <= VORBIS_SILENCE_DB then
      w = VORBIS_SILENCE_WEIGHT
    elseif db >= VORBIS_FULL_DB then
      w = 1.0
    else
      -- quiet zone: cost from spectral occupancy, not level
      local w_fft
      if fft_ok then
        fbuf.clear()
        for i = 1, n do fbuf[i] = t[(i - 1) * nch + 1] * hann[i] end
        local ok = pcall(fbuf.fft_real, block, true)
        if ok then
          -- packing: [1]=DC, [2]=Nyquist, then re/im pairs for bins 1..half-1
          local fb = fbuf.table()
          local active = 0
          for k = 2, half do
            local re, im = fb[2 * k - 1], fb[2 * k]
            if re * re + im * im > bin_floor2 then active = active + 1 end
          end
          local occ = math.min(1, (active / half) / VORBIS_ACTIVE_REF)
          w_fft = VORBIS_SILENCE_WEIGHT
                + (1 - VORBIS_SILENCE_WEIGHT) * occ ^ VORBIS_OCC_GAMMA
        else
          fft_ok = false -- FFT unavailable: fall back to ramp from here on
        end
      end
      if w_fft then
        w = w_fft
      else
        local tt = (db - VORBIS_SILENCE_DB) / (VORBIS_FULL_DB - VORBIS_SILENCE_DB)
        w = VORBIS_SILENCE_WEIGHT + tt * (1.0 - VORBIS_SILENCE_WEIGHT)
      end
    end
    total_w = total_w + w
    nblocks = nblocks + 1
    pos = pos + stride
  end

  reaper.DestroyAudioAccessor(acc)
  reaper.DeleteTrack(tr) -- frees item/take/source too
  reaper.PreventUIRefresh(-1)

  if nblocks == 0 then return nil end
  return total_w / nblocks
end

local function get_content_factor(path)
  local m = get_source_meta(path)
  if not m then return nil end
  if not m.factor then
    m.factor = analyze_content_factor(path) or 1.0
  end
  return m.factor
end


-- collect audio items from all descendant tracks of a top-level track:
-- position span + whether they are effectively mono (1ch source, or mono
-- channel mode on the take: I_CHANMODE 2..66)
local function collect_descendant_items(top)
  local list = {}
  for t = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, t)
    if tr ~= top then
      local p = reaper.GetParentTrack(tr)
      while p and p ~= top do p = reaper.GetParentTrack(p) end
      if p == top then
        for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
          local it = reaper.GetTrackMediaItem(tr, i)
          local take = reaper.GetActiveTake(it)
          if take then
            local src = reaper.GetMediaItemTake_Source(take)
            if src and reaper.GetMediaSourceFileName(src, '') ~= '' then
              local nch = reaper.GetMediaSourceNumChannels(src)
              local cm  = reaper.GetMediaItemTakeInfo_Value(take, 'I_CHANMODE')
              local pos = reaper.GetMediaItemInfo_Value(it, 'D_POSITION')
              local len = reaper.GetMediaItemInfo_Value(it, 'D_LENGTH')
              list[#list + 1] = {
                pos  = pos,
                fin  = pos + len,
                mono = nch == 1 or (cm >= 2 and cm <= 66),
              }
            end
          end
        end
      end
    end
  end
  return list
end

local function compute()
  results.rows, results.total_bytes = {}, 0
  results.included_count, results.excluded_count, results.excluded_bytes = 0, 0, 0
  results.rendered_count = 0
  results.cat_bytes, results.cat_excluded = {}, {}
  for i = 1, #CATEGORIES do
    results.cat_bytes[i] = 0
    results.cat_excluded[i] = 0
  end

  local sr = SAMPLE_RATES[settings.sr_idx + 1]
  local proj = 0

  for t = 0, reaper.CountTracks(proj) - 1 do
    local track = reaper.GetTrack(proj, t)
    -- top-level tracks only (no parent)
    if reaper.GetParentTrack(track) == nil then
      local channels = reaper.GetMediaTrackInfo_Value(track, 'I_NCHAN')
      local _, tr_name = reaper.GetTrackName(track)
      local ci = cat_index(tr_name)

      -- mono precision: for stereo parents, inspect descendant content
      local desc_items = nil
      if settings.mono_check and channels == 2 then
        desc_items = collect_descendant_items(track)
      end

      for i = 0, reaper.CountTrackMediaItems(track) - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        -- empty item (no PCM source) and not muted
        if is_empty_item(item)
           and reaper.GetMediaItemInfo_Value(item, 'B_MUTE') == 0 then

          local len = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
          if len < 0 then len = 0 end
          local pos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')

          -- if every descendant item overlapping this empty item is mono,
          -- the rendered file will be mono: estimate as 1 channel
          local ch = channels
          if desc_items then
            local found, all_mono = false, true
            for _, d in ipairs(desc_items) do
              if d.pos < pos + len and d.fin > pos then
                found = true
                if not d.mono then all_mono = false; break end
              end
            end
            if found and all_mono then ch = 1 end
          end

          local iname = get_item_name(item)

          -- precise sizing from already-rendered files, when available
          local bytes, precise
          if settings.use_rendered then
            local path, ext = find_rendered_file(iname ~= '(unnamed)' and iname or nil, tr_name)
            if path then
              if settings.format_idx == 2 and ext == 'ogg' then
                bytes = file_size(path) -- real encoded size
                precise = bytes ~= nil
              else
                local m = get_source_meta(path)
                if m then
                  bytes = estimate_bytes(m.len, m.nch, sr) -- real length/channels
                  if settings.format_idx == 2 then
                    bytes = bytes * (get_content_factor(path) or 1.0)
                  end
                  precise = true
                end
              end
            end
          end
          if not bytes then bytes = estimate_bytes(len, ch, sr) end

          local stream = settings.exclude_enabled and len > settings.exclude_seconds

          results.rows[#results.rows + 1] = {
            track   = tr_name,
            name    = iname,
            len     = len,
            ch      = ch,
            bytes   = bytes,
            stream  = stream,
            precise = precise,
          }
          if precise then results.rendered_count = results.rendered_count + 1 end

          if stream then
            results.excluded_count = results.excluded_count + 1
            results.excluded_bytes = results.excluded_bytes + bytes
            results.cat_excluded[ci] = results.cat_excluded[ci] + bytes
          else
            results.total_bytes    = results.total_bytes + bytes
            results.included_count = results.included_count + 1
            results.cat_bytes[ci]  = results.cat_bytes[ci] + bytes
          end
        end
      end
    end
  end

  sort_rows()
  results.computed = true
end

local function format_bytes(b)
  if b >= 1024 ^ 3 then return string.format('%.2f GB', b / 1024 ^ 3) end
  if b >= 1024 ^ 2 then return string.format('%.2f MB', b / 1024 ^ 2) end
  if b >= 1024     then return string.format('%.1f KB', b / 1024) end
  return string.format('%.0f B', b) -- %.0f, not %d: b can be fractional (Lua 5.4 %d errors on floats)
end

--------------------------------------------------------------------------
-- STYLE
--------------------------------------------------------------------------
local function apply_style()
  local col = reaper.ImGui_ColorConvertDouble4ToU32

  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), col(0.1, 0.1, 0.1, 1))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), col(0.45, 0.45, 0.45, 2))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_BorderShadow(), col(0, 0, 0, 2))

  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), col(0.1, 0.1, 0.1, 2))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), col(0.1, 0.1, 0.1, 2))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), col(0.18, 0.18, 0.18, 2))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_MenuBarBg(), col(0.1, 0.1, 0.1, 2))

  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), col(0.18, 0.18, 0.18, 2))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), col(0.3, 0.3, 0.3, 2))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), col(0.18, 0.18, 0.18, 2))

  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ResizeGrip(), col(0.1, 0.1, 0.1, 2))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ResizeGripActive(), col(0.3, 0.3, 0.3, 2))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ResizeGripHovered(), col(0.18, 0.18, 0.18, 2))

  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBg(), col(0.14, 0.14, 0.14, 2))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBgActive(), col(0.18, 0.18, 0.18, 2))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBgCollapsed(), col(0.18, 0.18, 0.18, 2))

  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), col(0.2, 0.2, 0.2, 2))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgActive(), col(0.4, 0.4, 0.4, 2))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(), col(0.25, 0.25, 0.25, 2))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_SliderGrab(), col(0.5, 0.5, 0.5, 2))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_SliderGrabActive(), col(0.13, 0.13, 0.13, 2))

  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_CheckMark(), col(0.8, 0.8, 0.8, 2))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Separator(), col(0.35, 0.35, 0.35, 2))

  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ScrollbarSize(), 10)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarBg(), col(0.09, 0.09, 0.09, 1))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrab(), col(0.3, 0.3, 0.3, 1))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrabActive(), col(0.2, 0.2, 0.2, 1))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrabHovered(), col(0.5, 0.5, 0.5, 1))

  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 7)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ScrollbarRounding(), 7)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_GrabRounding(), 7)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ChildRounding(), 7)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 5)
end

local STYLE_COLORS, STYLE_VARS = 27, 6

--------------------------------------------------------------------------
-- SETTINGS WIDGETS (shared: full window + detached settings window)
--------------------------------------------------------------------------
local function draw_settings_widgets()
  local rv
  local dirty = false

  reaper.ImGui_SeparatorText(ctx, 'Estimate format')

  reaper.ImGui_SetNextItemWidth(ctx, 120)
  rv, settings.format_idx = reaper.ImGui_Combo(ctx, 'Format', settings.format_idx, FORMAT_COMBO)
  dirty = dirty or rv

  reaper.ImGui_SetNextItemWidth(ctx, 120)
  rv, settings.sr_idx = reaper.ImGui_Combo(ctx, 'Sample rate', settings.sr_idx, SR_COMBO)
  dirty = dirty or rv

  -- always visible, disabled (grayed out) when not applicable to the format
  local is_pcm, is_vorbis = settings.format_idx == 0, settings.format_idx == 2

  if not is_pcm then reaper.ImGui_BeginDisabled(ctx) end
  reaper.ImGui_SetNextItemWidth(ctx, 120)
  rv, settings.bd_idx = reaper.ImGui_Combo(ctx, 'Bit depth', settings.bd_idx, BD_COMBO)
  dirty = dirty or rv
  if not is_pcm then reaper.ImGui_EndDisabled(ctx) end

  if not is_vorbis then reaper.ImGui_BeginDisabled(ctx) end
  reaper.ImGui_SetNextItemWidth(ctx, 200)
  rv, settings.vorbis_quality = reaper.ImGui_SliderInt(ctx, 'Quality', settings.vorbis_quality, 1, 100, '%d%%')
  dirty = dirty or rv
  if not is_vorbis then reaper.ImGui_EndDisabled(ctx) end

  reaper.ImGui_SeparatorText(ctx, 'Exclusions')

  rv, settings.exclude_enabled = reaper.ImGui_Checkbox(ctx, 'Exclude items longer than', settings.exclude_enabled)
  dirty = dirty or rv
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_SetNextItemWidth(ctx, -60)
  if not settings.exclude_enabled then reaper.ImGui_BeginDisabled(ctx) end
  rv, settings.exclude_seconds = reaper.ImGui_SliderDouble(ctx, 'sec', settings.exclude_seconds, 0.0, 120.0, '%.1f s')
  dirty = dirty or rv
  if not settings.exclude_enabled then reaper.ImGui_EndDisabled(ctx) end

  reaper.ImGui_SeparatorText(ctx, 'Categories')

  local remove_idx
  for i, pat in ipairs(settings.categories) do
    reaper.ImGui_PushID(ctx, 'cat' .. i)
    reaper.ImGui_ColorButton(ctx, '##swatch', PALETTE[(i - 1) % #PALETTE + 1],
      reaper.ImGui_ColorEditFlags_NoTooltip(), 14, 14)
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_Text(ctx, pat)
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_SmallButton(ctx, 'X') then remove_idx = i end
    reaper.ImGui_PopID(ctx)
  end
  if remove_idx then
    table.remove(settings.categories, remove_idx)
    rebuild_categories()
    dirty = true
  end

  reaper.ImGui_SetNextItemWidth(ctx, 120)
  rv, state.new_cat = reaper.ImGui_InputText(ctx, '##newcat', state.new_cat)
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, 'Add category') then
    local pat = state.new_cat:gsub('[,;]', '') -- separators reserved by serialization
    if pat ~= '' then
      settings.categories[#settings.categories + 1] = pat
      state.new_cat = ''
      rebuild_categories()
      dirty = true
    end
  end

  reaper.ImGui_SeparatorText(ctx, 'General')

  reaper.ImGui_SetNextItemWidth(ctx, 120)
  rv, settings.budget_mb = reaper.ImGui_InputInt(ctx, 'Memory budget (MB)', settings.budget_mb, 0, 0)
  if settings.budget_mb < 1 then settings.budget_mb = 1 end
  dirty = dirty or rv

  rv, settings.mono_check = reaper.ImGui_Checkbox(ctx, 'Detect mono content on stereo tracks', settings.mono_check)
  dirty = dirty or rv

  rv, settings.use_rendered = reaper.ImGui_Checkbox(ctx, 'Use rendered files when available', settings.use_rendered)
  dirty = dirty or rv

  if dirty then save_settings() end

  return dirty
end

--------------------------------------------------------------------------
-- STACKED CATEGORY BAR
--------------------------------------------------------------------------
local function legend_swatch(color)
  local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
  local dl = reaper.ImGui_GetWindowDrawList(ctx)
  reaper.ImGui_DrawList_AddRectFilled(dl, x, y + 2, x + 12, y + 14, color, 2)
  reaper.ImGui_Dummy(ctx, 12, 14)
  reaper.ImGui_SameLine(ctx)
end

-- full-width horizontal bar: solid segments = RAM per category,
-- ghost (translucent) segments = excluded/streaming items, not counted in total.
-- bar span = budget (or RAM+ghost total, if bigger); red marker = budget limit.
local function draw_stacked_bar()
  local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
  local w, h = avail_w, 22
  local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
  local dl = reaper.ImGui_GetWindowDrawList(ctx)

  local used = results.total_bytes
  local ghost = results.excluded_bytes
  local budget = settings.budget_mb * 1024 * 1024
  local span = math.max(used + ghost, budget)

  reaper.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, 0x202020FF, 4)

  local px = x
  -- solid RAM segments
  for i, cat in ipairs(CATEGORIES) do
    local b = results.cat_bytes[i] or 0
    if b > 0 then
      local seg = (b / span) * w
      reaper.ImGui_DrawList_AddRectFilled(dl, px, y, px + seg, y + h, cat.color)
      px = px + seg
    end
  end
  -- ghost segments (excluded, streaming): same colors, low alpha
  for i, cat in ipairs(CATEGORIES) do
    local b = results.cat_excluded[i] or 0
    if b > 0 then
      local seg = (b / span) * w
      local ghost_col = (cat.color & 0xFFFFFF00) | 0x48
      reaper.ImGui_DrawList_AddRectFilled(dl, px, y, px + seg, y + h, ghost_col)
      px = px + seg
    end
  end

  -- budget limit marker when the bar spans beyond the budget
  if used + ghost > budget then
    local bx = x + (budget / span) * w
    reaper.ImGui_DrawList_AddLine(dl, bx, y - 2, bx, y + h + 2, 0xE06060FF, 2)
  end

  reaper.ImGui_DrawList_AddRect(dl, x, y, x + w, y + h, 0x555555FF, 4, 0, 1)
  reaper.ImGui_Dummy(ctx, w, h)
end

local function draw_legend()
  local total = results.total_bytes
  if total <= 0 and results.excluded_bytes <= 0 then
    reaper.ImGui_Text(ctx, results.computed and 'No data' or 'Not computed yet')
    return
  end
  local first = true
  for i, cat in ipairs(CATEGORIES) do
    local b = results.cat_bytes[i] or 0
    if b > 0 then
      if not first then reaper.ImGui_SameLine(ctx, 0, 14) end
      legend_swatch(cat.color)
      reaper.ImGui_Text(ctx, string.format('%s %s (%.0f%%)', cat.label, format_bytes(b), b / total * 100))
      first = false
    end
  end

  -- streaming (excluded) share of the grand total
  local ghost = results.excluded_bytes
  if ghost > 0 then
    if not first then reaper.ImGui_SameLine(ctx, 0, 14) end
    legend_swatch(0xAAAAAA55)
    reaper.ImGui_Text(ctx, string.format('Excluded %s (%.0f%%)',
      format_bytes(ghost), ghost / (total + ghost) * 100))
  end
end

--------------------------------------------------------------------------
-- FILE DETAILS TABLE (shared: full window + detached details window)
--------------------------------------------------------------------------
local function draw_details_table()
  local table_flags = reaper.ImGui_TableFlags_Borders()
                    | reaper.ImGui_TableFlags_RowBg()
                    | reaper.ImGui_TableFlags_ScrollY()
                    | reaper.ImGui_TableFlags_Resizable()
                    | reaper.ImGui_TableFlags_Sortable()

  if reaper.ImGui_BeginTable(ctx, 'results', 5, table_flags, 0, -1) then
    reaper.ImGui_TableSetupScrollFreeze(ctx, 0, 1)
    -- user_id set equal to column index (last arg)
    reaper.ImGui_TableSetupColumn(ctx, 'Track',  0, 0, 0)
    reaper.ImGui_TableSetupColumn(ctx, 'Item',   0, 0, 1)
    reaper.ImGui_TableSetupColumn(ctx, 'Length', reaper.ImGui_TableColumnFlags_WidthFixed(), 60, 2)
    reaper.ImGui_TableSetupColumn(ctx, 'Ch',     reaper.ImGui_TableColumnFlags_WidthFixed(), 30, 3)
    reaper.ImGui_TableSetupColumn(ctx, 'Size',   reaper.ImGui_TableColumnFlags_WidthFixed()
      | reaper.ImGui_TableColumnFlags_DefaultSort()
      | reaper.ImGui_TableColumnFlags_PreferSortDescending(), 80, 4)
    reaper.ImGui_TableHeadersRow(ctx)

    -- re-sort on header click. Return count of TableGetColumnSortSpecs varies
    -- across ReaImGui versions: take column from ret[2] (column_index ==
    -- user_id by design) and sort direction from the LAST return value.
    if reaper.ImGui_TableNeedSort(ctx) then
      local ret = { reaper.ImGui_TableGetColumnSortSpecs(ctx, 0) }
      if ret[1] then
        state.sort_col = ret[2]
        state.sort_asc = (ret[#ret] == reaper.ImGui_SortDirection_Ascending())
        sort_rows()
      end
    end

    for _, row in ipairs(results.rows) do
      reaper.ImGui_TableNextRow(ctx)
      -- excluded (streaming) rows shown grayed out
      if row.stream then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x808080FF) end
      reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_Text(ctx, row.track)
      reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_Text(ctx, row.name)
      reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_Text(ctx, string.format('%.2f s', row.len))
      reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_Text(ctx, string.format('%.0f', row.ch))
      -- '*' = size taken from a rendered file
      reaper.ImGui_TableNextColumn(ctx)
      reaper.ImGui_Text(ctx, format_bytes(row.bytes) .. (row.precise and ' *' or ''))
      if row.stream then reaper.ImGui_PopStyleColor(ctx) end
    end
    reaper.ImGui_EndTable(ctx)
  end
end

--------------------------------------------------------------------------
-- DOCKED (compact) UI
--------------------------------------------------------------------------
local function draw_dock_ui()
  local rv

  if reaper.ImGui_Button(ctx, 'Estimate') then compute() end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, 'Settings') then state.show_settings = true end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, 'Details') then state.show_details = true end

  -- current format indicator
  local fmt_label
  if settings.format_idx == 0 then
    fmt_label = string.format('PCM %d bit', BITDEPTHS[settings.bd_idx + 1])
  elseif settings.format_idx == 1 then
    fmt_label = 'FADPCM'
  else
    fmt_label = string.format('Vorbis %d%%', settings.vorbis_quality)
  end
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x9A9A9AFF)
  reaper.ImGui_Text(ctx, '[' .. fmt_label .. ']')
  reaper.ImGui_PopStyleColor(ctx)

  local used = results.total_bytes
  local budget = settings.budget_mb * 1024 * 1024
  local over = used > budget
  if over then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xE06060FF) end
  reaper.ImGui_Text(ctx, string.format('Used: %s / %d MB%s',
    format_bytes(used), settings.budget_mb, over and '  (OVER BUDGET)' or ''))
  if over then reaper.ImGui_PopStyleColor(ctx) end

  draw_stacked_bar()
  draw_legend()
end

--------------------------------------------------------------------------
-- FULL (undocked) UI
--------------------------------------------------------------------------
local function draw_full_ui()
  -- live recompute: the scan is lightweight (no rendering), safe while dragging
  local dirty = draw_settings_widgets()
  if dirty and results.computed then compute() end

  reaper.ImGui_Spacing(ctx)
  if reaper.ImGui_Button(ctx, 'Estimate memory', -1, 32) then
    compute()
  end

  if not results.computed then return end

  reaper.ImGui_SeparatorText(ctx, 'Results')

  local used = results.total_bytes
  local budget = settings.budget_mb * 1024 * 1024
  local frac = budget > 0 and used / budget or 0
  local over = used > budget

  if over then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xE06060FF) end
  reaper.ImGui_Text(ctx, string.format('Used: %s / %d MB (%.0f%%)%s',
    format_bytes(used), settings.budget_mb, frac * 100, over and '  (OVER BUDGET)' or ''))
  if over then reaper.ImGui_PopStyleColor(ctx) end

  draw_stacked_bar()
  draw_legend()

  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Text(ctx, string.format('Estimated RAM total: %s', format_bytes(used)))
  reaper.ImGui_Text(ctx, string.format('Grand total (RAM + streaming): %s',
    format_bytes(used + results.excluded_bytes)))
  reaper.ImGui_Text(ctx, string.format('Total files: %d%s', results.included_count,
    results.rendered_count > 0
      and string.format('  (%d sized from rendered files)', results.rendered_count) or ''))
  if settings.exclude_enabled then
    reaper.ImGui_Text(ctx, string.format('Excluded (> %.1f sec, streaming): %d  (~%s)',
      settings.exclude_seconds, results.excluded_count, format_bytes(results.excluded_bytes)))
  end

  reaper.ImGui_Spacing(ctx)

  -- collapsed by default, expand with the arrow
  if reaper.ImGui_CollapsingHeader(ctx, 'File details') then
    draw_details_table()
  end
end

--------------------------------------------------------------------------
-- DETACHED SETTINGS WINDOW
--------------------------------------------------------------------------
local function draw_settings_window()
  reaper.ImGui_SetNextWindowSize(ctx, 380, 420, reaper.ImGui_Cond_FirstUseEver())
  local visible, open = reaper.ImGui_Begin(ctx, 'MemoryEstimate Settings', true)
  if visible then
    local dirty = draw_settings_widgets()
    if dirty and results.computed then compute() end
    reaper.ImGui_End(ctx)
  end
  if not open then state.show_settings = false end
end

--------------------------------------------------------------------------
-- DETACHED DETAILS WINDOW (opened from dock mode)
--------------------------------------------------------------------------
local function draw_details_window()
  reaper.ImGui_SetNextWindowSize(ctx, 520, 400, reaper.ImGui_Cond_FirstUseEver())
  local visible, open = reaper.ImGui_Begin(ctx, 'MemoryEstimate Details', true)
  if visible then
    draw_details_table()
    reaper.ImGui_End(ctx)
  end
  if not open then state.show_details = false end
end

--------------------------------------------------------------------------
-- LOOP
--------------------------------------------------------------------------
local function loop()
  -- reload per-project settings when the active project changes (and on startup)
  local proj_id = tostring(reaper.EnumProjects(-1))
  if proj_id ~= state.proj_id then
    state.proj_id = proj_id
    load_settings()
    results.computed = false
  end

  apply_style()
  reaper.ImGui_SetNextWindowSize(ctx, 480, 560, reaper.ImGui_Cond_FirstUseEver())

  local visible, open = reaper.ImGui_Begin(ctx, 'mtt_MemoryEstimate', true)
  if visible then
    if reaper.ImGui_IsWindowDocked(ctx) then
      draw_dock_ui()
    else
      draw_full_ui()
    end
    reaper.ImGui_End(ctx)
  end

  if state.show_settings then
    draw_settings_window()
  end

  if state.show_details then
    draw_details_window()
  end

  reaper.ImGui_PopStyleColor(ctx, STYLE_COLORS)
  reaper.ImGui_PopStyleVar(ctx, STYLE_VARS)

  if open then reaper.defer(loop) end
end

reaper.defer(loop)
