-- @description mtt_TimbreMatch
-- @version 0.2.5
-- @author MTT
-- Load this action after manually installing the complete companion effect folder.
-- Window: ReaImGui, with the look of mtt_FmodSync (palette, square corners, font,
-- gear and settings view, status footer, remembered place and full screen).

if not reaper.APIExists('ImGui_GetBuiltinPath') then
  reaper.MB('ReaImGui is required (ReaPack: ReaTeam Extensions).', 'Missing dependency', 0)
  return
end
package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'

local dir = debug.getinfo(1, 'S').source:match('^@(.+[\\/])')
local Core = dofile(dir .. 'match_core.lua')
local Analyzer = dofile(dir .. 'analyzer.lua')
local R = reaper
-- Mailbox v2: 32 slots x 65568 (same total gmem as v1). Offsets: 0 token, 1 FFT size,
-- 2 sample rate, 3 acknowledgement, 4 attack hold ms (0 = static), 16 body curve,
-- 16+16385 attack curve. Must match the JSFX.
local SEGMENT = 'mtt_TimbreMatch_v2'
local SLOTS, STRIDE, ATTACK_OFFSET = 32, 65568, 16 + 16385
local FX_NAME = 'JS: mtt_TimbreMatch'
local EXT, LEGACY_EXT = 'mtt_TimbreMatch', 'mtt_TimbreMatchOffline'

local function get_preference(key)
  local section = R.HasExtState(EXT, key) and EXT or LEGACY_EXT
  return R.GetExtState(section, key)
end

local ctx = ImGui.CreateContext('mtt_TimbreMatch')

------------------------------------------------------------------------------
-- Look: the palette, rounding and font of mtt_FmodSync (itself mtt_MetadataAssistant's).

local COL_ERR = 0xFF6464FF
local COL_WARN = 0xE6B43CFF
local COL_OK = 0x78D278FF
local COL_DIM = 0x9A9A9AFF
local COL_ACCENT = 0xE89B3CFF
local COL_SELECTED = 0x9A6322FF
local COL_SELECTED_HOVER = 0xAE7229FF
local COL_SELECTED_ACTIVE = 0x84541AFF
local COL_BUTTON = 0x303435FF
local COL_BODY = 0x8FB8C8FF -- body curve in the spectrum, next to the accent (attack)
local palette = {
  { ImGui.Col_WindowBg, 0x191A1BFF }, { ImGui.Col_TitleBg, 0x202223FF },
  { ImGui.Col_TitleBgActive, 0x292B2CFF }, { ImGui.Col_Text, 0xECEEEBFF },
  { ImGui.Col_TextDisabled, 0xA6AAA8FF }, { ImGui.Col_Separator, 0x464A49FF },
  { ImGui.Col_FrameBg, 0x2D3031FF }, { ImGui.Col_FrameBgHovered, 0x373B3CFF },
  { ImGui.Col_FrameBgActive, 0x3C4142FF }, { ImGui.Col_Button, COL_BUTTON },
  { ImGui.Col_ButtonHovered, 0x414948FF }, { ImGui.Col_ButtonActive, 0x4D5956FF },
  { ImGui.Col_CheckMark, COL_ACCENT }, { ImGui.Col_Header, 0x3A3328FF },
  { ImGui.Col_HeaderHovered, 0x4D4129FF }, { ImGui.Col_HeaderActive, COL_SELECTED },
  { ImGui.Col_SliderGrab, COL_ACCENT }, { ImGui.Col_SliderGrabActive, 0xF0B462FF },
  { ImGui.Col_TextSelectedBg, 0xE89B3C66 },
  { ImGui.Col_ScrollbarGrab, 0x58534AFF }, { ImGui.Col_ScrollbarGrabHovered, 0x756A4FFF },
  { ImGui.Col_ScrollbarGrabActive, COL_ACCENT },
  { ImGui.Col_ResizeGrip, 0xE89B3C33 }, { ImGui.Col_ResizeGripHovered, 0xE89B3C99 },
  { ImGui.Col_ResizeGripActive, COL_ACCENT },
}
local ITEM_SPACING_X = 8
local FRAME_PAD_X = 9
local style_vars = {
  { ImGui.StyleVar_WindowRounding, 0 }, { ImGui.StyleVar_ChildRounding, 0 },
  { ImGui.StyleVar_PopupRounding, 0 }, { ImGui.StyleVar_ScrollbarRounding, 0 },
  { ImGui.StyleVar_GrabRounding, 0 }, { ImGui.StyleVar_FrameRounding, 0 },
  { ImGui.StyleVar_WindowPadding, 16, 14 },
  { ImGui.StyleVar_ItemSpacing, ITEM_SPACING_X, 7 },
  { ImGui.StyleVar_FramePadding, FRAME_PAD_X, 5 },
}

local FONT_SIZE = 15
local FOOTER_SIZE = 12 -- font size of the footer and of the small notes
local ok_font, font = pcall(function()
  local f = ImGui.CreateFont('sans-serif', FONT_SIZE)
  ImGui.Attach(ctx, f)
  return f
end)
if not ok_font then font = nil end

local function push_style()
  if font then ImGui.PushFont(ctx, font, FONT_SIZE) end
  for _, pair in ipairs(palette) do ImGui.PushStyleColor(ctx, pair[1], pair[2]) end
  for _, v in ipairs(style_vars) do
    if v[3] then ImGui.PushStyleVar(ctx, v[1], v[2], v[3]) else ImGui.PushStyleVar(ctx, v[1], v[2]) end
  end
end

local function pop_style()
  ImGui.PopStyleVar(ctx, #style_vars)
  ImGui.PopStyleColor(ctx, #palette)
  if font then ImGui.PopFont(ctx) end
end

local function accent_button(label, width)
  ImGui.PushStyleColor(ctx, ImGui.Col_Button, COL_SELECTED)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, COL_SELECTED_HOVER)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, COL_SELECTED_ACTIVE)
  local clicked = ImGui.Button(ctx, label, width or 0)
  ImGui.PopStyleColor(ctx, 3)
  return clicked
end

local function align_right(width)
  local avail = ImGui.GetContentRegionAvail(ctx)
  if avail > width then ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + avail - width) end
end

local function button_width(label)
  return ImGui.CalcTextSize(ctx, label) + 2 * FRAME_PAD_X
end

-- Tooltip for the item just drawn, also while it is disabled.
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

