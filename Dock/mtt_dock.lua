-- mtt_dock.lua
-- A waveform strip made to live in a long horizontal docker. What it shows
-- follows REAPER's selection:
--
--  * Exactly one item selected: the whole source of its active take, with the
--    part the item plays highlighted. Dragging the highlight slips the content
--    (the item keeps its place and length). Double-click on a take found in
--    the file brings the item window there (anywhere else: centres the window
--    on that point). Left-drag elsewhere selects a zone of the file; dragging
--    the zone onto the arrange makes a new item on the same file.
--  * Anything else: the loopback recorder on the master (mtt_dock_recorder.jsfx,
--    last in the master chain). Sound enters on the right. Left-drag selects
--    (the edges of the selection drag too, and snap to the sounds found in the
--    recording), double-click selects the sound under the mouse, and dragging
--    the selection takes it out onto the arrange as a new item, cut at the
--    sound's first sample: stereo, or with Cmd held mono / stereo / original.
--
-- In both: holding the right button listens from that point (the item through
-- its track and FX, the recording through the master output); wheel zooms,
-- Shift+wheel scrolls, Cmd/Ctrl+wheel scales the waveform height, and the
-- waveform's dynamics are compressed for display (settings: Dynamics). The
-- gear in the bottom right corner opens the settings.
-- Needs ReaImGui and SWS (CF_Preview for track previews, BR_ for the drop).

if not reaper.APIExists('ImGui_GetBuiltinPath') then
  reaper.MB('ReaImGui is required (ReaPack: ReaTeam Extensions).', 'Missing dependency', 0)
  return
end
if not reaper.APIExists('CF_CreatePreview') or not reaper.APIExists('BR_GetMouseCursorContext') then
  reaper.MB('The SWS extension is required (www.sws-extension.org).', 'Missing dependency', 0)
  return
end
package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'

local SCRIPT_DIR = debug.getinfo(1, 'S').source:match[[^@?(.*[\/])[^\/]-$]]
local SEP = reaper.GetOS():find('Win') and '\\' or '/'
local EXT = 'mtt_dock'
local ctx = ImGui.CreateContext('mtt_dock')

------------------------------------------------------------------------------
-- Pure helpers (no reaper.*, no ImGui): run on their own in .scratch tests.
-- BEGIN PURE

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

