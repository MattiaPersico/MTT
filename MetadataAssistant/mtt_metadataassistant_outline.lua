-- mtt_metadataassistant_outline.lua
-- Outlines, on REAPER's timeline, the items that have a card, by its state:
--   done    final metadata (reviewed): steady green
--   waiting a draft with its questions, no final metadata yet: blinking yellow
--   busy    being analyzed (Describe) or finalized (after the review): orange,
--           warm white and blue running around the item
-- REAPER has no API to draw on the arrange view from Lua, so the outlines live in a
-- transparent ReaImGui window laid exactly over the track view: WindowFlags_NoInputs
-- makes it click-through (ReaImGui sets the viewport NoInputs: ignoresMouseEvents on
-- macOS, WS_EX_TRANSPARENT on Windows, mouse wheel forwarded), NoBackground leaves
-- only the lines. The track view's screen rectangle needs js_ReaScriptAPI.
-- The lines skip this script's own windows (holes), which the outline window would
-- otherwise cover when they float over the arrange.
-- Limits: the window is redrawn once per defer cycle, so the lines trail REAPER by a
-- frame while scrolling, zooming or dragging; it floats above REAPER's main window,
-- so another floating window over the arrange (FX, mixer) can show the lines on top of it.
-- Everything above "REAPER side" is pure.

local M = {}

-- REAPER's track view (arrange) inside the main window. A long-standing convention
-- used by many scripts; REAPER's documentation does not state it.
local TRACKVIEW_ID = 1000
local THICKNESS = 2
local RESCAN_S = 2 -- the tagged items are listed again at least this often

local COL_DONE = 0x5ED46BFF
local COL_WAITING = 0xFFD83AFF
local WAIT_PERIOD = 1.2  -- seconds per blink, as the Review tab's pulse
local WAIT_MIN_ALPHA = 0.15
-- Busy: a cyclic palette running around the outline, CHASE_WAVES times per lap.
local BUSY_PALETTE = { 0xFF6A00FF, 0xFFA53CFF, 0xFFF3DEFF, 0xFFA53CFF, 0x33ADFF, 0xFFA53CFF } -- deep orange, amber, warm white, amber, blue, amber
local CHASE_WAVES = 2
local CHASE_PERIOD = 1.6 -- seconds for one wave to travel its length
local CHASE_STEP = 6     -- pixels per coloured piece
local CHASE_MAX_PIECES = 240

function M.available()
  return reaper.APIExists('JS_Window_FindChildByID') and reaper.APIExists('JS_Window_GetClientRect')
end

-- Colour between a and b (0xRRGGBBAA), k from 0 (a) to 1 (b), channel by channel.
function M.mix_color(a, b, k)
  k = math.max(0, math.min(1, k))
  local out = 0
  for shift = 24, 0, -8 do
    local ca, cb = (a >> shift) & 0xFF, (b >> shift) & 0xFF
    out = out | (math.floor(ca + (cb - ca) * k + 0.5) << shift)
  end
  return out
end

-- Kind of an open card from its flow state: "done", "waiting", "busy" or nil.
local KIND_OF_STATE = { done = 'done', questions = 'waiting', listening = 'busy', drafting = 'busy', finalizing = 'busy' }
function M.session_kind(state)
  return KIND_OF_STATE[state]
end

-- Kind of a saved card, as flow.from_card restores it: final values = "done", a
-- draft without them = "waiting", else nil (no request runs on a saved card).
function M.card_kind(card)
  if type(card) ~= 'table' then return nil end
  if card.values ~= nil then return 'done' end
  if card.draft ~= nil then return 'waiting' end
  return nil
end

-- An item's rectangle in track-view units (REAPER's pixels, 0,0 = the track view's
-- top-left corner). view = { start = time at the left edge (s), zoom = pixels per
-- second }; it = { pos, len (s), tcpy (track top), lasty, lasth (item top and
-- height inside the track) }. nil when the item is not drawn (no height).
function M.item_rect(view, it)
  if not it.lasth or it.lasth <= 0 then return nil end
  local x1 = (it.pos - view.start) * view.zoom
  local x2 = (it.pos + it.len - view.start) * view.zoom
  local y1 = it.tcpy + it.lasty
  return x1, y1, x2, y1 + it.lasth