-- A square icon button one frame tall (as in mtt_FmodSync).
local function icon_button(id, active, paint)
  local h = ImGui.GetFrameHeight(ctx)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local clicked = ImGui.InvisibleButton(ctx, id, h, h)
  local hovered, held = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
  local dl = ImGui.GetWindowDrawList(ctx)
  if hovered then
    ImGui.DrawList_AddRectFilled(dl, x, y, x + h, y + h,
      ImGui.GetColor(ctx, held and ImGui.Col_ButtonActive or ImGui.Col_ButtonHovered))
  end
  paint(dl, math.floor(x), math.floor(y), h, active and COL_ACCENT or ImGui.GetColor(ctx, ImGui.Col_Text))
  return clicked
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

------------------------------------------------------------------------------
-- Window placement and full screen (as in mtt_FmodSync).

-- The window's place from the last run: ExtState "x,y,w,h,fs" (fs = 1 when
-- it was full screen; x, y, w, h are then where it goes back to).
local function saved_geometry(key)
  local v = get_preference('window_' .. key)
  local x, y, w, h, fs = v:match('^(%-?%d+),(%-?%d+),(%d+),(%d+),(%d)$')
  if not x then return nil end
  return { tonumber(x), tonumber(y), tonumber(w), tonumber(h), fs = fs == '1' }
end

-- True when the centre of g lies on a screen (a screen may be gone since).
local function on_screen(g)
  local cx, cy = g[1] + g[3] / 2, g[2] + g[4] / 2
  local nx, ny = ImGui.PointConvertNative(ctx, cx, cy, true)
  nx, ny = math.floor(nx), math.floor(ny)
  local l, t, r, b = R.my_getViewport(0, 0, 0, 0, nx, ny, nx + 1, ny + 1, true)
  if not (l and t and r and b) then return true end
  return nx >= math.min(l, r) and nx <= math.max(l, r) and ny >= math.min(t, b) and ny <= math.max(t, b)
end

local opened_windows = {}
local enter_fullscreen = {} -- key -> true: enter full screen on the first frame
local function prepare_window(key, width, height)
  if opened_windows[key] then return end
  local viewport = ImGui.GetMainViewport(ctx)
  local x, y = ImGui.Viewport_GetWorkPos(viewport)
  local w, h = ImGui.Viewport_GetWorkSize(viewport)
  if w <= 0 or h <= 0 then return end -- retry when the main viewport is ready
  ImGui.SetNextWindowDockID(ctx, 0, ImGui.Cond_Always)
  ImGui.SetNextWindowCollapsed(ctx, false, ImGui.Cond_Always)
  local g = saved_geometry(key)
  if g and g[3] >= 100 and g[4] >= 100 and on_screen(g) then
    ImGui.SetNextWindowPos(ctx, g[1], g[2], ImGui.Cond_Always)
    ImGui.SetNextWindowSize(ctx, g[3], g[4], ImGui.Cond_Always)
    enter_fullscreen[key] = g.fs or nil
  else
    ImGui.SetNextWindowPos(ctx, x + w / 2, y + h / 2, ImGui.Cond_Always, 0.5, 0.5)
    ImGui.SetNextWindowSize(ctx, math.min(width, math.max(1, w - 32)),
      math.min(height, math.max(1, h - 32)), ImGui.Cond_Always)
    enter_fullscreen[key] = g and g.fs or nil
  end
  opened_windows[key] = true
end

local fullscreen = {}      -- key -> { back = {x, y, w, h}, screen = {x, y, w, h} }
local fullscreen_back = {} -- key -> the geometry to put back on the next frame

-- Work area of the screen holding most of the current window, in ReaImGui
-- coordinates; nil when REAPER gives nothing usable (see mtt_FmodSync).
local function window_screen()
  local x, y = ImGui.GetWindowPos(ctx)
  local w, h = ImGui.GetWindowSize(ctx)
  local ax, ay = ImGui.PointConvertNative(ctx, x, y, true)
  local bx, by = ImGui.PointConvertNative(ctx, x + w, y + h, true)
  local l, t, r, b = R.my_getViewport(0, 0, 0, 0,
    math.floor(math.min(ax, bx)), math.floor(math.min(ay, by)),
    math.floor(math.max(ax, bx)), math.floor(math.max(ay, by)), true)
  if not (l and t and r and b) then return nil end
  local x1, y1 = ImGui.PointConvertNative(ctx, l, t)
  local x2, y2 = ImGui.PointConvertNative(ctx, r, b)
  local sw, sh = math.abs(x2 - x1), math.abs(y2 - y1)
  if sw < 100 or sh < 100 then return nil end
  return { math.min(x1, x2), math.min(y1, y2), sw, sh }
end

-- Before Begin (after prepare_window): returns the window flags full screen adds.
local function prepare_fullscreen(key)
  local fs = fullscreen[key]
  if fs then
    local sc = fs.screen
    ImGui.SetNextWindowCollapsed(ctx, false, ImGui.Cond_Always)
    ImGui.SetNextWindowPos(ctx, sc[1], sc[2], ImGui.Cond_Always)
    ImGui.SetNextWindowSize(ctx, sc[3], sc[4], ImGui.Cond_Always)
    return ImGui.WindowFlags_NoMove | ImGui.WindowFlags_NoResize
  end
  local back = fullscreen_back[key]
  if back then
    ImGui.SetNextWindowPos(ctx, back[1], back[2], ImGui.Cond_Always)
    ImGui.SetNextWindowSize(ctx, back[3], back[4], ImGui.Cond_Always)
    fullscreen_back[key] = nil
  end
  return 0
end

-- Between Begin and End. The screen is read once, on entering.
local function toggle_fullscreen(key)
  if fullscreen[key] then
    fullscreen_back[key], fullscreen[key] = fullscreen[key].back, nil
    return
  end
  local x, y = ImGui.GetWindowPos(ctx)
  local w, h = ImGui.GetWindowSize(ctx)
  local screen = window_screen()
  if not screen then -- REAPER's main window instead
    local viewport = ImGui.GetMainViewport(ctx)
    local vx, vy = ImGui.Viewport_GetWorkPos(viewport)
    local vw, vh = ImGui.Viewport_GetWorkSize(viewport)
    if vw <= 0 or vh <= 0 then return end
    screen = { vx, vy, vw, vh }
  end
  fullscreen[key] = { back = { x, y, w, h }, screen = screen }
