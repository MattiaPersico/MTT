-- mtt_fmodsync_render.lua
-- Renders takes: one file per block, the top-level folder track rendered as a
-- stem (its children and its own FX, not the master), over the block's time
-- range plus the tail. Every take has its own settings (M.resolve): channels
-- (the folder track's count unless set; 1 = mono), sample rate, tail, 2nd pass,
-- normalization.
-- Each take renders isolated: every track outside its folder is muted and no
-- track is soloed while it renders, so assets that overlap in time (dialogue
-- lines of two characters) do not bleed into each other's files.
-- Every project render setting it touches, the track selection and every
-- track's mute and solo are read
-- first and put back afterwards, also when a render fails (same approach as
-- mtt_metadataassistant_render.lua).
--
-- Render settings used (GetSetProjectInfo / GetSetProjectInfo_String):
--   RENDER_SETTINGS   2 (stems: selected tracks) | 2048 (2nd pass render, optional)
--   RENDER_BOUNDSFLAG 0 (custom time bounds) with RENDER_STARTPOS / RENDER_ENDPOS
--   RENDER_SRATE, RENDER_CHANNELS, RENDER_TAILFLAG 0 (the tail is added to the end
--   bound instead), RENDER_ADDTOPROJ 0
--   RENDER_NORMALIZE &1 = normalize (source LUFS-I: &14 = 0), &64 = brickwall
--   limiter; RENDER_NORMALIZE_TARGET / RENDER_BRICKWALL as amplitudes.
--   RENDER_FILE / RENDER_PATTERN = output folder / take name (REAPER adds .wav)
--   RENDER_FORMAT WAV24, RENDER_FORMAT2 ""

local M = {}

-- 'evaw' sink: 24-bit PCM (the string mtt_metadataassistant_render.lua uses).
M.WAV24 = 'ZXZhdxgAAQ=='

local ACTION_RENDER = 41824 -- File: Render project, using the most recent render settings
local STEMS = 2
local SECOND_PASS = 2048
local NORMALIZE = 1   -- RENDER_NORMALIZE: enable, source LUFS-I
local BRICKWALL = 64  -- RENDER_NORMALIZE: brickwall limiter

local NUM_KEYS = { 'RENDER_SETTINGS', 'RENDER_BOUNDSFLAG', 'RENDER_STARTPOS', 'RENDER_ENDPOS',
                   'RENDER_SRATE', 'RENDER_CHANNELS', 'RENDER_TAILFLAG', 'RENDER_ADDTOPROJ',
                   'RENDER_NORMALIZE', 'RENDER_NORMALIZE_TARGET', 'RENDER_BRICKWALL' }
local STR_KEYS = { 'RENDER_FILE', 'RENDER_PATTERN', 'RENDER_FORMAT', 'RENDER_FORMAT2' }

M.SEP = reaper.GetOS():find('Win') and '\\' or '/'

-- Render settings of an asset with no override: channels nil = the channel
-- count of the folder track, srate nil = the project's, normalize = target in
-- LUFS-I or nil (off), limit = brickwall ceiling in dB or nil (off).
function M.defaults()
  return { channels = nil, srate = nil, tail = 0, second_pass = false, normalize = nil, limit = nil }
end

-- The keys an asset may override (cfg.assets[guid].render), in UI order.
M.KEYS = { 'channels', 'srate', 'tail', 'second_pass', 'normalize', 'limit' }

-- The project's defaults (cfg.render_defaults) over the built-in ones. Pure.
function M.project_defaults(project)
  local r = M.defaults()
  for _, k in ipairs(M.KEYS) do
    if project and project[k] ~= nil and project[k] ~= false then r[k] = project[k] end
  end
  return r
end

-- A take's settings: the project's defaults, then its asset's (track's)
-- overrides, then the take's own (in an override, false = off / auto / the
-- project's, except for second_pass); srate_project fills the sample rate
-- when it is not set. Pure.
function M.resolve(override, srate_project, take_override, project)
  local r = M.project_defaults(project)
  local function apply(o, k)
    local t = o and o[k]
    if t == nil then return end
    if t == false and k ~= 'second_pass' then r[k] = (k == 'tail') and 0 or nil else r[k] = t end
  end
  for _, k in ipairs(M.KEYS) do
    apply(override, k)
    apply(take_override, k)
  end
  r.srate_used = r.srate or srate_project or 48000
  return r
end

-- dB -> amplitude, as RENDER_NORMALIZE_TARGET and RENDER_BRICKWALL want it. Pure.
function M.db_to_amp(db) return 10 ^ (db / 20) end