-- Takes found in a file: bursts of sound separated by quieter gaps, or by a
-- dip followed by a new attack when one take's tail runs into the next.
-- env: linear peak per analysis point (1-based), rate: points per second.
-- sens_db: how far a take must rise (above the noise floor, and out of the dip
-- before it); gap_ms: the shortest quiet gap that separates two takes.
-- Continuous material (ambiences, music) gives no takes.
-- Returns { { s = sec, e = sec }, ... }.
local function detect_takes(env, rate, sens_db, gap_ms)
  local n = #env
  if n < 4 then return {} end
  local FLOOR_DB = -120
  local db, hist = {}, {}
  for i = 1, n do
    local v = env[i]
    local d = v > 1e-6 and 20 * math.log(v, 10) or FLOOR_DB
    d = clamp(d, FLOOR_DB, 24)
    db[i] = d
    local k = math.floor(d - FLOOR_DB)
    hist[k] = (hist[k] or 0) + 1
  end
  local function percentile(p)
    local want, acc = p * n, 0
    for k = 0, 150 do
      acc = acc + (hist[k] or 0)
      if acc >= want then return FLOOR_DB + k end
    end
    return FLOOR_DB + 150
  end
  local floor_db, top_db = percentile(0.05), percentile(0.995)
  local range = top_db - floor_db
  if range < sens_db + 6 then return {} end
  local on = floor_db + math.max(sens_db, range * 0.3)
  local off = floor_db + math.max(sens_db * 0.5, range * 0.15)
  local gap = math.max(1, math.floor(gap_ms / 1000 * rate))
  local min_len = math.max(1, math.floor(0.02 * rate))

  local regions, i = {}, 1
  while i <= n do
    if db[i] >= on then
      -- The take starts where the sound first rose above the lower threshold.
      local s = i
      local prev_end = regions[#regions] and regions[#regions].ie or 0
      while s > prev_end + 1 and db[s - 1] >= off do s = s - 1 end
      -- It ends once the sound stays under the lower threshold for a gap.
      local last, j = i, i + 1
      while j <= n and j - last <= gap do
        if db[j] >= off then last = j end
        j = j + 1
      end
      if last - s + 1 >= min_len then regions[#regions + 1] = { is = s, ie = last } end
      i = j
    else
      i = i + 1
    end
  end

  local covered = 0
  for _, r in ipairs(regions) do covered = covered + (r.ie - r.is + 1) end
  if #regions == 0 or covered > 0.85 * n or (#regions == 1 and covered > 0.6 * n) then
    return {}
  end

  -- Inside a region (where a tail never went quiet), a dip that stays sens_db
  -- under the peak before it for at least a gap, followed by a rise of
  -- sens_db, starts a new take at the bottom of the dip. Shorter dips
  -- (dropouts, tremolo) do not. The envelope is first held over 25 ms so the
  -- grains of a crackle do not count as dips.
  local HOLD = math.max(1, math.floor(0.0125 * rate))
  local min_piece = math.max(min_len, math.floor(math.max(0.06, gap_ms / 2000) * rate))
  local takes = {}
  for _, r in ipairs(regions) do
    local sd = {}
    for k = r.is, r.ie do
      local m = FLOOR_DB
      for q = math.max(r.is, k - HOLD), math.min(r.ie, k + HOLD) do
        if db[q] > m then m = db[q] end
      end
      sd[k] = m
    end
    local cuts = { r.is }
    local peak, valley, vi, low_from = sd[r.is], math.huge, nil, nil
    for k = r.is + 1, r.ie do
      local d = sd[k]
      if vi and d - valley >= sens_db and k - low_from >= gap and vi - cuts[#cuts] >= min_piece then
        cuts[#cuts + 1] = vi
        peak, valley, vi, low_from = d, math.huge, nil, nil
      elseif d >= peak then
        peak, valley, vi, low_from = d, math.huge, nil, nil
      elseif d > peak - sens_db then
        -- Back near the peak: the dip before separated nothing.
        valley, vi, low_from = math.huge, nil, nil
      else
        low_from = low_from or k
        if d < valley then valley, vi = d, k end
      end
    end
    -- A last piece too short to be a take stays with the one before.
    if #cuts > 1 and r.ie - cuts[#cuts] + 1 < min_piece then cuts[#cuts] = nil end
    for k = 1, #cuts do
      local s, e = cuts[k], (cuts[k + 1] and cuts[k + 1] - 1 or r.ie)
      takes[#takes + 1] = { s = (s - 1) / rate, e = e / rate }
    end
  end
  return takes
end

-- Where the item window goes on a double-click at source time t.
-- ws / wl: current window start and length; lo / hi: allowed window starts;
-- tol: how far (in seconds) a click may land from a take and still pick it.
-- On a take: the take's start lands where the start of the take now in the
-- window sits (so the sync in the timeline holds). Elsewhere: centred on t.
local function jump_window(takes, t, ws, wl, lo, hi, tol)
  local hit, best = nil, tol or 0
  for _, tk in ipairs(takes) do
    if t >= tk.s and t <= tk.e then hit = tk; break end
    local d = t < tk.s and tk.s - t or t - tk.e
    if d <= best then hit, best = tk, d end
  end
  local nws
  if hit then
    -- The reference: the first take starting inside the window; failing
    -- that, the take the window starts in (the cut falls inside it).
    local rel
    for _, tk in ipairs(takes) do
      if tk.s >= ws and tk.s < ws + wl then rel = tk.s - ws; break end
    end
    if not rel then
      for _, tk in ipairs(takes) do
        if tk.s < ws and tk.e > ws then rel = tk.s - ws; break end
      end
    end
    nws = hit.s - (rel or 0)
  else
    nws = t - wl / 2
  end
  if hi < lo then hi = lo end
  return clamp(nws, lo, hi), hit ~= nil
end

-- The sounds inside one recorder segment (between its pre-roll and its hold,
-- both near silence). levels: linear peak per bin (1-based), rate: bins per
-- second. Several sounds are split as takes are in a file; a segment that is
-- sound throughout is only trimmed of its quiet ends. Returns
-- { { s = sec, e = sec }, ... } from the segment's first bin.
local function segment_sounds(levels, rate, sens_db, gap_ms)
  local n = #levels
  if n < 4 then return { { s = 0, e = n / rate } } end
  local tk = detect_takes(levels, rate, sens_db, gap_ms)
  if #tk > 0 then return tk end
  -- Trim: the first and last bins clearly above the quietest 5 %.
  local db = {}
  for i = 1, n do
    local v = levels[i]
    db[i] = v > 1e-6 and 20 * math.log(v, 10) or -120
  end
  local sorted = {}
  for i = 1, n do sorted[i] = db[i] end
  table.sort(sorted)
  local floor_db, top_db = sorted[math.max(1, math.floor(n * 0.05))], sorted[n]
  if top_db - floor_db < sens_db then return { { s = 0, e = n / rate } } end
  local thr = floor_db + math.max(6, (top_db - floor_db) * 0.15)
  local a, b = 1, n
  while a < n and db[a] < thr do a = a + 1 end
  while b > a and db[b] < thr do b = b - 1 end
  return { { s = (a - 1) / rate, e = b / rate } }
end

-- Pulls frame f onto the nearest boundary (s or e of any span in segs)
-- closer than tol frames.
local function snap_frame(f, segs, tol)
  local best, dist = f, tol
  for _, sg in ipairs(segs) do
    local d = math.abs(sg.s - f)
    if d <= dist then best, dist = sg.s, d end
    d = math.abs(sg.e - f)
    if d <= dist then best, dist = sg.e, d end
  end
  return best
end

-- What dragging the selection from height y takes out: stereo; with the
-- formats shown (Cmd held) its height splits in three bands, top to bottom:
-- mono, stereo, original.
local GRIP_BANDS = { 'mono', 'stereo', 'orig' }
local function grip_at(y, top, h, formats)
  if not formats then return 'stereo' end
  return GRIP_BANDS[clamp(math.floor((y - top) / (h / 3)) + 1, 1, 3)]
end

-- What a dragged-out selection becomes. peaks: per-channel peak (1-based),
-- lr_diff: peak of (ch1 - ch2). A channel "plays" within 60 dB of the
-- loudest one. With auto_mono, stereo turns mono when only one side plays or
-- both sides are the same signal; mono mixes only the channels that play.
-- Returns the output kind ('mono' | 'stereo' | 'orig') and the channels to mix
-- (1-based) for mono.
local function export_layout(fmt, peaks, lr_diff, auto_mono)
  local n = #peaks
  local top = 0
  for c = 1, n do if peaks[c] > top then top = peaks[c] end end
  local floor_ = top * 10 ^ (-60 / 20)
  local function plays(c) return peaks[c] and peaks[c] > 0 and peaks[c] >= floor_ end
  if fmt == 'orig' and n > 1 then return 'orig', nil end
  if fmt == 'stereo' and n > 1 then
    if not auto_mono then return 'stereo', nil end
    local l, r = plays(1), plays(2)
    if l and r then
      if lr_diff <= math.max(peaks[1], peaks[2]) * 1e-4 then return 'mono', { 1 } end
      return 'stereo', nil
    end
    if r then return 'mono', { 2 } end
    return 'mono', { 1 }
  end
  local mix = {}
  for c = 1, n do if plays(c) then mix[#mix + 1] = c end end
  if #mix == 0 then for c = 1, n do mix[c] = c end end
  return 'mono', mix
end

-- Where a sound really starts, to the sample. levels: per-frame peak over
-- all channels (1-based); the first `lead` frames come before the selection
-- and hold only noise; peak: the loudest sample of the selection. The onset
-- is the first frame after the lead that clearly rises above that noise (and
-- above -60 dB under the peak); the cut goes `margin` frames before it.
-- Returns the 0-based frame to start from (lead when nothing rises).
local function find_onset(levels, lead, peak, margin)
  local noise = 0
  for i = 1, lead do
    if levels[i] > noise then noise = levels[i] end
  end
  local thr = math.max(noise * 2, peak * 10 ^ (-60 / 20), 1e-6)
  if lead == 0 then thr = math.max(thr, peak * 10 ^ (-50 / 20)) end
  for i = lead + 1, #levels do
    if levels[i] >= thr then return math.max(0, i - 1 - margin) end
  end
  return lead
end

-- 32-bit float WAV (format 3), interleaved.
local function wav_header(nch, srate, frames)
  local data_bytes = frames * nch * 4
  return 'RIFF' .. string.pack('<I4', 36 + data_bytes) .. 'WAVE'
    .. 'fmt ' .. string.pack('<I4I2I2I4I4I2I2', 16, 3, nch, srate, srate * nch * 4, nch * 4, 32)
    .. 'data' .. string.pack('<I4', data_bytes)
end

local PACK_BATCH = 2048
local PACK_FMT = '<' .. string.rep('f', PACK_BATCH)
local function pack_floats(t, n)
  local parts = {}
  local i = 1
  while i <= n do
    local m = math.min(PACK_BATCH, n - i + 1)
    local fmt = m == PACK_BATCH and PACK_FMT or ('<' .. string.rep('f', m))
    parts[#parts + 1] = string.pack(fmt, table.unpack(t, i, i + m - 1))
    i = i + m
  end
  return table.concat(parts)
end

-- The floats in a string of packed little-endian floats, into t from 1.
local function unpack_floats(s, t)
  local n, pos, len = 0, 1, #s // 4
  while n < len do
    local m = math.min(PACK_BATCH, len - n)
    local fmt = m == PACK_BATCH and PACK_FMT or ('<' .. string.rep('f', m))
    local vals = { string.unpack(fmt, s, pos) }
    for k = 1, m do t[n + k] = vals[k] end
    pos = vals[m + 1]
    n = n + m
  end
  return n
end

-- END PURE
------------------------------------------------------------------------------
-- Settings: saved in ExtState, edited in the gear panel.

local DEFAULTS = {
  rec_threshold = -74, -- dBFS: the recorder writes only above this
  rec_preroll = 50,    -- ms kept from before the signal crossed the threshold
  rec_hold = 300,      -- ms the recorder keeps going after the signal fell below
  rec_length = 60,     -- s of sound the recorder keeps
  take_sens = 12,      -- dB above the noise floor a take in a file must rise
  take_gap = 150,      -- ms of quiet that separates two takes in a file
  drop_snap = true,    -- dropped recordings snap to the grid when snapping is on
  stereo_auto_mono = false, -- a stereo drag-out turns mono when both sides are the same
  wave_gamma = 0.5,    -- waveform display curve: 1 = linear, lower = dynamics compressed
}
local cfg = {}
for k, v in pairs(DEFAULTS) do
  local s = reaper.GetExtState(EXT, k)
  if s == '' then cfg[k] = v
  elseif type(v) == 'boolean' then cfg[k] = s == '1'
  else cfg[k] = tonumber(s) or v end
end
local function save_cfg(k)
  local v = cfg[k]
  if type(v) == 'boolean' then v = v and '1' or '0' end
  reaper.SetExtState(EXT, k, tostring(v), true)
end

------------------------------------------------------------------------------
-- Look: mtt_FmodSync's palette, square corners and gear; docked, the colours
-- come from the REAPER theme's background as in FMOD Sync Mini.

local COL_ACCENT = 0xE89B3CFF
local COL_REC = 0xFF6464FF
local COL_BUTTON = 0x303435FF
local palette = {
  { ImGui.Col_WindowBg, 0x191A1BFF }, { ImGui.Col_TitleBg, 0x202223FF },
  { ImGui.Col_TitleBgActive, 0x292B2CFF }, { ImGui.Col_Text, 0xECEEEBFF },
  { ImGui.Col_TextDisabled, 0xA6AAA8FF }, { ImGui.Col_Separator, 0x464A49FF },
  { ImGui.Col_FrameBg, 0x2D3031FF }, { ImGui.Col_FrameBgHovered, 0x373B3CFF },
  { ImGui.Col_FrameBgActive, 0x3C4142FF }, { ImGui.Col_Button, COL_BUTTON },
  { ImGui.Col_ButtonHovered, 0x414948FF }, { ImGui.Col_ButtonActive, 0x4D5956FF },
  { ImGui.Col_CheckMark, COL_ACCENT }, { ImGui.Col_Header, 0x3A3328FF },
  { ImGui.Col_HeaderHovered, 0x4D4129FF }, { ImGui.Col_HeaderActive, 0x9A6322FF },
  { ImGui.Col_SliderGrab, COL_ACCENT }, { ImGui.Col_SliderGrabActive, 0xF0B462FF },
  { ImGui.Col_TextSelectedBg, 0xE89B3C66 },
  { ImGui.Col_ScrollbarGrab, 0x58534AFF }, { ImGui.Col_ScrollbarGrabHovered, 0x756A4FFF },
  { ImGui.Col_ScrollbarGrabActive, COL_ACCENT },
  { ImGui.Col_ResizeGrip, 0xE89B3C33 }, { ImGui.Col_ResizeGripHovered, 0xE89B3C99 },
  { ImGui.Col_ResizeGripActive, COL_ACCENT },
}
local style_vars = {
  { ImGui.StyleVar_WindowRounding, 0 }, { ImGui.StyleVar_ChildRounding, 0 },
  { ImGui.StyleVar_PopupRounding, 0 }, { ImGui.StyleVar_ScrollbarRounding, 0 },
  { ImGui.StyleVar_GrabRounding, 0 }, { ImGui.StyleVar_FrameRounding, 0 },
  { ImGui.StyleVar_WindowPadding, 6, 5 },
  { ImGui.StyleVar_ItemSpacing, 8, 5 },
  { ImGui.StyleVar_FramePadding, 9, 3 },
}

local FONT_SIZE = 13
local ok_font, font = pcall(function()
  local f = ImGui.CreateFont('sans-serif')
  ImGui.Attach(ctx, f)
  return f
end)
if not ok_font then font = nil end

local function theme_palette()
  local native = reaper.GetThemeColor('col_main_bg', 0)
  if not native or native == -1 then return {} end
  local r, g, b = reaper.ColorFromNative(native)
  local light = (0.299 * r + 0.587 * g + 0.114 * b) > 128
  local function shade(d, a)
    if light then d = -d end
    local function c(v) return math.max(0, math.min(255, v + d)) end
    return (c(r) << 24) | (c(g) << 16) | (c(b) << 8) | (a or 0xFF)
  end
  local out = {
    { ImGui.Col_WindowBg, shade(0) }, { ImGui.Col_ChildBg, 0 }, { ImGui.Col_PopupBg, shade(10) },
    { ImGui.Col_FrameBg, shade(20) }, { ImGui.Col_FrameBgHovered, shade(30) }, { ImGui.Col_FrameBgActive, shade(36) },
    { ImGui.Col_Button, shade(26) }, { ImGui.Col_ButtonHovered, shade(38) }, { ImGui.Col_ButtonActive, shade(48) },
    { ImGui.Col_TableHeaderBg, shade(16) }, { ImGui.Col_TableBorderStrong, shade(34) },
    { ImGui.Col_TableBorderLight, shade(24) },
    { ImGui.Col_Separator, shade(34) }, { ImGui.Col_Border, shade(30) },
  }
  if light then
    out[#out + 1] = { ImGui.Col_Text, 0x1E1F20FF }
    out[#out + 1] = { ImGui.Col_TextDisabled, 0x5E6260FF }
  end
  return out
end

local pushed_theme = 0
local function push_style()
  if font then ImGui.PushFont(ctx, font, FONT_SIZE) end
  for _, pair in ipairs(palette) do ImGui.PushStyleColor(ctx, pair[1], pair[2]) end
  local theme = theme_palette()
  for _, pair in ipairs(theme) do ImGui.PushStyleColor(ctx, pair[1], pair[2]) end
  pushed_theme = #theme
  for _, v in ipairs(style_vars) do
    if v[3] then ImGui.PushStyleVar(ctx, v[1], v[2], v[3]) else ImGui.PushStyleVar(ctx, v[1], v[2]) end
  end
end

local function pop_style()
  ImGui.PopStyleVar(ctx, #style_vars)
  ImGui.PopStyleColor(ctx, #palette + pushed_theme)
  if font then ImGui.PopFont(ctx) end
end

-- Six-tooth gear in a 1 px outline (mtt_FmodSync's icon).
local function paint_gear(dl, x, y, h, col)
  local TEETH = 6
  local cx, cy = math.floor(x + h / 2) + 0.5, math.floor(y + h / 2) + 0.5
  local r_out, r_in, r_hole = h * 0.27, h * 0.20, h * 0.093
  local pitch = 2 * math.pi / TEETH
  ImGui.DrawList_PathClear(dl)
  for i = 0, TEETH - 1 do
    local a = i * pitch - math.pi / 2
    for _, p in ipairs({ { a - pitch * 0.21, r_in }, { a - pitch * 0.11, r_out },
                         { a + pitch * 0.11, r_out }, { a + pitch * 0.21, r_in } }) do
      ImGui.DrawList_PathLineTo(dl, cx + math.cos(p[1]) * p[2], cy + math.sin(p[1]) * p[2])
    end
  end
  ImGui.DrawList_PathStroke(dl, col, ImGui.DrawFlags_Closed, 1)
  ImGui.DrawList_AddCircle(dl, cx, cy, r_hole, col, 0, 1)
end

-- Same colour with another alpha (0..255).
local function with_alpha(col, a) return (col & 0xFFFFFF00) | a end

------------------------------------------------------------------------------
-- The recorder: mtt_dock_recorder.jsfx on the master, reached through gmem.
-- These slots must match the G_*/L_* ones in the JSFX.

local G = { MAGIC = 0, PROTO = 1, HB = 2, GEN = 3, SRATE = 4, NCH = 5, CAP = 6, W = 7,
  K = 8, NB = 9, GATE = 10, LEVEL = 11, SEGTOT = 12, PLAYPOS = 13, EXPDONE = 14,
  EXPN = 15, EXPSTART = 16 }
local L = { HB = 20, THR = 21, PRE = 22, HOLD = 23, LEN = 24, PAUSE = 25, PLAY = 26,
  PLAYID = 27, PLAYFROM = 28, EXPID = 29, EXPSTART = 30, EXPN = 31, CLEAR = 32, CFG = 33 }
local SEG_BASE, SEGN = 64, 2048
local PK_BASE = SEG_BASE + 2 * SEGN
local EXP_BASE, EXP_FLOATS = 1048576, 131072
local MAGIC, PROTO = 7741, 2 -- PROTO must match the JSFX's
local JSFX_FILE = 'mtt_dock_recorder.jsfx'
local JSFX_DESC = 'mtt_dock recorder'
local JSFX_MEMTOP = 128000000 -- the JSFX's options:maxmem
local REC_LEN_MIN, REC_LEN_MAX = 10, 600 -- s; the JSFX accepts 5..600

-- gmem is restored to what this script had attached before, in atexit.
local prev_gmem = reaper.gmem_attach('mtt_dock')
local rd, wr = reaper.gmem_read, reaper.gmem_write

local R = {
  alive = false, proto_ok = true, hb = -1, hb_time = 0, lua_hb = 0, gen = -1,
  srate = 48000, nch = 2, cap = 0, K = 64, nb = 0, W = 0, oldest = 0,
  pmax = {}, pmin = {}, next_bin = 0, segs = {},
  sounds = {}, snaps = {}, sound_cache = {}, -- sounds found inside the segments
  gate = false, level = 0, playpos = -1,
  fx_idx = nil, fx_count = 0, fx_check = 0, -- where the recorder sits on the master
  sel = nil,             -- { a, b } absolute frames
  span = nil,            -- frames shown; nil = the whole buffer
  view_end = nil,        -- last frame shown; nil = live (follows the recording)
  pinned_by_hover = false,
  gain = 1,
}

local function recorder_update(now)
  R.lua_hb = R.lua_hb % 1000000 + 1
  wr(L.HB, R.lua_hb)
  wr(L.THR, cfg.rec_threshold); wr(L.PRE, cfg.rec_preroll); wr(L.HOLD, cfg.rec_hold)
  wr(L.LEN, cfg.rec_length); wr(L.CFG, 1)

  local hb = rd(G.HB)
  if hb ~= R.hb then R.hb, R.hb_time = hb, now end
  R.alive = rd(G.MAGIC) == MAGIC and now - R.hb_time < 1.0
  R.proto_ok = rd(G.PROTO) == PROTO
  if not R.alive then return end

  local gen = rd(G.GEN)
  if gen ~= R.gen then
    -- The recorder was (re)started, cleared or resized: start over.
    R.gen = gen
    R.srate, R.nch, R.cap = rd(G.SRATE), math.floor(rd(G.NCH)), rd(G.CAP)
    R.K, R.nb = math.floor(rd(G.K)), math.floor(rd(G.NB))
    R.pmax, R.pmin, R.next_bin, R.sel = {}, {}, 0, nil
    R.span, R.view_end, R.pinned_by_hover = nil, nil, false
    R.sound_cache = {}
  end
  R.W = rd(G.W)
  R.oldest = math.max(0, R.W - R.cap)
  R.gate = rd(G.GATE) > 0
  R.level = rd(G.LEVEL)
  R.playpos = rd(G.PLAYPOS)
  if R.nb <= 0 or R.K <= 0 then return end

  -- Peaks: the bins completed since last frame, plus the one being filled.
  local full = math.floor(R.W / R.K)
  local last = math.floor((R.W - 1) / R.K)
  -- (bin full - nb shares its slot with the bin being filled: skip it)
  for b = math.max(R.next_bin, full - R.nb + 1), last do
    local slot = b % R.nb
    R.pmax[slot] = rd(PK_BASE + 2 * slot)
    R.pmin[slot] = rd(PK_BASE + 2 * slot + 1)
  end
  R.next_bin = full

  -- Segments still (partly) in the buffer, oldest first.
  local tot = math.floor(rd(G.SEGTOT))
  local segs = {}
  for k = tot - 1, math.max(0, tot - SEGN), -1 do
    local slot = k % SEGN
    local s, e = rd(SEG_BASE + 2 * slot), rd(SEG_BASE + 2 * slot + 1)
    if e < 0 then e = R.W end
    if e <= R.oldest then break end
    segs[#segs + 1] = { s = math.max(s, R.oldest), e = e, raw = s }
  end
  R.segs = {}
  for k = #segs, 1, -1 do R.segs[#R.segs + 1] = segs[k] end

  if R.sel then
    if R.sel[2] <= R.oldest then R.sel = nil else R.sel[1] = math.max(R.sel[1], R.oldest) end
  end
end

-- Max and min of the recording over frames [f0, f1), or nil where there is none.
local function rec_peak(f0, f1)
  local lo, hi = math.max(f0, R.oldest), math.min(f1, R.W)
  if hi <= lo or R.nb <= 0 then return nil end
  local mx, mn = 0, 0
  local pmax, pmin, nb = R.pmax, R.pmin, R.nb
  local b0 = math.max(math.floor(lo / R.K), math.floor(R.W / R.K) - nb + 1)
  for b = b0, math.floor((hi - 1) / R.K) do
    local slot = b % nb
    local a = pmax[slot]
    if a and a > mx then mx = a end
    a = pmin[slot]
    if a and a < mn then mn = a end
  end
  return mx, mn
end

-- The sounds inside each segment, onset to tail (segment_sounds on the peak
-- bins), padded a little and cut at the segment. A segment that is closed and
-- whole never changes, so its sounds are kept; the one still recording (or
-- being overwritten at the old end) is looked at again every 0.25 s.
-- The onset bin starts at most one bin (K frames) before the sound; the
-- export then cuts at the sample (find_onset).
local SOUND_PRE, SOUND_POST = 0, 0.010 -- s kept before an onset / after a tail
local function segment_sound_list(sg, now)
  local params = cfg.take_sens .. '|' .. cfg.take_gap
  local c = R.sound_cache[sg.raw]
  if c and c.params == params and ((c.e == sg.e and c.s == sg.s) or now - c.t < 0.25) then
    return c.list
  end
  local K, nb = R.K, R.nb
  local b0 = math.max(math.floor(sg.s / K), math.floor(R.W / K) - nb + 1)
  local b1 = math.floor((sg.e - 1) / K)
  local levels = {}
  for b = b0, b1 do
    local slot = b % nb
    local a, m = R.pmax[slot] or 0, -(R.pmin[slot] or 0)
    levels[#levels + 1] = a > m and a or m
  end
  local list = {}
  for _, t in ipairs(segment_sounds(levels, R.srate / K, cfg.take_sens, cfg.take_gap)) do
    local a = math.floor(clamp(b0 * K + (t.s - SOUND_PRE) * R.srate, sg.s, sg.e))
    local e = math.floor(clamp(b0 * K + (t.e + SOUND_POST) * R.srate, sg.s, sg.e))
    if #list > 0 and a < list[#list].e then a = list[#list].e end
    if e > a then list[#list + 1] = { s = a, e = e } end
  end
  R.sound_cache[sg.raw] = { s = sg.s, e = sg.e, t = now, params = params, list = list }
  return list
end

local function recorder_sounds(now)
  R.sounds, R.snaps = {}, {}
  if R.nb <= 0 then return end
  -- Every few seconds, forget the segments that left the buffer.
  if now - (R.cache_pruned or 0) > 5 then
    R.cache_pruned = now
    local keep = {}
    for _, sg in ipairs(R.segs) do keep[sg.raw] = R.sound_cache[sg.raw] end
    R.sound_cache = keep
  end
  for _, sg in ipairs(R.segs) do
    R.snaps[#R.snaps + 1] = sg
    for _, so in ipairs(segment_sound_list(sg, now)) do
      R.sounds[#R.sounds + 1] = so
      R.snaps[#R.snaps + 1] = so
    end
  end
end

-- The longest buffer the JSFX memory holds at the master's channel count and
-- sample rate (its pre-roll ring comes first), within REC_LEN_MIN..REC_LEN_MAX.
local function rec_len_max()
  if not R.alive or R.srate <= 0 or R.nch < 1 then return REC_LEN_MAX end
  local pre = math.ceil(0.5 * R.srate)
  local frames = (JSFX_MEMTOP - 64 - pre * R.nch) / R.nch
  return clamp(math.floor(frames / R.srate), REC_LEN_MIN, REC_LEN_MAX)
end

-- The recorders on the master (indices) and where the first one sits.
local function find_recorders(master)
  local list = {}
  for i = 0, reaper.TrackFX_GetCount(master) - 1 do
    local _, name = reaper.TrackFX_GetFXName(master, i)
    local _, ident = reaper.TrackFX_GetNamedConfigParm(master, i, 'fx_ident')
    if (name or ''):find(JSFX_DESC, 1, true) or (ident or ''):find(JSFX_FILE, 1, true) then
      list[#list + 1] = i
    end
  end
  return list
end

-- Checked twice a second.
local function recorder_fx(now)
  if now - R.fx_check < 0.5 then return end
  R.fx_check = now
  local master = reaper.GetMasterTrack(0)
  local list = find_recorders(master)
  R.fx_count = reaper.TrackFX_GetCount(master)
  R.fx_idx, R.fx_n = list[1], #list
end

-- Copies the JSFX next to this script into <resources>/Effects/mtt/ (when it
-- is missing or differs) and adds it at the end of the master chain. replace:
-- the recorders already on the master go first (an older version, or more
-- than one); their recordings are lost.
local install_error = nil
local function install_recorder(replace)
  install_error = nil
  local f = io.open(SCRIPT_DIR .. JSFX_FILE, 'rb')
  if not f then install_error = JSFX_FILE .. ' is missing next to the script.'; return end
  local data = f:read('a')
  f:close()
  local dir = reaper.GetResourcePath() .. SEP .. 'Effects' .. SEP .. 'mtt'
  local dst = dir .. SEP .. JSFX_FILE
  local cur
  local g = io.open(dst, 'rb')
  if g then cur = g:read('a'); g:close() end
  if cur ~= data then
    reaper.RecursiveCreateDirectory(dir, 0)
    local h = io.open(dst, 'wb')
    if not h then install_error = 'Cannot write ' .. dst; return end
    h:write(data)
    h:close()
  end
  local master = reaper.GetMasterTrack(0)
  reaper.Undo_BeginBlock()
  if replace then
    local list = find_recorders(master)
    for k = #list, 1, -1 do reaper.TrackFX_Delete(master, list[k]) end -- from the last: indices shift
  end
  local idx = -1
  for _, name in ipairs({ 'JS:mtt/' .. JSFX_FILE, 'mtt/' .. JSFX_FILE, 'JS:mtt/mtt_dock_recorder' }) do
    idx = reaper.TrackFX_AddByName(master, name, false, -1)
    if idx >= 0 then break end
  end
  reaper.Undo_EndBlock(replace and 'mtt_dock: update recorder on master' or 'mtt_dock: add recorder to master', -1)
  if idx < 0 then install_error = 'REAPER could not load ' .. dst end
  R.fx_check = 0
end

local function move_recorder_last()
  local master = reaper.GetMasterTrack(0)
  local n = reaper.TrackFX_GetCount(master)
  if not R.fx_idx or R.fx_idx == n - 1 then return end
  reaper.Undo_BeginBlock()
  reaper.TrackFX_CopyToTrack(master, R.fx_idx, master, n - 1, true)
  reaper.Undo_EndBlock('mtt_dock: move recorder to the end of the master chain', -1)
  R.fx_check = 0
end

local function rec_play_start(frame)
  wr(L.PLAYFROM, frame)
  wr(L.PLAYID, rd(L.PLAYID) + 1)
  wr(L.PAUSE, 1) -- the recorder must not record what the dock plays
  wr(L.PLAY, 1)
end

local function rec_play_stop()
  wr(L.PLAY, 0)
  wr(L.PAUSE, 0)
end

------------------------------------------------------------------------------
-- Export: the selection is fetched from the recorder one chunk per round trip
-- into a raw temporary file (all channels), measuring each channel on the way;
-- then export_layout decides what it becomes (stereo turns mono when both
-- sides carry the same signal) and the WAV is written in the project's
-- recording folder, a slice per frame, then inserted where it was dropped.
-- It starts when the drag starts, so it is usually done by the drop.

local job = nil
local peak_jobs = {} -- sources of inserted items whose peaks are being built
local CONVERT_FRAMES = 65536 -- frames converted per defer cycle

local function close_job_files()
  if job.raw_f then job.raw_f:close(); job.raw_f = nil end
  if job.out_f then job.out_f:close(); job.out_f = nil end
end

local function export_cancel(msg)
  if not job then return end
  close_job_files()
  -- Only the files this job wrote, by their exact paths.
  if job.raw_path then os.remove(job.raw_path) end
  if job.path and job.state ~= 'done' then os.remove(job.path) end
  job.state, job.msg = 'failed', msg
end

local function unique_path(dir, base, ext)
  local path, n = dir .. SEP .. base .. ext, 1
  while reaper.file_exists(path) do
    n = n + 1
    path = dir .. SEP .. base .. '_' .. n .. ext
  end
  return path
end

-- trim: the selection starts on a sound found in the recording; a few ms
-- before it are fetched too (within its segment) to measure the noise, and
-- the file is cut at the sound's first sample.
local ONSET_LEAD, ONSET_SCAN, ONSET_MARGIN = 0.005, 0.02, 0.00025 -- s
local function export_start(a, b, fmt, trim)
  if job and job.state ~= 'done' and job.state ~= 'failed' then export_cancel() end
  local lead = 0
  if trim then
    local lo = R.oldest
    for _, sg in ipairs(R.segs) do
      if a >= sg.s and a < sg.e then lo = math.max(lo, sg.s); break end
    end
    lead = math.max(0, math.min(math.floor(ONSET_LEAD * R.srate), a - lo))
  end
  local dir = reaper.GetProjectPath()
  reaper.RecursiveCreateDirectory(dir, 0)
  local stamp = 'mtt_dock_' .. os.date('%Y%m%d_%H%M%S')
  local peaks = {}
  for c = 1, R.nch do peaks[c] = 0 end
  job = { a = a - lead, b = b, next = a - lead, fmt = fmt, nin = R.nch, srate = math.floor(R.srate + 0.5),
    dir = dir, stamp = stamp, frames = 0, peaks = peaks, lr_diff = 0, trim = trim, lead = lead,
    gen = R.gen, state = 'request', t = 0 }
  job.raw_path = unique_path(dir, stamp, '.mtt_dock_tmp')
  job.raw_f = io.open(job.raw_path, 'wb')
  if not job.raw_f then
    job.raw_path = nil
    job.state, job.msg = 'failed', 'Cannot write in ' .. dir
  end
end

local function export_read_chunk(n)
  local nin, peaks = job.nin, job.peaks
  local out, k, d = {}, 0, job.lr_diff
  for i = 0, n - 1 do
    local o = EXP_BASE + i * nin
    for c = 1, nin do
      local v = rd(o + c - 1)
      k = k + 1
      out[k] = v
      if v < 0 then v = -v end
      if v > peaks[c] then peaks[c] = v end
    end
    if nin > 1 then
      local x = out[k - nin + 1] - out[k - nin + 2]
      if x < 0 then x = -x end
      if x > d then d = x end
    end
  end
  job.lr_diff = d
  job.raw_f:write(pack_floats(out, k))
  job.frames = job.frames + n
end

-- All fetched: decide the layout, open the raw file for reading and the WAV.
local function export_begin_convert()
  job.raw_f:close()
  job.raw_f = io.open(job.raw_path, 'rb')
  if not job.raw_f then return export_cancel('Cannot read ' .. job.raw_path) end
  -- Where to start: the sound's first sample when trimming, else the selection.
  local start = job.lead
  if job.trim then
    local nin = job.nin
    local head = math.min(job.frames, job.lead + math.floor(ONSET_SCAN * job.srate))
    local t = {}
    unpack_floats(job.raw_f:read(head * nin * 4) or '', t)
    local levels, peak = {}, 0
    for i = 0, head - 1 do
      local m = 0
      for c = 1, nin do
        local v = t[i * nin + c] or 0
        if v < 0 then v = -v end
        if v > m then m = v end
      end
      levels[i + 1] = m
    end
    for c = 1, nin do if job.peaks[c] > peak then peak = job.peaks[c] end end
    start = find_onset(levels, job.lead, peak, math.floor(ONSET_MARGIN * job.srate))
  end
  job.raw_f:seek('set', start * job.nin * 4)
  job.frames = job.frames - start
  local kind, mix = export_layout(job.fmt, job.peaks, job.lr_diff, cfg.stereo_auto_mono)
  job.kind, job.mix = kind, mix
  job.nout = kind == 'mono' and 1 or kind == 'stereo' and 2 or job.nin
  local label = kind == 'orig' and (job.nin .. 'ch') or kind
  job.name = job.stamp .. '_' .. label
  job.path = unique_path(job.dir, job.name, '.wav')
  job.out_f = io.open(job.path, 'wb')
  if not job.out_f then return export_cancel('Cannot write ' .. job.path) end
  job.out_f:write(wav_header(job.nout, job.srate, job.frames))
  job.done_frames = 0
  job.state = 'convert'
end

local function export_convert_slice()
  local nin = job.nin
  local m = math.min(CONVERT_FRAMES, job.frames - job.done_frames)
  if m > 0 then
    local data = job.raw_f:read(m * nin * 4) or ''
    local t = {}
    local got = unpack_floats(data, t) // nin
    local out, k = {}, 0
    if job.kind == 'mono' then
      local mix, nm = job.mix, #job.mix
      for i = 0, got - 1 do
        local s = 0
        for q = 1, nm do s = s + t[i * nin + mix[q]] end
        k = k + 1
        out[k] = s / nm
      end
    elseif job.kind == 'stereo' then
      for i = 0, got - 1 do -- more than two channels: the first pair
        out[k + 1], out[k + 2] = t[i * nin + 1], t[i * nin + 2]
        k = k + 2
      end
    else
      out, k = t, got * nin
    end
    job.out_f:write(pack_floats(out, k))
    job.done_frames = job.done_frames + got
    if got < m then job.frames = job.done_frames end -- raw file shorter than counted
  end
  if job.done_frames >= job.frames then
    if job.done_frames ~= job.frames then
      job.out_f:seek('set', 0)
      job.out_f:write(wav_header(job.nout, job.srate, job.frames))
    end
    close_job_files()
    os.remove(job.raw_path)
    job.raw_path = nil
    job.state = 'written'
  end
end

local function insert_recording(target)
  local pos = target.pos
  -- 1157 = Options: Toggle snapping (the magnet); its toggle state is "snap on".
  if cfg.drop_snap and reaper.GetToggleCommandState(1157) == 1 then
    pos = reaper.SnapToGrid(0, pos)
  end
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  local track = target.track
  if not track then
    reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
    track = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
  end
  local item = reaper.AddMediaItemToTrack(track)
  local take = reaper.AddTakeToMediaItem(item)
  local src = reaper.PCM_Source_CreateFromFile(job.path)
  reaper.SetMediaItemTake_Source(take, src)
  reaper.SetMediaItemInfo_Value(item, 'D_POSITION', pos)
  reaper.SetMediaItemInfo_Value(item, 'D_LENGTH', job.frames / job.srate)
  reaper.GetSetMediaItemTakeInfo_String(take, 'P_NAME', job.name, true)
  -- The new item becomes the only selected one (the dock then shows it).
  reaper.SelectAllMediaItems(0, false)
  reaper.SetMediaItemSelected(item, true)
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock('mtt_dock: insert recording', -1)
  peak_jobs[#peak_jobs + 1] = { src = reaper.GetMediaItemTake_Source(take), started = false }
end

local function export_step(now)
  if not job or job.state == 'done' or job.state == 'failed' then return end
  if job.state == 'request' or job.state == 'wait' then
    if not R.alive or R.gen ~= job.gen then return export_cancel('The recorder was reset.') end
  end
  for _ = 1, 2 do
    if job.state == 'request' then
      local n = math.min(job.b - job.next, EXP_FLOATS // job.nin)
      if n <= 0 then
        export_begin_convert()
        break
      end
      job.id = rd(L.EXPID) + 1
      wr(L.EXPSTART, job.next)
      wr(L.EXPN, n)
      wr(L.EXPID, job.id)
      job.state, job.t = 'wait', now
    end
    if job.state == 'wait' then
      if rd(G.EXPDONE) ~= job.id then
        if now - job.t > 2 then export_cancel('The recorder did not answer.') end
        break
      end
      local n = math.floor(rd(G.EXPN))
      if n < 0 or rd(G.EXPSTART) ~= job.next then
        return export_cancel('That part of the recording was overwritten.')
      end
      export_read_chunk(n)
      job.next = job.next + n
      job.state = 'request'
    end
  end
  if job.state == 'convert' then export_convert_slice() end
  if job.state == 'written' then
    if job.drop then
      insert_recording(job.drop)
      job.state = 'done'
    elseif job.dropped then
      export_cancel() -- released outside the arrange
    end
  end
end

-- Peaks of inserted recordings are built in the background.
local function peak_jobs_step()
  for i = #peak_jobs, 1, -1 do
    local pj = peak_jobs[i]
    if not reaper.ValidatePtr2(0, pj.src, 'PCM_source*') then
      table.remove(peak_jobs, i) -- the item was deleted meanwhile
    elseif not pj.started then
      pj.started = true
      if reaper.PCM_Source_BuildPeaks(pj.src, 0) == 0 then table.remove(peak_jobs, i) end
    elseif reaper.PCM_Source_BuildPeaks(pj.src, 1) == 0 then
      reaper.PCM_Source_BuildPeaks(pj.src, 2)
      table.remove(peak_jobs, i)
      reaper.UpdateArrange()
    end
  end
end

-- What lies under the mouse on release: a track lane, or the empty arrange
-- below the tracks (a new track is made there).
local function drop_target()
  local window, segment = reaper.BR_GetMouseCursorContext()
  if window ~= 'arrange' then return nil end
  local pos = reaper.BR_GetMouseCursorContext_Position()
  if segment == 'track' or segment == 'envelope' then
    local tr = reaper.BR_GetMouseCursorContext_Track()
    if tr then return { track = tr, pos = pos } end
  elseif segment == 'empty' then
    return { track = nil, pos = pos }
  end
  return nil
end

------------------------------------------------------------------------------
-- The selected item: its take, its source and the window the item plays.

local function item_state()
  if reaper.CountSelectedMediaItems(0) ~= 1 then return nil end
  local item = reaper.GetSelectedMediaItem(0, 0)
  local take = reaper.GetActiveTake(item)
  local st = { item = item, take = take }
  if not take then st.err = 'Empty item'; return st end
  if reaper.TakeIsMIDI(take) then st.err = 'MIDI item'; return st end
  local src = reaper.GetMediaItemTake_Source(take)
  local root, sec_off, sec_len = src, 0, nil
  local is_sec, offs, len, rev = reaper.PCM_Source_GetSectionInfo(src)
  if is_sec then
    if rev then st.err = 'Reversed take: not shown'; return st end
    local parent = reaper.GetMediaSourceParent(src)
    if parent then root, sec_off, sec_len = parent, offs, len end
  end
  local full = reaper.GetMediaSourceLength(root)
  if not full or full <= 0 then st.err = 'No audio'; return st end
  st.src, st.root, st.sec_off = src, root, sec_off
  st.full = full
  st.nch = math.max(1, reaper.GetMediaSourceNumChannels(root))
  st.srate = reaper.GetMediaSourceSampleRate(root)
  st.rate = reaper.GetMediaItemTakeInfo_Value(take, 'D_PLAYRATE')
  st.offs = reaper.GetMediaItemTakeInfo_Value(take, 'D_STARTOFFS')
  st.ws = sec_off + st.offs                                    -- window start, source time
  st.wl = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH') * st.rate -- window length
  -- Slip bounds: the window stays inside the source (or its section).
  st.lo = sec_off
  st.hi = sec_off + (sec_len or full) - st.wl
  st.track = reaper.GetMediaItem_Track(item)
  st.name = reaper.GetTakeName(take) or ''
  st.vol = math.abs(reaper.GetMediaItemInfo_Value(item, 'D_VOL') * reaper.GetMediaItemTakeInfo_Value(take, 'D_VOL'))
  st.pan = reaper.GetMediaItemTakeInfo_Value(take, 'D_PAN')
  st.pitch = reaper.GetMediaItemTakeInfo_Value(take, 'D_PITCH')
  st.ppitch = reaper.GetMediaItemTakeInfo_Value(take, 'B_PPITCH') ~= 0
  st.pitchmode = reaper.GetMediaItemTakeInfo_Value(take, 'I_PITCHMODE')
  st.key = select(2, reaper.GetSetMediaItemInfo_String(item, 'GUID', '', false)) .. '|' .. tostring(root)
  st.file = reaper.GetMediaSourceFileName(root)
  st.fkey = st.file .. '|' .. full -- the file: view, selection and takes go with it
  return st
end

local IV = { key = nil, view_s = 0, view_len = 1, gain = 1 } -- item view zoom and selection, per file
local PV = { key = nil }                                      -- peaks of the visible range
local peak_buf, peak_buf_size = nil, 0

local function get_buf(size)
  if size > peak_buf_size then
    peak_buf = reaper.new_array(size)
    peak_buf_size = size
  end
  return peak_buf
end

-- Peaks of the source from `start` over `len` seconds in n columns, all
-- channels merged: { n = columns read, mx = {}, mn = {} } (0-based).
local function source_peaks(st, start, len, n)
  local nch = st.nch
  local buf = get_buf(n * nch * 2)
  buf.clear()
  local ret = reaper.PCM_Source_GetPeaks(st.root, n / len, start, nch, n, 0, buf)
  local got = ret & 0xFFFFF
  local t = buf.table(1, n * nch * 2)
  local mx, mn = {}, {}
  for i = 0, got - 1 do
    local a, b = 0, 0
    for c = 0, nch - 1 do
      local v = t[i * nch + c + 1]
      if v > a then a = v end
      v = t[n * nch + i * nch + c + 1]
      if v < b then b = v end
    end
    mx[i], mn[i] = a, b
  end
  return { n = got, mx = mx, mn = mn }
end

-- Peaks of the visible range, one per pixel column.
local function view_peaks(st, w)
  local n = math.max(1, math.floor(w))
  local key = st.fkey .. '|' .. IV.view_s .. '|' .. IV.view_len .. '|' .. n
  if PV.key ~= key then
    PV = source_peaks(st, IV.view_s, IV.view_len, n)
    PV.key = key
  end
  return PV
end

-- Peak files: built when missing, a slice per frame.
local peaks_ready = {}
local function ensure_peaks(src)
  local k = tostring(src)
  local s = peaks_ready[k]
  if s == 'ready' then return true end
  if not s then
    if reaper.PCM_Source_BuildPeaks(src, 0) == 0 then peaks_ready[k] = 'ready'; return true end
    peaks_ready[k] = 'building'
  end
  if reaper.PCM_Source_BuildPeaks(src, 1) == 0 then
    reaper.PCM_Source_BuildPeaks(src, 2)
    peaks_ready[k] = 'ready'
    return true
  end
  return false
end

-- Take detection: an envelope of the whole file (200 points/s) read a few
-- chunks per frame, then detect_takes on it.
local ARATE, ACHUNK = 200, 16384
local TA = { key = nil }
local function analysis_step(st)
  if TA.key ~= st.fkey then
    TA = { key = st.fkey, env = {}, n = 0, total = math.ceil(st.full * ARATE), takes = nil, params = nil }
  end
  local params = cfg.take_sens .. '|' .. cfg.take_gap
  if TA.n >= TA.total then
    if TA.params ~= params then
      TA.takes = detect_takes(TA.env, ARATE, cfg.take_sens, cfg.take_gap)
      TA.params = params
    end
    return TA.takes
  end
  local nch = st.nch
  for _ = 1, 4 do
    local m = math.min(ACHUNK, TA.total - TA.n)
    local buf = get_buf(m * nch * 2)
    buf.clear()
    local ret = reaper.PCM_Source_GetPeaks(st.root, ARATE, TA.n / ARATE, nch, m, 0, buf)
    local got = ret & 0xFFFFF
    local t = buf.table(1, m * nch * 2)
    local env = TA.env
    for i = 0, got - 1 do
      local v = 0
      for c = 0, nch - 1 do
        local a = t[i * nch + c + 1]
        if a > v then v = a end
        a = -t[m * nch + i * nch + c + 1]
        if a > v then v = a end
      end
      TA.n = TA.n + 1
      env[TA.n] = v
    end
    if got < m then TA.total = TA.n end
    if TA.n >= TA.total then break end
  end
  return nil
end

-- Hold-to-play of the item: the take's own source previewed through its
-- track (FX included), with the take's volume, pan, rate and pitch.
local preview = nil
local function item_preview_stop()
  if preview then
    reaper.CF_Preview_Stop(preview)
    preview = nil
    wr(L.PAUSE, 0)
  end
end

local function item_preview_start(st, t)
  item_preview_stop()
  local p = reaper.CF_CreatePreview(st.src) -- a take's source: not ours to destroy
  if not p then return end
  reaper.CF_Preview_SetValue(p, 'D_POSITION', math.max(0, t - st.sec_off))
  reaper.CF_Preview_SetValue(p, 'D_VOLUME', st.vol)
  reaper.CF_Preview_SetValue(p, 'D_PAN', st.pan)
  reaper.CF_Preview_SetValue(p, 'D_PLAYRATE', st.rate)
  reaper.CF_Preview_SetValue(p, 'D_PITCH', st.pitch)
  reaper.CF_Preview_SetValue(p, 'B_PPITCH', st.ppitch and 1 or 0)
  reaper.CF_Preview_SetValue(p, 'D_FADEINLEN', 0.005)
  reaper.CF_Preview_SetOutputTrack(p, 0, st.track)
  reaper.CF_Preview_Play(p)
  wr(L.PAUSE, 1) -- the recorder must not record the preview passing the master
  preview = p
end

------------------------------------------------------------------------------
-- Drawing and mouse.

local S = {
  press = nil,    -- left button held in the waveform: what it started ({ kind = 'item' | 'rec', ... })
  listen = nil,   -- right button held: 'item' or 'rec' is playing
  drag = nil,     -- recorder selection being dragged out: { fmt }
  gear_rect = nil,
}

local function in_rect(x, y, r)
  return r and x >= r[1] and x < r[3] and y >= r[2] and y < r[4]
end

-- Colour a mixed into b by t (0..1), opaque.
local function blend(a, b, t)
  local function ch(c, sh) return (c >> sh) & 0xFF end
  local function mix(sh) return math.floor(ch(a, sh) * t + ch(b, sh) * (1 - t) + 0.5) end
  return (mix(24) << 24) | (mix(16) << 16) | (mix(8) << 8) | 0xFF
end

-- Orange is what the user selected (in both views); white is the part the
-- selected item plays. Waveforms are opaque, so the centre line stays under them.
local function wave_colors()
  local text = ImGui.GetColor(ctx, ImGui.Col_Text)
  local bg = ImGui.GetColor(ctx, ImGui.Col_WindowBg) -- the REAPER theme background (theme_palette)
  return {
    bg = bg,
    wave = blend(text, bg, 0.55),
    hi = COL_ACCENT,
    hi_bg = with_alpha(COL_ACCENT, 0x24),
    item = blend(text, bg, 0.95),
    item_bg = with_alpha(text, 0x16),
    item_edge = with_alpha(text, 0xC0),
    mid = ImGui.GetColor(ctx, ImGui.Col_Separator),
    dim = ImGui.GetColor(ctx, ImGui.Col_TextDisabled),
    text = text,
  }
end

-- The waveform fades out at the left and right edges of the view, so it
-- vanishes there instead of being cut: the background drawn over it, opaque
-- at the edge and clear EDGE_FADE px inside. Highlighted zones (keep: a list
-- of { x1, x2 }) are left out: they always show whole.
local EDGE_FADE = 16
local function draw_edge_fades(dl, x0, y0, w, h, col, keep)
  local fw = math.min(EDGE_FADE, w * 0.1)
  if fw <= 0 then return end
  -- One fade from xa (opaque) to xb (clear), minus the kept zones.
  local function fade(xa, xb)
    local lo, hi = math.min(xa, xb), math.max(xa, xb)
    local parts = { { lo, hi } }
    for _, k in ipairs(keep or {}) do
      local out = {}
      for _, p in ipairs(parts) do
        if k[2] <= p[1] or k[1] >= p[2] then out[#out + 1] = p
        else
          if k[1] > p[1] then out[#out + 1] = { p[1], k[1] } end
          if k[2] < p[2] then out[#out + 1] = { k[2], p[2] } end
        end
      end
      parts = out
    end
    local function col_at(x)
      local t = clamp(1 - math.abs(x - xa) / fw, 0, 1)
      return with_alpha(col.bg, math.floor(t * 255 + 0.5))
    end
    for _, p in ipairs(parts) do
      local cl, cr = col_at(p[1]), col_at(p[2])
      ImGui.DrawList_AddRectFilledMultiColor(dl, p[1], y0, p[2], y0 + h, cl, cr, cr, cl)
    end
  end
  fade(x0, x0 + fw)
  fade(x0 + w, x0 + w - fw)
end

-- While zoomed in, a thin bar along the top: the whole length and, lighter,
-- the part in view (its place and its share).
local function draw_zoom_bar(dl, x0, y0, w, frac_start, frac_len, col)
  if frac_len >= 0.999 then return end
  local y1, y2 = y0 + 1, y0 + 4
  ImGui.DrawList_AddRectFilled(dl, x0, y1, x0 + w, y2, with_alpha(col.text, 0x22))
  local a = x0 + clamp(frac_start, 0, 1) * w
  local b = x0 + clamp(frac_start + frac_len, 0, 1) * w
  ImGui.DrawList_AddRectFilled(dl, a, y1, math.max(b, a + 3), y2, with_alpha(col.text, 0xA0))
end

-- Take and sound brackets show only while the mouse is over the dock.
local function marks_visible()
  return ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_ChildWindows | ImGui.HoveredFlags_AllowWhenBlockedByActiveItem)
end

-- Display curve: the height follows |a| ^ wave_gamma (1 = linear, as REAPER
-- draws; lower values lift quiet material and squeeze the loud peaks).
local function shape(v, gain)
  local a = v * gain
  local neg = a < 0
  if neg then a = -a end
  a = a >= 1 and 1 or a ^ cfg.wave_gamma
  return neg and -a or a
end

-- One stroke per pixel column, from max to min. A filled rectangle, not a
-- line: ImGui draws 1 px lines anti-aliased (never fully opaque), so the
-- centre line under the waveform showed through.
local function stroke(dl, x, cy, half, mx, mn, gain, col)
  local y1 = cy - shape(mx, gain) * half
  local y2 = cy - shape(mn, gain) * half
  if y2 - y1 < 1 then y2 = y1 + 1 end
  x = math.floor(x)
  ImGui.DrawList_AddRectFilled(dl, x, y1, x + 1, y2, col)
end

-- Wheel over the waveform: zoom (around the mouse), scroll with Shift (or a
-- horizontal wheel), height with Cmd/Ctrl. Returns zoom factor, scroll, gain factor.
-- Shift is read here rather than left to ImGui: with a trackpad on macOS,
-- Shift+swipe still arrives as vertical wheel. A swipe that is mostly
-- sideways scrolls too.
local function wheel_input()
  local v, h = ImGui.GetMouseWheel(ctx)
  if v == 0 and h == 0 then return nil end
  local mods = ImGui.GetKeyMods(ctx)
  if mods & ImGui.Mod_Ctrl ~= 0 then
    return 1, 0, (v ~= 0 and 1.15 ^ v or 1)
  end
  if mods & ImGui.Mod_Shift ~= 0 then
    return 1, (h ~= 0 and h or v), 1
  end
  if math.abs(h) > math.abs(v) then return 1, h, 1 end
  return 0.85 ^ v, 0, 1
end

local function header_text(dl, x, y, parts, col)
  ImGui.DrawList_AddText(dl, x, y, col, table.concat(parts, '   '))
end

local function fmt_time(sec)
  if sec >= 60 then return string.format('%d:%04.1f', math.floor(sec / 60), sec % 60) end
  return string.format('%.2f s', sec)
end

----------------------------------------------------------------- item view
-- A zone of the selected item's file, dropped on the arrange: a new item on
-- the same file (no new file), starting at the zone, with the take's rate and
-- pitch; it becomes the only selected item.
local function drop_position(target)
  local pos = target.pos
  -- 1157 = Options: Toggle snapping (the magnet); its toggle state is "snap on".
  if cfg.drop_snap and reaper.GetToggleCommandState(1157) == 1 then
    pos = reaper.SnapToGrid(0, pos)
  end
  return pos
end

local function insert_source_zone(target, z)
  local pos = drop_position(target)
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  local track = target.track
  if not track then
    reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
    track = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
  end
  local item = reaper.AddMediaItemToTrack(track)
  local take = reaper.AddTakeToMediaItem(item)
  reaper.SetMediaItemTake_Source(take, reaper.PCM_Source_CreateFromFile(z.file))
  reaper.SetMediaItemTakeInfo_Value(take, 'D_STARTOFFS', z.s0)
  reaper.SetMediaItemTakeInfo_Value(take, 'D_PLAYRATE', z.rate)
  reaper.SetMediaItemTakeInfo_Value(take, 'D_PITCH', z.pitch)
  reaper.SetMediaItemTakeInfo_Value(take, 'B_PPITCH', z.ppitch and 1 or 0)
  reaper.SetMediaItemTakeInfo_Value(take, 'I_PITCHMODE', z.pitchmode)
  reaper.SetMediaItemInfo_Value(item, 'D_POSITION', pos)
  reaper.SetMediaItemInfo_Value(item, 'D_LENGTH', (z.s1 - z.s0) / z.rate)
  reaper.GetSetMediaItemTakeInfo_String(take, 'P_NAME', z.name, true)
  reaper.SelectAllMediaItems(0, false)
  reaper.SetMediaItemSelected(item, true)
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock('mtt_dock: insert zone of ' .. z.name, -1)
end

local function draw_item_view(st, x0, y0, w, h, dl, col)
  if st.err then
    ImGui.DrawList_AddText(dl, x0 + 8, y0 + 6, col.dim, st.err)
    return
  end
  -- Zoom and selection belong to the file: they stay when another item of
  -- the same file gets selected (a zone just dropped, for one).
  if IV.key ~= st.fkey then
    IV = { key = st.fkey, view_s = 0, view_len = st.full, gain = 1, sel = nil }
    item_preview_stop()
  end
  if IV.item ~= st.key then IV.item = st.key; item_preview_stop() end
  IV.view_len = clamp(IV.view_len, math.min(0.01, st.full), st.full)
  IV.view_s = clamp(IV.view_s, 0, st.full - IV.view_len)

  local ready = ensure_peaks(st.root)
  local takes = ready and analysis_step(st) or nil
  local mx_, my_ = ImGui.GetMousePos(ctx)
  local hovered = ImGui.IsItemHovered(ctx) and not in_rect(mx_, my_, S.gear_rect)
  local function x_to_t(x) return IV.view_s + (x - x0) / w * IV.view_len end
  local function t_to_x(t) return x0 + (t - IV.view_s) / IV.view_len * w end

  -- Wheel
  if hovered then
    local zf, scroll, gf = wheel_input()
    if zf then
      local tm = x_to_t(mx_)
      local nl = clamp(IV.view_len * zf, math.min(0.01, st.full), st.full)
      IV.view_s = tm - (tm - IV.view_s) * nl / IV.view_len
      IV.view_len = nl
      IV.view_s = IV.view_s - scroll * 0.1 * nl
      IV.view_s = clamp(IV.view_s, 0, st.full - nl)
      IV.gain = clamp(IV.gain * gf, 1, 64)
    end
  end

  -- Right button held: listen from that point.
  local t_mouse = x_to_t(mx_)
  if hovered and ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right) then
    if t_mouse >= 0 and t_mouse < st.full then
      item_preview_start(st, t_mouse)
      S.listen = 'item'
    end
  end
  if S.listen == 'item' and not ImGui.IsMouseDown(ctx, ImGui.MouseButton_Right) then
    item_preview_stop()
    S.listen = nil
  end

  -- What the left button would grab: an edge of the selection (5 px either
  -- side), the selection (to take it out), or the highlight (to slip).
  local tol = 8 / w * IV.view_len -- takes and the highlight pull the selection within 8 px
  local snaps = { { s = st.ws, e = st.ws + st.wl } }
  for _, tk in ipairs(takes or {}) do snaps[#snaps + 1] = tk end
  local function t_snapped() return snap_frame(clamp(t_mouse, 0, st.full), snaps, tol) end
  local sel = IV.sel
  local sx1, sx2
  if sel then sx1, sx2 = t_to_x(sel[1]), t_to_x(sel[2]) end
  local EDGE_PX = 5
  local edge_hover, in_sel, on_hi
  if hovered and not S.press and not S.drag then
    if sel then
      local d1, d2 = math.abs(mx_ - sx1), math.abs(mx_ - sx2)
      if d1 <= EDGE_PX and d1 <= d2 then edge_hover = 1 elseif d2 <= EDGE_PX then edge_hover = 2 end
      in_sel = not edge_hover and mx_ > sx1 and mx_ < sx2
    end
    on_hi = not edge_hover and not in_sel and t_mouse >= st.ws and t_mouse <= st.ws + st.wl
  end

  -- Left button: double-click jumps the item window; on an edge it moves that
  -- edge; inside the selection it takes the zone out to the arrange; on the
  -- highlight it slips; anywhere else it drags a new selection (a click alone
  -- clears it).
  if hovered and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
    S.press = nil
    IV.sel = nil
    -- A click up to 8 px off a take still picks it.
    local nws = jump_window(takes or {}, t_mouse, st.ws, st.wl, st.lo, st.hi, tol)
    if math.abs(nws - st.ws) > 1e-9 then
      reaper.SetMediaItemTakeInfo_Value(st.take, 'D_STARTOFFS', nws - st.sec_off)
      reaper.UpdateItemInProject(st.item)
      reaper.Undo_OnStateChange_Item(0, 'mtt_dock: move item window', st.item)
      st.ws = nws
    end
  elseif hovered and ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) then
    if edge_hover then
      S.press = { kind = 'item', edge = edge_hover }
    elseif in_sel then
      S.press = { kind = 'item', zone = true, x = mx_, y = my_ }
    elseif on_hi then
      S.press = { kind = 'item', x = mx_, ws0 = st.ws }
    else
      local t = t_snapped()
      S.press = { kind = 'item', select = true, x = mx_, anchor = t }
      IV.sel = { t, t }
    end
  end
  if S.press and S.press.kind == 'item' then
    local p = S.press
    if ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left) then
      if p.edge and IV.sel then
        IV.sel[p.edge] = t_snapped()
        if IV.sel[1] > IV.sel[2] then -- dragged past the other edge
          IV.sel = { IV.sel[2], IV.sel[1] }
          p.edge = 3 - p.edge
        end
      elseif p.zone and not S.drag then
        local dx, dy = mx_ - p.x, my_ - p.y
        if dx * dx + dy * dy > 16 then
          local a, b = IV.sel[1], IV.sel[2]
          S.drag = { from = 'item', fmt = 'zone', len = (b - a) / st.rate,
            peaks = source_peaks(st, a, b - a, 160),
            zone = { file = st.file, s0 = a, s1 = b, rate = st.rate, pitch = st.pitch,
              ppitch = st.ppitch, pitchmode = st.pitchmode, name = st.name } }
        end
      elseif p.select then
        local t, a = t_snapped(), p.anchor
        IV.sel = { math.min(a, t), math.max(a, t) }
      elseif p.ws0 then
        if not p.slip and math.abs(mx_ - p.x) > 3 then p.slip = true end
        if p.slip then
          local nws = clamp(p.ws0 + (mx_ - p.x) / w * IV.view_len, st.lo, math.max(st.lo, st.hi))
          if math.abs(nws - st.ws) > 1e-9 then
            reaper.SetMediaItemTakeInfo_Value(st.take, 'D_STARTOFFS', nws - st.sec_off)
            reaper.UpdateItemInProject(st.item)
            st.ws = nws
          end
        end
      end
    else
      if S.drag and S.drag.from == 'item' then
        local target = drop_target()
        local zone = S.drag.zone
        S.drag = nil
        if target then insert_source_zone(target, zone) end
      end
      if p.slip then reaper.Undo_OnStateChange_Item(0, 'mtt_dock: slip item content', st.item) end
      if p.select and math.abs(mx_ - p.x) < 3 then IV.sel = nil end
      if p.edge and IV.sel and IV.sel[2] <= IV.sel[1] then IV.sel = nil end
      S.press = nil
    end
  end
  if S.drag or in_sel then
    ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_Hand)
  elseif edge_hover or on_hi or (S.press and S.press.kind == 'item' and (S.press.edge or S.press.slip)) then
    ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeEW)
  end
  sel = IV.sel
  if sel and sel[2] <= sel[1] then sel = nil end
  sx1, sx2 = nil, nil
  if sel then sx1, sx2 = t_to_x(sel[1]), t_to_x(sel[2]) end

  -- Paint: the highlight (what the item plays) in white, the selection (a
  -- zone to take out) in orange, as selections are in the recorder.
  local cy, half = y0 + h / 2, h / 2 - 2
  local hx1, hx2 = t_to_x(st.ws), t_to_x(st.ws + st.wl)
  ImGui.DrawList_AddRectFilled(dl, math.max(x0, hx1), y0, math.min(x0 + w, hx2), y0 + h, col.item_bg)
  if sx1 then
    ImGui.DrawList_AddRectFilled(dl, math.max(x0, sx1), y0, math.min(x0 + w, sx2), y0 + h,
      (in_sel or S.drag) and with_alpha(COL_ACCENT, 0x40) or col.hi_bg)
  end
  ImGui.DrawList_AddLine(dl, x0, cy, x0 + w, cy, col.mid, 1)
  if ready then
    local pv = view_peaks(st, w)
    for i = 0, pv.n - 1 do
      local x = x0 + i
      local c = (sx1 and x >= sx1 and x <= sx2) and col.hi or (x >= hx1 and x <= hx2) and col.item or col.wave
      stroke(dl, x, cy, half, pv.mx[i], pv.mn[i], IV.gain, c)
    end
  else
    ImGui.DrawList_AddText(dl, x0 + 8, cy - 7, col.dim, 'Building peaks...')
  end
  draw_edge_fades(dl, x0, y0, w, h, col, { { hx1, hx2 }, sx1 and { sx1, sx2 } or nil })
  draw_zoom_bar(dl, x0, y0, w, IV.view_s / st.full, IV.view_len / st.full, col)
  -- Takes found in the file: a thin bracket along the bottom.
  for _, tk in ipairs(marks_visible() and takes or {}) do
    local a, b = t_to_x(tk.s), t_to_x(tk.e)
    if b >= x0 and a <= x0 + w then
      a, b = math.max(a, x0), math.min(b, x0 + w)
      ImGui.DrawList_AddLine(dl, a, y0 + h - 2, b, y0 + h - 2, col.dim, 2)
      ImGui.DrawList_AddLine(dl, a, y0 + h - 6, a, y0 + h - 1, col.dim, 1)
    end
  end
  for _, x in ipairs({ hx1, hx2 }) do
    if x >= x0 and x <= x0 + w then ImGui.DrawList_AddLine(dl, x, y0, x, y0 + h, col.item_edge, 1) end
  end
  if sx1 then
    for k, x in ipairs({ sx1, sx2 }) do
      if x >= x0 and x <= x0 + w then
        local grabbed = edge_hover == k or (S.press and S.press.kind == 'item' and S.press.edge == k)
        ImGui.DrawList_AddLine(dl, x, y0, x, y0 + h, col.hi, grabbed and 3 or 1)
      end
    end
  end
  if preview then
    local ok, pos = reaper.CF_Preview_GetValue(preview, 'D_POSITION')
    if ok then
      local x = t_to_x(pos + st.sec_off)
      if x >= x0 and x <= x0 + w then ImGui.DrawList_AddLine(dl, x, y0, x, y0 + h, col.text, 1) end
    end
  end
end

------------------------------------------------------------- recorder view
local function recorder_status()
  if not R.fx_idx then return 'missing' end
  if not R.alive then return 'stopped' end
  if not R.proto_ok then return 'old' end
  if (R.fx_n or 1) > 1 then return 'dup' end
  if R.fx_idx ~= R.fx_count - 1 then return 'not_last' end
  return 'ok'
end

local function recorder_buttons(status)
  if status == 'missing' then
    if ImGui.Button(ctx, 'Add recorder to master') then install_recorder() end
  elseif status == 'old' then
    if ImGui.Button(ctx, 'Update recorder') then install_recorder(true) end
  elseif status == 'dup' then
    if ImGui.Button(ctx, 'Keep one recorder') then install_recorder(true) end
  elseif status == 'not_last' then
    if ImGui.Button(ctx, 'Move recorder to the end of the master chain') then move_recorder_last() end
  end
end

-- In place of the recorder view while there is no running recorder.
local function draw_recorder_message(status)
  ImGui.TextDisabled(ctx, status == 'missing' and 'The recorder is not on the master.'
    or status == 'old' and 'The recorder on the master is an older version (its recording is lost on update).'
    or 'The recorder is on the master but not running (audio device stopped?).')
  if install_error then ImGui.TextColored(ctx, COL_REC, install_error) end
  recorder_buttons(status)
end

local function draw_recorder_view(x0, y0, w, h, dl, col, status)
  local now = reaper.time_precise()
  recorder_sounds(now)
  local mx_, my_ = ImGui.GetMousePos(ctx)
  local hovered = ImGui.IsItemHovered(ctx) and not in_rect(mx_, my_, S.gear_rect)
  local busy = S.press or S.listen or S.drag

  -- Live view follows the recording; it holds still under the mouse.
  if hovered or busy then
    if not R.view_end then R.view_end, R.pinned_by_hover = R.W, true end
  elseif R.pinned_by_hover then
    R.view_end, R.pinned_by_hover = nil, false
  end
  local cap = math.max(1, R.cap)
  local span = clamp(R.span or cap, math.max(1, R.srate * 0.05), cap)
  local E = R.view_end or R.W
  local function x_to_f(x) return E - span + (x - x0) / w * span end
  local function f_to_x(f) return x0 + (f - (E - span)) / span * w end
  local f_mouse = x_to_f(mx_)

  -- Wheel
  if hovered then
    local zf, scroll, gf = wheel_input()
    -- Showing the whole buffer leaves nothing to scroll to.
    if zf and zf == 1 and gf == 1 and span >= cap then zf = nil end
    if zf then
      local ns = clamp(span * zf, math.max(1, R.srate * 0.05), cap)
      local ne = f_mouse + (E - f_mouse) * ns / span
      ne = ne - scroll * 0.1 * ns
      -- The view stays inside the buffer: its left edge no earlier than the
      -- buffer's (W - cap), its right edge no later than the newest frame.
      ne = clamp(ne, math.min(R.W, R.W - cap + ns), R.W)
      R.span = ns
      if ne >= R.W then
        R.view_end, R.pinned_by_hover = R.W, true -- back to live once the mouse leaves
      else
        R.view_end, R.pinned_by_hover = ne, false
      end
      R.gain = clamp(R.gain * gf, 1, 256)
      E, span = R.view_end or R.W, ns
      f_mouse = x_to_f(mx_)
    end
  end

  local tol = 8 / w * span -- sound and burst edges pull the selection within 8 px
  local function f_snapped() return snap_frame(clamp(f_mouse, R.oldest, R.W), R.snaps, tol) end
  local formats = ImGui.GetKeyMods(ctx) & ImGui.Mod_Ctrl ~= 0 -- Cmd shows mono / stereo / original
  local has_sel = R.sel and R.sel[2] > R.sel[1]
  local sx1, sx2
  if has_sel then sx1, sx2 = f_to_x(R.sel[1]), f_to_x(R.sel[2]) end

  -- What the left button would grab: an edge of the selection (5 px either
  -- side), or the selection itself (to take it out).
  local EDGE_PX = 5
  local edge_hover, grip_hover
  if has_sel and hovered and not busy then
    local d1, d2 = math.abs(mx_ - sx1), math.abs(mx_ - sx2)
    if d1 <= EDGE_PX and d1 <= d2 then edge_hover = 1 elseif d2 <= EDGE_PX then edge_hover = 2 end
    if not edge_hover and mx_ > sx1 and mx_ < sx2 then
      grip_hover = grip_at(my_, y0, h, formats)
    end
  end

  -- Right button held: listen from that point (through the master output).
  if hovered and ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right) and f_mouse < R.W then
    rec_play_start(math.floor(math.max(f_mouse, R.oldest)))
    S.listen = 'rec'
  end
  if S.listen == 'rec' and not ImGui.IsMouseDown(ctx, ImGui.MouseButton_Right) then
    rec_play_stop()
    S.listen = nil
  end

  -- Left button: double-click selects the sound (or the burst) under the
  -- mouse; on an edge it moves that edge; inside the selection it takes it
  -- out to the arrange; anywhere else it drags a new selection (a click alone
  -- clears it).
  if hovered and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
    S.press = nil
    local pick, best = nil, tol
    for _, so in ipairs(R.sounds) do
      if f_mouse >= so.s and f_mouse <= so.e then pick = so; break end
      local d = f_mouse < so.s and so.s - f_mouse or f_mouse - so.e
      if d <= best then pick, best = so, d end
    end
    if not pick then
      for _, sg in ipairs(R.segs) do
        if f_mouse >= sg.s and f_mouse <= sg.e then pick = sg; break end
      end
    end
    if pick then R.sel = { pick.s, pick.e } end
  elseif hovered and ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) then
    if edge_hover then
      S.press = { kind = 'rec', edge = edge_hover }
    elseif grip_hover then
      S.press = { kind = 'rec', grip = grip_hover, x = mx_, y = my_ }
    else
      local f = f_snapped()
      S.press = { kind = 'rec', select = true, x = mx_, anchor = f }
      R.sel = { f, f }
    end
  end
  if S.press and S.press.kind == 'rec' then
    if ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left) then
      if S.press.edge and R.sel then
        R.sel[S.press.edge] = f_snapped()
        if R.sel[1] > R.sel[2] then -- dragged past the other edge
          R.sel = { R.sel[2], R.sel[1] }
          S.press.edge = 3 - S.press.edge
        end
      elseif S.press.grip and not S.drag then
        local dx, dy = mx_ - S.press.x, my_ - S.press.y
        if dx * dx + dy * dy > 16 then
          S.drag = { fmt = S.press.grip }
          -- A selection that starts on a sound found in the recording is cut
          -- at that sound's first sample in the file.
          local on_sound = false
          for _, so in ipairs(R.sounds) do
            if math.abs(so.s - R.sel[1]) < 1 then on_sound = true; break end
          end
          export_start(math.floor(R.sel[1]), math.floor(R.sel[2]), S.press.grip, on_sound)
        end
      elseif S.press.select then
        local f, a = f_snapped(), S.press.anchor
        R.sel = { math.min(a, f), math.max(a, f) }
      end
    else
      if S.drag then
        if job then
          local target = drop_target()
          if target then job.drop = target else job.dropped = true end
        end
        S.drag = nil
      end
      if S.press.select and math.abs(mx_ - S.press.x) < 3 then R.sel = nil end
      if S.press.edge and R.sel and R.sel[2] <= R.sel[1] then R.sel = nil end
      S.press = nil
    end
  end
  if S.drag or grip_hover then
    ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_Hand)
  elseif edge_hover or (S.press and S.press.edge) then
    ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeEW)
  end
  has_sel = R.sel and R.sel[2] > R.sel[1]
  sx1, sx2 = nil, nil
  if has_sel then sx1, sx2 = f_to_x(R.sel[1]), f_to_x(R.sel[2]) end

  -- Paint
  local cy, half = y0 + h / 2, h / 2 - 2
  ImGui.DrawList_AddLine(dl, x0, cy, x0 + w, cy, col.mid, 1)
  if sx1 then
    ImGui.DrawList_AddRectFilled(dl, math.max(x0, sx1), y0, math.min(x0 + w, sx2), y0 + h, col.hi_bg)
  end
  local fpp = span / w
  for i = 0, math.floor(w) - 1 do
    local f0 = E - span + i * fpp
    local mx, mn = rec_peak(f0, f0 + fpp)
    if mx then
      local x = x0 + i
      local c = (sx1 and x >= sx1 and x <= sx2) and col.hi or col.wave
      stroke(dl, x, cy, half, mx, mn, R.gain, c)
    end
  end
  -- Where one burst ends and the next begins (the silence between them was
  -- not recorded): a faint line with a tick on top.
  for k, sg in ipairs(R.segs) do
    if k > 1 then
      local x = f_to_x(sg.s)
      if x >= x0 and x <= x0 + w then
        ImGui.DrawList_AddLine(dl, x, y0, x, y0 + h, with_alpha(col.dim, 0x30), 1)
        ImGui.DrawList_AddRectFilled(dl, x - 1, y0, x + 1, y0 + 4, col.dim)
      end
    end
  end
  draw_edge_fades(dl, x0, y0, w, h, col, { sx1 and { sx1, sx2 } or nil })
  draw_zoom_bar(dl, x0, y0, w, (E - span - (R.W - cap)) / cap, span / cap, col)
  -- The sounds found inside the bursts: a thin bracket along the bottom, as
  -- the takes of a file in the item view.
  for _, so in ipairs(marks_visible() and R.sounds or {}) do
    local a, b = f_to_x(so.s), f_to_x(so.e)
    if b >= x0 and a <= x0 + w then
      a, b = math.max(a, x0), math.min(b, x0 + w)
      ImGui.DrawList_AddLine(dl, a, y0 + h - 2, b, y0 + h - 2, col.dim, 2)
      ImGui.DrawList_AddLine(dl, a, y0 + h - 6, a, y0 + h - 1, col.dim, 1)
    end
  end
  if sx1 then
    for k, x in ipairs({ sx1, sx2 }) do
      if x >= x0 and x <= x0 + w then
        local grabbed = edge_hover == k or (S.press and S.press.edge == k)
        ImGui.DrawList_AddLine(dl, x, y0, x, y0 + h, col.hi, grabbed and 3 or 1)
      end
    end
  end
  -- While the mouse is over the selection (or dragging it out) it lights up;
  -- with Cmd held it shows its three bands: mono, stereo, original.
  local over_sel = sx1 and hovered and not busy and not edge_hover and mx_ > sx1 and mx_ < sx2
  if sx1 and (over_sel or S.drag) then
    local bx1, bx2 = math.max(x0, sx1), math.min(x0 + w, sx2)
    if formats and not S.drag then
      local labels = { mono = 'MONO', stereo = 'STEREO',
        orig = R.nch > 2 and ('ORIGINAL ' .. R.nch .. ' ch') or 'ORIGINAL' }
      for k, b in ipairs(GRIP_BANDS) do
        local by1 = y0 + (k - 1) * h / 3
        local by2 = by1 + h / 3
        local hot = b == grip_hover
        ImGui.DrawList_AddRectFilled(dl, bx1, by1, bx2, by2, with_alpha(COL_ACCENT, hot and 0x50 or 0x1C))
        if k > 1 then ImGui.DrawList_AddLine(dl, bx1, by1, bx2, by1, with_alpha(COL_ACCENT, 0x90), 1) end
        -- The name sits on a plate, so it reads even past a narrow selection.
        local tw, th = ImGui.CalcTextSize(ctx, labels[b])
        local tx, ty = (bx1 + bx2 - tw) / 2, (by1 + by2 - th) / 2
        ImGui.DrawList_AddRectFilled(dl, tx - 4, ty - 1, tx + tw + 4, ty + th + 1,
          with_alpha(col.bg, 0xD0))
        ImGui.DrawList_AddText(dl, tx, ty, hot and col.text or col.dim, labels[b])
      end
    else
      ImGui.DrawList_AddRectFilled(dl, bx1, y0, bx2, y0 + h, with_alpha(COL_ACCENT, 0x18))
    end
  end
  if R.playpos >= 0 then
    local x = f_to_x(R.playpos)
    if x >= x0 and x <= x0 + w then ImGui.DrawList_AddLine(dl, x, y0, x, y0 + h, col.text, 1) end
  end

  -- No captions: only a line when something needs attention.
  local info = {}
  if status == 'not_last' then info[#info + 1] = 'The recorder is not last on the master: see the settings.' end
  if status == 'dup' then info[#info + 1] = 'More than one recorder on the master: see the settings.' end
  if job and job.state == 'failed' and job.msg then info[#info + 1] = job.msg end
  header_text(dl, x0 + 6, y0 + 3, info, col.dim)
end

-- The selection following the mouse while it is dragged out.
local function draw_drag_overlay()
  if not S.drag then return end
  local from_item = S.drag.from == 'item'
  if not from_item and not R.sel then return end
  local mx, my = ImGui.GetMousePos(ctx)
  local W_, H_ = 170, 46
  -- Offset from the cursor so the arrange, not this window, is under the mouse.
  ImGui.SetNextWindowPos(ctx, mx + 16, my + 14, ImGui.Cond_Always)
  ImGui.SetNextWindowSize(ctx, W_, H_, ImGui.Cond_Always)
  local flags = ImGui.WindowFlags_NoDecoration | ImGui.WindowFlags_NoInputs | ImGui.WindowFlags_NoSavedSettings
    | ImGui.WindowFlags_NoFocusOnAppearing | ImGui.WindowFlags_NoDocking | ImGui.WindowFlags_NoNav
    | ImGui.WindowFlags_TopMost
  local visible = ImGui.Begin(ctx, '##mtt_dock_drag', nil, flags)
  if visible then
    local dl = ImGui.GetWindowDrawList(ctx)
    local x0, y0 = ImGui.GetWindowPos(ctx)
    local text_col = ImGui.GetColor(ctx, ImGui.Col_Text)
    ImGui.DrawList_AddRectFilled(dl, x0, y0, x0 + W_, y0 + H_, with_alpha(ImGui.GetColor(ctx, ImGui.Col_WindowBg), 0xF0))
    ImGui.DrawList_AddRect(dl, x0, y0, x0 + W_, y0 + H_, COL_ACCENT, 0, 0, 1)
    local cy = y0 + 18
    local label
    if from_item then
      -- A zone of the item's file: its peaks were read when the drag began.
      local pk = S.drag.peaks
      for i = 0, math.min(pk.n, W_ - 8) - 1 do
        stroke(dl, x0 + 4 + i, cy, 13, pk.mx[i], pk.mn[i], IV.gain, COL_ACCENT)
      end
      label = fmt_time(S.drag.len)
    else
      local a, b = R.sel[1], R.sel[2]
      local fpp = (b - a) / (W_ - 8)
      for i = 0, W_ - 9 do
        local mx_, mn_ = rec_peak(a + i * fpp, a + (i + 1) * fpp)
        if mx_ then stroke(dl, x0 + 4 + i, cy, 13, mx_, mn_, R.gain, COL_ACCENT) end
      end
      -- Once fetched, what it really becomes (stereo with equal sides turns mono).
      local kind = job and job.kind or S.drag.fmt
      label = ({ mono = 'MONO', stereo = 'STEREO', orig = 'ORIGINAL' })[kind]
        .. '  ' .. fmt_time((b - a) / R.srate)
    end
    ImGui.DrawList_AddText(dl, x0 + 5, y0 + H_ - 15, text_col, label)
    ImGui.End(ctx)
  end
end

----------------------------------------------------------------- settings
-- As FMOD Sync Mini: a floating window over the docker, sections with a
-- title rule, a label column with tooltips, the controls at its right.
local LABEL_W = 190
local CONTROL_W = 320

-- Tooltip for the item just drawn, also while it is disabled (as in mtt_FmodSync).
local function tip(text)
  if text and text ~= '' and ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
    if ImGui.BeginTooltip(ctx) ~= false then
      ImGui.PushTextWrapPos(ctx, ImGui.GetFontSize(ctx) * 30)
      ImGui.Text(ctx, text)
      ImGui.PopTextWrapPos(ctx)
      ImGui.EndTooltip(ctx)
    end
  end
end

local function setting_label(text, help)
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx, text)
  tip(help)
  ImGui.SameLine(ctx, LABEL_W)
end

local function slider(id, key, lo, hi, fmt, apply_on_release)
  ImGui.SetNextItemWidth(ctx, CONTROL_W)
  local v = S.pending and S.pending[key] or cfg[key]
  local changed, nv = ImGui.SliderDouble(ctx, id, v, lo, hi, fmt, ImGui.SliderFlags_AlwaysClamp)
  if apply_on_release then
    -- Applied when released: a change empties the recording.
    if changed then S.pending = S.pending or {}; S.pending[key] = nv end
    if ImGui.IsItemDeactivatedAfterEdit(ctx) and S.pending and S.pending[key] then
      cfg[key] = math.floor(S.pending[key] + 0.5)
      S.pending[key] = nil
      save_cfg(key)
    end
  elseif changed then
    cfg[key] = nv
    save_cfg(key)
  end
end

local function checkbox(label, key)
  local changed, v = ImGui.Checkbox(ctx, label, cfg[key])
  if changed then cfg[key] = v; save_cfg(key) end
end

local function draw_level_meter(w)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local h = ImGui.GetFrameHeight(ctx)
  local dl = ImGui.GetWindowDrawList(ctx)
  local function db_x(db) return x + clamp((db + 100) / 100, 0, 1) * w end
  local lvl = R.alive and R.level > 0 and 20 * math.log(R.level, 10) or -100
  local by1, by2 = y + h / 2 - 3, y + h / 2 + 3
  ImGui.DrawList_AddRectFilled(dl, x, by1, x + w, by2, ImGui.GetColor(ctx, ImGui.Col_FrameBg))
  ImGui.DrawList_AddRectFilled(dl, x, by1, db_x(lvl), by2, lvl >= cfg.rec_threshold and COL_ACCENT
    or ImGui.GetColor(ctx, ImGui.Col_TextDisabled))
  local tx = db_x(cfg.rec_threshold)
  ImGui.DrawList_AddLine(dl, tx, by1 - 3, tx, by2 + 3, ImGui.GetColor(ctx, ImGui.Col_Text), 1)
  ImGui.Dummy(ctx, w, h)
end

local function draw_settings()
  ImGui.SeparatorText(ctx, 'Recorder')
  local status = recorder_status()
  setting_label('On the master', 'mtt_dock_recorder.jsfx, last in the master FX chain: it keeps what passes the master, only while it is above the threshold.')
  if status == 'ok' then
    ImGui.Text(ctx, string.format('running, %d ch, %.0f s kept', R.nch, R.cap / R.srate))
  elseif status == 'missing' then ImGui.TextDisabled(ctx, 'not on the master')
  elseif status == 'stopped' then ImGui.TextDisabled(ctx, 'on the master, not running (audio device stopped?)')
  elseif status == 'old' then ImGui.TextDisabled(ctx, 'an older version (updating it loses its recording)')
  elseif status == 'dup' then ImGui.TextDisabled(ctx, 'more than one on the master')
  else ImGui.TextDisabled(ctx, 'not last in the master chain') end
  if status ~= 'ok' and status ~= 'stopped' then
    ImGui.SetCursorPosX(ctx, LABEL_W)
    recorder_buttons(status)
  end
  if install_error then
    ImGui.SetCursorPosX(ctx, LABEL_W)
    ImGui.TextColored(ctx, COL_REC, install_error)
  end
  setting_label('Input', 'What reaches the recorder now; the line is the threshold.')
  draw_level_meter(CONTROL_W)
  setting_label('Threshold', 'The recorder writes only while the master is above this.')
  slider('##thr', 'rec_threshold', -100, -20, '%.0f dB')
  setting_label('Pre-roll', 'Kept from just before the signal crossed the threshold, so that attacks are whole.')
  slider('##pre', 'rec_preroll', 0, 500, '%.0f ms')
  setting_label('Hold', 'How long the recorder goes on after the signal fell under the threshold.')
  slider('##hold', 'rec_hold', 0, 2000, '%.0f ms')
  local len_max = rec_len_max()
  setting_label('Keep', "How much sound the recorder keeps. The most it can hold depends on the master's channels and sample rate. Changing it clears the recording.")
  slider('##len', 'rec_length', REC_LEN_MIN, len_max, '%.0f s', true)
  ImGui.SameLine(ctx)
  ImGui.TextDisabled(ctx, REC_LEN_MIN .. ' to ' .. len_max .. ' s')
  if status ~= 'missing' then
    ImGui.SetCursorPosX(ctx, LABEL_W)
    if ImGui.Button(ctx, 'Clear recording') then wr(L.CLEAR, rd(L.CLEAR) + 1) end
  end

  ImGui.SeparatorText(ctx, 'Display')
  setting_label('Dynamics', 'How the waveform is drawn: 1 = linear, as REAPER draws it; lower values compress it, so quiet sounds show and loud peaks stay inside.')
  slider('##gamma', 'wave_gamma', 0.25, 1, '%.2f')

  ImGui.SeparatorText(ctx, 'Takes and sounds')
  setting_label('Sensitivity', 'How far a take (in a file) or a sound (in the recorder) must rise above the noise floor, and out of a dip, to count as one.')
  slider('##sens', 'take_sens', 4, 40, '%.0f dB')
  setting_label('Gap', 'The shortest quiet stretch (or dip) that separates two takes or two sounds.')
  slider('##gap', 'take_gap', 20, 2000, '%.0f ms')
  ImGui.SetCursorPosX(ctx, LABEL_W)
  ImGui.TextDisabled(ctx, 'Continuous sound (ambiences) gives no takes.')

  ImGui.SeparatorText(ctx, 'Drag to the arrange')
  setting_label('Snap', "Dropped recordings land on the grid while REAPER's snapping is on.")
  checkbox('Snap to grid##drop_snap', 'drop_snap')
  setting_label('Stereo', 'The selection goes out as stereo; hold Cmd over it to pick mono or the original channels instead.')
  checkbox('Mono when both sides are the same##auto_mono', 'stereo_auto_mono')
  setting_label('Files', 'Where dropped recordings are written: the project recording folder.')
  ImGui.TextDisabled(ctx, reaper.GetProjectPath())
end

------------------------------------------------------------------- frame
local function frame()
  local now = reaper.time_precise()
  recorder_update(now)
  recorder_fx(now)
  export_step(now)
  peak_jobs_step()

  push_style()
  ImGui.SetNextWindowSize(ctx, 1200, 160, ImGui.Cond_FirstUseEver)
  local visible, open = ImGui.Begin(ctx, 'mtt_dock', true,
    ImGui.WindowFlags_NoCollapse | ImGui.WindowFlags_NoScrollbar | ImGui.WindowFlags_NoScrollWithMouse)
  if visible then
    -- A line along the top, as in FMOD Sync Mini: the edge between REAPER's
    -- arrange (its scrollbar) and the dock.
    local wx, wy = ImGui.GetWindowPos(ctx)
    local ww = ImGui.GetWindowSize(ctx)
    ImGui.DrawList_AddLine(ImGui.GetWindowDrawList(ctx), wx, wy + 0.5, wx + ww, wy + 0.5,
      ImGui.GetColor(ctx, ImGui.Col_Separator), 1)
    local x0, y0 = ImGui.GetCursorScreenPos(ctx)
    local w, h = ImGui.GetContentRegionAvail(ctx)
    w, h = math.max(w, 40), math.max(h, 30)
    local gs = ImGui.GetFrameHeight(ctx)
    S.gear_rect = { x0 + w - gs, y0 + h - gs, x0 + w, y0 + h } -- bottom right corner
    local dl = ImGui.GetWindowDrawList(ctx)

    -- Space plays / stops REAPER while the dock has the focus (as in mtt_FmodSync).
    if ImGui.IsWindowFocused(ctx, ImGui.FocusedFlags_RootAndChildWindows)
      and not ImGui.IsAnyItemActive(ctx) and ImGui.IsKeyPressed(ctx, ImGui.Key_Space, false) then
      reaper.Main_OnCommand(40044, 0) -- Transport: Play/stop
    end

    -- The gear is submitted before the waveform it sits on, so it gets the mouse
    -- first (with overlapping items the first one submitted takes the hover).
    ImGui.SetCursorScreenPos(ctx, S.gear_rect[1], S.gear_rect[2])
    if ImGui.InvisibleButton(ctx, '##gear', gs, gs) then ImGui.OpenPopup(ctx, 'mtt_dock_settings') end
    local gear_hovered, gear_held = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
    tip('Settings')
    local settings_open = ImGui.IsPopupOpen(ctx, 'mtt_dock_settings')
    ImGui.SetCursorScreenPos(ctx, x0, y0)

    do
      local col = wave_colors()
      -- The view follows the selection: one item = that item; otherwise the
      -- recorder. A drag-out keeps the recorder until it ends.
      local st = (not S.drag or S.drag.from == 'item') and item_state() or nil
      local rstatus = recorder_status()
      if st or rstatus == 'ok' or rstatus == 'not_last' or rstatus == 'dup' then
        ImGui.InvisibleButton(ctx, '##wave', w, h,
          ImGui.ButtonFlags_MouseButtonLeft | ImGui.ButtonFlags_MouseButtonRight)
        ImGui.DrawList_AddRectFilled(dl, x0, y0, x0 + w, y0 + h, col.bg)
        ImGui.DrawList_PushClipRect(dl, x0, y0, x0 + w, y0 + h, true)
        if st then
          if S.listen == 'rec' then rec_play_stop(); S.listen = nil end
          if S.press and S.press.kind == 'rec' then S.press = nil end
          draw_item_view(st, x0, y0, w, h, dl, col)
        else
          if S.listen == 'item' then item_preview_stop(); S.listen = nil end
          if S.press and S.press.kind == 'item' then S.press = nil end
          if S.drag and S.drag.from == 'item' then S.drag = nil end -- the item went away mid-drag
          draw_recorder_view(x0, y0, w, h, dl, col, rstatus)
        end
        ImGui.DrawList_PopClipRect(dl)
      else
        if S.listen then item_preview_stop(); rec_play_stop(); S.listen = nil end
        S.press = nil
        ImGui.SetCursorScreenPos(ctx, x0 + 8, y0 + 6)
        draw_recorder_message(rstatus)
      end
    end

    -- The gear shows only while the mouse is over the dock (or its settings
    -- are open), a little faded; it lights up under the mouse.
    local r = S.gear_rect
    if settings_open or marks_visible() then
      if gear_hovered or settings_open then
        ImGui.DrawList_AddRectFilled(dl, r[1], r[2], r[3], r[4],
          ImGui.GetColor(ctx, gear_held and ImGui.Col_ButtonActive or ImGui.Col_ButtonHovered))
      end
      paint_gear(dl, math.floor(r[1]), math.floor(r[2]), gs, settings_open and COL_ACCENT
        or gear_hovered and ImGui.GetColor(ctx, ImGui.Col_Text) or ImGui.GetColor(ctx, ImGui.Col_TextDisabled, 0.8))
    end
    -- The settings open in a floating window over the docker (as FMOD Sync Mini).
    ImGui.SetNextWindowSizeConstraints(ctx, 560, 0, 900, 700)
    if ImGui.BeginPopup(ctx, 'mtt_dock_settings') then
      draw_settings()
      ImGui.EndPopup(ctx)
    end
    ImGui.End(ctx)
  end
  draw_drag_overlay()
  pop_style()
  return open
end

local cleaned = false
local function cleanup()
  if cleaned then return end
  cleaned = true
  item_preview_stop()
  rec_play_stop()
  if job and job.state ~= 'done' and job.state ~= 'failed' then export_cancel() end
  reaper.gmem_attach(prev_gmem or '')
end

-- A script error stops the script and writes where it happened to REAPER's console.
local function loop()
  local ok, open = xpcall(frame, debug.traceback)
  if not ok then
    reaper.ShowConsoleMsg('\nmtt_dock stopped on an error:\n' .. tostring(open) .. '\n')
    cleanup()
    return
  end
  if open then reaper.defer(loop) end
end

reaper.atexit(cleanup)
reaper.defer(loop)