end

-- Right after Begin: enters full screen when the last run ended in it, and
-- remembers the window's place (not while a mouse button is down).
local last_geometry = {}
local function remember_window(key)
  if enter_fullscreen[key] then
    enter_fullscreen[key] = nil
    if not fullscreen[key] then toggle_fullscreen(key) end
  end
  if ImGui.IsMouseDown(ctx, 0) then return end
  local g, fs = nil, fullscreen[key]
  if fs then g = fs.back
  elseif fullscreen_back[key] then return -- leaving: the next frame puts it back
  else
    local x, y = ImGui.GetWindowPos(ctx)
    local w, h = ImGui.GetWindowSize(ctx)
    g = { x, y, w, h }
  end
  local v = string.format('%d,%d,%d,%d,%d', math.floor(g[1] + 0.5), math.floor(g[2] + 0.5),
    math.floor(g[3] + 0.5), math.floor(g[4] + 0.5), fs and 1 or 0)
  if v ~= last_geometry[key] then
    last_geometry[key] = v
    R.SetExtState(EXT, 'window_' .. key, v, true)
  end
end

-- Right after Begin: the full screen icon in the title bar, left of the close
-- button, placed and drawn as in mtt_FmodSync.
local function fullscreen_title_button(key)
  local wx, wy = ImGui.GetWindowPos(ctx)
  local ww = ImGui.GetWindowSize(ctx)
  local pad_x, pad_y = ImGui.GetStyleVar(ctx, ImGui.StyleVar_FramePadding)
  local inner_x = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemInnerSpacing)
  local sz = ImGui.GetFontSize(ctx)
  local line_h = ImGui.GetTextLineHeight(ctx)
  local bx = wx + ww - pad_x - sz - inner_x - sz
  local by = wy + pad_y + (line_h - sz) * 0.5
  local cur_x, cur_y = ImGui.GetCursorPos(ctx)
  ImGui.PushClipRect(ctx, wx, wy, wx + ww, wy + line_h + 2 * pad_y, false) -- the title bar
  ImGui.SetCursorScreenPos(ctx, bx, by)
  local clicked = ImGui.InvisibleButton(ctx, '##fullscreen', sz, sz)
  local hovered, held = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
  local dl = ImGui.GetWindowDrawList(ctx)
  if hovered then
    ImGui.DrawList_AddRectFilled(dl, bx, by, bx + sz, by + sz,
      ImGui.GetColor(ctx, held and ImGui.Col_ButtonActive or ImGui.Col_ButtonHovered))
  end
  local col = ImGui.GetColor(ctx, ImGui.Col_Text)
  local cx, cy = bx + sz / 2 - 0.5, by + sz / 2 - 0.5
  local outer = sz * 0.5 * 0.7071 - 1
  local near = outer * 0.3
  local on = fullscreen[key] ~= nil
  for _, sign in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
    local sx, sy = sign[1], sign[2]
    local corner, tip_end = on and near or outer, on and outer or near
    local px, py = cx + sx * corner, cy + sy * corner
    ImGui.DrawList_AddLine(dl, px, py, cx + sx * tip_end, py, col, 1)
    ImGui.DrawList_AddLine(dl, px, py, px, cy + sy * tip_end, col, 1)
  end
  ImGui.PopClipRect(ctx)
  tip(on and 'Leave full screen: the window goes back where and as large as it was.'
    or 'Full screen on the display this window is on.')
  ImGui.SetCursorPos(ctx, cur_x, cur_y)
  if clicked then toggle_fullscreen(key) end
end

-- Right after Begin: a double click on the title bar (not on its icons) enters or
-- leaves full screen, as on macOS.
local function title_double_click(key)
  if not ImGui.IsMouseDoubleClicked(ctx, 0) or not ImGui.IsWindowHovered(ctx) then return end
  local mx, my = ImGui.GetMousePos(ctx)
  local wx, wy = ImGui.GetWindowPos(ctx)
  local ww = ImGui.GetWindowSize(ctx)
  local pad_x, pad_y = ImGui.GetStyleVar(ctx, ImGui.StyleVar_FramePadding)
  local inner_x = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemInnerSpacing)
  local sz = ImGui.GetFontSize(ctx)
  local icons_x = wx + ww - pad_x - 2 * sz - inner_x
  local title_h = ImGui.GetTextLineHeight(ctx) + 2 * pad_y
  if my >= wy and my < wy + title_h and mx >= wx and mx < icons_x then toggle_fullscreen(key) end
end

------------------------------------------------------------------------------
-- Settings: saved in REAPER's ExtState on every change.

local DEFAULTS = { n = 32768, hop_ms = 10, smooth = 1/3, range = 24, attack_ms = 15, split = 'auto' }
-- 1/3 octave: a short minimum-phase FIR cannot reproduce finer low-frequency detail
-- without long ringing. Attack hold 15 ms with the 10 dB detector: best spectro-temporal
-- match on impact tests. Auto: attack + body only for impulsive material.
local function default_cfg()
  return Core.settings(DEFAULTS.n, DEFAULTS.hop_ms, DEFAULTS.smooth, DEFAULTS.range, DEFAULTS.attack_ms, DEFAULTS.split)
end
local function load_cfg()
  local v = get_preference('analysis')
  local a, b, c, d, e, f = v:match('^([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),(%a+)$')
  local ok, loaded = pcall(Core.settings, a, b, c, d, e, f)
  if a and ok then return loaded end
  return default_cfg()
end
local cfg = load_cfg()

------------------------------------------------------------------------------
-- State and logic.

local job, reference, dragging, view
-- Footer status: kind is 'idle', 'busy', 'ok', 'warn' or 'err'.
local status = { kind = 'idle', text = 'Select a reference item, then Analyze reference.' }
local progress = 0
local plot_cache -- display curves of the reference, per plot width

local function set_status(kind, text) status = { kind = kind, text = text } end
local function stop_job()
  if job then job:close(); job = nil end
end
local function message(err)
  set_status('err', (tostring(err):match('[^\n]+'):gsub('^.-:%d+: ', '')))
end
local function current_sr()
  local sr = R.GetSetProjectInfo(0, 'PROJECT_SRATE', 0, false)
  if sr <= 0 then local ok, value = R.GetAudioDeviceInfo('SRATE'); sr = ok and tonumber(value) or 48000 end
  return math.floor(Core.clamp(sr or 48000, 8000, 384000) + 0.5)