end

-- Track-view units -> ReaImGui screen coordinates. frame = { x, y (the track view's
-- top-left in ReaImGui coordinates), w, h, sx, sy (ReaImGui units per track-view
-- unit) }. nil when the rectangle is entirely outside the track view.
function M.to_screen(frame, x1, y1, x2, y2)
  local ax1, ay1 = frame.x + x1 * frame.sx, frame.y + y1 * frame.sy
  local ax2, ay2 = frame.x + x2 * frame.sx, frame.y + y2 * frame.sy
  if ax2 <= frame.x or ay2 <= frame.y or ax1 >= frame.x + frame.w or ay1 >= frame.y + frame.h then return nil end
  return ax1, ay1, ax2, ay2
end

-- Intervals {a, b} minus [c, d].
local function subtract(list, c, d)
  local out = {}
  for _, iv in ipairs(list) do
    if d <= iv[1] or c >= iv[2] then
      out[#out + 1] = iv
    else
      if c > iv[1] then out[#out + 1] = { iv[1], c } end
      if d < iv[2] then out[#out + 1] = { d, iv[2] } end
    end
  end
  return out
end

-- The four edges of an outline r = {x1, y1, x2, y2} as line segments
-- {xa, ya, xb, yb, edge = "top" | "right" | "bottom" | "left"}, each line of width
-- 2 * inset lying inside r, without the parts that fall inside one of the holes
-- (rectangles {x1, y1, x2, y2}). Top and bottom run the full width, so the corners
-- are filled.
function M.outline_segments(r, holes, inset)
  local segs = {}
  local function edge(name, fixed, from, to, horizontal)
    local list = { { from, to } }
    for _, h in ipairs(holes or {}) do
      local lo, hi, c, d
      if horizontal then lo, hi, c, d = h[2], h[4], h[1], h[3] else lo, hi, c, d = h[1], h[3], h[2], h[4] end
      if fixed + inset > lo and fixed - inset < hi then list = subtract(list, c, d) end
    end
    for _, iv in ipairs(list) do
      if horizontal then segs[#segs + 1] = { iv[1], fixed, iv[2], fixed, edge = name }
      else segs[#segs + 1] = { fixed, iv[1], fixed, iv[2], edge = name } end
    end
  end
  edge('top', r[2] + inset, r[1], r[3], true)
  edge('bottom', r[4] - inset, r[1], r[3], true)
  edge('left', r[1] + inset, r[2], r[4], false)
  edge('right', r[3] - inset, r[2], r[4], false)
  return segs
end

-- Distance of a point of edge `edge` from the top-left corner of r, clockwise
-- (top left to right, right top to bottom, bottom right to left, left bottom to top),
-- and the perimeter length.
function M.perimeter_pos(r, edge, x, y)
  local w, h = r[3] - r[1], r[4] - r[2]
  local s
  if edge == 'top' then s = x - r[1]
  elseif edge == 'right' then s = w + (y - r[2])
  elseif edge == 'bottom' then s = w + h + (r[3] - x)
  else s = 2 * w + h + (r[4] - y) end
  return s, 2 * (w + h)
end

-- Colour of the cyclic palette at u (any number: only its fractional part counts).
function M.palette_color(palette, u)
  local p = (u % 1) * #palette
  local i = math.floor(p)
  return M.mix_color(palette[i + 1], palette[(i + 1) % #palette + 1], p - i)
end

-- Yellow of a waiting item at time t: a smooth blink between WAIT_MIN_ALPHA and full.
function M.waiting_color(t)
  local k = 0.5 + 0.5 * math.cos(2 * math.pi * (t % WAIT_PERIOD) / WAIT_PERIOD)
  local alpha = math.floor(255 * (WAIT_MIN_ALPHA + (1 - WAIT_MIN_ALPHA) * k) + 0.5)
  return (COL_WAITING & 0xFFFFFF00) | alpha
end

-- The coloured lines of one outline: { xa, ya, xb, yb, col }. kind: "done" | "waiting"
-- | "busy"; t: seconds (animation). A busy outline is cut into pieces of at most
-- CHASE_STEP pixels (fewer pieces on long outlines), each coloured by where it lies
-- on the perimeter, so the palette runs clockwise around the item.
function M.outline_lines(r, kind, t, holes)
  local inset = THICKNESS / 2
  local out = {}
  local segs = M.outline_segments(r, holes, inset)
  if kind ~= 'busy' then
    local col = kind == 'done' and COL_DONE or M.waiting_color(t)
    for _, s in ipairs(segs) do out[#out + 1] = { s[1], s[2], s[3], s[4], col } end
    return out
  end
  local _, perimeter = M.perimeter_pos(r, 'top', r[1], r[2])
  local step = math.max(CHASE_STEP, perimeter / CHASE_MAX_PIECES)
  local shift = t / CHASE_PERIOD
  for _, s in ipairs(segs) do
    local len = math.abs(s[3] - s[1]) + math.abs(s[4] - s[2])
    local n = math.max(1, math.ceil(len / step))
    for i = 0, n - 1 do
      local xa, ya = s[1] + (s[3] - s[1]) * i / n, s[2] + (s[4] - s[2]) * i / n
      local xb, yb = s[1] + (s[3] - s[1]) * (i + 1) / n, s[2] + (s[4] - s[2]) * (i + 1) / n
      local pos = M.perimeter_pos(r, s.edge, (xa + xb) / 2, (ya + yb) / 2)
      -- Minus: the waves travel clockwise as t grows.
      out[#out + 1] = { xa, ya, xb, yb, M.palette_color(BUSY_PALETTE, pos / perimeter * CHASE_WAVES - shift) }
    end
  end
  return out
end

---------------------------------------------------------------- REAPER side

-- Tagged items of the active project: { item, key }, listed again when the project
-- changes (state change count, project tab) or every RESCAN_S seconds.
-- cards[key] = the kind of that saved card, false for none (read once per key and project).
local scan = { proj = nil, count = nil, at = 0, entries = {}, cards = {} }

local function rescan(store)
  local proj = reaper.EnumProjects(-1)
  local count = reaper.GetProjectStateChangeCount(proj)
  local now = reaper.time_precise()
  if proj == scan.proj and count == scan.count and now - scan.at < RESCAN_S then return end
  if proj ~= scan.proj then scan.cards = {} end
  scan.proj, scan.count, scan.at = proj, count, now
  local entries = {}
  for i = 0, reaper.CountMediaItems(0) - 1 do
    local item = reaper.GetMediaItem(0, i)
    local _, tag = reaper.GetSetMediaItemInfo_String(item, store.TAG, '', false)
    local key = store.parse_tag(tag)
    if key then entries[#entries + 1] = { item = item, key = key } end
  end
  scan.entries = entries
end

-- A card was deleted or rewritten outside a session: read it again next time.
function M.forget(key)
  scan.cards[key] = nil
end

-- Items of the active project to outline: { item, kind }. sessions: the cards open in
-- this run, by key (their state is current); the others are read from the project.
function M.items(sessions, store, json)
  rescan(store)
  local out, seen = {}, {}
  for key, s in pairs(sessions) do
    local kind = M.session_kind(s.state)
    if kind and s.item and reaper.ValidatePtr2(0, s.item, 'MediaItem*') then
      out[#out + 1] = { item = s.item, kind = kind }
      seen[key] = true
    end
  end
  for _, e in ipairs(scan.entries) do
    if not seen[e.key] and reaper.ValidatePtr2(0, e.item, 'MediaItem*') then
      local s = sessions[e.key]
      local kind
      if s then
        kind = M.session_kind(s.state) -- an open card whose item was moved by a cut and paste
      else
        kind = scan.cards[e.key]
        if kind == nil then
          kind = M.card_kind(store.load(json, e.key, scan.proj)) or false
          scan.cards[e.key] = kind
        end
      end
      if kind then
        out[#out + 1] = { item = e.item, kind = kind }
        seen[e.key] = true
      end
    end
  end
  return out
end

-- The track view's rectangle in ReaImGui coordinates (see M.to_screen), or nil.
local trackview = nil
local function trackview_frame(ctx, ImGui)
  if not trackview then trackview = reaper.JS_Window_FindChildByID(reaper.GetMainHwnd(), TRACKVIEW_ID) end
  if not trackview then return nil end
  local ok, l, t, r, b = reaper.JS_Window_GetClientRect(trackview)
  if not ok then trackview = nil; return nil end
  -- Native screen coordinates (macOS: origin at the bottom left, y up) -> ReaImGui's.
  local x1, y1 = ImGui.PointConvertNative(ctx, l, t)
  local x2, y2 = ImGui.PointConvertNative(ctx, r, b)
  local native_w, native_h = math.abs(r - l), math.abs(b - t)
  if native_w <= 0 or native_h <= 0 then return nil end
  local w, h = math.abs(x2 - x1), math.abs(y2 - y1)
  -- REAPER's pixels are taken as the native window units (points on macOS).
  return { x = math.min(x1, x2), y = math.min(y1, y2), w = w, h = h, sx = w / native_w, sy = h / native_h }
end

local FLAGS = nil

-- Draws the outlines of these entries ({ item, kind }, from M.items) over the track
-- view at time t (seconds), except inside the holes (this script's windows,
-- ReaImGui coordinates). Nothing to draw: no window at all.
function M.draw(ctx, ImGui, entries, t, holes)
  if #entries == 0 then return end
  local frame = trackview_frame(ctx, ImGui)
  if not frame then return end
  FLAGS = FLAGS or (ImGui.WindowFlags_NoDecoration | ImGui.WindowFlags_NoInputs | ImGui.WindowFlags_NoBackground
    | ImGui.WindowFlags_NoFocusOnAppearing | ImGui.WindowFlags_NoSavedSettings | ImGui.WindowFlags_NoDocking
    | ImGui.WindowFlags_NoMove)
  local start, finish = reaper.GetSet_ArrangeView2(0, false, 0, 0, 0, 0)
  local view = { start = start, zoom = reaper.GetHZoomLevel() }
  local lines = {}
  for _, e in ipairs(entries) do
    local pos = reaper.GetMediaItemInfo_Value(e.item, 'D_POSITION')
    local len = reaper.GetMediaItemInfo_Value(e.item, 'D_LENGTH')
    local track = (pos <= finish and pos + len >= start) and reaper.GetMediaItem_Track(e.item) or nil
    if track and reaper.GetMediaTrackInfo_Value(track, 'B_SHOWINTCP') ~= 0
        and reaper.GetMediaTrackInfo_Value(track, 'I_TCPH') > 0 then
      local x1, y1, x2, y2 = M.item_rect(view, {
        pos = pos, len = len,
        tcpy = reaper.GetMediaTrackInfo_Value(track, 'I_TCPY'),
        lasty = reaper.GetMediaItemInfo_Value(e.item, 'I_LASTY'),
        lasth = reaper.GetMediaItemInfo_Value(e.item, 'I_LASTH'),
      })
      if x1 then
        local a1, b1, a2, b2 = M.to_screen(frame, x1, y1, x2, y2)
        if a1 then
          for _, l in ipairs(M.outline_lines({ a1, b1, a2, b2 }, e.kind, t, holes)) do lines[#lines + 1] = l end
        end
      end
    end
  end
  if #lines == 0 then return end
  ImGui.SetNextWindowPos(ctx, frame.x, frame.y)
  ImGui.SetNextWindowSize(ctx, frame.w, frame.h)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 0, 0)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowBorderSize, 0)
  local visible = ImGui.Begin(ctx, 'Metadata Assistant outlines', nil, FLAGS)
  if visible then
    local dl = ImGui.GetWindowDrawList(ctx)
    for _, l in ipairs(lines) do
      ImGui.DrawList_AddLine(dl, l[1], l[2], l[3], l[4], l[5], THICKNESS)
    end
    ImGui.End(ctx)
  end
  ImGui.PopStyleVar(ctx, 2)
end

return M