-- Output folder: absolute, or relative to the RPP's folder. Pure.
function M.output_dir(setting, rpp_dir)
  local s = tostring(setting or ''):gsub('^%s+', ''):gsub('%s+$', '')
  if s == '' then s = 'Render' end
  if s:match('^[/\\]') or s:match('^%a:[/\\]') then return (s:gsub('[/\\]+$', '')) end
  return rpp_dir .. M.SEP .. s:gsub('[/\\]+', M.SEP):gsub('[/\\]+$', '')
end

-- Channels of a take's render: its setting, else the folder track's. Pure.
function M.channels(asset, settings)
  if settings and settings.channels and settings.channels > 0 then return settings.channels end
  return math.max(1, asset.nchan or 2)
end

local function snapshot(proj)
  local s = { num = {}, str = {}, selected = {} }
  for _, k in ipairs(NUM_KEYS) do s.num[k] = reaper.GetSetProjectInfo(proj, k, 0, false) end
  for _, k in ipairs(STR_KEYS) do
    local _, v = reaper.GetSetProjectInfo_String(proj, k, '', false)
    s.str[k] = v
  end
  for i = 0, reaper.CountSelectedTracks(proj) - 1 do
    s.selected[#s.selected + 1] = reaper.GetSelectedTrack(proj, i)
  end
  s.master_selected = reaper.IsTrackSelected(reaper.GetMasterTrack(proj))
  -- Mute and solo of every track: a render mutes what is outside the take's
  -- folder and clears every solo (isolate), then puts them back.
  s.tracks = {}
  for i = 0, reaper.CountTracks(proj) - 1 do
    local tr = reaper.GetTrack(proj, i)
    s.tracks[#s.tracks + 1] = { tr = tr, mute = reaper.GetMediaTrackInfo_Value(tr, 'B_MUTE'),
                                solo = reaper.GetMediaTrackInfo_Value(tr, 'I_SOLO') }
  end
  return s
end

-- Lets only the folder `folder_track` and the tracks under it sound: every
-- other track is muted (its sends too, so nothing outside the folder can reach
-- it or the render) and no track is soloed. Tracks inside keep the mute they
-- had. s = snapshot(proj).
local function isolate(proj, s, folder_track)
  local first = math.floor(reaper.GetMediaTrackInfo_Value(folder_track, 'IP_TRACKNUMBER')) - 1
  local depth0 = reaper.GetTrackDepth(folder_track)
  local inside = {}
  for i = first, reaper.CountTracks(proj) - 1 do
    local tr = reaper.GetTrack(proj, i)
    if i > first and reaper.GetTrackDepth(tr) <= depth0 then break end
    inside[tr] = true
  end
  for _, t in ipairs(s.tracks) do
    if t.solo ~= 0 then reaper.SetMediaTrackInfo_Value(t.tr, 'I_SOLO', 0) end
    local want = inside[t.tr] and t.mute or 1
    if reaper.GetMediaTrackInfo_Value(t.tr, 'B_MUTE') ~= want then
      reaper.SetMediaTrackInfo_Value(t.tr, 'B_MUTE', want)
    end
  end
end

local function restore(proj, s)
  for _, k in ipairs(NUM_KEYS) do reaper.GetSetProjectInfo(proj, k, s.num[k], true) end
  for _, k in ipairs(STR_KEYS) do reaper.GetSetProjectInfo_String(proj, k, s.str[k], true) end
  for _, t in ipairs(s.tracks) do
    if reaper.ValidatePtr2(proj, t.tr, 'MediaTrack*') then
      reaper.SetMediaTrackInfo_Value(t.tr, 'B_MUTE', t.mute)
      reaper.SetMediaTrackInfo_Value(t.tr, 'I_SOLO', t.solo)
    end
  end
  local n = reaper.CountTracks(proj)
  for i = 0, n - 1 do reaper.SetTrackSelected(reaper.GetTrack(proj, i), false) end
  for _, tr in ipairs(s.selected) do reaper.SetTrackSelected(tr, true) end
  reaper.SetTrackSelected(reaper.GetMasterTrack(proj), s.master_selected)
end

-- Renders the takes `jobs` = { { asset, name, block, settings }, ... } into
-- dir; settings = M.resolve(...) of each take.
-- Returns results = { { job, path } or { job, err } }. A file already at a
-- target path is deleted first (only that exact path).
function M.render_jobs(proj, jobs, dir)
  local results = {}
  if #jobs == 0 then return results end
  reaper.RecursiveCreateDirectory(dir, 0)
  local s = snapshot(proj)
  local ok, err = pcall(function()
    reaper.GetSetProjectInfo(proj, 'RENDER_BOUNDSFLAG', 0, true)
    reaper.GetSetProjectInfo(proj, 'RENDER_TAILFLAG', 0, true)
    reaper.GetSetProjectInfo(proj, 'RENDER_ADDTOPROJ', 0, true)
    reaper.GetSetProjectInfo_String(proj, 'RENDER_FILE', dir, true)
    reaper.GetSetProjectInfo_String(proj, 'RENDER_FORMAT', M.WAV24, true)
    reaper.GetSetProjectInfo_String(proj, 'RENDER_FORMAT2', '', true)

    for _, job in ipairs(jobs) do
      local st = job.settings
      reaper.GetSetProjectInfo(proj, 'RENDER_SETTINGS', STEMS | (st.second_pass and SECOND_PASS or 0), true)
      reaper.GetSetProjectInfo(proj, 'RENDER_SRATE', st.srate_used or 48000, true)
      reaper.GetSetProjectInfo(proj, 'RENDER_NORMALIZE', (st.normalize and NORMALIZE or 0) | (st.limit and BRICKWALL or 0), true)
      if st.normalize then reaper.GetSetProjectInfo(proj, 'RENDER_NORMALIZE_TARGET', M.db_to_amp(st.normalize), true) end
      if st.limit then reaper.GetSetProjectInfo(proj, 'RENDER_BRICKWALL', M.db_to_amp(st.limit), true) end
      local path = dir .. M.SEP .. job.name .. '.wav'
      if reaper.file_exists(path) then os.remove(path) end
      -- Only this folder is selected (the master too is deselected: a
      -- selected master is one more stem, the full mix, under the same file
      -- name) and only this folder sounds: another asset playing at the same
      -- time (overlapping dialogue lines) must not end up in this file.
      reaper.SetOnlyTrackSelected(job.asset.track)
      reaper.SetTrackSelected(reaper.GetMasterTrack(proj), false)
      isolate(proj, s, job.asset.track)
      reaper.GetSetProjectInfo(proj, 'RENDER_CHANNELS', M.channels(job.asset, st), true)
      reaper.GetSetProjectInfo(proj, 'RENDER_STARTPOS', job.block[1], true)
      reaper.GetSetProjectInfo(proj, 'RENDER_ENDPOS', job.block[2] + math.max(0, st.tail or 0), true)
      reaper.GetSetProjectInfo_String(proj, 'RENDER_PATTERN', job.name, true)
      reaper.Main_OnCommand(ACTION_RENDER, 0)
      if reaper.file_exists(path) then
        local cues = M.take_markers(job.asset.track, job.block[1], job.block[2] + math.max(0, st.tail or 0))
        local cue_err
        if #cues > 0 then
          local okw, e = M.write_cues(path, cues, st.srate_used or 48000)
          if not okw then cue_err = e end
        end
        results[#results + 1] = { job = job, path = path, cue_err = cue_err }
      else
        results[#results + 1] = { job = job, err = 'not rendered (cancelled?): ' .. path }
      end
    end
  end)
  restore(proj, s)
  if not ok then results[#results + 1] = { err = 'render failed: ' .. tostring(err) } end
  return results
end

-- Take markers of the items on the folder track (the folder items, where
-- mtt_Whisper_AddTakeMarkersOnTopFolderItem puts them) that fall inside
-- [start, stop]: { { pos = seconds from start, name }, ... } sorted by pos.
-- Only the active take; a marker outside its item is skipped.
function M.take_markers(track, start, stop)
  local out = {}
  for i = 0, reaper.CountTrackMediaItems(track) - 1 do
    local item = reaper.GetTrackMediaItem(track, i)
    local take = reaper.GetActiveTake(item)
    if take then
      local ipos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
      local ilen = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
      local offs = reaper.GetMediaItemTakeInfo_Value(take, 'D_STARTOFFS')
      local rate = reaper.GetMediaItemTakeInfo_Value(take, 'D_PLAYRATE')
      if not rate or rate <= 0 then rate = 1 end
      for m = 0, reaper.GetNumTakeMarkers(take) - 1 do
        local srcpos, name = reaper.GetTakeMarker(take, m)
        local rel = (srcpos - offs) / rate -- from the item's start
        local t = ipos + rel
        if rel >= -1e-9 and rel <= ilen + 1e-9 and t >= start - 1e-9 and t <= stop + 1e-9 then
          out[#out + 1] = { pos = math.max(0, t - start), name = name or '' }
        end
      end
    end
  end
  table.sort(out, function(a, b) return a.pos < b.pos end)
  return out
end

-- Writes cues = { { pos (s), name }, ... } into the WAV at path as a 'cue '
-- chunk and a LIST/adtl chunk of 'labl' names (what Soundminer, FMOD and most
-- editors read as markers), replacing any already there; srate converts
-- seconds to sample frames. Rewrites the file through path .. '.tmp'.
-- Returns true or nil, error.
function M.write_cues(path, cues, srate)
  local f = io.open(path, 'rb')
  if not f then return nil, 'cannot open ' .. path end
  local data = f:read('a')
  f:close()
  if #data < 12 or data:sub(1, 4) ~= 'RIFF' or data:sub(9, 12) ~= 'WAVE' then
    return nil, 'not a RIFF WAVE file (RF64?): ' .. path
  end
  local parts, frames = { }, nil
  local fmt_block, data_len
  local p = 13
  while p + 7 <= #data do
    local id = data:sub(p, p + 3)
    local size = string.unpack('<I4', data, p + 4)
    local body_end = math.min(#data, p + 7 + size)
    local padded = body_end + (size % 2)
    local keep = true
    if id == 'cue ' then keep = false
    elseif id == 'LIST' and data:sub(p + 8, p + 11) == 'adtl' then keep = false
    elseif id == 'fmt ' then fmt_block = string.unpack('<I2', data, p + 8 + 12)
    elseif id == 'data' then data_len = size end
    if keep then parts[#parts + 1] = data:sub(p, math.min(#data, padded)) end
    p = padded + 1
  end
  if fmt_block and fmt_block > 0 and data_len then frames = data_len // fmt_block end

  local cue, labl = { string.pack('<I4', #cues) }, { 'adtl' }
  for i, c in ipairs(cues) do
    local s = math.floor(c.pos * srate + 0.5)
    if frames then s = math.min(s, math.max(0, frames - 1)) end
    cue[#cue + 1] = string.pack('<I4I4c4I4I4I4', i, s, 'data', 0, 0, s)
    local text = (c.name or '') .. '\0'
    local chunk = 'labl' .. string.pack('<I4I4', 4 + #text, i) .. text
    if #chunk % 2 == 1 then chunk = chunk .. '\0' end
    labl[#labl + 1] = chunk
  end
  local cue_body = table.concat(cue)
  local adtl_body = table.concat(labl)
  parts[#parts + 1] = 'cue ' .. string.pack('<I4', #cue_body) .. cue_body
  parts[#parts + 1] = 'LIST' .. string.pack('<I4', #adtl_body) .. adtl_body
  local body = 'WAVE' .. table.concat(parts)
  if #body > 0xFFFFFFFF then return nil, 'file too large for RIFF: ' .. path end

  local tmp = path .. '.tmp'
  local o = io.open(tmp, 'wb')
  if not o then return nil, 'cannot write ' .. tmp end
  o:write('RIFF', string.pack('<I4', #body), body)
  o:close()
  os.remove(path)
  local okr, e = os.rename(tmp, path)
  if not okr then return nil, 'cannot replace ' .. path .. ': ' .. tostring(e) end
  return true
end

-- Tail suggestion from the reverbs the take renders through: the FX of the
-- top-level folder track and of every track under it (the stem). A reverb is
-- an enabled, online FX whose name has one of REVERB_WORDS. Its decay is the
-- formatted value of a parameter named like a decay time (DECAY_WORDS, first
-- match wins; "ms" -> seconds, a bare number over 30 counts as ms), plus its
-- pre-delay when it has one; a reverb with only a size parameter (ReaVerbate)
-- gets 0.5 + 4.5 * size s, one with nothing readable REVERB_FALLBACK s.
-- Returns the longest of them rounded up to 0.1 s, and a list of
-- { name, track, tail, how } (how = 'decay' | 'size' | 'default'), or nil
-- when there is no reverb.
local REVERB_WORDS = { 'reverb', 'verb', 'room', 'hall', 'plate', 'spring', 'chamber',
  'convol', 'shimmer', 'supermassive', 'blackhole', 'cathedral', 'ambience', 'raum',
  'altiverb', 'bricasti', 'lexicon', 'pro%-r', 'seventh heaven', 'cinematic rooms', 'space' }
local NOT_REVERB_WORDS = { 'delay', 'echo', 'gate', 'room ?eq', 'roomeq', 'room correction' }
local DECAY_WORDS = { 'decay', 'rt60', 'rt 60', 'reverb time', 'reverb length', 'tail', 'length', 'time', 'space' } -- Pro-R: Space is the decay in s
local NOT_DECAY_WORDS = { 'pre', 'early', 'er ', 'mod', 'attack', 'release', 'gate', 'freeze',
  'damp', 'diffus', 'multiplier', 'mult', 'ratio', 'scale', 'low', 'high', 'mid', 'bass', 'treble', 'crossover', 'xover' }
local PREDELAY_WORDS = { 'pre%-?delay', 'pre delay', 'predly', 'pre%-dly' }
local REVERB_FALLBACK = 2

local function has_word(s, words)
  for _, w in ipairs(words) do if s:find(w) then return true end end
  return false
end

M.is_reverb_name = function(name)
  local n = name:lower():gsub('^%w+i?:%s*', '') -- "VST3: ", "JS: "...
  n = n:gsub('%s*%(.-%)%s*$', '')               -- " (maker)"
  if not has_word(n, REVERB_WORDS) then return false end
  -- "ValhallaDelay", "Room EQ"... unless it says reverb too.
  if has_word(n, NOT_REVERB_WORDS) and not n:find('verb') then return false end
  return true
end

-- Seconds from a formatted parameter value: "2.50 s", "2500 ms", "2.5";
-- another unit ("%", "dB", "Hz") -> nil. Pure.
M.parse_seconds = function(text)
  if not text then return nil end
  local t = text:lower():gsub(',', '.')
  local num, unit = t:match('(%-?%d+%.?%d*)%s*([^%s%d]*)')
  num = tonumber(num)
  if not num or num < 0 then return nil end
  if unit == 'ms' or unit == 'msec' then return num / 1000 end
  if unit == 's' or unit == 'sec' or unit == 'secs' or unit == 'seconds' then return num end
  if unit == 'm' or unit == 'min' then return num * 60 end
  if unit ~= '' then return nil end -- "%", "db", "hz"...
  if num > 30 then return num / 1000 end
  return num
end

local function fx_decay(track, fx)
  local n = reaper.TrackFX_GetNumParams(track, fx)
  local best, best_rank, predelay, size
  for p = 0, n - 1 do
    local _, pname = reaper.TrackFX_GetParamName(track, fx, p)
    local l = (pname or ''):lower()
    if predelay == nil and has_word(l, PREDELAY_WORDS) then
      local _, f = reaper.TrackFX_GetFormattedParamValue(track, fx, p)
      local v = M.parse_seconds(f)
      if v and v < 1 then predelay = v end
    elseif not has_word(l, NOT_DECAY_WORDS) then
      for rank, w in ipairs(DECAY_WORDS) do
        if l:find(w) and (not best_rank or rank < best_rank) then
          local _, f = reaper.TrackFX_GetFormattedParamValue(track, fx, p)
          local v = M.parse_seconds(f)
          if v and v > 0 and v <= 60 then best, best_rank = v, rank end
          break
        end
      end
      if size == nil and (l == 'room size' or l == 'size' or l == 'roomsize') then
        size = reaper.TrackFX_GetParamNormalized(track, fx, p)
      end
    end
  end
  if best then return best + (predelay or 0), 'decay' end
  if size then return 0.5 + 4.5 * size + (predelay or 0), 'size' end
  return REVERB_FALLBACK, 'default'
end

function M.reverb_tail(folder_track, proj)
  proj = proj or 0
  local first = math.floor(reaper.GetMediaTrackInfo_Value(folder_track, 'IP_TRACKNUMBER')) - 1
  if first < 0 then return nil end
  local depth0 = reaper.GetTrackDepth(folder_track)
  local found, longest = {}, nil
  local i, count = first, reaper.CountTracks(proj)
  while i < count do
    local tr = reaper.GetTrack(proj, i)
    if i > first and reaper.GetTrackDepth(tr) <= depth0 then break end
    if reaper.GetMediaTrackInfo_Value(tr, 'I_FXEN') ~= 0 then
      for fx = 0, reaper.TrackFX_GetCount(tr) - 1 do
        local _, name = reaper.TrackFX_GetFXName(tr, fx)
        if name and M.is_reverb_name(name) and reaper.TrackFX_GetEnabled(tr, fx)
          and not reaper.TrackFX_GetOffline(tr, fx) then
          local tail, how = fx_decay(tr, fx)
          local _, tname = reaper.GetTrackName(tr)
          found[#found + 1] = { name = name, track = tname, tail = tail, how = how }
          if not longest or tail > longest then longest = tail end
        end
      end
    end
    i = i + 1
  end
  if not longest then return nil, found end
  return math.ceil(longest * 10 - 1e-6) / 10, found
end

return M