end

local function save_cfg(new)
  cfg = new
  R.SetExtState(EXT, 'analysis', string.format('%d,%.17g,%.17g,%.17g,%.17g,%s',
    cfg.n, cfg.hop_ms, cfg.smooth, cfg.range, cfg.attack_ms, cfg.split), true)
  if reference then
    reference, plot_cache = nil, nil
    set_status('warn', 'Settings changed. Analyze the reference again.')
  end
end

-- items: one or more items, pooled into one profile (Analyzer.pool).
local function begin_analysis(items, role)
  if job then return end
  local sr = role == 'target' and reference.sr or current_sr()
  local settings = role == 'target' and reference.cfg or cfg
  local ok, result = pcall(Analyzer.pool, R, items, settings, sr, Core)
  if not ok then message(result); return end
  job = result; job.role = role; job.cfg = settings
  progress = 0
  set_status('busy', (role == 'reference' and 'Analyzing the reference' or 'Analyzing the destination')
    .. (result.rendered > 0 and string.format(' (%d temporary render%s)...', result.rendered, result.rendered > 1 and 's' or '') or '...'))
end

local function reserve(body, attack, n, sr, attack_ms)
  R.gmem_attach(SEGMENT)
  local slot
  for s = 0, SLOTS - 1 do if R.gmem_read(s * STRIDE) == 0 then slot = s; break end end
  assert(slot, 'All transfer slots are busy. Close other match actions and retry.')
  local token = 0
  for c in R.genGuid():gmatch('.') do token = (token * 33 + c:byte()) % 16777214 end
  token = token + 1
  local base = slot * STRIDE
  R.gmem_write(base + 3, 0)
  R.gmem_write(base + 1, n); R.gmem_write(base + 2, sr); R.gmem_write(base + 4, attack and attack_ms or 0)
  for i, value in ipairs(body) do R.gmem_write(base + 15 + i, value) end
  if attack then for i, value in ipairs(attack) do R.gmem_write(base + ATTACK_OFFSET + i - 1, value) end end
  R.gmem_write(base, token) -- Publish last; the payload is immutable until acknowledged.
  return slot, token
end

-- One new instance per destination take (each with its own transfer slot and
-- acknowledgement), all in one undo point. A failure removes every instance added.
local function insert_match(analysis, body, attack, attack_ms)
  assert(analysis:valid(), 'The destination changed. Analyze again.')
  for _, t in ipairs(analysis.items) do
    assert(R.GetMediaItemInfo_Value(t.item, 'C_LOCK') == 0,
      #analysis.items == 1 and 'The destination item is locked.' or 'A destination item is locked.')
  end
  local added = {} -- takes whose new instance is now first in their chain
  R.Undo_BeginBlock2(analysis.project)
  local ok, err = xpcall(function()
    for _, t in ipairs(analysis.items) do
      local take, fx = t.take, -1
      local slot, token = reserve(body, attack, analysis.n, analysis.sr, attack_ms)
      local done, failure = xpcall(function()
        fx = R.TakeFX_AddByName(take, FX_NAME, -1)
        assert(fx >= 0, 'Install the complete mtt_TimbreMatch folder in REAPER Effects first.')
        assert(R.TakeFX_SetParam(take, fx, 2, slot), 'Cannot set the profile slot.')
        assert(R.TakeFX_SetParam(take, fx, 3, token), 'Cannot set the profile token.')
        -- Saving a chunk invokes @serialize even if the take has not played yet.
        local saved = R.GetItemStateChunk(t.item, '', false)
        assert(saved and R.gmem_read(slot * STRIDE + 3) == token,
          'The JSFX did not acknowledge the saved profile. The new effect was removed.')
        -- Accessor samples are pre-FX, so this EQ must be first in the take chain.
        if fx > 0 then R.TakeFX_CopyToTake(take, fx, take, 0, true); fx = 0 end
        R.TakeFX_SetNamedConfigParm(take, fx, 'renamed_name', 'mtt_TimbreMatch - ' .. reference.name)
        R.UpdateItemInProject(t.item)
      end, debug.traceback)
      R.gmem_write(slot * STRIDE, 0)
      if not done then
        if fx >= 0 and R.ValidatePtr2(analysis.project, take, 'MediaItem_Take*') then R.TakeFX_Delete(take, fx) end
        error(failure, 0)
      end
      added[#added + 1] = take
    end
  end, debug.traceback)
  if not ok then
    for _, take in ipairs(added) do
      if R.ValidatePtr2(analysis.project, take, 'MediaItem_Take*') then R.TakeFX_Delete(take, 0) end
    end
  end
  R.Undo_EndBlock2(analysis.project, ok and 'mtt_TimbreMatch: apply match' or 'mtt_TimbreMatch: cancel failed match', -1)
  if not ok then error(err) end
  local name = #analysis.items == 1 and R.GetTakeName(analysis.take) or (#analysis.items .. ' items')
  set_status('ok', (attack and string.format('Applied to %s: attack (%g ms) + body curves.', name, attack_ms)
    or ('Applied to ' .. name .. ': one whole-item curve.')) .. ' Undo available.')
end

local function finish_job()
  if job.role == 'reference' then
    Core.normalize(job.power) -- Reject silence before displaying or accepting a drop.
    local name = R.GetTakeName(job.take)
    if #job.items > 1 then name = string.format('%s + %d more', name ~= '' and name or '(unnamed take)', #job.items - 1) end
    local items = {}
    for i, t in ipairs(job.items) do items[i] = t.item end
    reference = { power = job.power, power_attack = job.power_attack, power_body = job.power_body,
      stats = job.stats, sr = job.sr, n = job.n, cfg = job.cfg, name = name, frames = job.frames,
      items = items, project = job.project }
    plot_cache = nil
    set_status('ok', 'Reference ready. Drag its spectrum onto a destination item.')
  else
    local c = reference.cfg
    -- Auto: attack + body only when both items are impulsive (impacts, hits, footsteps);
    -- speech, whooshes and ambiences get one whole-item curve.
    local use_split, why = false, nil
    if job.split then
      if c.split == 'always' then use_split = true
      else
        local ref_imp, dst_imp = Core.impulsive(reference.stats), Core.impulsive(job.stats)
        use_split = ref_imp and dst_imp
        why = not ref_imp and 'the reference' or not dst_imp and 'the destination' or nil
      end
    end
    if use_split then
      local body, attack, split = Core.match_split(reference.power_attack, reference.power_body,
        job.power_attack, job.power_body, c.smooth, c.range, reference.power, job.power)
      insert_match(job, body, split and attack or nil, c.attack_ms)
      if not split then
        set_status('warn', 'No transient in one of the items: applied one whole-item curve. Undo available.')
      end
    else
      insert_match(job, Core.match(reference.power, job.power, c.smooth, c.range), nil, 0)
      if why then
        set_status('ok', 'Auto: one whole-item curve (' .. why .. ' is not impulsive). Undo available.')
      end
    end
  end
end

-- Runs the analysis for up to 20 ms per frame.
local function run_job()
  if not job then return end
  local ok, err = xpcall(function()
    local deadline = R.time_precise() + 0.02
    while job and R.time_precise() < deadline do
      local done = job:step()
      progress = job:progress()
      if done then finish_job(); stop_job() end
    end
  end, debug.traceback)
  if not ok then stop_job(); dragging = false; message(err) end
end

-- All selected items: several (a montage, layers) are analyzed as one sound.
local function selected()
  local count = R.CountSelectedMediaItems(0)
  assert(count > 0, 'Select one or more audio items.')
  local items = {}
  for i = 0, count - 1 do items[#items + 1] = R.GetSelectedMediaItem(0, i) end
  return items
end
local function on_selected(role)
  local ok, items = pcall(selected)
  if ok then begin_analysis(items, role) else message(items) end
end

------------------------------------------------------------------------------
-- Spectrum.

local F_MIN, DB_RANGE = 20, 72
local COL_DRAGGED = 0x3A3D3EFF -- the curves left behind while they are dragged out

-- Whether the reference is shown (and, in Auto, likely matched) as attack + body.
local function reference_split()
  if not reference or not reference.power_attack then return false end
  if reference.cfg.split == 'always' then return true end
  return (Core.impulsive(reference.stats))
end

-- Display curves (dB re. peak per pixel column), smoothed with the analysis smoothing
-- (at least 1/12 octave) so the plot shows what the match uses, not FFT noise.
local function plot_curves(w)
  if plot_cache and plot_cache.w == w then return plot_cache end
  local f_max = math.min(20000, reference.sr / 2)
  local oct = math.max(1/12, reference.cfg.smooth)
  local function columns(power)
    local s = Core.smooth(power, oct)
    local peak = 0
    for _, v in ipairs(s) do peak = math.max(peak, v) end
    local out = {}
    for x = 0, w - 1 do
      local hz = F_MIN * (f_max / F_MIN) ^ (x / math.max(1, w - 1))
      local k = hz * reference.n / reference.sr
      local a = math.floor(k)
      local v1, v2 = s[a + 1] or 0, s[a + 2] or s[a + 1] or 0
      local v = v1 + (v2 - v1) * (k - a)
      out[x + 1] = 10 * math.log(math.max(1e-12, v / math.max(peak, 1e-30)), 10)
    end
    return out
  end
  plot_cache = { w = w, f_max = f_max }
  if reference_split() then
    plot_cache.body = columns(reference.power_body)
    plot_cache.attack = columns(reference.power_attack)
  else
    plot_cache.whole = columns(reference.power)
  end
  return plot_cache
end

-- Curves of `c` in the box x0, y0, w, h (top/bottom margins scale with h).
local function draw_curves(dl, c, x0, y0, w, h, top, bottom, dim)
  local function one(values, col)
    local px, py
    local step = #values / w
    for i = 0, w - 1 do
      local db = values[math.min(#values, math.floor(i * step) + 1)]
      local y = y0 + top + (h - top - bottom) * math.min(1, math.max(0, -db / DB_RANGE))
      local x = x0 + i
      if px then ImGui.DrawList_AddLine(dl, px, py, x, y, dim or col, 1.5) end
      px, py = x, y
    end
  end
  if c.whole then one(c.whole, COL_ACCENT)
  else one(c.body, COL_BODY); one(c.attack, COL_ACCENT) end
end

local function hz_label(f) return f >= 1000 and string.format('%gk', f / 1000) or string.format('%g', f) end

-- While dragging: a borderless, transparent window under the mouse with the same
-- curves, small (as mtt_envelope_stealer drags its envelope out of its plot).
local GHOST_W, GHOST_H = 150, 64
local function draw_drag_ghost(c)
  local mx, my = ImGui.GetMousePos(ctx)
  ImGui.SetNextWindowPos(ctx, mx + 12, my - GHOST_H / 2, ImGui.Cond_Always)
  ImGui.SetNextWindowSize(ctx, GHOST_W, GHOST_H, ImGui.Cond_Always)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 0, 0)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowBorderSize, 0)
  local flags = ImGui.WindowFlags_NoDecoration | ImGui.WindowFlags_NoBackground
    | ImGui.WindowFlags_NoSavedSettings | ImGui.WindowFlags_NoMove | ImGui.WindowFlags_NoInputs
    | ImGui.WindowFlags_NoFocusOnAppearing | ImGui.WindowFlags_NoNav | ImGui.WindowFlags_NoDocking
    | ImGui.WindowFlags_TopMost
  if ImGui.Begin(ctx, '##drag_ghost', nil, flags) then
    local x, y = ImGui.GetWindowPos(ctx)
    draw_curves(ImGui.GetWindowDrawList(ctx), c, x, y, GHOST_W, GHOST_H, 4, 4)
    ImGui.End(ctx)
  end
  ImGui.PopStyleVar(ctx, 2)
end

-- The reference spectrum, framed; it is also the drag source for a destination.
local function draw_spectrum(h)
  local w = math.max(100, math.floor(ImGui.GetContentRegionAvail(ctx)))
  local x0, y0 = ImGui.GetCursorScreenPos(ctx)
  ImGui.InvisibleButton(ctx, '##spectrum', w, h)
  local hovered, active = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
  local released = ImGui.IsItemDeactivated(ctx)
  local dl = ImGui.GetWindowDrawList(ctx)
  ImGui.DrawList_AddRectFilled(dl, x0, y0, x0 + w, y0 + h, ImGui.GetColor(ctx, ImGui.Col_FrameBg))
  local grid, label = 0x464A4980, ImGui.GetColor(ctx, ImGui.Col_TextDisabled)
  local f_max = reference and math.min(20000, reference.sr / 2) or 20000
  for _, f in ipairs({ 50, 100, 200, 500, 1000, 2000, 5000, 10000 }) do
    if f < f_max then
      local x = x0 + math.floor((w - 1) * math.log(f / F_MIN) / math.log(f_max / F_MIN)) + 0.5
      ImGui.DrawList_AddLine(dl, x, y0, x, y0 + h - 18, grid, 1)
      ImGui.DrawList_AddText(dl, x + 3, y0 + h - 17, label, hz_label(f))
    end
  end
  for db = 0, DB_RANGE, 24 do
    local y = math.floor(y0 + 8 + (h - 30) * db / DB_RANGE) + 0.5
    ImGui.DrawList_AddLine(dl, x0, y, x0 + w, y, grid, 1)
  end
  if reference then
    if not job and active and ImGui.IsMouseDragging(ctx, 0) then dragging = true end
    local c = plot_curves(w)
    draw_curves(dl, c, x0, y0, w, h, 8, 22, dragging and COL_DRAGGED or nil)
    if not c.whole then
      local lx = x0 + w - 130
      ImGui.DrawList_AddLine(dl, lx, y0 + 15, lx + 14, y0 + 15, COL_ACCENT, 2)
      ImGui.DrawList_AddText(dl, lx + 20, y0 + 7, label, 'attack')
      ImGui.DrawList_AddLine(dl, lx + 70, y0 + 15, lx + 84, y0 + 15, COL_BODY, 2)
      ImGui.DrawList_AddText(dl, lx + 90, y0 + 7, label, 'body')
    end
    if dragging then
      ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_Hand)
      draw_drag_ghost(c)
    elseif hovered and not job then
      -- As mtt_envelope_stealer: the plot lights up and says what to do with it.
      ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_Hand)
      ImGui.DrawList_AddRectFilled(dl, x0, y0, x0 + w, y0 + h, 0x4D4D4D40)
      ImGui.DrawList_AddRect(dl, x0, y0, x0 + w, y0 + h, 0xCCCCCCFF, 0, 0, 1)
      local text = 'Drag onto an item in the arrange view'
      local tw, th = ImGui.CalcTextSize(ctx, text)
      ImGui.DrawList_AddText(dl, x0 + (w - tw) / 2, y0 + (h - th) / 2, ImGui.GetColor(ctx, ImGui.Col_Text), text)
    end
  else
    local text = job and 'Analyzing...' or 'Analyze an audio item to create a draggable reference.'
    local tw, th = ImGui.CalcTextSize(ctx, text)
    ImGui.DrawList_AddText(dl, x0 + (w - tw) / 2, y0 + (h - th) / 2, label, text)
  end
  if released and dragging then
    dragging = false
    if not hovered then -- released outside the spectrum: the item under the mouse, if any
      local mx, my = R.GetMousePosition()
      local item = R.GetItemFromPoint(mx, my, false)
      if item then begin_analysis({ item }, 'target')
      else set_status('warn', 'Drop over an unlocked audio item, or use Apply to selected items.') end
    end
  end
end

------------------------------------------------------------------------------
-- Views.

-- Progress bar with its label fixed at the centre (ImGui's own label follows the fill).
-- The label is drawn twice, clipped at the fill edge: dark over the accent fill, the
-- normal text colour over the empty part, so a letter cut by the edge stays readable.
local COL_ON_ACCENT = 0x191A1BFF -- the window background: dark on the orange fill
local function progress_bar(fraction, w, h, label)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  ImGui.Dummy(ctx, w, h)
  local dl = ImGui.GetWindowDrawList(ctx)
  local fill = x + w * math.max(0, math.min(1, fraction))
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, ImGui.GetColor(ctx, ImGui.Col_FrameBg))
  if fill > x then ImGui.DrawList_AddRectFilled(dl, x, y, fill, y + h, COL_ACCENT) end
  local tw, th = ImGui.CalcTextSize(ctx, label)
  local tx, ty = math.floor(x + (w - tw) / 2), math.floor(y + (h - th) / 2)
  ImGui.DrawList_PushClipRect(dl, x, y, fill, y + h, true)
  ImGui.DrawList_AddText(dl, tx, ty, COL_ON_ACCENT, label)
  ImGui.DrawList_PopClipRect(dl)
  ImGui.DrawList_PushClipRect(dl, fill, y, x + w, y + h, true)
  ImGui.DrawList_AddText(dl, tx, ty, ImGui.GetColor(ctx, ImGui.Col_Text), label)
  ImGui.DrawList_PopClipRect(dl)
end

local function draw_toolbar()
  ImGui.BeginDisabled(ctx, job ~= nil)
  if accent_button('Analyze reference') then on_selected('reference') end
  tip('Analyzes the selected item (pre-FX) as the timbre to match.'
    .. '\nSeveral selected items (a montage) are analyzed as one sound, without gluing.')
  ImGui.SameLine(ctx)
  ImGui.BeginDisabled(ctx, reference == nil)
  if ImGui.Button(ctx, 'Apply to selected items') then on_selected('target') end
  tip('Analyzes the selected items as one sound and inserts the same matching EQ first'
    .. '\nin the take FX of each.'
    .. '\nOr drag the reference spectrum onto any item.')
  ImGui.EndDisabled(ctx)
  ImGui.EndDisabled(ctx)
  if job then
    ImGui.SameLine(ctx)
    local cancel_w = button_width('Cancel')
    local bar_w = ImGui.GetContentRegionAvail(ctx) - cancel_w - ITEM_SPACING_X
    progress_bar(progress, bar_w, ImGui.GetFrameHeight(ctx),
      string.format('%s %d%%', job.role == 'reference' and 'Reference' or 'Destination', math.floor(progress * 100)))
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, 'Cancel') then stop_job(); set_status('idle', 'Analysis cancelled.') end
  end
end

local SPLIT_LABEL = { auto = 'Auto', static = 'One curve', always = 'Attack + body' }

local function analysis_line(c, sr)
  local mode = c.split == 'static' and 'one curve'
    or string.format('%s, hold %g ms', c.split == 'auto' and 'auto split' or 'attack + body', c.attack_ms)
  local smooth = c.smooth == 0 and 'no smoothing' or (c.smooth == 1/3 and '1/3' or string.format('%.3g', c.smooth)) .. ' oct'
  return string.format('FFT %d (%.2f Hz)   ·   hop %g ms   ·   %s   ·   %s',
    c.n, sr / c.n, math.min(c.hop_ms, c.n / sr * 500), smooth, mode)
end

-- Small grey text under a line (the footer's font size).
local function small_note(text)
  if font then ImGui.PushFont(ctx, font, FOOTER_SIZE) end
  ImGui.TextDisabled(ctx, text)
  if font then ImGui.PopFont(ctx) end
end

-- The reference's name as a link (as in mtt_envelope_stealer): brighter with a hand
-- on hover; a click moves the edit cursor to the reference items and selects only them.
local function reference_link()
  local name = reference.name ~= '' and reference.name or '(unnamed take)'
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx, name)
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_Hand)
    local w, h = ImGui.GetItemRectSize(ctx)
    local ix, iy = ImGui.GetItemRectMin(ctx)
    ImGui.DrawList_AddLine(ImGui.GetWindowDrawList(ctx), ix, iy + h - 1, ix + w, iy + h - 1, COL_ACCENT, 1)
  end
  tip(#reference.items == 1 and 'Go to the reference item' or 'Go to the reference items')
  if ImGui.IsItemClicked(ctx, 0) then
    local proj, items, start = reference.project, {}, nil
    if R.EnumProjects(-1) == proj then
      for _, item in ipairs(reference.items) do
        if R.ValidatePtr2(proj, item, 'MediaItem*') then
          items[#items + 1] = item
          local pos = R.GetMediaItemInfo_Value(item, 'D_POSITION')
          start = start and math.min(start, pos) or pos
        end
      end
    end
    if #items == 0 then
      set_status('warn', 'The reference items are no longer in the current project.')
    else
      R.SetEditCurPos2(proj, start, true, false)
      R.Main_OnCommand(40289, 0) -- Item: Unselect (clear selection of) all items
      for _, item in ipairs(items) do R.SetMediaItemSelected(item, true) end
      R.UpdateArrange()
    end
  end
end

-- What the transient detector found in the reference, for Auto.
local function draw_impulsiveness()
  if not reference.stats then return end
  local imp, share, density = Core.impulsive(reference.stats)
  ImGui.SameLine(ctx)
  if imp then
    ImGui.TextColored(ctx, COL_ACCENT, 'impulsive')
  else
    ImGui.TextDisabled(ctx, 'not impulsive')
  end
  tip(string.format('Attacks hold %.0f%% of the energy in %.0f%% of the time (%.1fx denser).\n'
    .. 'Impulsive (impacts, hits, footsteps): at least 25%% of the energy, at least 4x denser.\n'
    .. 'Auto gives attack + body curves only when the reference and the destination are both '
    .. 'impulsive; speech, whooshes and ambiences get one whole-item curve.',
    share * 100, reference.stats.duty * 100, density))
end

local function draw_main()
  draw_toolbar()
  ImGui.SeparatorText(ctx, 'Reference')
  if reference then
    reference_link()
    draw_impulsiveness()
    small_note(analysis_line(reference.cfg, reference.sr))
  else
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.TextDisabled(ctx, 'None yet')
    small_note(analysis_line(cfg, current_sr()))
  end
  local avail_h = select(2, ImGui.GetContentRegionAvail(ctx))
  draw_spectrum(math.max(140, avail_h - 1))
end

local LABEL_W = 190

local function setting_label(text, help)
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx, text)
  tip(help)
  ImGui.SameLine(ctx, LABEL_W)
end

-- Applies one changed value through Core.settings (which validates it).
local function change(key, value)
  local t = { n = cfg.n, hop_ms = cfg.hop_ms, smooth = cfg.smooth, range = cfg.range,
    attack_ms = cfg.attack_ms, split = cfg.split }
  t[key] = value
  if key == 'attack_ms' and value == 0 then t.split = 'static' end
  local ok, new = pcall(Core.settings, t.n, t.hop_ms, t.smooth, t.range, t.attack_ms, t.split)
  if ok then save_cfg(new) else message(new) end
end

-- A number field that applies its value when editing ends (Enter, Tab, click
-- elsewhere), not at every keystroke: each change asks for a new reference analysis.
local edits = {}
local function number_field(key, fmt)
  ImGui.SetNextItemWidth(ctx, 110)
  local changed, v = ImGui.InputDouble(ctx, '##' .. key, edits[key] or cfg[key], 0, 0, fmt)
  if changed then edits[key] = v end
  if ImGui.IsItemDeactivatedAfterEdit(ctx) then
    local value = edits[key]
    edits[key] = nil
    if value and value ~= cfg[key] then change(key, value) end
  end
end

local SMOOTHING = { { 0, 'Off (every bin)' }, { 1/12, '1/12 octave' }, { 1/6, '1/6 octave' },
  { 1/3, '1/3 octave' }, { 1/2, '1/2 octave' }, { 1, '1 octave' } }
local SPLITS = {
  { 'auto', 'Auto', 'Attack + body when both items are impulsive (impacts, hits, footsteps); '
    .. 'one curve for speech, whooshes, ambiences.' },
  { 'static', 'One curve', 'One whole-item curve, whatever the material (no transient detection).' },
  { 'always', 'Attack + body', 'Always separate curves for attacks and the rest, when both items have transients.' },
}

local function draw_settings()
  ImGui.SeparatorText(ctx, 'Analysis')
  setting_label('FFT size', 'Analysis window. Longer: finer frequency detail, more time blur. '
    .. 'The EQ itself always uses a short minimum-phase filter.')
  ImGui.SetNextItemWidth(ctx, 220)
  if ImGui.BeginCombo(ctx, '##fft', string.format('%d (%.0f ms)', cfg.n, cfg.n / current_sr() * 1000)) then
    for _, n in ipairs({ 1024, 2048, 4096, 8192, 16384, 32768 }) do
      if ImGui.Selectable(ctx, string.format('%d (%.0f ms)', n, n / current_sr() * 1000), n == cfg.n) then change('n', n) end
    end
    ImGui.EndCombo(ctx)
  end
  setting_label('Hop (ms)', 'Distance between analysis frames (at most half the window).')
  number_field('hop_ms', '%.1f')

  ImGui.SeparatorText(ctx, 'Correction')
  setting_label('Smoothing', 'Width of the spectral envelope that is matched. 1/3 octave suits the '
    .. 'short filter; finer settings follow noise and resonances of one recording.')
  ImGui.SetNextItemWidth(ctx, 220)
  local current = string.format('%.3g octave', cfg.smooth)
  for _, s in ipairs(SMOOTHING) do if math.abs(s[1] - cfg.smooth) < 1e-9 then current = s[2] end end
  if ImGui.BeginCombo(ctx, '##smooth', current) then
    for _, s in ipairs(SMOOTHING) do
      if ImGui.Selectable(ctx, s[2], math.abs(s[1] - cfg.smooth) < 1e-9) then change('smooth', s[1]) end
    end
    ImGui.EndCombo(ctx)
  end
  setting_label('Max boost/cut (dB)', 'Limit of the correction at any frequency (0–48 dB).')
  number_field('range', '%.1f')

  ImGui.SeparatorText(ctx, 'Attack / body')
  setting_label('Split', 'Transients (a rise of 10 dB within a few ms) can get their own curve: '
    .. 'the attack of a hit often has a different timbre from its tail.')
  ImGui.SetNextItemWidth(ctx, 220)
  if ImGui.BeginCombo(ctx, '##split', SPLIT_LABEL[cfg.split]) then
    for _, s in ipairs(SPLITS) do
      if ImGui.Selectable(ctx, s[2], s[1] == cfg.split) then
        if s[1] ~= 'static' and cfg.attack_ms == 0 then change('attack_ms', DEFAULTS.attack_ms) end
        change('split', s[1])
      end
      tip(s[3])
    end
    ImGui.EndCombo(ctx)
  end
  for _, s in ipairs(SPLITS) do
    if s[1] == cfg.split then ImGui.SameLine(ctx); ImGui.TextDisabled(ctx, s[1] == 'auto' and 'impulsive items only' or '') end
  end
  setting_label('Attack hold (ms)', 'How long after each transient the attack curve applies.')
  ImGui.BeginDisabled(ctx, cfg.split == 'static')
  number_field('attack_ms', '%.0f')
  ImGui.EndDisabled(ctx)

  ImGui.SetCursorPosX(ctx, LABEL_W)
  if ImGui.SmallButton(ctx, 'Defaults') then save_cfg(default_cfg()) end
  ImGui.SeparatorText(ctx, 'Notes')
  ImGui.TextDisabled(ctx, 'Both items are read pre-FX; the EQ goes first in the destination take FX.')
  ImGui.TextDisabled(ctx, 'Changing a setting asks for the reference to be analyzed again.')
end

-- The gear at the right of the current line: settings in, settings out.
local function draw_gear()
  align_right(ImGui.GetFrameHeight(ctx))
  if icon_button('##settings', view == 'settings', paint_gear) then
    view = view ~= 'settings' and 'settings' or nil
  end
  tip(view == 'settings' and 'Close the settings and go back to the reference.' or 'Settings')
end

local STATUS_COL = { idle = COL_DIM, busy = COL_ACCENT, ok = COL_OK, warn = COL_WARN, err = COL_ERR }

-- Footer: the last thing that happened, small, and the gear.
local function draw_footer()
  local col = STATUS_COL[status.kind] or COL_DIM
  local full = ImGui.GetFrameHeight(ctx)
  if font then ImGui.PushFont(ctx, font, FOOTER_SIZE) end
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 6, 1)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local h = ImGui.GetFrameHeight(ctx)
  local line_y = y
  if full > h then
    y = y + math.floor((full - h) / 2)
    ImGui.SetCursorScreenPos(ctx, x, y)
  end
  ImGui.DrawList_AddCircleFilled(ImGui.GetWindowDrawList(ctx), x + 4, y + h / 2, 3, col)
  ImGui.Dummy(ctx, 8, h)
  ImGui.SameLine(ctx)
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.TextColored(ctx, col, status.text)
  ImGui.PopStyleVar(ctx)
  if font then ImGui.PopFont(ctx) end
  ImGui.SameLine(ctx)
  ImGui.SetCursorScreenPos(ctx, (ImGui.GetCursorScreenPos(ctx)), line_y)
  draw_gear()
end

local function footer_height()
  if font then ImGui.PushFont(ctx, font, FOOTER_SIZE) end
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 6, 1)
  local h = ImGui.GetFrameHeight(ctx)
  ImGui.PopStyleVar(ctx)
  if font then ImGui.PopFont(ctx) end
  return math.max(h, ImGui.GetFrameHeight(ctx)) + 2 * select(2, ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing))
end

------------------------------------------------------------------------------
-- Window.

local function frame()
  run_job()
  push_style()
  prepare_window('main', 820, 520)
  local fs_flags = prepare_fullscreen('main')
  ImGui.SetNextWindowSizeConstraints(ctx, 560, 360, 100000, 100000)
  local visible, open = ImGui.Begin(ctx, 'mtt_TimbreMatch', true,
    ImGui.WindowFlags_NoDocking | ImGui.WindowFlags_NoCollapse | fs_flags)
  if visible then
    remember_window('main')
    fullscreen_title_button('main')
    title_double_click('main')
    -- Escape closes the window while it has the focus, except while typing or dragging.
    if ImGui.IsWindowFocused(ctx, ImGui.FocusedFlags_RootAndChildWindows) and not ImGui.IsAnyItemActive(ctx)
      and ImGui.IsKeyPressed(ctx, ImGui.Key_Escape, false) then
      open = false
    end
    if ImGui.BeginChild(ctx, 'content', 0, -footer_height(), ImGui.ChildFlags_None) then
      if view == 'settings' then draw_settings() else draw_main() end
      ImGui.EndChild(ctx)
    end
    ImGui.Separator(ctx)
    draw_footer()
    ImGui.End(ctx)
  end
  pop_style()
  return open
end

-- A script error stops the script and writes where it happened to REAPER's console.
local function loop()
  local ok, open = xpcall(frame, debug.traceback)
  if not ok then
    R.ShowConsoleMsg('\nmtt_TimbreMatch stopped on an error:\n' .. tostring(open) .. '\n')
    stop_job()
    return
  end
  if open then R.defer(loop) else stop_job() end
end

R.atexit(stop_job)
-- Running the action with selected items starts capture immediately.
if R.CountSelectedMediaItems(0) > 0 then on_selected('reference') end
R.defer(loop)
