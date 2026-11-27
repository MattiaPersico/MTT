-- mtt_FmodSync.lua
-- Links a REAPER project to an FMOD Studio project: the assets rendered in
-- REAPER go to asset folders chosen in REAPER and are kept in sync with the FMOD
-- project through FMOD Studio's scripting terminal (TCP 3663).
--
-- The main view is the take table: one row per file to
-- render (the takes of every top-level folder track), its full file name
-- (renamed in the panel, wildcards allowed), its track, channels and how it
-- stands in FMOD (Linked, New, or a Link / Adopt button). Rows sort by header,
-- select with click / Shift / Cmd (the time selection follows), and the panel
-- under the table edits the render settings of the selected takes' assets.
-- The gear opens the settings (link, default name, render folder,
-- diagnostics), which save themselves on every change. FMOD Studio is found on
-- its own while it runs with "Enable Script Server" on.
-- Two actions: this script opens the window floating (full FMOD Sync),
-- mtt_FmodSync_Mini.lua opens it docked (FMOD Sync Mini). Docking or floating
-- the window switches between the two views.
-- 0.1: first release.

local major_version = 0
local minor_version = 1
local VERSION = major_version .. '.' .. minor_version

if not reaper.APIExists('ImGui_GetBuiltinPath') then
  reaper.MB('ReaImGui is required (ReaPack: ReaTeam Extensions).', 'Missing dependency', 0)
  return
end
package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'

local script_path = debug.getinfo(1, 'S').source:match[[^@?(.*[\/])[^\/]-$]]
local SOCKET_EXT = reaper.GetOS():find('Win') and 'dll' or 'so'
package.cpath = package.cpath .. ';' .. script_path .. 'socket module/?.' .. SOCKET_EXT
local socket_core = require('socket.core')

local json = dofile(script_path .. 'dkjson.lua')
local link = dofile(script_path .. 'mtt_fmodsync_link.lua')
local config = dofile(script_path .. 'mtt_fmodsync_config.lua')
local assets_mod = dofile(script_path .. 'mtt_fmodsync_assets.lua')
local render = dofile(script_path .. 'mtt_fmodsync_render.lua')
link.init(socket_core)

-- One window, two views. Docked in a REAPER docker it is FMOD Sync Mini: the
-- takes of the tracks selected in REAPER, laid out in width, in the colours of
-- the REAPER theme. Floating it is the full window. MINI follows the dock: the
-- dock is known only inside the window (after Begin), so the style of a frame
-- comes from the dock of the frame before.
-- The two actions open the same window: this script floating (full),
-- mtt_FmodSync_Mini.lua (which sets MTT_FMODSYNC_MINI) docked. When the window
-- is already open, the other action only docks or undocks it.
local EXT = 'mtt_FmodSync'
-- The view's state, in one table (the main chunk is near Lua's 200 locals).
local V = { open_docked = MTT_FMODSYNC_MINI == true }
MTT_FMODSYNC_MINI = nil
do
  local alive = tonumber(reaper.GetExtState(EXT, 'alive'))
  if alive and math.abs(reaper.time_precise() - alive) < 2 then
    reaper.SetExtState(EXT, 'request', V.open_docked and 'dock' or 'undock', false)
    return
  end
  reaper.DeleteExtState(EXT, 'request', false) -- left by a window that has since closed
end
local MINI = reaper.GetExtState(EXT, 'docked') == '1'
local ctx = ImGui.CreateContext('mtt_FmodSync', ImGui.ConfigFlags_DockingEnable)

------------------------------------------------------------------------------
-- Look: the palette, rounding and font of mtt_MetadataAssistant.

local COL_ERR = 0xFF6464FF
local COL_WARN = 0xE6B43CFF
local COL_OK = 0x78D278FF
local COL_DIM = 0x9A9A9AFF
local COL_ACCENT = 0xE89B3CFF
local COL_SELECTED = 0x9A6322FF
local COL_SELECTED_HOVER = 0xAE7229FF
local COL_SELECTED_ACTIVE = 0x84541AFF
local COL_BUTTON = 0x303435FF
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
local function style_vars()
  return {
  -- No rounded corners anywhere, as mtt_Shelf next to it in the docker.
  { ImGui.StyleVar_WindowRounding, 0 }, { ImGui.StyleVar_ChildRounding, 0 },
  { ImGui.StyleVar_PopupRounding, 0 }, { ImGui.StyleVar_ScrollbarRounding, 0 },
  { ImGui.StyleVar_GrabRounding, 0 }, { ImGui.StyleVar_FrameRounding, 0 },
  { ImGui.StyleVar_WindowPadding, MINI and 10 or 16, MINI and 8 or 14 },
  { ImGui.StyleVar_ItemSpacing, ITEM_SPACING_X, MINI and 5 or 7 },
  { ImGui.StyleVar_FramePadding, FRAME_PAD_X, MINI and 3 or 5 },
  }
end

-- Font size of each view; `font` is the one of the current frame.
V.font_sizes = { full = 15, mini = 13 }
V.fonts = {}
for view, size in pairs(V.font_sizes) do
  local ok, f = pcall(function()
    local f = ImGui.CreateFont('sans-serif', size)
    ImGui.Attach(ctx, f)
    return f
  end)
  V.fonts[view] = ok and f or nil
end
local font = V.fonts.full

-- Mini sits in REAPER's docker: its colours come from the REAPER theme's
-- background (col_main_bg, as mtt_Shelf does), frames and buttons a little
-- lighter (darker on a light theme). Read every frame: the theme may change.
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
    { ImGui.Col_TableBorderLight, shade(24) }, { ImGui.Col_TableRowBg, 0 }, { ImGui.Col_TableRowBgAlt, shade(8, 0x80) },
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
  local view = MINI and 'mini' or 'full'
  font = V.fonts[view]
  V.pushed_font = font
  if font then ImGui.PushFont(ctx, font, V.font_sizes[view]) end
  for _, pair in ipairs(palette) do ImGui.PushStyleColor(ctx, pair[1], pair[2]) end
  pushed_theme = 0
  if MINI then
    local theme = theme_palette()
    for _, pair in ipairs(theme) do ImGui.PushStyleColor(ctx, pair[1], pair[2]) end
    pushed_theme = #theme
  end
  local vars = style_vars()
  for _, v in ipairs(vars) do
    if v[3] then ImGui.PushStyleVar(ctx, v[1], v[2], v[3]) else ImGui.PushStyleVar(ctx, v[1], v[2]) end
  end
  V.pushed_vars = #vars
end

local function pop_style()
  ImGui.PopStyleVar(ctx, V.pushed_vars)
  ImGui.PopStyleColor(ctx, #palette + pushed_theme)
  if V.pushed_font then ImGui.PopFont(ctx) end
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

-- A square icon button one frame tall (as in mtt_MetadataAssistant).
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

-- Six-tooth gear in a 1 px outline (mtt_MetadataAssistant's icon).
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
-- Window placement and full screen (as in mtt_MetadataAssistant).

-- Recover each window on its first opening in this run, before Begin restores
-- a saved off-screen position or dock. Later frames leave moves/resizes alone.
-- Keep all geometry in ReaImGui coordinates, including on Retina displays.
-- The window's place from the last run: ExtState "x,y,w,h,fs" (fs = 1 when
-- it was full screen; x, y, w, h are then where it goes back to).
local function saved_geometry(key)
  local v = reaper.GetExtState(EXT, 'window_' .. key)
  local x, y, w, h, fs = v:match('^(%-?%d+),(%-?%d+),(%d+),(%d+),(%d)$')
  if not x then return nil end
  return { tonumber(x), tonumber(y), tonumber(w), tonumber(h), fs = fs == '1' }
end

-- True when the centre of g lies on a screen (a screen may be gone since).
local function on_screen(g)
  local cx, cy = g[1] + g[3] / 2, g[2] + g[4] / 2
  local nx, ny = ImGui.PointConvertNative(ctx, cx, cy, true)
  nx, ny = math.floor(nx), math.floor(ny)
  local l, t, r, b = reaper.my_getViewport(0, 0, 0, 0, nx, ny, nx + 1, ny + 1, true)
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

-- The current window's rectangle {x1, y1, x2, y2} in ReaImGui coordinates.
local function window_rect()
  local x, y = ImGui.GetWindowPos(ctx)
  local w, h = ImGui.GetWindowSize(ctx)
  return { x, y, x + w, y + h }
end

-- Full screen: the window covers the work area (no menu bar, Dock or taskbar)
-- of the screen that holds most of it, and cannot be moved, resized or
-- collapsed. The icon left of the title bar's close button enters and leaves
-- it; leaving puts the window back where and as large as it was. Per run only.
local fullscreen = {}      -- key -> { back = {x, y, w, h}, screen = {x, y, w, h} }
local fullscreen_back = {} -- key -> the geometry to put back on the next frame

-- Work area of the screen holding most of the current window (call between
-- Begin and End), in ReaImGui coordinates; nil when REAPER gives nothing usable.
-- my_getViewport takes and returns native coordinates (macOS: origin at the
-- bottom left, y up; Windows: physical pixels): each corner is converted on its
-- own and the results sorted, so the orientation does not matter.
local function window_screen()
  local x, y = ImGui.GetWindowPos(ctx)
  local w, h = ImGui.GetWindowSize(ctx)
  local ax, ay = ImGui.PointConvertNative(ctx, x, y, true)
  local bx, by = ImGui.PointConvertNative(ctx, x + w, y + h, true)
  local l, t, r, b = reaper.my_getViewport(0, 0, 0, 0,
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


-- Right after Begin (window visible): enters full screen when the last run
-- ended in it, and remembers the window's place (while no mouse button is down,
-- so not at every step of a drag). Full screen remembers where it goes back to.
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
    reaper.SetExtState(EXT, 'window_' .. key, v, true)
  end
end

-- Right after Begin (window visible): the full screen icon in the title bar, left
-- of the close button. Placed and sized as ReaImGui's Dear ImGui (cfillion/imgui,
-- RenderWindowTitleBarContents + CloseButton) does its close button: FramePadding
-- from the right edge, a square one font size wide, ItemInnerSpacing between the
-- two, lowered by half of (line height - font size), drawn around the square's
-- centre minus half a pixel, as far out as the cross's arms.
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
  -- The title bar lies outside the content's clip rectangle: open it for this button only.
  ImGui.PushClipRect(ctx, wx, wy, wx + ww, wy + line_h + 2 * pad_y, false) -- the title bar
  ImGui.SetCursorScreenPos(ctx, bx, by)
  local clicked = ImGui.InvisibleButton(ctx, '##fullscreen', sz, sz)
  local hovered, held = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
  local dl = ImGui.GetWindowDrawList(ctx)
  if hovered then
    ImGui.DrawList_AddRectFilled(dl, bx, by, bx + sz, by + sz,
      ImGui.GetColor(ctx, held and ImGui.Col_ButtonActive or ImGui.Col_ButtonHovered))
  end
  -- Four corner brackets: corners outside = enter full screen, corners near the centre = leave.
  local col = ImGui.GetColor(ctx, ImGui.Col_Text)
  local cx, cy = bx + sz / 2 - 0.5, by + sz / 2 - 0.5
  local outer = sz * 0.5 * 0.7071 - 1 -- the close button's cross_extent
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
  ImGui.SetCursorPos(ctx, cur_x, cur_y) -- the content starts where it would have
  if clicked then toggle_fullscreen(key) end
end

-- Dock / undock icons: a window outline with its lower part filled (dock it in
-- REAPER's docker) or a small window lifted out of a bigger one (float it).
function V.paint_dock(dl, x, y, h, col)
  local m = math.floor(h * 0.25)
  local x1, y1, x2, y2 = x + m + 0.5, y + m + 0.5, x + h - m - 0.5, y + h - m - 0.5
  ImGui.DrawList_AddRect(dl, x1, y1, x2, y2, col, 0, 0, 1)
  ImGui.DrawList_AddRectFilled(dl, x1, y2 - math.floor((y2 - y1) * 0.4), x2, y2, col)
end

function V.paint_undock(dl, x, y, h, col)
  local m = math.floor(h * 0.25)
  local x1, y1, x2, y2 = x + m + 0.5, y + m + 0.5, x + h - m - 0.5, y + h - m - 0.5
  local d = math.floor((x2 - x1) * 0.4)
  ImGui.DrawList_AddRect(dl, x1, y1 + d, x2 - d, y2, col, 0, 0, 1)
  ImGui.DrawList_AddRectFilled(dl, x1 + d, y1, x2, y2 - d, ImGui.GetColor(ctx, ImGui.Col_WindowBg))
  ImGui.DrawList_AddRect(dl, x1 + d, y1, x2, y2 - d, col, 0, 0, 1)
end

-- V.dock_request: 'dock' / 'undock' for the next Begin (button, or the other action).

-- Right after Begin (floating window): the dock icon in the title bar, left of
-- the full screen icon (same size and spacing as it and the close button).
function V.dock_title_button()
  if fullscreen.main then return end
  local wx, wy = ImGui.GetWindowPos(ctx)
  local ww = ImGui.GetWindowSize(ctx)
  local pad_x, pad_y = ImGui.GetStyleVar(ctx, ImGui.StyleVar_FramePadding)
  local inner_x = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemInnerSpacing)
  local sz = ImGui.GetFontSize(ctx)
  local line_h = ImGui.GetTextLineHeight(ctx)
  local bx = wx + ww - pad_x - 3 * sz - 2 * inner_x
  local by = wy + pad_y + (line_h - sz) * 0.5
  local cur_x, cur_y = ImGui.GetCursorPos(ctx)
  ImGui.PushClipRect(ctx, wx, wy, wx + ww, wy + line_h + 2 * pad_y, false) -- the title bar
  ImGui.SetCursorScreenPos(ctx, bx, by)
  local clicked = ImGui.InvisibleButton(ctx, '##dock', sz, sz)
  local hovered, held = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
  local dl = ImGui.GetWindowDrawList(ctx)
  if hovered then
    ImGui.DrawList_AddRectFilled(dl, bx, by, bx + sz, by + sz,
      ImGui.GetColor(ctx, held and ImGui.Col_ButtonActive or ImGui.Col_ButtonHovered))
  end
  V.paint_dock(dl, math.floor(bx), math.floor(by), sz, ImGui.GetColor(ctx, ImGui.Col_Text))
  ImGui.PopClipRect(ctx)
  tip('Dock in REAPER\'s docker: FMOD Sync Mini, the takes of the tracks selected in REAPER.')
  ImGui.SetCursorPos(ctx, cur_x, cur_y)
  if clicked then V.dock_request = 'dock' end
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
  local icons_x = wx + ww - pad_x - 3 * sz - 2 * inner_x -- the dock and full screen icons, the close cross
  local title_h = ImGui.GetTextLineHeight(ctx) + 2 * pad_y
  if my >= wy and my < wy + title_h and mx >= wx and mx < icons_x then toggle_fullscreen(key) end
end

------------------------------------------------------------------------------
-- State and logic.

-- JavaScript bodies sent to FMOD Studio (see link.wrap: no // comments).
local JS_PROJECT = [[return { filePath: studio.project.filePath, filepath: studio.project.filepath };]]
-- Only the audio files that can matter to this RPP come back: those whose base
-- name (lowercase, no extension) is one of `keys` or ends with "_" + one of them.
-- The whole list would be printed in FMOD's console at every refresh.
local function js_audio_files(keys)
  return 'var keys = ' .. json.encode(keys) .. ';'
    .. ' var a = studio.project.model.AudioFile.findInstances(); var out = [], chs = [];'
    .. ' for (var i = 0; i < a.length; i++) { var p = a[i].getAssetPath();'
    .. ' var b = p.substring(p.lastIndexOf("/") + 1); var d = b.lastIndexOf(".");'
    .. ' if (d > 0) { b = b.substring(0, d); } b = b.toLowerCase();'
    .. ' var hit = keys[b] === true; var u = b.indexOf("_");'
    .. ' while (!hit && u >= 0) { hit = keys[b.substring(u + 1)] === true; u = b.indexOf("_", u + 1); }'
    .. ' if (hit) { out.push(p); var c = -1; try { c = a[i].channelCount; } catch (e) {} chs.push(c); } }'
    .. ' return { n: a.length, paths: out, chs: chs };'
end

-- FMOD keeps each asset folder as an EncodableAsset with assetPath "a/b/"
-- (Metadata/Asset/*.xml); a folder made on disk by setAssetPath has none and
-- shows #unimported. A script cannot make one: studio.project.create gives an
-- EncodableAsset whose assetPath ignores setValue, and getAsset finds nothing
-- (tried 2026-11-20); setAssetPath on a new one would move the whole Assets
-- folder (its getAbsoluteAssetPath is the Assets folder). The user imports it (Import Contents); the script never
-- writes FMOD's files or does source control work.

local RECONNECT_EVERY = 3 -- seconds between attempts while FMOD Studio is not reachable

local query_audio_files -- defined with refresh_fmod
local sync_rendered -- defined before render_rows
local is_rendered -- defined with the status cell

local S = {
  proj = nil,               -- the REAPER project shown
  rpp = '',                 -- its file path ('' = never saved)
  cfg = nil,                -- its config (config.load)
  cfg_err = nil,
  fmod_open = nil,          -- path of the .fspro open in FMOD Studio (when online)
  fmod_err = nil,
  audio_files = nil,        -- asset paths imported in FMOD (when online)
  fmod_idx = assets_mod.index_fmod({}),
  next_connect = 0,         -- time of the next connection attempt
  view = nil,               -- nil = assets, 'settings'
  assets = {},              -- assets_mod.scan of the project
  state_count = -1,         -- project state change count at the last scan
  filter = '',              -- table filter
  folders = {},             -- every asset folder of the linked project (rel paths)
  sel = {},                 -- selected takes: key -> true
  anchor = nil,             -- take a Shift click selects from
  order = {},               -- rows in the order shown (for Shift clicks)
  sort = nil,               -- { col, asc } from the table header
  pick_keys = nil,          -- takes whose FMOD folder is being chosen
  pick_filter = '',
}

-- dkjson writes an empty table as []: these must stay JSON objects.
local OBJECT = { __jsontype = 'object' }
local function obj(t) return setmetatable(t or {}, OBJECT) end

local function project_info(key)
  local _, t = reaper.GetSetProjectInfo_String(S.proj or 0, key, '', false)
  return t or ''
end

-- The REAPER project's sample rate (the audio device's when the project sets none).
local function project_srate()
  local sr = 0
  if reaper.GetSetProjectInfo(S.proj or 0, 'PROJECT_SRATE_USE', 0, false) == 1 then
    sr = reaper.GetSetProjectInfo(S.proj or 0, 'PROJECT_SRATE', 0, false)
  end
  if not sr or sr <= 0 then
    local ok, v = reaper.GetAudioDeviceInfo('SRATE')
    sr = ok and tonumber(v) or 48000
  end
  return math.floor(sr + 0.5)
end

-- Two runs of this script may be open on one project (another REAPER window,
-- or a run started before the window was one): each save leaves a mark in
-- ExtState (not kept on disk) that tells the other to read the config again (loop).
local INSTANCE = 'win' .. tostring(reaper.time_precise())
local function save_cfg()
  if not S.cfg then return end
  local ok, err = config.save(json, S.rpp, S.cfg)
  if not ok then S.cfg_err = 'Cannot save the settings: ' .. tostring(err); return end
  S.cfg_mark = S.rpp .. '|' .. INSTANCE .. '|' .. tostring(reaper.time_precise())
  reaper.SetExtState(EXT, 'cfg_saved', S.cfg_mark, false)
end

local function asset_cfg(guid)
  S.cfg.assets[guid] = S.cfg.assets[guid] or obj()
  return S.cfg.assets[guid]
end

local function take_cfg(key)
  S.cfg.takes[key] = S.cfg.takes[key] or obj()
  return S.cfg.takes[key]
end

-- Drops what a take no longer overrides, so the file stays readable.
local function prune_take(key)
  local t = S.cfg.takes[key]
  if t and next(t) == nil then S.cfg.takes[key] = nil end
end

-- The assets of these rows, each once.
local function assets_of(rows)
  local out, seen = {}, {}
  for _, r in ipairs(rows) do
    if not seen[r.asset] then seen[r.asset] = true; out[#out + 1] = r.asset end
  end
  return out
end

-- The project's name template: the setting, or the old prefix setting, or the default.
local function default_template()
  if S.cfg.name_template and S.cfg.name_template ~= '' then return S.cfg.name_template end
  if S.cfg.prefix and S.cfg.prefix ~= '' then return S.cfg.prefix .. '_$track_$index' end
  return assets_mod.DEFAULT_TEMPLATE
end

-- A take's template with no name of its own: the base its asset adopted, else the project's.
local function asset_template(a)
  local acfg = S.cfg.assets[a.guid]
  if acfg and acfg.base and acfg.base ~= '' then return acfg.base .. '_$index' end
  return default_template()
end

-- Takes of one line: takes marked together in the panel ("Same line",
-- takes[key].group, 2 or more in the asset) get "_01", "_02"... in time order
-- after their name. In an asset with such a line, $index counts lines in time
-- order: the line is one (its takes share it), any other take one each, so
-- the take after House_02_01.._02_04 is House_03. Other assets keep the take
-- number. Returns { [block key] = take number in its line }, { [block key] =
-- $index } (empty when the asset has no line).
local function take_numbers(a)
  local blocks = {}
  for i, b in ipairs(a.blocks) do blocks[i] = b end
  table.sort(blocks, function(x, y) return (x[1] or 0) < (y[1] or 0) end)
  local size = {}
  for _, b in ipairs(blocks) do
    local t = S.cfg.takes[b.key]
    if t and t.group then size[t.group] = (size[t.group] or 0) + 1 end
  end
  local grp, any = {}, false
  for _, b in ipairs(blocks) do
    local t = S.cfg.takes[b.key]
    -- A line of one take left (the others deleted) is a plain take.
    if t and t.group and size[t.group] >= 2 then grp[b.key] = t.group; any = true end
  end
  local count, out, line, first, n = {}, {}, {}, {}, 0
  for _, b in ipairs(blocks) do
    local g = grp[b.key]
    if g then
      count[g] = (count[g] or 0) + 1
      out[b.key] = count[g]
    end
    if any then
      if g then
        if not first[g] then n = n + 1; first[g] = n end
        line[b.key] = first[g]
      else
        n = n + 1
        line[b.key] = n
      end
    end
  end
  return out, line
end

-- The first number of $index and of a line's "_NN": 1, or 0 with Settings >
-- Numbering (cfg.index_start = 0). Takes are counted from 1 inside the
-- script (block.index, line numbers); only names are written from 0.
local function index_start() return (S.cfg and S.cfg.index_start == 0) and 0 or 1 end
local function index_number(n) return (n or 1) - 1 + index_start() end
local function index_text(n) return string.format('%02d', index_number(n)) end

-- A take's file name: its template expanded, and "_NN" after it for a take of a line.
local function take_name(template, vars, n)
  local name, unknown = assets_mod.expand(template, vars)
  if n then name = name .. '_' .. index_text(n) end
  return name, unknown
end

local function rescan_assets()
  local gap = (S.cfg and S.cfg.block_gap) or 0
  S.assets = assets_mod.scan(S.proj or 0, gap, index_start())
  S.state_count = reaper.GetProjectStateChangeCount(S.proj or 0)
end

local function fspro_name() return S.cfg and S.cfg.fmod_project end
local function fspro_path() return config.user_fspro_path(fspro_name()) end

-- The asset folders of the linked project, read from its Assets folder on disk.
local function load_folders()
  S.folders = {}
  local p = fspro_path()
  if not p then return end
  local tree = config.scan_asset_folders(p)
  local function flat(node)
    if node.rel ~= '' then S.folders[#S.folders + 1] = node.rel end
    for _, c in ipairs(node.children) do flat(c) end
  end
  if tree then flat(tree) end
  -- Folders made in the picker that FMOD does not have yet.
  local have = {}
  for _, r in ipairs(S.folders) do have[r] = true end
  for rel in pairs(S.extra_folders or {}) do
    if not have[rel] then S.folders[#S.folders + 1] = rel end
  end
  table.sort(S.folders, function(x, y) return x:lower() < y:lower() end)
  S.children_of = nil
end

-- Re-reads everything that depends on the active REAPER project.
local function load_project(proj, rpp)
  S.proj, S.rpp = proj, rpp
  S.cfg, S.cfg_err = config.load(json, rpp)
  S.sel, S.anchor = {}, nil
  if S.cfg then
    -- Keys are GUIDs: objects even when empty or after a load of [].
    for _, field in ipairs({ 'assets', 'takes' }) do
      local t = obj()
      for k, v in pairs(S.cfg[field] or {}) do
        if type(k) == 'string' and type(v) == 'table' then
          t[k] = obj(v)
          -- Ch per take, before every setting could be: now in render.
          if field == 'takes' and type(v.channels) == 'number' then
            if type(v.render) ~= 'table' then v.render = {} end
            v.render.channels = v.channels
          end
          v.channels = nil
          if type(v.render) == 'table' then
            obj(v.render)
            -- The first version's captured normalization: now a LUFS value.
            -- (A take's false = off, over its track's.)
            local off = v.render.normalize == false
            if type(v.render.normalize) ~= 'number' and not off then v.render.normalize = nil end
            if next(v.render) == nil then v.render = nil end
          end
          v.override = nil -- the first version's overrides: replaced by render
        end
      end
      S.cfg[field] = t
    end
    -- The old project-wide render folder.
    if not S.cfg.render_dir and type(S.cfg.render) == 'table' then S.cfg.render_dir = S.cfg.render.dir end
    S.cfg.render = nil
    -- The project's render defaults (Settings): only values that differ from
    -- the built-in ones.
    if type(S.cfg.render_defaults) == 'table' then
      local d = obj()
      for _, k in ipairs(render.KEYS) do
        local v = S.cfg.render_defaults[k]
        if v ~= nil and v ~= false or (k == 'second_pass' and v == true) then d[k] = v end
      end
      S.cfg.render_defaults = next(d) and d or nil
    else
      S.cfg.render_defaults = nil
    end
  end
  load_folders()
  rescan_assets()
end

local function same_path(a, b)
  if not a or not b then return false end
  local function norm(p) return (p:gsub('\\', '/')):lower() end
  return norm(a) == norm(b)
end

-- Asks FMOD Studio for the audio files that match the takes' names
-- (S.wanted_keys, set by build_rows).
query_audio_files = function()
  if not S.wanted_keys or link.status ~= 'online' then return end
  link.request(js_audio_files(S.wanted_keys), function(v, err)
    if err then S.fmod_err = err; return end
    S.fmod_err = nil
    S.audio_files = v.paths or {}
    S.audio_total = v.n
    -- Channel count of each file (FMOD's AudioFile.channelCount; -1 = unknown).
    S.audio_ch = {}
    for i, p in ipairs(S.audio_files) do
      local c = type(v.chs) == 'table' and tonumber(v.chs[i])
      if c and c > 0 then S.audio_ch[p] = c end
    end
    S.fmod_idx = assets_mod.index_fmod(S.audio_files)
  end)
end

-- Asks FMOD Studio which project it has open and which audio files it holds.
local function refresh_fmod()
  S.fmod_err = nil
  link.request(JS_PROJECT, function(v, err)
    if err then S.fmod_err = err; return end
    S.fmod_err = nil
    S.fmod_open = v.filePath or v.filepath
    -- The user's copy of the linked project is wherever FMOD has it open.
    local name = fspro_name()
    if name and S.fmod_open and config.basename(S.fmod_open) == name
      and not same_path(S.fmod_open, fspro_path()) then
      config.set_user_fspro_path(name, S.fmod_open)
      load_folders()
    end
  end)
  query_audio_files()
end

-- While offline, tries again every RECONNECT_EVERY seconds. A refused
-- connection on localhost returns at once, so this does not stall the UI.
local function keep_connected()
  if link.status == 'online' then return end
  local now = reaper.time_precise()
  if now < S.next_connect then return end
  S.next_connect = now + RECONNECT_EVERY
  S.fmod_open = nil
  if link.connect() then refresh_fmod() end
end

local function link_to_open_project()
  if not S.cfg or not S.fmod_open then return end
  local name = config.basename(S.fmod_open)
  S.cfg.fmod_project = name
  config.set_user_fspro_path(name, S.fmod_open)
  save_cfg()
  load_folders()
  -- Asked once, when the project is linked: see draw_legacy_question.
  if S.cfg.legacy == nil then S.legacy_open = true end
end

local function fmod_has_linked_project()
  return S.fmod_open ~= nil and config.basename(S.fmod_open) == fspro_name()
end

-- Filter: every word typed must be somewhere in the text, case and spaces,
-- "_", "-" and "/" ignored ("train door close" finds "TrainDoorClose_01"). Pure.
local function filter_words(filter)
  local words = {}
  for w in filter:lower():gmatch('[^%s_%-/]+') do words[#words + 1] = w end
  return words
end

local function filter_match(words, ...)
  if #words == 0 then return true end
  local text = table.concat({ ... }, ' '):lower():gsub('[%s_%-/]+', '')
  for _, w in ipairs(words) do
    if not text:find(w, 1, true) then return false end
  end
  return true
end

local function folder_label(folder)
  if folder == nil then return nil end
  return folder == '' and '(Assets root)' or folder
end

------------------------------------------------------------------------------
-- Rows: one per take, that is one per file to render.

-- Builds every row with its file name, folder, settings and FMOD status.
local function build_rows()
  local rows, by_key, names = {}, {}, {}
  local similar_n = 0
  local rpp_name = config.basename(S.rpp):gsub('%.[Rr][Pp][Pp]$', '')
  local vars = { project = rpp_name, title = project_info('PROJECT_TITLE'), author = project_info('PROJECT_AUTHOR') }
  local dirty = false
  -- The FMOD file each take was last linked to. A take whose new name is
  -- another take's file (numbers shifted by Settings > Numbering, a take
  -- renumbered) is not linked to it: that file is the other take's.
  local claimed = {}
  for _, a in ipairs(S.assets) do
    for _, b in ipairs(a.blocks) do
      local t = S.cfg.takes[b.key]
      if t and type(t.linked) == 'string' then claimed[t.linked:lower()] = b.key end
    end
  end
  for ai, a in ipairs(S.assets) do
    local acfg = S.cfg.assets[a.guid]
    -- Takes of a line ("Same line"): their number in it.
    local takes_n, line_n = take_numbers(a)
    for _, b in ipairs(a.blocks) do
      local tcfg = S.cfg.takes[b.key]
      local template = (tcfg and tcfg.name) or asset_template(a)
      vars.track, vars.item, vars.index = a.name, b.label or '', index_text(line_n[b.key] or b.index)
      local name, unknown = take_name(template, vars, takes_n[b.key])
      local folder
      if tcfg and tcfg.folder ~= nil then folder = tcfg.folder or nil else folder = acfg and acfg.folder end
      -- The take's own render settings win over its asset's (track's).
      local settings = render.resolve(acfg and acfg.render, project_srate(), tcfg and tcfg.render, S.cfg.render_defaults)
      local own_render = tcfg ~= nil and tcfg.render ~= nil
      local row = {
        key = b.key, asset = a, block = b, index = b.index, order = ai * 100000 + b.index,
        template = template, own_name = tcfg and tcfg.name ~= nil, name = name, unknown = unknown,
        folder = folder, no_folder = tcfg ~= nil and tcfg.folder == false, settings = settings, overridden = (acfg ~= nil and acfg.render ~= nil) or own_render, own_render = own_render,
        ch = render.channels(a, settings),
      }
      row.st = assets_mod.status(name, folder, a.name, index_number(b.index), S.fmod_idx)
      -- A file under another name with another channel count is another sound.
      if row.st.kind == 'similar' then
        local fch = S.audio_ch and S.audio_ch[row.st.path]
        if fch and fch ~= row.ch then row.st = { kind = 'none' }
        -- Answered "not the same" for this file: not asked again.
        elseif tcfg and tcfg.not_similar == row.st.path then row.st = { kind = 'none' }
        -- Only a project rendered to FMOD before FMOD Sync has files under
        -- other names to adopt (cfg.legacy, asked when the project is linked).
        else
          similar_n = similar_n + 1
          if S.cfg.legacy ~= true then row.st = { kind = 'none' } end
        end
      end
      -- The FMOD file this take was last linked to: remembered, so that a
      -- rename or a new folder here shows as a mismatch with it (fixed in FMOD by the row's button).
      local linked = tcfg and tcfg.linked
      local owner = row.st.kind == 'linked' and claimed[row.st.path:lower()]
      if owner and owner ~= b.key then row.st = { kind = 'new' } end
      if row.st.kind == 'linked' then
        if linked ~= row.st.path then take_cfg(b.key).linked = row.st.path; dirty = true end
      elseif linked and S.audio_files then
        local ldir, lbase = assets_mod.split_asset_path(linked)
        local still = S.fmod_idx.by_dir[ldir] and S.fmod_idx.by_dir[ldir][lbase:lower()] == linked
        -- Renamed or given another folder here, the file still where it was.
        local moved = folder ~= nil and folder ~= ldir
        local renamed = lbase:lower() ~= name:lower()
        if still and (moved or renamed) and folder ~= nil then
          row.st = { kind = 'renamed', path = linked, dir = ldir, old = lbase, moved = moved, renamed = renamed }
        end
      end
      rows[#rows + 1] = row
      by_key[b.key] = row
      local k = name:lower()
      names[k] = (names[k] or 0) + 1
    end
  end
  for _, r in ipairs(rows) do r.dup = names[r.name:lower()] > 1 end
  S.similar_n = similar_n
  if dirty then save_cfg() end
  -- The names to ask FMOD about: each take's, its "<track>_<NN>" and the base
  -- name it was last linked to. Asked again when they change.
  local keys, list = {}, {}
  local function want(k)
    k = k:lower()
    if k ~= '' and not keys[k] then keys[k] = true; list[#list + 1] = k end
  end
  for _, r in ipairs(rows) do
    want(r.name)
    want((r.asset.name or '') .. '_' .. index_text(r.index))
    local tcfg = S.cfg.takes[r.key]
    if tcfg and tcfg.linked then want(select(2, assets_mod.split_asset_path(tcfg.linked))) end
  end
  table.sort(list)
  local sig = table.concat(list, '\0')
  if sig ~= S.wanted_sig then
    S.wanted_sig, S.wanted_keys = sig, keys
    query_audio_files()
  end
  return rows, by_key
end

local STATUS_RANK = { linked = 1, renamed = 2, new = 3, found = 4, similar = 5, ambiguous = 6, none = 7 }

local function sort_rows(rows)
  local sort = S.sort
  local function key(r)
    if not sort then return r.order end
    if sort.col == 1 then return r.name:lower() end
    if sort.col == 3 then return r.ch end
    return STATUS_RANK[r.st.kind] or 9
  end
  table.sort(rows, function(a, b)
    local ka, kb = key(a), key(b)
    if ka == kb then return a.order < b.order end
    if sort and not sort.asc then return ka > kb end
    return ka < kb
  end)
end

-- The selected rows, in the order shown.
local function selected_rows()
  local out = {}
  for _, r in ipairs(S.order) do if S.sel[r.key] then out[#out + 1] = r end end
  return out
end

-- The time selection follows the selected takes.
local function select_time(rows)
  local s, e
  for _, r in ipairs(rows) do
    if not s or r.block[1] < s then s = r.block[1] end
    if not e or r.block[2] > e then e = r.block[2] end
  end
  if s then reaper.GetSet_LoopTimeRange2(S.proj or 0, true, false, s, e, false) end
end

local function click_row(row)
  local mods = ImGui.GetKeyMods(ctx)
  if mods & ImGui.Mod_Shift ~= 0 and S.anchor then
    local from, to
    for i, r in ipairs(S.order) do
      if r.key == S.anchor then from = i end
      if r.key == row.key then to = i end
    end
    if from and to then
      if from > to then from, to = to, from end
      if mods & (ImGui.Mod_Ctrl | ImGui.Mod_Super) == 0 then S.sel = {} end
      for i = from, to do S.sel[S.order[i].key] = true end
    end
  elseif mods & (ImGui.Mod_Ctrl | ImGui.Mod_Super) ~= 0 then
    S.sel[row.key] = not S.sel[row.key] or nil
    S.anchor = row.key
  else
    S.sel = { [row.key] = true }
    S.anchor = row.key
  end
  select_time(selected_rows())
  -- The edit cursor goes to the start of the take clicked.
  reaper.SetEditCurPos2(S.proj or 0, row.block[1], true, false)
end

-- Sets the FMOD folder of these takes. The asset keeps it as the folder of
-- its takes to come when it has none yet; a take with the asset's folder keeps no copy.
local function set_folder(rows, folder)
  for _, r in ipairs(rows) do
    local acfg = asset_cfg(r.asset.guid)
    if acfg.folder == nil and folder ~= nil then acfg.folder = folder end
    local t = take_cfg(r.key)
    if folder == acfg.folder then t.folder = nil
    elseif folder == nil then t.folder = false
    else t.folder = folder end
    prune_take(r.key)
  end
  save_cfg()
end

-- Empty = the project's default name. An asset whose name came from an old
-- adoption (assets[guid].base) loses it for these takes; its other takes keep
-- that name as their own.
local function set_name(rows, template)
  template = (template or ''):gsub('^%s+', ''):gsub('%s+$', '')
  local chosen = {}
  for _, r in ipairs(rows) do chosen[r.key] = true end
  for _, a in ipairs(assets_of(rows)) do
    local acfg = S.cfg.assets[a.guid]
    if acfg and acfg.base then
      local old = acfg.base .. '_$index'
      for _, b in ipairs(a.blocks) do
        if not chosen[b.key] and not (S.cfg.takes[b.key] and S.cfg.takes[b.key].name) then
          take_cfg(b.key).name = old
        end
      end
      acfg.base = nil
    end
  end
  for _, r in ipairs(rows) do
    local t = take_cfg(r.key)
    if template == '' or template == default_template() then t.name = nil else t.name = template end
    prune_take(r.key)
  end
  save_cfg()
end

-- Marks the takes as one line of several takes (on = true), per asset, or
-- takes them out of their line.
local function set_same_line(rows, on)
  local id = string.format('%x', math.floor(reaper.time_precise() * 1000))
  for _, r in ipairs(rows) do
    local t = take_cfg(r.key)
    t.group = on and (id .. '-' .. r.asset.guid) or nil
    prune_take(r.key)
  end
  save_cfg()
end

-- What adopting a row means: the folder, and for a file found under another
-- prefix the name template that gives its name. Takes of the same asset found
-- the same way are adopted with it.
local function adoption(r)
  if r.st.kind == 'found' then return r.st.dir, nil end
  if r.st.kind == 'similar' then
    local rest = r.st.matched == 'name' and r.template or '$track_$index'
    return r.st.dir, r.st.prefix .. rest
  end
end

local function adopt(row, rows)
  local dir, template = adoption(row)
  if dir == nil then return end
  local list = {}
  for _, r in ipairs(rows) do
    if r.asset == row.asset then
      local d, t = adoption(r)
      if d == dir and t == template then list[#list + 1] = r end
    end
  end
  if template then set_name(list, template) end
  set_folder(list, dir)
end

-- Renames in FMOD the files of these takes to their new names (same folder,
-- same extension), and the files already rendered here. Outcome in S.render_report.
local function rename_in_fmod(list)
  local lines, pending = {}, #list
  local dir = render.output_dir(S.cfg.render_dir, config.dirname(S.rpp))
  local new_folders = {} -- folders made in the picker that a Move puts a file into
  local function done()
    pending = pending - 1
    if pending == 0 then
      -- Only failures are shown, and the folders FMOD made for a Move: FMOD
      -- tags them #unimported, and its scripting API cannot import a folder.
      local failed = {}
      for _, l in ipairs(lines) do if l:find('^failed') then failed[#failed + 1] = l end end
      local made = {}
      for f in pairs(new_folders) do made[#made + 1] = f end
      table.sort(made)
      if #failed > 0 then
        S.render_report = { text = table.concat(failed, '\n'), col = COL_ERR }
      elseif #made > 0 then
        S.render_report = { col = COL_WARN, text = 'New folder in FMOD: ' .. table.concat(made, ', ')
          .. '.\nIf FMOD shows it as #unimported: right-click it in the Assets browser > Import Contents.' }
      else
        S.render_report = nil
      end
      refresh_fmod()
      load_folders() -- a Move may have made a folder
    end
  end
  local function new_path(r)
    local ext = r.st.path:match('(%.[^./]*)$') or '.wav'
    return (r.folder ~= '' and (r.folder .. '/') or '') .. r.name .. ext
  end
  -- FMOD runs the requests in order: a file whose new path another of these
  -- still holds goes after that one (Door_01 -> Door_00 before Door_02 -> Door_01).
  local holder, ordered, placed = {}, {}, {}
  for _, r in ipairs(list) do holder[r.st.path:lower()] = r end
  local left = #list
  while left > 0 do
    local progress = false
    for _, r in ipairs(list) do
      local h = holder[new_path(r):lower()]
      if not placed[r] and (not h or h == r or placed[h]) then
        placed[r], left, progress = true, left - 1, true
        ordered[#ordered + 1] = r
      end
    end
    if not progress then
      -- A cycle (two takes swapping names): FMOD refuses those; reported.
      for _, r in ipairs(list) do if not placed[r] then placed[r] = true; ordered[#ordered + 1] = r end end
      left = 0
    end
  end
  for _, r in ipairs(ordered) do
    local new = new_path(r)
    local body = 'var old = ' .. json.encode(r.st.path) .. '; var nu = ' .. json.encode(new) .. ';'
      .. ' var a = studio.project.model.AudioFile.findInstances(); var f = null;'
      .. ' for (var i = 0; i < a.length; i++) { if (a[i].getAssetPath() === old) { f = a[i]; break; } }'
      .. ' if (!f) { throw "not in FMOD any more: " + old; }'
      .. ' for (var i = 0; i < a.length; i++) { if (a[i] !== f && a[i].getAssetPath().toLowerCase() === nu.toLowerCase()) {'
      .. ' throw "FMOD already has another file at " + nu; } }'
      .. ' f.setAssetPath(nu); return f.getAssetPath();'
    local key, old_base, name, old_path = r.key, r.st.old, r.name, r.st.path
    link.request(body, function(res, err)
      local v = type(res) == 'table' and res.p or res
      if not err and type(v) == 'string' and v:lower() ~= new:lower() then
        err = 'FMOD left it at ' .. v .. ': a file is already at ' .. new .. ', or one under source control. Free that path and try again.'
      end
      if err then
        lines[#lines + 1] = 'failed: ' .. r.st.path .. ': ' .. err
      else
        lines[#lines + 1] = 'changed in FMOD: ' .. tostring(v)
        if S.extra_folders and S.extra_folders[r.folder] then
          S.extra_folders[r.folder] = nil
          new_folders[r.folder] = true
        end
        if type(v) == 'string' then
          take_cfg(key).linked = v
          -- The file is this take's now: another take still remembering this
          -- path (a file no longer there, or FMOD would have refused) would
          -- claim it and show this take as New.
          for k, t in pairs(S.cfg.takes) do
            if k ~= key and type(t.linked) == 'string' and t.linked:lower() == v:lower() then t.linked = nil end
          end
          -- FMOD's files as known here follow at once, without waiting for
          -- the next answer about them: the row shows Linked right away.
          if S.audio_files then
            local files, found = {}, false
            for _, p in ipairs(S.audio_files) do
              if p == old_path then
                if not found then files[#files + 1] = v; found = true end
              elseif p:lower() ~= v:lower() then
                files[#files + 1] = p
              end
            end
            if not found then files[#files + 1] = v end
            if S.audio_ch and S.audio_ch[old_path] then S.audio_ch[v], S.audio_ch[old_path] = S.audio_ch[old_path], nil end
            S.audio_files = files
            S.fmod_idx = assets_mod.index_fmod(files)
          end
        end
        save_cfg()
        -- The render already on disk follows the name.
        local from, to = dir .. render.SEP .. old_base .. '.wav', dir .. render.SEP .. name .. '.wav'
        if reaper.file_exists(from) and not reaper.file_exists(to) then os.rename(from, to) end
      end
      done()
    end)
  end
end

-- Copies a file (binary). Returns true, or false and why.
local function copy_file(from, to)
  local src = io.open(from, 'rb')
  if not src then return false, 'cannot read ' .. from end
  local data = src:read('a')
  src:close()
  local dst, err = io.open(to, 'wb')
  if dst then
    dst:write(data)
    dst:close()
    return true
  end
  -- A read-only file (Perforce leaves its files so): written beside it, then
  -- put in its place, as Finder does when a file is replaced. Only the folder
  -- has to be writable.
  local tmp = to .. '.fmodsync_tmp'
  local t, terr = io.open(tmp, 'wb')
  if not t then return false, tostring(err) .. '; ' .. tostring(terr) end
  t:write(data)
  t:close()
  local ok, rerr = os.rename(tmp, to)
  if not ok then
    os.remove(tmp)
    return false, tostring(err) .. '; ' .. tostring(rerr)
  end
  return true
end

-- Sends the takes just rendered (done = { {row, path}, ... }) to FMOD Studio:
--   Linked: the rendered file overwrites FMOD's (its absolute path asked to
--           FMOD), then FMOD is asked to refresh modified assets;
--   New:    imported (studio.project.importAudioFile, which copies it into the
--           Assets root) and moved to its folder and name (setAssetPath).
-- Takes with another status (Rename / Move, Adopt, Link) are not synced: the
-- report says so. `lines`: the render's problems, shown with the sync's.
sync_rendered = function(done, lines)
  if #done == 0 then return end
  local function report(extra_warn)
    -- FMOD stops answering while one of its dialogs is open (an error, a
    -- source control prompt): every request then times out. One line for all.
    local failed, silent = {}, {}
    for _, l in ipairs(lines) do
      local who = l:match('^not %a+: (.-): no answer from FMOD Studio')
      if who then silent[#silent + 1] = who else failed[#failed + 1] = l end
    end
    if #silent > 0 then
      table.insert(failed, 1, 'FMOD Studio did not answer: ' .. #silent .. (#silent == 1 and ' take' or ' takes')
        .. ' not synced (' .. table.concat(silent, ', ') .. ').'
        .. '\nIs a window open in FMOD (an error, a source control prompt)? Close it, then Render these takes again.')
    end
    if #failed > 0 then
      S.render_report = { text = table.concat(failed, '\n'), col = COL_ERR }
      -- Also in REAPER's console, where it can be read in full and copied.
      reaper.ShowConsoleMsg('FMOD Sync:\n' .. S.render_report.text .. '\n')
    elseif extra_warn then
      S.render_report = { text = extra_warn, col = COL_WARN }
    else
      S.render_report = nil
    end
  end
  if link.status ~= 'online' or not fmod_has_linked_project() then
    lines[#lines + 1] = 'rendered, not synced: FMOD Studio does not have ' .. (fspro_name() or 'the linked project') .. ' open'
    report()
    return
  end
  local pending, new_folders = 0, {}
  local function finish()
    pending = pending - 1
    if pending > 0 then return end
    save_cfg()
    -- FMOD only reloads a file changed on disk when told to (#modified). Each
    -- overwritten file was already asked to (refreshAudio); this catches the
    -- rest. Both names come from FMOD 2.04 itself (asked on 2026-11-19: actions
    -- RefreshModifiedAssets, ScriptReload; AudioFile _reload, refreshAudio), they
    -- are not in the docs, so each is used only if it exists.
    link.request('var a = studio.window.actions.RefreshModifiedAssets;'
      .. ' if (a !== undefined) { studio.window.triggerAction(a); } return a !== undefined;', function() end)
    local made = {}
    for f in pairs(new_folders) do made[#made + 1] = f end
    table.sort(made)
    report(#made > 0 and ('New folder in FMOD: ' .. table.concat(made, ', ')
      .. '.\nIf FMOD shows it as #unimported: right-click it in the Assets browser > Import Contents.') or nil)
    refresh_fmod()
    load_folders()
  end
  local jobs = {}
  for _, d in ipairs(done) do
    local r = d.row
    local kind = r.st.kind
    if kind == 'linked' or kind == 'new' then
      jobs[#jobs + 1] = d
    else
      lines[#lines + 1] = 'rendered, not synced (' .. (kind == 'renamed' and 'Rename / Move first'
        or kind == 'found' and 'Adopt first' or kind == 'similar' and 'answer Similar? first' or 'choose its folder') .. '): ' .. r.name
    end
  end
  if #jobs == 0 then report(); return end
  pending = #jobs
  for _, d in ipairs(jobs) do
    local r, path = d.row, d.path
    if r.st.kind == 'linked' then
      local body = 'var p = ' .. json.encode(r.st.path) .. ';'
        .. ' var a = studio.project.model.AudioFile.findInstances(); var f = null;'
        .. ' for (var i = 0; i < a.length; i++) { if (a[i].getAssetPath() === p) { f = a[i]; break; } }'
        .. ' if (!f) { throw "not in FMOD any more: " + p; }'
        .. ' return f.getAbsoluteAssetPath();'
      link.request(body, function(v, err)
        if err then
          lines[#lines + 1] = 'not synced: ' .. r.name .. ': ' .. err
        elseif type(v) ~= 'string' then
          lines[#lines + 1] = 'not synced: ' .. r.name .. ': FMOD gave no file path'
        else
          local ok, why = copy_file(path, v)
          if ok then
            take_cfg(r.key).synced = os.time()
            -- FMOD reloads this file now, instead of showing it #modified.
            pending = pending + 1
            link.request('var p = ' .. json.encode(r.st.path) .. ';'
              .. ' var a = studio.project.model.AudioFile.findInstances();'
              .. ' for (var i = 0; i < a.length; i++) { if (a[i].getAssetPath() === p) {'
              .. ' if (typeof a[i].refreshAudio === "function") { a[i].refreshAudio(); return true; } } }'
              .. ' return false;', function() finish() end)
          else
            lines[#lines + 1] = 'not synced: ' .. r.name .. ': cannot overwrite ' .. v .. ' (' .. tostring(why) .. ')'
          end
        end
        finish()
      end)
    else
      local rel = (r.folder ~= '' and (r.folder .. '/') or '') .. r.name .. '.wav'
      local body = 'var a = studio.project.importAudioFile(' .. json.encode(path) .. ');'
        .. ' if (!a) { throw "FMOD did not import " + ' .. json.encode(path) .. '; }'
        .. ' var t = ' .. json.encode(rel) .. ';'
        -- Another file of FMOD's already there: not moved (FMOD would fail).
        .. ' var all = studio.project.model.AudioFile.findInstances();'
        .. ' for (var i = 0; i < all.length; i++) { if (all[i] !== a && all[i].getAssetPath().toLowerCase() === t.toLowerCase()) { return a.getAssetPath(); } }'
        .. ' a.setAssetPath(t); return a.getAssetPath();'
      link.request(body, function(res, err)
        local v = type(res) == 'table' and res.p or res
        if err then
          lines[#lines + 1] = 'not imported: ' .. r.name .. ': ' .. err
        else
          -- Imported, but left where FMOD put it: the take shows Move, to
          -- try again once the path is free.
          if type(v) == 'string' and v:lower() ~= rel:lower() then
            lines[#lines + 1] = 'imported but not moved: ' .. r.name .. ' is at ' .. v .. ', not ' .. rel
              .. ': FMOD already has a file at that path, or one under source control.'
              .. ' Free that path, then press Move on the take.'
          end
          if type(v) == 'string' then take_cfg(r.key).linked = v end
          take_cfg(r.key).synced = os.time()
          if S.extra_folders and S.extra_folders[r.folder] then
            S.extra_folders[r.folder] = nil
            new_folders[r.folder] = true
          end
        end
        finish()
      end)
    end
  end
end

-- Renders these takes, then syncs them (sync_rendered); the outcome goes to S.render_report.
local function render_rows(list)
  local jobs, seen, lines = {}, {}, {}
  for _, r in ipairs(list) do
    local k = r.name:lower()
    if r.asset.muted or r.folder == nil then
      -- Muted tracks and takes with no FMOD folder are never rendered.
    elseif r.name == '' then
      lines[#lines + 1] = 'no file name: ' .. r.asset.name .. ' take ' .. r.index
    elseif seen[k] then
      lines[#lines + 1] = 'same file name twice, rendered once: ' .. r.name
    else
      seen[k] = true
      jobs[#jobs + 1] = { asset = r.asset, name = r.name, block = r.block, settings = r.settings, key = r.key, row = r }
    end
  end
  local dir = render.output_dir(S.cfg.render_dir, config.dirname(S.rpp))
  local results = render.render_jobs(S.proj, jobs, dir)
  local done = {}
  for _, res in ipairs(results) do
    if res.path then
      take_cfg(res.job.key).rendered = os.time()
      done[#done + 1] = { row = res.job.row, path = res.path }
      if res.cue_err then lines[#lines + 1] = 'take markers not written: ' .. res.cue_err end
    else
      lines[#lines + 1] = res.err
    end
  end
  save_cfg()
  -- Only problems are shown; the sync adds its own.
  S.render_report = #lines > 0 and { text = table.concat(lines, '\n'), col = COL_ERR } or nil
  sync_rendered(done, lines)
end

------------------------------------------------------------------------------
-- Folder picker.

local function open_picker(rows)
  local keys = {}
  for _, r in ipairs(rows) do keys[#keys + 1] = r.key end
  -- Opened after the table: OpenPopup inside a PushID would be scoped by it.
  S.pick_keys, S.pick_filter, S.pick_open = keys, '', true
  S.pick_dir = rows[1] and rows[1].folder or '' -- the browser starts where the first take is
  S.pick_title = #rows == 1 and rows[1].name or (#rows .. ' takes')
  S.pick_suggest = nil
end

-- Suggested folders: how the other assets of this project are placed, applied
-- to this one. The track name splits on "_" into words (Point_MetroSignNeon:
-- Point, MetroSignNeon). An asset with a folder gives a formula:
--   a folder part equal to its track name    -> that part becomes this track name
--   last parts equal to its last words       -> they become this track's last words
--   otherwise                                -> its folder as it is
-- Assets sharing more leading words with this one come first (Point_... with
-- Point_...). Folders of FMOD named as this track or its last word come first
-- of all. Each suggestion is { label, folder_of = function(asset) -> folder, why }.
local function name_words(name)
  local w = {}
  for t in (name or ''):gmatch('[^_]+') do w[#w + 1] = t end
  return w
end

local function split_path(rel)
  local parts = {}
  for p in (rel or ''):gmatch('[^/]+') do parts[#parts + 1] = p end
  return parts
end

-- The formula of one placed asset (track name `from`, folder `folder`), as a
-- function giving the folder of another track name.
local function folder_formula(from, folder)
  local parts, fw = split_path(folder), name_words(from)
  for i, p in ipairs(parts) do
    if p:lower() == from:lower() then
      return function(to)
        local out = {}
        for j, q in ipairs(parts) do out[j] = (j == i) and to or q end
        return table.concat(out, '/')
      end, true
    end
  end
  -- Last k parts = last k words of the track name (k as large as it goes).
  local k = 0
  while k < #parts and k < #fw and parts[#parts - k]:lower() == fw[#fw - k]:lower() do k = k + 1 end
  if k > 0 then
    return function(to)
      local tw = name_words(to)
      if #tw < k then return nil end
      local out = {}
      for j = 1, #parts - k do out[j] = parts[j] end
      for j = #tw - k + 1, #tw do out[#out + 1] = tw[j] end
      return table.concat(out, '/')
    end, true
  end
  return function() return folder end, false
end

local function shared_words(a, b)
  local wa, wb = name_words(a), name_words(b)
  local n = 0
  while n < #wa and n < #wb and wa[n + 1]:lower() == wb[n + 1]:lower() do n = n + 1 end
  return n
end

local function suggest_folders(rows, all_rows)
  local target = rows[1].asset
  local mine = {}
  for _, r in ipairs(rows) do mine[r.asset] = true end
  -- One placed asset each: its folder (the asset's, else its first take's).
  local placed, seen = {}, {}
  for _, r in ipairs(all_rows) do
    local a = r.asset
    if not mine[a] and not seen[a] then
      local acfg = S.cfg.assets[a.guid]
      local f = (acfg and acfg.folder) or r.folder
      if f and f ~= '' then seen[a] = true; placed[#placed + 1] = { asset = a, folder = f } end
    end
  end
  table.sort(placed, function(x, y)
    local sx, sy = shared_words(x.asset.name, target.name), shared_words(y.asset.name, target.name)
    if sx ~= sy then return sx > sy end
    return x.asset.name:lower() < y.asset.name:lower()
  end)
  local out, have = {}, {}
  local function add(sugg)
    local f = sugg.folder_of(target)
    if not f or f == '' or have[f:lower()] then return end
    have[f:lower()] = true
    sugg.label = f
    out[#out + 1] = sugg
  end
  -- FMOD folders named as the track, or as its last word.
  local tw = name_words(target.name)
  for _, rel in ipairs(S.folders) do
    local last = rel:match('([^/]+)$')
    if last and (last:lower() == target.name:lower() or (#tw > 1 and last:lower() == tw[#tw]:lower())) then
      add({ folder_of = function() return rel end, why = 'An FMOD folder named as this track.' })
    end
    if #out >= 1 then break end
  end
  for _, p in ipairs(placed) do
    if #out >= 3 then break end
    local fn, formula = folder_formula(p.asset.name, p.folder)
    add({ folder_of = function(a) return fn(a.name) end,
      why = (formula and 'As ' or 'Same folder as ') .. p.asset.name .. ' (' .. p.folder .. ')'
        .. (formula and ', with this track\'s name.' or '.') })
  end
  -- Files in FMOD with this track's "<track>_<NN>" under another prefix (an
  -- older or sibling project, e.g. Enemies_OtherEnemy_Foley_Walk_01): their
  -- folder, with the word of that prefix that names a folder swapped for the
  -- one of this take's prefix (Enemies/OtherEnemy/Fx -> Enemies/ThisEnemy/Fx).
  local idx = S.fmod_idx
  if idx and idx.by_tail and #out < 4 then
    local seen_dir = {}
    for _, r in ipairs(rows) do
      if r.asset == target then
        local tn = target.name .. '_' .. index_text(r.index)
        local tkey = tn:lower()
        local own = r.name:lower():sub(-#tkey) == tkey and r.name:sub(1, #r.name - #tn) or ''
        for _, c in ipairs(idx.by_tail[tkey] or {}) do
          if not seen_dir[c.dir] then
            seen_dir[c.dir] = true
            local other = c.base:sub(1, #c.base - #tn)
            local ow, tw2 = name_words(own), name_words(other)
            -- Drop the words both prefixes share at the start and at the end.
            local i = 0
            while i < #ow and i < #tw2 and ow[i + 1]:lower() == tw2[i + 1]:lower() do i = i + 1 end
            local j = 0
            while j < #ow - i and j < #tw2 - i and ow[#ow - j]:lower() == tw2[#tw2 - j]:lower() do j = j + 1 end
            local mine_mid = table.concat(ow, '_', i + 1, #ow - j)
            local their_mid = table.concat(tw2, '_', i + 1, #tw2 - j)
            local parts, swapped = split_path(c.dir), false
            if mine_mid ~= '' and their_mid ~= '' then
              for k, q in ipairs(parts) do
                if q:lower() == their_mid:lower() then parts[k] = mine_mid; swapped = true end
              end
            end
            local f = table.concat(parts, '/')
            add({ folder_of = function() return f end,
              why = swapped and ('As ' .. c.base .. ' (' .. c.dir .. '), with ' .. mine_mid .. ' for ' .. their_mid .. '.')
                or ('Where ' .. c.base .. ' is.') })
            if #out >= 4 then break end
          end
        end
      end
      if #out >= 4 then break end
    end
  end
  return out
end

-- The subfolders of each asset folder: parent rel path -> { names, sorted }.
local function folder_children()
  if S.children_of == S.folders then return S.children end
  local ch = {}
  for _, rel in ipairs(S.folders) do
    local parent, name = rel:match('^(.*)/([^/]+)$')
    if not parent then parent, name = '', rel end
    ch[parent] = ch[parent] or {}
    table.insert(ch[parent], name)
  end
  for _, l in pairs(ch) do table.sort(l, function(x, y) return x:lower() < y:lower() end) end
  S.children, S.children_of = ch, S.folders
  return ch
end

-- Folder browser: a click on a folder opens it, the path at the top goes back
-- up, "Use this folder" chooses the one open. Typing in the filter lists every
-- matching folder; a click opens it.
local function draw_folder_picker(by_key, all_rows)
  if not ImGui.BeginPopup(ctx, 'pick_folder') then return end
  local rows = {}
  for _, k in ipairs(S.pick_keys or {}) do if by_key[k] then rows[#rows + 1] = by_key[k] end end
  if #rows == 0 then ImGui.CloseCurrentPopup(ctx); ImGui.EndPopup(ctx); return end
  local W = 520
  local dir = S.pick_dir or ''
  local children = folder_children()
  ImGui.Text(ctx, 'FMOD folder for ' .. (S.pick_title or ''))
  -- Suggested: how the other assets of this project are placed. Each asset of
  -- these takes gets its own folder from the same formula.
  if ImGui.IsWindowAppearing(ctx) or not S.pick_suggest then
    S.pick_suggest = suggest_folders(rows, all_rows or {})
    local known = {}
    for _, rel in ipairs(S.folders) do known[rel:lower()] = true end
    for _, sg in ipairs(S.pick_suggest) do sg.new = not known[sg.label:lower()] end
  end
  if #S.pick_suggest > 0 then
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.TextDisabled(ctx, 'Suggested')
    for n, sg in ipairs(S.pick_suggest) do
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, sg.label .. (sg.new and ' (new)' or '') .. '##sugg' .. n) then
        local groups, order = {}, {}
        for _, r in ipairs(rows) do
          if not groups[r.asset] then groups[r.asset] = {}; order[#order + 1] = r.asset end
          table.insert(groups[r.asset], r)
        end
        S.auto_move = {}
        local known = {}
        for _, rel in ipairs(S.folders) do known[rel:lower()] = true end
        for _, a in ipairs(order) do
          local f = sg.folder_of(a)
          if f and f ~= '' then
            -- A folder FMOD does not have yet: virtual, as New folder.
            if not known[f:lower()] then
              S.extra_folders = S.extra_folders or {}
              S.extra_folders[f] = true
              S.folders[#S.folders + 1] = f
              known[f:lower()] = true
              S.children_of = nil
            end
            set_folder(groups[a], f)
            for _, r in ipairs(groups[a]) do S.auto_move[r.key] = true end
          end
        end
        table.sort(S.folders, function(x, y) return x:lower() < y:lower() end)
        S.pick_suggest = nil
        ImGui.CloseCurrentPopup(ctx)
      end
      tip(sg.why .. (sg.new and '\nNot in FMOD yet: made when the first take is moved into it.' or '')
        .. (#assets_of(rows) > 1 and '\nEvery asset of these takes gets its own folder this way.' or ''))
    end
  end
  -- Folders that already hold these names, marked in the list.
  local places = {}
  for _, r in ipairs(rows) do
    for _, p in ipairs(r.st.places or {}) do places[p.dir] = true end
    if r.st.dir then places[r.st.dir] = true end
  end
  local function holds_place(rel)
    for d in pairs(places) do
      if d == rel or (rel == '' and d ~= '') or d:sub(1, #rel + 1) == rel .. '/' then return true end
    end
    return false
  end

  -- Path: every part goes back to that folder.
  ImGui.Spacing(ctx)
  if ImGui.SmallButton(ctx, 'Assets##crumb') then dir = '' end
  local acc = ''
  local i = 0
  for part in dir:gmatch('[^/]+') do
    i = i + 1
    acc = acc == '' and part or (acc .. '/' .. part)
    ImGui.SameLine(ctx, 0, 2)
    ImGui.TextDisabled(ctx, '/')
    ImGui.SameLine(ctx, 0, 2)
    local target = acc
    if ImGui.SmallButton(ctx, part .. '##crumb' .. i) then dir = target end
  end

  ImGui.SetNextItemWidth(ctx, W)
  if ImGui.IsWindowAppearing(ctx) then ImGui.SetKeyboardFocusHere(ctx) end
  local _, f = ImGui.InputTextWithHint(ctx, '##pick_filter', 'search all folders', S.pick_filter)
  S.pick_filter = f

  if ImGui.BeginChild(ctx, 'pick_list', W, 320, ImGui.ChildFlags_Borders) then
    local words = filter_words(S.pick_filter)
    if #words > 0 then
      for n, rel in ipairs(S.folders) do
        if filter_match(words, rel) then
          if ImGui.Selectable(ctx, rel .. '##s' .. n, false) then dir, S.pick_filter = rel, '' end
        end
      end
    else
      if dir ~= '' then
        if ImGui.Selectable(ctx, '..##up', false) then dir = dir:match('^(.*)/[^/]+$') or '' end
      end
      for n, name in ipairs(children[dir] or {}) do
        local rel = dir == '' and name or (dir .. '/' .. name)
        local mark = holds_place(rel)
        if mark then ImGui.PushStyleColor(ctx, ImGui.Col_Text, COL_ACCENT) end
        local has_sub = children[rel] ~= nil
        if ImGui.Selectable(ctx, name .. (has_sub and '  /' or '') .. '##c' .. n, false) then dir = rel end
        if mark then ImGui.PopStyleColor(ctx) end
        if mark then tip('These takes\' names are already in FMOD in here.') end
      end
      if not children[dir] then ImGui.TextDisabled(ctx, 'No subfolders.') end
    end
    ImGui.EndChild(ctx)
  end
  -- A new folder inside the one open, then opened. It exists only here until a
  -- file is moved into it.
  ImGui.SetNextItemWidth(ctx, W - button_width('New folder') - ITEM_SPACING_X)
  local _, nf = ImGui.InputTextWithHint(ctx, '##new_folder', 'new folder in ' .. folder_label(dir), S.pick_new or '')
  S.pick_new = nf
  local entered = ImGui.IsItemDeactivatedAfterEdit(ctx) and ImGui.IsKeyPressed(ctx, ImGui.Key_Enter)
  ImGui.SameLine(ctx)
  local name = (S.pick_new or ''):gsub('^%s+', ''):gsub('%s+$', '')
  local valid = name ~= '' and not name:find('[/\\:%*%?"<>|]') and name ~= '.' and name ~= '..'
  ImGui.BeginDisabled(ctx, not valid or not fspro_path())
  if ImGui.Button(ctx, 'New folder') or (entered and valid and fspro_path()) then
    local rel = dir == '' and name or (dir .. '/' .. name)
    -- Not made on disk: a folder made outside FMOD shows as #unimported there.
    -- FMOD makes it when the first file is moved into it (Move).
    S.extra_folders = S.extra_folders or {}
    S.extra_folders[rel] = true
    local exists = false
    for _, r in ipairs(S.folders) do if r == rel then exists = true end end
    if not exists then
      S.folders[#S.folders + 1] = rel
      table.sort(S.folders, function(x, y) return x:lower() < y:lower() end)
      S.children_of = nil
    end
    dir, S.pick_new = rel, ''
  end
  ImGui.EndDisabled(ctx)
  tip('A new folder inside the one open. FMOD makes it when the first take is moved into it.')
  S.pick_dir = dir

  if accent_button('Use ' .. folder_label(dir)) then
    set_folder(rows, dir)
    -- Takes already in FMOD are moved there at once (next frame, once their
    -- status shows the new folder).
    S.auto_move = {}
    for _, r in ipairs(rows) do S.auto_move[r.key] = true end
    ImGui.CloseCurrentPopup(ctx)
  end
  tip('These takes go to this folder of FMOD.')
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, 'No folder') then
    set_folder(rows, nil)
    ImGui.CloseCurrentPopup(ctx)
  end
  tip('These takes are not synced to FMOD.')
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, 'Cancel') then ImGui.CloseCurrentPopup(ctx) end
  ImGui.EndPopup(ctx)
end

------------------------------------------------------------------------------
-- Main view: the take table and, under it, the settings of the selection.

local COL_ROW_SELECTED = 0x4D412999

local function wildcard_help()
  local lines = { 'Wildcards:' }
  for _, w in ipairs(assets_mod.WILDCARDS) do lines[#lines + 1] = w[1] .. '   ' .. w[2] end
  return table.concat(lines, '\n')
end

-- Whether the take's file is in the render folder (looked up once a second).
is_rendered = function(r)
  local now = reaper.time_precise()
  if not S.rendered_at or now - S.rendered_at > 1 then S.rendered_cache, S.rendered_at = {}, now end
  local v = S.rendered_cache[r.name]
  if v == nil then
    local dir = render.output_dir(S.cfg.render_dir, config.dirname(S.rpp))
    v = reaper.file_exists(dir .. render.SEP .. r.name .. '.wav')
    S.rendered_cache[r.name] = v
  end
  return v
end

local function draw_status_cell(r, rows)
  local st = r.st
  -- Buttons fill the cell, less the "muted" note after them.
  local function cell_button(label)
    local w = ImGui.GetContentRegionAvail(ctx)
    if r.asset.muted then w = w - ImGui.CalcTextSize(ctx, 'muted') - ITEM_SPACING_X end
    return ImGui.Button(ctx, label, math.max(1, w), 0)
  end
  if st.kind == 'linked' then
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.TextColored(ctx, COL_OK, 'Linked')
    tip(st.path)
  elseif st.kind == 'new' then
    ImGui.AlignTextToFramePadding(ctx)
    if is_rendered(r) then
      ImGui.TextColored(ctx, COL_ACCENT, 'New')
      tip('Rendered, not in FMOD yet: the next render of it imports it into ' .. folder_label(r.folder) .. '.')
    else
      ImGui.TextColored(ctx, COL_DIM, 'Not rendered')
      tip('Not in FMOD, and no render of it in the render folder: Render makes it and imports it into '
        .. folder_label(r.folder) .. '.')
    end
  elseif st.kind == 'renamed' then
    local label = (st.moved and st.renamed) and 'Move+Rename' or (st.moved and 'Move' or 'Rename')
    -- Asked first: the file FMOD has may be another sound that only had this
    -- take's old name (a take renumbered or renamed to a new line), and a
    -- Rename would take that file away from it.
    local pid = 'rename_ask##' .. r.key
    if cell_button(label) then ImGui.OpenPopup(ctx, pid) end
    tip((st.moved and 'Moved' or 'Renamed') .. ' here: FMOD still has ' .. st.path .. '\n' .. label
      .. ' changes that file in FMOD to ' .. folder_label(r.folder) .. '/' .. r.name
      .. (st.renamed and ' (and renames the file already rendered here)' or '')
      .. '; or keep that file and make this take a new one. On a selected row, every selected one.')
    if ImGui.BeginPopup(ctx, pid) then
      -- On a selected row: every selected row with the same mismatch.
      local list = {}
      if S.sel[r.key] then
        for _, x in ipairs(selected_rows()) do if x.st.kind == 'renamed' then list[#list + 1] = x end end
      else
        list = { r }
      end
      local more = #list > 1 and (' (and ' .. (#list - 1) .. ' more selected)') or ''
      ImGui.Text(ctx, 'FMOD has ' .. st.old .. ', last linked to this take' .. more .. '.')
      ImGui.TextDisabled(ctx, 'Is it this take, renamed here, or another sound that keeps its name?')
      ImGui.Spacing(ctx)
      if ImGui.Button(ctx, label .. ' it in FMOD') then
        rename_in_fmod(list)
        ImGui.CloseCurrentPopup(ctx)
      end
      tip('Same sound: the file in FMOD becomes ' .. folder_label(r.folder) .. '/' .. r.name .. '.')
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, 'Keep it, this take is new') then
        for _, x in ipairs(list) do take_cfg(x.key).linked = nil end
        save_cfg()
        ImGui.CloseCurrentPopup(ctx)
      end
      tip("Another sound: FMOD's file stays as it is, this take is rendered and imported as a new file.")
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, 'Cancel') then ImGui.CloseCurrentPopup(ctx) end
      ImGui.EndPopup(ctx)
    end
  elseif st.kind == 'similar' then
    -- Another file, under another prefix: maybe the same sound, maybe not.
    -- Never adopted in one click: the popup shows both and asks.
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, COL_DIM)
    if cell_button('Similar?') then S.adopt_ask = { key = r.key } end
    ImGui.PopStyleColor(ctx)
    tip('A file in FMOD has a name like this take\'s: ' .. st.path
      .. '\nClick to compare them and decide if this take is that file.')
  elseif st.kind == 'found' then
    if cell_button('Adopt') then
      -- On a selected row: every selected row that can be adopted.
      if S.sel[r.key] then
        for _, x in ipairs(selected_rows()) do
          if x.st.kind == 'found' then adopt(x, rows) end
        end
      else
        adopt(r, rows)
      end
    end
    local text
    if r.folder ~= nil then
      text = 'Moved in FMOD to ' .. folder_label(st.dir) .. ': use that folder from now on.'
    else
      text = 'Already in FMOD: ' .. st.path .. '\nUse that folder.'
    end
    tip(text .. '\nTakes of ' .. r.asset.name .. ' found the same way are adopted too;'
      .. ' on a selected row, every selected take is.')
  else
    if cell_button('Link') then
      open_picker(S.sel[r.key] and selected_rows() or { r })
    end
    if st.kind == 'ambiguous' then
      local lines = {}
      for _, p in ipairs(st.places) do lines[#lines + 1] = folder_label(p.dir) .. ' / ' .. p.base end
      tip('Found in more than one place: choose the folder.\n' .. table.concat(lines, '\n'))
    else
      tip('Choose the FMOD folder of this take (of the selected ones when it is selected).')
    end
  end
  -- Muted only stops the render: link, adopt and rename still work.
  if r.asset.muted then
    ImGui.SameLine(ctx)
    ImGui.TextDisabled(ctx, 'muted')
    tip(r.asset.name .. ' is muted: its takes are not rendered.')
  end
end

-- Drag to FMOD. REAPER scripts cannot start a drag to another app, so a
-- helper process (mtt_fmodsync_drag.js, macOS osascript + AppKit) keeps a
-- small native window that this script puts exactly over the drag handle the
-- mouse is on: the press then lands in it and drags the FMOD files of the
-- take (of every selected one when it is selected), in one gesture. Files
-- are taken from FMOD's Assets folder: FMOD links a file dropped from there
-- to its asset, no copy. The helper reads DRAG_CMD (rewritten at least every
-- second while this runs; it quits 3 s after it stops) and writes DRAG_ACK.
local IS_MAC = reaper.GetOS():find('OSX') ~= nil or reaper.GetOS():find('mac') ~= nil
local DRAG_DIR = (os.getenv('TMPDIR') or '/tmp/'):gsub('/?$', '/')
local DRAG_CMD, DRAG_ACK = DRAG_DIR .. 'mtt_fmodsync_drag.cmd', DRAG_DIR .. 'mtt_fmodsync_drag.ack'
local function sh_quote(v) return "'" .. tostring(v):gsub("'", "'\\''") .. "'" end
local drag = { text = nil, written = 0, seq = 0, launched = 0, ack_checked = 0, alive = false, hovered = false }

local function theme_hex(key, fallback)
  local native = reaper.GetThemeColor(key, 0)
  if not native or native < 0 then return fallback end
  local r, g, b = reaper.ColorFromNative(native)
  return string.format('%02X%02X%02X', r, g, b)
end

-- The FMOD files of these rows that are on disk (Linked takes only).
local function fmod_files(list)
  local fspro = fspro_path()
  if not fspro then return {} end
  local assets = config.dirname(fspro) .. '/Assets/'
  local out = {}
  for _, x in ipairs(list) do
    if x.st.kind == 'linked' and reaper.file_exists(assets .. x.st.path) then out[#out + 1] = assets .. x.st.path end
  end
  return out
end

local function drag_send(text)
  local now = reaper.time_precise()
  if text == drag.text and now - drag.written < 1 then return end
  drag.seq = drag.seq + 1
  local f = io.open(DRAG_CMD, 'w')
  if not f then return end
  f:write(drag.seq, '\n', text)
  f:close()
  drag.text, drag.written = text, now
end

-- Once per frame, after the tables: hides the handle window when the mouse
-- is over this window but on no handle, keeps the helper alive.
local function drag_frame()
  if not IS_MAC then return end
  if not drag.cleaned then
    -- At start: no helper from an earlier run stays (it would keep its window).
    drag.cleaned = true
    os.execute("/usr/bin/pkill -f 'mtt_fmodsync_drag[.]js' >/dev/null 2>&1")
  end
  if not drag.hovered and ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_RootAndChildWindows | ImGui.HoveredFlags_AllowWhenBlockedByActiveItem) then
    drag_send('hide')
  elseif drag.text then
    drag_send(drag.text) -- heartbeat
  end
  drag.hovered = false
  local now = reaper.time_precise()
  if drag.text and now - drag.ack_checked > 1 then
    drag.ack_checked = now
    local f = io.open(DRAG_ACK, 'r')
    local t = f and tonumber(f:read('l') or '')
    if f then f:close() end
    drag.alive = t ~= nil and math.abs(os.time() - t) <= 3
    if not drag.alive and now - drag.launched > 3 then
      drag.launched = now
      -- A helper left from before (stuck, or of an older version) goes first.
      os.execute("/usr/bin/pkill -f 'mtt_fmodsync_drag[.]js' >/dev/null 2>&1")
      os.execute('/usr/bin/osascript -l JavaScript ' .. sh_quote(script_path .. 'mtt_fmodsync_drag.js') .. ' '
        .. sh_quote(DRAG_CMD) .. ' ' .. sh_quote(DRAG_ACK) .. ' >/dev/null 2>&1 &')
    end
  end
end

-- The drag handle cell of a row (`pool`: the rows a selected row drags with it).
local function draw_drag_cell(r, pool)
  local h = ImGui.GetFrameHeight(ctx)
  local w = ImGui.GetContentRegionAvail(ctx)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  ImGui.InvisibleButton(ctx, '##drag', math.max(w, 1), h)
  local linked = r.st.kind == 'linked'
  local dl = ImGui.GetWindowDrawList(ctx)
  local col = ImGui.GetColor(ctx, linked and ImGui.Col_Text or ImGui.Col_TextDisabled)
  -- Six dots: the grip.
  local cx, cy = x + w / 2, y + h / 2
  for i = -1, 1 do for j = -1, 1, 2 do
    ImGui.DrawList_AddRectFilled(dl, cx + j * 2 - 1, cy + i * 4 - 1, cx + j * 2 + 1, cy + i * 4 + 1, col)
  end end
  if not linked then
    tip('Only takes Linked in FMOD can be dragged there.')
    return
  end
  if not IS_MAC then
    tip('Dragging to FMOD works on macOS only for now.')
    return
  end
  tip('Drag into FMOD Studio (an instrument, the asset browser...): its FMOD file'
    .. (S.sel[r.key] and ', with every selected Linked take.' or '.'))
  if ImGui.IsItemHovered(ctx) and not ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left) then
    drag.hovered = true
    local list = { r }
    if S.sel[r.key] then
      list = {}
      for _, x2 in ipairs(pool) do if S.sel[x2.key] then list[#list + 1] = x2 end end
    end
    local files = fmod_files(list)
    if #files == 0 then return end
    -- Cocoa coordinates of the cell (origin bottom left).
    local ax, ay = ImGui.PointConvertNative(ctx, x, y, true)
    local bx, by = ImGui.PointConvertNative(ctx, x + w, y + h, true)
    local lines = { 'show',
      string.format('%d %d %d %d', math.floor(math.min(ax, bx)), math.floor(math.min(ay, by)),
        math.ceil(math.abs(bx - ax)), math.ceil(math.abs(by - ay))),
      theme_hex('col_main_bg', '2B2B2B') .. ' ' .. string.format('%06X', COL_ACCENT >> 8),
      #files == 1 and '1 file' or (#files .. ' files') }
    for _, f in ipairs(files) do lines[#lines + 1] = f end
    drag_send(table.concat(lines, '\n'))
  end
end

-- File cell: a click selects (the name is edited in the panel under the table).
local function draw_file_cell(r)
  ImGui.AlignTextToFramePadding(ctx)
  local col = (#r.unknown > 0 or r.dup or r.name == '') and COL_WARN or nil
  if col then ImGui.PushStyleColor(ctx, ImGui.Col_Text, col) end
  local shown = (r.name == '' and '(no name)' or r.name):gsub('##', '# #')
  local clicked = ImGui.Selectable(ctx, shown .. '##file', false)
  if col then ImGui.PopStyleColor(ctx) end
  if clicked then click_row(r) end
  local lines = { 'Take ' .. r.index .. ' of ' .. r.asset.name .. ' (from its ' .. r.asset.block_source .. ')',
    'Name: ' .. r.template .. (r.own_name and '' or '   (project default)') }
  if #r.unknown > 0 then lines[#lines + 1] = 'Unknown wildcards: ' .. table.concat(r.unknown, ' ') end
  if r.dup then lines[#lines + 1] = 'Another take has the same file name.' end
  lines[#lines + 1] = 'Shift / Cmd click to select more; rename in the panel below.'
  tip(table.concat(lines, '\n'))
end

-- Values of one setting across rows: the value, and whether they differ.
local function encode(v) return type(v) == 'table' and json.encode(v) or tostring(v) end
local function common(rows, k)
  local first = rows[1].settings[k]
  for i = 2, #rows do
    if encode(rows[i].settings[k]) ~= encode(first) then return first, true end
  end
  return first, false
end

-- Where the panel's render settings go: 'take' when takes are selected (each
-- selected take gets its own value, which wins over its track's), 'asset' when
-- no take is selected and the panel shows the takes of the tracks selected in
-- REAPER (the asset's value, for every take of it with none of its own).
local panel_scope = 'take'

-- A take's or track's value: false stands for "off / auto / project's" (nil in
-- the settings), so that it can win over a value that is on above it. A
-- track's value equal to the project's default is not kept (it follows it).
local function set_render(rows, k, v)
  if panel_scope == 'take' then
    for _, r in ipairs(rows) do
      local t = take_cfg(r.key)
      t.render = t.render or obj()
      if v == nil then t.render[k] = false else t.render[k] = v end
    end
  else
    local d = render.project_defaults(S.cfg.render_defaults)[k]
    for _, a in ipairs(assets_of(rows)) do
      local acfg = asset_cfg(a.guid)
      acfg.render = acfg.render or obj()
      if encode(v) == encode(d) then acfg.render[k] = nil
      elseif v == nil then acfg.render[k] = false
      else acfg.render[k] = v end
      if next(acfg.render) == nil then acfg.render = nil end
    end
  end
  save_cfg()
end

-- Drops the takes' own render settings: they render with their track's again.
local function clear_take_render(rows)
  for _, r in ipairs(rows) do
    if S.cfg.takes[r.key] then S.cfg.takes[r.key].render = nil; prune_take(r.key) end
  end
  save_cfg()
end

-- Tail the reverbs of an asset's stem suggest (render.reverb_tail), read
-- again at most once a second: seconds or nil (no reverb), and what was found.
local TAIL_NO_REVERB = 1 -- what ticking Tail sets when there is no reverb
local tail_cache = {}
local function reverb_tail_of(a)
  local now = reaper.time_precise()
  local c = tail_cache[a.track or 0]
  if not c or now - c.t > 1 then
    c = { t = now, found = {} }
    if a.track and reaper.ValidatePtr2(0, a.track, 'MediaTrack*') then
      local ok, v, found = pcall(render.reverb_tail, a.track)
      if ok then c.v, c.found = v, found or {} end
    end
    tail_cache[a.track or 0] = c
  end
  return c.v, c.found
end

-- The suggestion for the selected takes (the longest of their assets) and a
-- tooltip naming the reverbs it comes from.
local function tail_suggestion(rows)
  local best, lines = nil, {}
  for _, a in ipairs(assets_of(rows)) do
    local v, found = reverb_tail_of(a)
    if v and (not best or v > best) then best = v end
    for _, f in ipairs(found) do
      local how = f.how == 'decay' and '' or (f.how == 'size' and ' (from its size)' or ' (decay not readable)')
      lines[#lines + 1] = string.format('%s on %s: %.1f s%s', f.name, f.track, f.tail, how)
    end
  end
  if not best then
    return nil, 'No reverb on these tracks: ticked, the tail is ' .. TAIL_NO_REVERB .. ' s.'
  end
  if #lines > 6 then lines = { table.unpack(lines, 1, 6) }; lines[7] = '...' end
  return best, string.format('Suggested from the reverbs: %.1f s (taken when you tick it).\n', best)
    .. table.concat(lines, '\n')
end

local PANEL_LABEL_W = 120
local SRATES = { 44100, 48000, 88200, 96000 }
local CHANNELS = { 1, 2, 4, 6, 8 }

-- The next label's colour when a selected take has a value of its own for
-- that setting (over its track's); used by the next panel_label / field.
local label_hl
local function own_note()
  return panel_scope == 'take' and '\nOrange: some selected takes have their own value, over their track\'s.'
    or '\nOrange: some of these tracks have their own value, over the project\'s default (Settings).'
end
local function own_hl(sel, k)
  for _, r in ipairs(sel) do
    local o
    if panel_scope == 'take' then
      o = S.cfg.takes[r.key] and S.cfg.takes[r.key].render
    else
      o = S.cfg.assets[r.asset.guid] and S.cfg.assets[r.asset.guid].render
    end
    if o and o[k] ~= nil then return COL_ACCENT end
  end
  return nil
end
local function draw_label(text)
  local hl = label_hl
  label_hl = nil
  if hl then ImGui.TextColored(ctx, hl, text) else ImGui.TextDisabled(ctx, text) end
  return hl ~= nil
end

local panel_label_w = PANEL_LABEL_W
local function panel_label(text, help)
  ImGui.AlignTextToFramePadding(ctx)
  local hl = draw_label(text)
  tip((help or '') .. (hl and own_note() or ''))
  ImGui.SameLine(ctx, panel_label_w)
end

-- Mini: the settings flow in width and wrap, each a short label and its
-- control; `w` is the control's width, to know whether it fits on the line.
local flow_right, flow_first, flow_indent
local function field(text, short, help, w)
  if not flow_right then panel_label(text, help); return end
  local need = ImGui.CalcTextSize(ctx, short) + ITEM_SPACING_X + w
  if not flow_first then
    local lx = ImGui.GetItemRectMax(ctx)
    if lx + 14 + need <= flow_right then ImGui.SameLine(ctx, 0, 14)
    elseif flow_indent then ImGui.SetCursorPosX(ctx, flow_indent) end -- a new line starts under the fields
  end
  flow_first = false
  if short == '' then label_hl = nil; return end
  ImGui.AlignTextToFramePadding(ctx)
  local hl = draw_label(short)
  tip(text .. (help and ('\n' .. help) or '') .. (hl and own_note() or ''))
  ImGui.SameLine(ctx)
end

local function mixed_note(mixed)
  if mixed then ImGui.SameLine(ctx); ImGui.TextDisabled(ctx, 'mixed') end
end

local PANEL_LINES = 5
local PANEL_SIDE_W = 430 -- width of the panel when it stands at the right of the table

-- Asks for a render: when some of these takes are on muted tracks, a window
-- asks first whether to unmute them or to render only the others.
local function request_render(list)
  local muted = 0
  for _, r in ipairs(list) do if r.asset.muted then muted = muted + 1 end end
  if muted == 0 then S.render_request = list; return end
  S.mute_list, S.mute_open = list, true
end

-- The window of request_render (opened outside any PushID / child).
local function draw_mute_question()
  if not ImGui.BeginPopupModal(ctx, 'Muted tracks', nil, ImGui.WindowFlags_AlwaysAutoResize) then return end
  local list = S.mute_list or {}
  local tracks, seen, unmuted = {}, {}, {}
  for _, r in ipairs(list) do
    if r.asset.muted then
      if not seen[r.asset] then seen[r.asset] = true; tracks[#tracks + 1] = r.asset end
    else
      unmuted[#unmuted + 1] = r
    end
  end
  ImGui.Text(ctx, (#list - #unmuted) .. ' of the ' .. #list .. ' takes to render are on muted tracks:')
  for i, a in ipairs(tracks) do
    if i > 12 then ImGui.TextDisabled(ctx, '... and ' .. (#tracks - 12) .. ' more'); break end
    ImGui.TextDisabled(ctx, '  ' .. a.name)
  end
  ImGui.Spacing(ctx)
  if accent_button('Unmute and render all (' .. #list .. ')') then
    reaper.Undo_BeginBlock2(S.proj or 0)
    for _, a in ipairs(tracks) do
      reaper.SetMediaTrackInfo_Value(a.track, 'B_MUTE', 0)
      a.muted = false
    end
    reaper.Undo_EndBlock2(S.proj or 0, 'FMOD Sync: unmute tracks to render', -1)
    S.render_request, S.mute_list = list, nil
    ImGui.CloseCurrentPopup(ctx)
  end
  ImGui.SameLine(ctx)
  ImGui.BeginDisabled(ctx, #unmuted == 0)
  if ImGui.Button(ctx, 'Render only unmuted (' .. #unmuted .. ')') then
    S.render_request, S.mute_list = unmuted, nil
    ImGui.CloseCurrentPopup(ctx)
  end
  ImGui.EndDisabled(ctx)
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, 'Cancel') then S.mute_list = nil; ImGui.CloseCurrentPopup(ctx) end
  ImGui.EndPopup(ctx)
end

-- Asked when a project is linked: did it send files to FMOD before FMOD Sync?
-- Only then are FMOD files under another prefix offered as its takes
-- ("Similar?"); unanswered counts as no. Saved as cfg.legacy.
local function draw_legacy_question()
  if S.legacy_open then S.legacy_open = false; ImGui.OpenPopup(ctx, 'Linked to FMOD') end
  if not ImGui.BeginPopupModal(ctx, 'Linked to FMOD', nil, ImGui.WindowFlags_AlwaysAutoResize) then return end
  ImGui.Text(ctx, 'Did this project already send files to FMOD before FMOD Sync?')
  ImGui.TextDisabled(ctx, 'Yes: files in FMOD with a take\'s track name under another prefix (Old_Door_01 for Door_01)'
    .. '\nare offered as that take ("Similar?").\nNo: those belong to other projects and are left alone.')
  ImGui.Spacing(ctx)
  if ImGui.Button(ctx, 'Yes, it has old renders') then S.cfg.legacy = true; save_cfg(); ImGui.CloseCurrentPopup(ctx) end
  ImGui.SameLine(ctx)
  if accent_button('No, new project') then S.cfg.legacy = false; save_cfg(); ImGui.CloseCurrentPopup(ctx) end
  ImGui.EndPopup(ctx)
end

-- The window of the "Similar?" button: this take and the FMOD file side by
-- side; Adopt renames and links this take only. "Not the same" is remembered.
local function draw_adopt_question(by_key)
  if S.adopt_ask and not S.adopt_ask.opened then
    S.adopt_ask.opened = true
    ImGui.OpenPopup(ctx, 'Same sound?')
  end
  if not ImGui.BeginPopupModal(ctx, 'Same sound?', nil, ImGui.WindowFlags_AlwaysAutoResize) then return end
  local r = S.adopt_ask and by_key[S.adopt_ask.key]
  if not r or r.st.kind ~= 'similar' then
    S.adopt_ask = nil
    ImGui.CloseCurrentPopup(ctx)
    ImGui.EndPopup(ctx)
    return
  end
  local st = r.st
  local dir, template = adoption(r)
  local tn, ln = take_numbers(r.asset)
  local vars = { track = r.asset.name, item = r.block.label or '', index = index_text(ln[r.key] or r.index) }
  local new_name = take_name(template or r.template, vars, tn[r.key])
  local fch = S.audio_ch and S.audio_ch[st.path]
  ImGui.Text(ctx, 'Is this take the file already in FMOD?')
  ImGui.Spacing(ctx)
  if ImGui.BeginTable(ctx, 'adopt_cmp', 3, ImGui.TableFlags_BordersInnerH | ImGui.TableFlags_SizingFixedFit) then
    local function line(a, b, c)
      ImGui.TableNextRow(ctx)
      ImGui.TableNextColumn(ctx); ImGui.TextDisabled(ctx, a)
      ImGui.TableNextColumn(ctx); ImGui.Text(ctx, b)
      ImGui.TableNextColumn(ctx); ImGui.Text(ctx, c)
    end
    line('', 'This take', 'In FMOD')
    line('Name', r.name, st.base)
    line('Folder', folder_label(r.folder), folder_label(st.dir))
    line('Ch', tostring(r.ch), fch and tostring(fch) or '?')
    line('Track', r.asset.name, '')
    ImGui.EndTable(ctx)
  end
  ImGui.Spacing(ctx)
  ImGui.TextDisabled(ctx, 'Adopt renames this take to ' .. new_name .. ' and links it to ' .. folder_label(dir)
    .. ':\nits next render overwrites that file. Only this take.')
  ImGui.Spacing(ctx)
  if ImGui.Button(ctx, 'Adopt this take') then
    set_name({ r }, template)
    -- This take's folder only: the asset's other takes do not follow it.
    local acfg = S.cfg.assets[r.asset.guid]
    take_cfg(r.key).folder = (acfg and acfg.folder == dir) and nil or dir
    prune_take(r.key)
    save_cfg()
    S.adopt_ask = nil
    ImGui.CloseCurrentPopup(ctx)
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, 'Not the same sound') then
    take_cfg(r.key).not_similar = st.path
    save_cfg()
    S.adopt_ask = nil
    ImGui.CloseCurrentPopup(ctx)
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, 'Cancel') then S.adopt_ask = nil; ImGui.CloseCurrentPopup(ctx) end
  ImGui.EndPopup(ctx)
end

-- Render All and Render Selected. Takes with no FMOD folder are never rendered.
local function draw_render_buttons(sel, side)
  local all = {}
  for _, r in ipairs(S.order or {}) do if r.folder ~= nil then all[#all + 1] = r end end
  local chosen = {}
  if panel_scope == 'take' then
    for _, r in ipairs(sel) do if r.folder ~= nil then chosen[#chosen + 1] = r end end
  end
  local all_label = 'Render All (' .. #all .. ')'
  local sel_label = 'Render Selected (' .. #chosen .. ')'
  if not side then align_right(button_width(all_label) + button_width(sel_label) + ITEM_SPACING_X) end
  ImGui.BeginDisabled(ctx, #all == 0)
  if ImGui.Button(ctx, all_label) then request_render(all) end
  ImGui.EndDisabled(ctx)
  tip('Renders every take shown that has an FMOD folder (the filter applies). Muted tracks: asks first.')
  ImGui.SameLine(ctx)
  ImGui.BeginDisabled(ctx, #chosen == 0)
  if accent_button(sel_label) then request_render(chosen) end
  ImGui.EndDisabled(ctx)
  tip('Renders the selected takes that have an FMOD folder. Muted tracks: asks first.')
end

-- side: the panel stands at the left of the table, one column of settings;
-- otherwise it lies under it, two columns.
-- mini: FMOD Sync Mini, three columns in width with the render buttons in the
-- last one; title: the line above the settings.
local function draw_selection_panel(sel, side, mini)
  local n = #sel
  local na = #assets_of(sel)
  if mini == 'basic' then
    -- Mini: Name, Folder and Ch on lines of their own; the other render
    -- settings follow Ch and wrap under the fields.
    flow_right, flow_first = ImGui.GetCursorScreenPos(ctx) + ImGui.GetContentRegionAvail(ctx), true
  elseif mini then
  else
    ImGui.AlignTextToFramePadding(ctx)
    if panel_scope == 'asset' then
      ImGui.Text(ctx, na == 1 and ('Track ' .. sel[1].asset.name) or (na .. ' tracks selected'))
      tip('No take selected: render settings go to the track and every take of it\n'
        .. 'renders with them, except the takes with settings of their own (*).')
    else
      ImGui.Text(ctx, n == 1 and sel[1].name or (n .. ' takes selected'))
      tip('Render settings set here belong to the selected takes and win over their track\'s.\n'
        .. 'With no take selected they go to the tracks selected in REAPER.')
    end
  end
  if not side and not mini then
    ImGui.SameLine(ctx)
    draw_render_buttons(sel, side)
  elseif side then
    ImGui.Spacing(ctx); ImGui.Separator(ctx); ImGui.Spacing(ctx)
  end
  -- Two columns of settings under the table, one at its side; Mini flows.
  local cols = not side and not mini and ImGui.BeginTable(ctx, 'panel', 2, ImGui.TableFlags_SizingStretchSame)
  if not side and not mini and not cols then return end
  if cols then ImGui.TableNextRow(ctx); ImGui.TableNextColumn(ctx) end

  if mini ~= 'advanced' then
  -- Name
  local template, tmixed = sel[1].template, false
  for i = 2, n do if sel[i].template ~= template then tmixed = true end end
  local default_label = 'Default'
  -- Mini: Name on a line of its own, as wide as the panel; Folder starts the next one.
  local mini_label_w = math.max((ImGui.CalcTextSize(ctx, 'Name')), (ImGui.CalcTextSize(ctx, 'Folder')),
    (ImGui.CalcTextSize(ctx, 'Ch'))) + ITEM_SPACING_X
  if mini == 'basic' then
    panel_label_w = mini_label_w
    flow_indent = mini_label_w
    panel_label('Name', wildcard_help())
  else
    field('Name', 'Name', wildcard_help(), 0)
  end
  -- Same line: the selected takes are takes of one line (see take_numbers).
  -- Shown with 2+ takes selected, or 1 take in a line (to take it out).
  local g1 = S.cfg.takes[sel[1].key] and S.cfg.takes[sel[1].key].group
  local same = g1 ~= nil
  for i = 2, n do
    local t = S.cfg.takes[sel[i].key]
    if not (t and t.group == g1) then same = false end
  end
  local same_label = 'Same line'
  local show_same = n >= 2 or g1 ~= nil
  local inner_x = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemInnerSpacing)
  local same_w = show_same and (ImGui.GetFrameHeight(ctx) + inner_x + ImGui.CalcTextSize(ctx, same_label) + ITEM_SPACING_X) or 0
  ImGui.SetNextItemWidth(ctx, -(button_width(default_label) + ITEM_SPACING_X + same_w))
  if S.panel_name_key ~= sel[1].key .. n or not S.panel_name_active then
    S.panel_name, S.panel_name_key = tmixed and '' or template, sel[1].key .. n
  end
  local _, nv = ImGui.InputTextWithHint(ctx, '##name', tmixed and 'mixed: type to set all' or '', S.panel_name)
  S.panel_name = nv
  S.panel_name_active = ImGui.IsItemActive(ctx)
  if ImGui.IsItemDeactivatedAfterEdit(ctx) then set_name(sel, S.panel_name); S.panel_name_active = false end
  tip(wildcard_help() .. '\nEmpty: the project\'s name.')
  if show_same then
    ImGui.SameLine(ctx)
    local c, v = ImGui.Checkbox(ctx, same_label, same)
    if c then set_same_line(sel, v and n >= 2) end
    tip(n >= 2 and ('Takes of one line: each gets _01, _02... after its name, in time order.'
      .. ' The line counts as one for $index: the take after it has the next number.')
      or 'This take is in a line with other takes: unticked, it leaves it.')
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, default_label) then
    set_name(sel, '')
    S.panel_name_key = nil
  end
  tip('Back to the project\'s name (Settings > Name: ' .. default_template() .. ') for the selected takes.')

  -- Folder
  local folder, fmixed = sel[1].folder, false
  for i = 2, n do if sel[i].folder ~= folder then fmixed = true end end
  local folder_text = (fmixed and 'mixed' or folder_label(folder) or 'none')
  if mini == 'basic' then
    panel_label('Folder', 'The FMOD folder of these takes.')
    if ImGui.Button(ctx, folder_text .. '##folder') then open_picker(sel) end
  else
    field('FMOD folder', 'Folder', nil, ImGui.CalcTextSize(ctx, folder_text) + 12)
    if ImGui.SmallButton(ctx, folder_text .. '##folder') then open_picker(sel) end
  end
  tip('Choose the FMOD folder of the selected takes.')

  -- Channels
  local ch, chmixed = common(sel, 'channels')
  if mini == 'basic' then
    -- Mini: Ch starts the third line, Render settings follows it.
    label_hl = own_hl(sel, 'channels')
    panel_label('Ch', 'Channels. Auto: the channel count of the folder track. 1 = mono.')
    panel_label_w = PANEL_LABEL_W
    flow_first = false
  else
    label_hl = own_hl(sel, 'channels')
    field('Channels', 'Ch', 'Auto: the channel count of the folder track. 1 = mono.', mini and 100 or 160)
  end
  ImGui.SetNextItemWidth(ctx, mini and 82 or 160)
  local function ch_label(c)
    if c == nil then return na == 1 and ('Auto (' .. sel[1].asset.nchan .. ')') or 'Auto' end
    return c == 1 and '1 (mono)' or tostring(c)
  end
  if ImGui.BeginCombo(ctx, '##ch', chmixed and 'mixed' or ch_label(ch)) then
    if ImGui.Selectable(ctx, ch_label(nil), not chmixed and ch == nil) then set_render(sel, 'channels', nil) end
    for _, c in ipairs(CHANNELS) do
      if ImGui.Selectable(ctx, ch_label(c), not chmixed and ch == c) then set_render(sel, 'channels', c) end
    end
    ImGui.EndCombo(ctx)
  end
  end

  -- Mini: the other render settings follow Ch on its line, wrapping under it.

  if cols then ImGui.TableNextColumn(ctx) end

  -- Sample rate
  local sr, srmixed = common(sel, 'srate')
  label_hl = own_hl(sel, 'srate')
  field('Sample rate', 'Rate', 'Project: the sample rate of the REAPER project (' .. project_srate() .. ' Hz).', mini and 82 or 160)
  ImGui.SetNextItemWidth(ctx, mini and 82 or 160)
  local function sr_label(v) return v == nil and ('Project (' .. project_srate() .. ' Hz)') or (v .. ' Hz') end
  -- Mini: the closed combo shows it short (Project, 48k); the list in full.
  local function sr_short(v) return v == nil and 'Project' or ((v % 1000 == 0) and (v // 1000 .. 'k') or (v / 1000 .. 'k')) end
  if ImGui.BeginCombo(ctx, '##srate', srmixed and 'mixed' or (mini and sr_short(sr) or sr_label(sr))) then
    if ImGui.Selectable(ctx, sr_label(nil), not srmixed and sr == nil) then set_render(sel, 'srate', nil) end
    for _, v in ipairs(SRATES) do
      if ImGui.Selectable(ctx, v .. ' Hz', not srmixed and sr == v) then set_render(sel, 'srate', v) end
    end
    ImGui.EndCombo(ctx)
  end

  -- Tail: a checkbox and the seconds. Off (tail 0), the field shows what the
  -- reverbs of the stem suggest; ticking it takes that value, each asset its
  -- own. It never turns on by itself.
  local tail, tmx = common(sel, 'tail')
  local tail_on = (tail or 0) > 0
  local sugg, sugg_tip = tail_suggestion(sel)
  label_hl = own_hl(sel, 'tail')
  field('Tail', 'Tail', 'Seconds added after the end of the take.',
    ImGui.GetFrameHeight(ctx) + ITEM_SPACING_X + 44 + ImGui.CalcTextSize(ctx, 's') + 8)
  local c0, on = ImGui.Checkbox(ctx, '##tail_on', tail_on)
  tip('Adds a tail after the end of the take.\n' .. sugg_tip)
  if c0 then
    if on then
      for _, a in ipairs(assets_of(sel)) do
        local rows_a = {}
        for _, r in ipairs(sel) do if r.asset == a then rows_a[#rows_a + 1] = r end end
        set_render(rows_a, 'tail', reverb_tail_of(a) or TAIL_NO_REVERB)
      end
    else
      set_render(sel, 'tail', 0)
    end
  end
  ImGui.SameLine(ctx)
  ImGui.BeginDisabled(ctx, not tail_on)
  ImGui.SetNextItemWidth(ctx, mini and 44 or 122)
  local c1, tv = ImGui.InputDouble(ctx, mini and '##tail' or 's##tail', tail_on and tail or (sugg or 0),
    mini and 0 or 0.1, mini and 0 or 0.5, '%.2f')
  tip(sugg_tip)
  if mini then ImGui.SameLine(ctx); ImGui.AlignTextToFramePadding(ctx); ImGui.TextDisabled(ctx, 's') end
  if c1 and tail_on then set_render(sel, 'tail', math.max(0, tv)) end
  ImGui.EndDisabled(ctx)
  mixed_note(tmx)

  -- 2nd pass
  local sp, spmixed = common(sel, 'second_pass')
  label_hl = own_hl(sel, 'second_pass')
  field('2nd pass', mini and '2-pass' or '2nd pass', nil, ImGui.GetFrameHeight(ctx))
  local c2, spv = ImGui.Checkbox(ctx, '##second_pass', sp == true)
  if c2 then set_render(sel, 'second_pass', spv) end
  mixed_note(spmixed)


  -- Normalize and limiter: a checkbox and the value next to it.
  local function level(key, label, short, unit, default, help, lo, hi)
    local v, mixed = common(sel, key)
    if mini then unit = (unit:gsub('%-I$', '')) end
    label_hl = own_hl(sel, key)
    field(label, mini and short or label, help, ImGui.GetFrameHeight(ctx) + ITEM_SPACING_X + 44 + ImGui.CalcTextSize(ctx, unit) + 8)
    local c, on = ImGui.Checkbox(ctx, '##' .. key .. '_on', v ~= nil)
    if c then set_render(sel, key, on and (v or default) or nil) end
    ImGui.SameLine(ctx)
    ImGui.BeginDisabled(ctx, v == nil)
    ImGui.SetNextItemWidth(ctx, mini and 44 or 122)
    local c2, nv = ImGui.InputDouble(ctx, (mini and '##v' or unit .. '##') .. key, v or default,
      mini and 0 or 0.5, mini and 0 or 1, '%.1f')
    if mini then ImGui.SameLine(ctx); ImGui.AlignTextToFramePadding(ctx); ImGui.TextDisabled(ctx, unit) end
    if c2 then set_render(sel, key, math.min(hi, math.max(lo, nv))) end
    ImGui.EndDisabled(ctx)
    mixed_note(mixed)
  end
  level('normalize', 'Normalize', 'Norm', 'LUFS-I', -24, 'Normalizes every file to this integrated loudness (LUFS-I).', -60, 0)
  level('limit', 'Limiter', 'Limit', 'dB', 0, 'Brickwall limiter at this ceiling, after the normalization.', -30, 0)

  -- Takes with settings of their own: back to their track's.
  if panel_scope == 'take' then
    local own = false
    for _, r in ipairs(sel) do if r.own_render then own = true end end
    if own then
      -- In line with the render settings: after Limiter, or flowing in Mini.
      local label = 'Use track settings##take_render'
      if flow_right then field('', '', nil, button_width('Use track settings'))
      else ImGui.SameLine(ctx, 0, 14) end
      if ImGui.Button(ctx, label) then clear_take_render(sel) end
      tip('Drops the render settings of the selected takes: they render with their track\'s again.')
    end
  end

  flow_right, flow_indent = nil, nil
  if cols then ImGui.EndTable(ctx) end
  if side then
    -- At the side the render buttons close the settings.
    ImGui.Spacing(ctx); ImGui.Separator(ctx); ImGui.Spacing(ctx)
    draw_render_buttons(sel, side)
  end
end

local COLUMNS = { '', 'File', 'Ch', 'Status' }
local draw_gear -- defined with the window, used by the toolbar
local footer_status -- defined with the footer, used by Mini

-- The rows of every take, after the links that need no one: auto-linked takes
-- and the moves of a folder just chosen in the picker.
local function prepare_rows()
  local rows, by_key = build_rows()
  -- A take with no folder whose exact file name is in one FMOD folder is
  -- linked to it on its own: nothing to check. "No folder" takes stay out.
  local auto = {}
  for _, r in ipairs(rows) do
    if r.folder == nil and not r.no_folder and r.st.kind == 'found' then auto[#auto + 1] = r end
  end
  if #auto > 0 then
    for _, r in ipairs(auto) do set_folder({ r }, r.st.dir) end
    rows, by_key = build_rows()
  end
  -- Folder just chosen in the picker: the takes whose file is in FMOD move there.
  if S.auto_move then
    local list = {}
    for _, r in ipairs(rows) do
      if S.auto_move[r.key] and r.st.kind == 'renamed' and r.st.moved and not r.st.renamed then list[#list + 1] = r end
    end
    S.auto_move = nil
    if #list > 0 and link.status == 'online' and fmod_has_linked_project() then rename_in_fmod(list) end
  end
  return rows, by_key
end

-- The top-level folder track above a track (the track itself when it has none).
local function top_track(tr)
  while true do
    local up = reaper.GetParentTrack(tr)
    if not up then return tr end
    tr = up
  end
end

-- The takes of the items selected in REAPER: an asset's folder item is its
-- take; an item on one of its child tracks belongs to the take whose time
-- range it overlaps. Returns keys (key -> true), their top-level tracks
-- (track -> true) and a signature of the item selection.
local function selected_item_takes(rows)
  local proj = S.proj or 0
  local n = reaper.CountSelectedMediaItems(proj)
  local keys, tops, guids = {}, {}, {}
  if n == 0 then return keys, tops, '' end
  local by_track = {}
  for _, r in ipairs(rows) do
    local l = by_track[r.asset.track] or {}
    l[#l + 1] = r
    by_track[r.asset.track] = l
  end
  for i = 0, n - 1 do
    local it = reaper.GetSelectedMediaItem(proj, i)
    local _, guid = reaper.GetSetMediaItemInfo_String(it, 'GUID', '', false)
    guids[#guids + 1] = guid
    local top = top_track(reaper.GetMediaItem_Track(it))
    local list = by_track[top]
    if list then
      tops[top] = true
      local s = reaper.GetMediaItemInfo_Value(it, 'D_POSITION')
      local e = s + reaper.GetMediaItemInfo_Value(it, 'D_LENGTH')
      local hit = false
      for _, r in ipairs(list) do
        if r.block.guid == guid then keys[r.key] = true; hit = true end
      end
      if not hit then
        for _, r in ipairs(list) do
          if s < r.block[2] and e > r.block[1] then keys[r.key] = true end
        end
      end
    end
  end
  return keys, tops, table.concat(guids, ' ')
end

-- When the items selected in REAPER change, the takes they belong to become
-- the selection. clear: with no item selected any more, nothing is selected.
local function follow_item_selection(rows, clear)
  local keys, tops, sig = selected_item_takes(rows)
  if sig ~= S.item_sig then
    S.item_sig = sig
    if next(keys) then S.sel, S.anchor = keys, nil
    elseif clear then S.sel, S.anchor = {}, nil end
  end
  return tops
end

local function draw_assets()
  if #S.assets == 0 then
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.TextDisabled(ctx, 'No takes: each top-level folder track with items is an asset.')
    return
  end
  local rows, by_key = prepare_rows()

  -- Shown rows: the filter, then the header's order.
  local words = filter_words(S.filter)
  local shown = {}
  for _, r in ipairs(rows) do
    if filter_match(words, r.name, r.asset.name) then
      shown[#shown + 1] = r
    end
  end
  follow_item_selection(rows, false)
  -- Selected takes no longer there are forgotten.
  for k in pairs(S.sel) do if not by_key[k] then S.sel[k] = nil end end
  local sel_before = selected_rows()
  -- No take selected: the panel edits the tracks selected in REAPER (their
  -- render settings belong to the track).
  local function panel_rows(sel)
    if #sel > 0 then panel_scope = 'take'; return sel end
    panel_scope = 'asset'
    local tops, out = {}, {}
    for i = 0, reaper.CountSelectedTracks(S.proj or 0) - 1 do
      tops[top_track(reaper.GetSelectedTrack(S.proj or 0, i))] = true
    end
    for _, r in ipairs(shown) do if tops[r.asset.track] then out[#out + 1] = r end end
    return out
  end
  local panel_before = panel_rows(sel_before)

  -- Not resizable: the File column is as wide as the longest file name shown,
  -- Ch and Status follow it, the rest of the width stays empty.
  local flags = ImGui.TableFlags_Borders | ImGui.TableFlags_RowBg | ImGui.TableFlags_ScrollY
    | ImGui.TableFlags_ScrollX | ImGui.TableFlags_Sortable | ImGui.TableFlags_NoSavedSettings
  local file_w = ImGui.CalcTextSize(ctx, 'File') + 40
  for _, r in ipairs(shown) do
    local w = ImGui.CalcTextSize(ctx, r.name) + 24
    if w > file_w then file_w = w end
  end
  -- The selection's panel: at the left when the table leaves room for it, else under it.
  local avail_w, avail_h = ImGui.GetContentRegionAvail(ctx)
  local table_need = 18 + file_w + 40 + 130 + 48 -- the columns, borders and the scrollbar
  -- Decided by the file names alone, selected or not, so the layout stays put.
  local side = avail_w >= table_need + PANEL_SIDE_W + ITEM_SPACING_X
  local panel_h, table_w = 0, 0
  if side then
    table_w = avail_w - PANEL_SIDE_W - ITEM_SPACING_X
  elseif #panel_before > 0 then
    panel_h = ImGui.GetFrameHeightWithSpacing(ctx) * (PANEL_LINES + 1) + 20
  else
    panel_h = ImGui.GetFrameHeightWithSpacing(ctx) + 10
  end
  if side then
    -- At the left of the table: what was selected when this frame began.
    if ImGui.BeginChild(ctx, 'side_panel', PANEL_SIDE_W, math.max(120, avail_h)) then
      if #panel_before > 0 then
        draw_selection_panel(panel_before, true)
      else
        ImGui.PushTextWrapPos(ctx, 0)
        ImGui.TextDisabled(ctx, 'Select takes (or tracks in REAPER) to edit their name, folder and render settings (Cmd/Ctrl+A: all).')
        ImGui.PopTextWrapPos(ctx)
        draw_render_buttons(sel_before, true)
      end
      ImGui.EndChild(ctx)
    end
    ImGui.SameLine(ctx)
  end
  -- Filter and render report right above the table, aligned with it.
  ImGui.BeginGroup(ctx)
  ImGui.SetNextItemWidth(ctx, 220)
  local _, f = ImGui.InputTextWithHint(ctx, '##filter', 'filter', S.filter)
  S.filter = f
  if S.render_report then
    ImGui.PushTextWrapPos(ctx, side and (ImGui.GetCursorPosX(ctx) + table_w) or 0)
    ImGui.TextColored(ctx, S.render_report.col, S.render_report.text)
    ImGui.PopTextWrapPos(ctx)
  end
  local _, table_avail_h = ImGui.GetContentRegionAvail(ctx)
  if ImGui.BeginTable(ctx, 'take_table', #COLUMNS, flags, table_w, math.max(120, table_avail_h - panel_h)) then
    ImGui.TableSetupScrollFreeze(ctx, 0, 1)
    ImGui.TableSetupColumn(ctx, '##drag', ImGui.TableColumnFlags_WidthFixed | ImGui.TableColumnFlags_NoSort, 18, 0)
    ImGui.TableSetupColumn(ctx, 'File', ImGui.TableColumnFlags_WidthFixed, file_w, 1)
    ImGui.TableSetupColumn(ctx, 'Ch', ImGui.TableColumnFlags_WidthFixed, 40, 3)
    ImGui.TableSetupColumn(ctx, 'Status', ImGui.TableColumnFlags_WidthFixed, 130, 4)
    ImGui.TableHeadersRow(ctx)
    local need, has_specs = ImGui.TableNeedSort(ctx)
    if need then
      S.sort = nil
      if has_specs then
        local ok, _, user_id, dir = ImGui.TableGetColumnSortSpecs(ctx, 0)
        if ok then S.sort = { col = user_id, asc = dir ~= ImGui.SortDirection_Descending } end
      end
    end
    sort_rows(shown)
    S.order = shown
    for _, r in ipairs(shown) do
      ImGui.PushID(ctx, r.key)
      ImGui.TableNextRow(ctx)
      if S.sel[r.key] then ImGui.TableSetBgColor(ctx, ImGui.TableBgTarget_RowBg1, COL_ROW_SELECTED) end

      ImGui.TableNextColumn(ctx)
      draw_drag_cell(r, shown)

      ImGui.TableNextColumn(ctx)
      draw_file_cell(r)

      ImGui.TableNextColumn(ctx)
      ImGui.AlignTextToFramePadding(ctx)
      ImGui.Text(ctx, tostring(r.ch) .. (r.overridden and '*' or ''))
      tip(r.own_render and 'This take has render settings of its own (*), over its track\'s.'
        or r.overridden and 'Its track has render settings of its own (*).' or 'Default render settings.')

      ImGui.TableNextColumn(ctx)
      draw_status_cell(r, rows)
      ImGui.PopID(ctx)
    end
    ImGui.EndTable(ctx)
  end
  ImGui.EndGroup(ctx)

  local sel = panel_rows(selected_rows())
  if side then
    -- Drawn at the left, before the table.
  elseif #sel == 0 then
    ImGui.Spacing(ctx)
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.TextDisabled(ctx, 'Select takes (or tracks in REAPER) to edit their name, folder and render settings (Cmd/Ctrl+A: all).')
    ImGui.SameLine(ctx)
    draw_render_buttons(sel, false)
  else
    ImGui.Spacing(ctx)
    draw_selection_panel(sel, false)
  end

  if S.pick_open then S.pick_open = false; ImGui.OpenPopup(ctx, 'pick_folder') end
  if S.mute_open then S.mute_open = false; ImGui.OpenPopup(ctx, 'Muted tracks') end
  draw_mute_question()
  draw_adopt_question(by_key)
  draw_legacy_question()
  draw_folder_picker(by_key, rows)
end

------------------------------------------------------------------------------
-- FMOD Sync Mini: the takes of the tracks selected in REAPER (a selected track
-- stands for the top-level folder track above it), a short list at the left and
-- the settings in three columns at its right; one under the other when the
-- dock is narrow. With no take clicked in the list, the settings and Render
-- apply to every take of the selected tracks.

local MINI_PANEL_MIN_W = 420
-- The list's scrollbar at its left: the track is a square outline as tall as
-- the list (its border's colour), the grab a narrower bar inside it (filling
-- the track when there is nothing to scroll).
local MINI_SB_W, MINI_SB_GAP, MINI_SB_GRAB_W = 10, 2, 4
local MINI_SB_INSET_Y, MINI_SB_MARGIN_Y = 0, 3
local MINI_SB_GRAB_COL, MINI_SB_GRAB_HOVER_COL = 0x404040FF, 0x606060FF

-- Moves the scroll of the current window (the list's table) from the strip at
-- x, y (screen), h tall; held / pressed: the strip's invisible button.
-- Returns what to draw after EndTable (while the table is open its clip
-- rectangle hides anything outside it).
local function left_scrollbar(x, y, h, held, pressed, hover)
  local max_y = ImGui.GetScrollMaxY(ctx)
  local top, bottom = y + MINI_SB_INSET_Y, y + h - MINI_SB_INSET_Y
  -- The grab travels inside the track, never touching its outline.
  local itop = top + MINI_SB_MARGIN_Y
  local th = bottom - top - 2 * MINI_SB_MARGIN_Y
  local grab_h, grab_top = th, itop
  if max_y > 0 then
    grab_h = math.min(th, math.max(24, th * h / (h + max_y)))
    grab_top = itop + ImGui.GetScrollY(ctx) / max_y * (th - grab_h)
  end
  local _, my = ImGui.GetMousePos(ctx)
  if pressed then
    -- On the grab: it keeps the point held; on the track: its centre jumps there.
    S.sb_offset = (my >= grab_top and my <= grab_top + grab_h) and (my - grab_top) or grab_h / 2
  end
  if held and max_y > 0 and th > grab_h then
    local v = (my - (S.sb_offset or grab_h / 2) - itop) / (th - grab_h) * max_y
    ImGui.SetScrollY(ctx, math.min(math.max(v, 0), max_y))
  end
  local gx = x + (MINI_SB_W - MINI_SB_GRAB_W) / 2
  return { x = x, top = top, bottom = bottom, gx = gx, gt = grab_top, gh = grab_h,
    col = (held or hover) and max_y > 0 and MINI_SB_GRAB_HOVER_COL or MINI_SB_GRAB_COL }
end

local function draw_left_scrollbar(dl, sb)
  ImGui.DrawList_AddRect(dl, sb.x, sb.top, sb.x + MINI_SB_W, sb.bottom, ImGui.GetColor(ctx, ImGui.Col_TableBorderStrong))
  ImGui.DrawList_AddRectFilled(dl, sb.gx, sb.gt, sb.gx + MINI_SB_GRAB_W, sb.gt + sb.gh, sb.col)
end

-- Top-level folder tracks of the tracks selected in REAPER: track -> true.
local function selected_tops()
  local set = {}
  local proj = S.proj or 0
  for i = 0, reaper.CountSelectedTracks(proj) - 1 do
    set[top_track(reaper.GetSelectedTrack(proj, i))] = true
  end
  return set
end

-- Mini: FMOD Studio's state in full (its colour tells it), then the gear, at the
-- bottom right of the current child, never above min_y (the last line drawn).
local function draw_mini_status(min_y)
  local h = ImGui.GetFrameHeight(ctx)
  local _, win_h = ImGui.GetWindowSize(ctx)
  ImGui.SetCursorPosY(ctx, math.max(win_h - h, min_y))
  local col, stext, shelp = footer_status()
  align_right(ImGui.CalcTextSize(ctx, stext) + 2 * (ITEM_SPACING_X + h))
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.TextColored(ctx, col, stext)
  tip(shelp)
  ImGui.SameLine(ctx)
  draw_gear()
end

local function draw_mini()
  local rows, by_key = prepare_rows()
  -- The assets of the selected tracks and of the selected items.
  local tops = selected_tops()
  local item_keys, item_tops, item_sig = selected_item_takes(rows)
  for t in pairs(item_tops) do tops[t] = true end
  local shown = {}
  for _, r in ipairs(rows) do if tops[r.asset.track] then shown[#shown + 1] = r end end
  -- Another set of takes: the takes clicked before are forgotten.
  local keys = {}
  for _, r in ipairs(shown) do keys[#keys + 1] = r.key end
  local sig = table.concat(keys, ' ')
  -- Just docked: the takes selected in the full window stay selected when shown here.
  if S.mini_enter then
    S.mini_enter, S.mini_sig = nil, sig
    local keep = {}
    for _, r in ipairs(shown) do if S.sel[r.key] then keep[r.key] = true end end
    S.sel, S.anchor = keep, nil
  end
  if sig ~= S.mini_sig then S.mini_sig, S.sel, S.anchor = sig, {}, nil end
  -- Selected items: their takes are the ones clicked (Render renders them).
  if item_sig ~= S.item_sig then
    S.item_sig = item_sig
    S.sel, S.anchor = next(item_keys) and item_keys or {}, nil
  end

  if #shown == 0 then
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.TextDisabled(ctx, #S.assets == 0 and 'No assets in this project.'
      or 'No asset selected.')
    draw_mini_status(ImGui.GetCursorPosY(ctx))
  else
    sort_rows(shown)
    S.order = shown
    local clicked = selected_rows()
    local target = #clicked > 0 and clicked or shown
    -- Takes clicked (or items selected): settings per take; none: per track.
    panel_scope = #clicked > 0 and 'take' or 'asset'
    local file_w = ImGui.CalcTextSize(ctx, 'File') + 40
    for _, r in ipairs(shown) do
      local w = ImGui.CalcTextSize(ctx, r.name) + 24
      if w > file_w then file_w = w end
    end
    local list_w = 18 + file_w + 40 + 130 + 38
    local avail_w, avail_h = ImGui.GetContentRegionAvail(ctx)
    local wide = avail_w >= list_w + ITEM_SPACING_X + MINI_PANEL_MIN_W
    if not wide then list_w = avail_w end
    local list_h = wide and avail_h
      or math.min(avail_h * 0.4, ImGui.GetFrameHeightWithSpacing(ctx) * (#shown + 1) + 8)
    -- The list's scrollbar stands at its left (as in mtt_Shelf): the native
    -- one is hidden (size 0, the wheel still scrolls) and a strip left of the
    -- table drives the table's scroll.
    local table_h = math.max(60, list_h)
    local sb_x, sb_y = ImGui.GetCursorScreenPos(ctx)
    ImGui.InvisibleButton(ctx, '##list_scrollbar', MINI_SB_W, table_h)
    local sb_held, sb_pressed = ImGui.IsItemActive(ctx), ImGui.IsItemActivated(ctx)
    local sb_hover = ImGui.IsItemHovered(ctx)
    local outer_dl = ImGui.GetWindowDrawList(ctx)
    ImGui.SameLine(ctx, 0, MINI_SB_GAP)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_ScrollbarSize, 0)
    local table_open = ImGui.BeginTable(ctx, 'mini_table', 4, ImGui.TableFlags_Borders | ImGui.TableFlags_RowBg
        | ImGui.TableFlags_ScrollY | ImGui.TableFlags_NoSavedSettings | ImGui.TableFlags_Sortable,
        list_w - MINI_SB_W - MINI_SB_GAP, table_h)
    ImGui.PopStyleVar(ctx)
    if table_open then
      ImGui.TableSetupScrollFreeze(ctx, 0, 1)
      -- Same ids as the big table's columns (sort_rows): 1 = file name, 3 = channels, 4 = status.
      ImGui.TableSetupColumn(ctx, '##drag', ImGui.TableColumnFlags_WidthFixed | ImGui.TableColumnFlags_NoSort, 18, 0)
      ImGui.TableSetupColumn(ctx, 'File', ImGui.TableColumnFlags_WidthStretch, 0, 1)
      ImGui.TableSetupColumn(ctx, 'Ch', ImGui.TableColumnFlags_WidthFixed, 40, 3)
      ImGui.TableSetupColumn(ctx, 'Status', ImGui.TableColumnFlags_WidthFixed, 130, 4)
      ImGui.TableHeadersRow(ctx)
      local need, has_specs = ImGui.TableNeedSort(ctx)
      if need then
        S.sort = nil
        if has_specs then
          local ok, _, user_id, dir = ImGui.TableGetColumnSortSpecs(ctx, 0)
          if ok then S.sort = { col = user_id, asc = dir ~= ImGui.SortDirection_Descending } end
        end
        sort_rows(shown)
      end
      for _, r in ipairs(shown) do
        ImGui.PushID(ctx, r.key)
        ImGui.TableNextRow(ctx)
        if S.sel[r.key] then ImGui.TableSetBgColor(ctx, ImGui.TableBgTarget_RowBg1, COL_ROW_SELECTED) end
        ImGui.TableNextColumn(ctx)
        draw_drag_cell(r, shown)
        ImGui.TableNextColumn(ctx)
        -- A click on the only take clicked lets it go: back to all of them.
        local only = S.sel[r.key] and #clicked == 1 and ImGui.GetKeyMods(ctx) == 0
        ImGui.AlignTextToFramePadding(ctx)
        local col = (#r.unknown > 0 or r.dup or r.name == '') and COL_WARN or nil
        if col then ImGui.PushStyleColor(ctx, ImGui.Col_Text, col) end
        local label = (r.name == '' and '(no name)' or r.name):gsub('##', '# #')
        local hit = ImGui.Selectable(ctx, label .. '##file', false)
        if col then ImGui.PopStyleColor(ctx) end
        if hit then
          if only then S.sel, S.anchor = {}, nil; select_time(shown) else click_row(r) end
        end
        tip('Take ' .. r.index .. ' of ' .. r.asset.name .. ' (' .. r.ch .. ' ch).\n'
          .. 'Click: only this take; click it again: all of them. Shift / Cmd click: more.')
        ImGui.TableNextColumn(ctx)
        ImGui.AlignTextToFramePadding(ctx)
        ImGui.Text(ctx, tostring(r.ch) .. (r.overridden and '*' or ''))
        tip(r.own_render and 'This take has render settings of its own (*), over its track\'s.'
        or r.overridden and 'Its track has render settings of its own (*).' or 'Default render settings.')
        ImGui.TableNextColumn(ctx)
        draw_status_cell(r, rows)
        ImGui.PopID(ctx)
      end
      -- Here the current window is the table's: its scroll.
      local sb = left_scrollbar(sb_x, sb_y, table_h, sb_held, sb_pressed, sb_hover)
      ImGui.EndTable(ctx)
      draw_left_scrollbar(outer_dl, sb)
    end
    if wide then ImGui.SameLine(ctx) end
    if ImGui.BeginChild(ctx, 'mini_panel', 0, wide and avail_h or 0) then
      draw_selection_panel(target, false, 'basic')
      -- Under Ch, aligned with the fields: Render, then the render report;
      -- FMOD's state and the gear at the right of the same line.
      local h = ImGui.GetFrameHeight(ctx)
      local list = {}
      for _, r in ipairs(target) do if r.folder ~= nil then list[#list + 1] = r end end
      local rlabel = 'Render (' .. #list .. ')'
      local field_x = math.max((ImGui.CalcTextSize(ctx, 'Name')), (ImGui.CalcTextSize(ctx, 'Folder')),
        (ImGui.CalcTextSize(ctx, 'Ch'))) + ITEM_SPACING_X
      ImGui.SetCursorPosX(ctx, field_x)
      local render_y = ImGui.GetCursorPosY(ctx)
      ImGui.BeginDisabled(ctx, #list == 0)
      if accent_button(rlabel) then request_render(list) end
      ImGui.EndDisabled(ctx)
      tip((#clicked > 0 and 'Renders the takes clicked' or 'Renders every take of the selected tracks')
        .. ' that has an FMOD folder, then syncs them to FMOD. Muted tracks: asks first.')
      if S.render_report then
        ImGui.SameLine(ctx)
        ImGui.AlignTextToFramePadding(ctx)
        local first = S.render_report.text:match('^[^\n]*')
        -- Cut to the room left before FMOD's state and the gear (the full
        -- report is in the tooltip).
        local _, stext = footer_status()
        local room = ImGui.GetContentRegionAvail(ctx) - ImGui.CalcTextSize(ctx, stext)
          - 2 * ITEM_SPACING_X - h - 14
        if ImGui.CalcTextSize(ctx, first) > room then
          while #first > 0 and ImGui.CalcTextSize(ctx, first .. '…') > room do
            first = first:gsub('[\0-\127\192-\255][\128-\191]*$', '') -- one UTF-8 character
          end
          first = first .. '…'
        end
        ImGui.TextColored(ctx, S.render_report.col, first)
        tip(S.render_report.text)
      end
      -- FMOD Studio's state in full (its colour tells it), then the gear: always
      -- at the bottom right, level with the list's bottom (never above the
      -- Render line, at the other end of which they then sit).
      if wide then draw_mini_status(render_y) else
        ImGui.SetCursorPosY(ctx, render_y)
        local col, stext, shelp = footer_status()
        align_right(ImGui.CalcTextSize(ctx, stext) + 2 * (ITEM_SPACING_X + h))
        ImGui.AlignTextToFramePadding(ctx)
        ImGui.TextColored(ctx, col, stext)
        tip(shelp)
        ImGui.SameLine(ctx)
        draw_gear()
      end
      ImGui.EndChild(ctx)
    end
  end

  if S.pick_open then S.pick_open = false; ImGui.OpenPopup(ctx, 'pick_folder') end
  if S.mute_open then S.mute_open = false; ImGui.OpenPopup(ctx, 'Muted tracks') end
  draw_mute_question()
  draw_adopt_question(by_key)
  draw_legacy_question()
  draw_folder_picker(by_key, rows)
end

------------------------------------------------------------------------------
-- Settings view: changes save themselves.

local LABEL_W = 190

local function setting_label(text, help)
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx, text)
  tip(help)
  ImGui.SameLine(ctx, LABEL_W)
end

local function draw_settings()
  local changed = false

  ImGui.SeparatorText(ctx, 'FMOD project')
  setting_label('Linked to', 'The FMOD project this REAPER project syncs with. Saved with the RPP.')
  ImGui.Text(ctx, fspro_name() or 'nothing yet')
  setting_label('On this computer', 'Where this computer keeps that project. Updated on its own from FMOD Studio.')
  ImGui.TextDisabled(ctx, fspro_path() or 'unknown: open it in FMOD Studio')
  local can_link = S.fmod_open and config.basename(S.fmod_open) ~= fspro_name()
  if can_link then
    ImGui.SetCursorPosX(ctx, LABEL_W)
    if ImGui.Button(ctx, 'Link to ' .. config.basename(S.fmod_open)) then link_to_open_project() end
    tip('Links this REAPER project to the project open in FMOD Studio.')
  end

  ImGui.SeparatorText(ctx, 'File names')
  setting_label('Name', 'The file name of every take that has no name of its own (rename takes in the panel under the table).\n'
    .. wildcard_help())
  ImGui.SetNextItemWidth(ctx, 320)
  local c1, p = ImGui.InputText(ctx, '##template', default_template())
  if c1 then
    S.cfg.name_template, S.cfg.prefix = p, nil
    changed = true
  end
  tip(wildcard_help())
  ImGui.SameLine(ctx)
  ImGui.TextDisabled(ctx, (assets_mod.expand(default_template(), {
    project = config.basename(S.rpp):gsub('%.[Rr][Pp][Pp]$', ''), title = project_info('PROJECT_TITLE'),
    author = project_info('PROJECT_AUTHOR'), track = 'Track', item = 'Item', index = index_text(1) })))
  setting_label('Numbering', 'The first number of $index, and of the "_NN" after takes marked "Same line".\n'
    .. 'A folder item whose name ends with a number keeps that number: with 00 first, "_00" is its first take.')
  local c_ix, zero = ImGui.Checkbox(ctx, 'Start at 00##index_start', S.cfg.index_start == 0)
  if c_ix then
    S.cfg.index_start = zero and 0 or nil
    changed, S.rescan = true, true
  end
  tip('Off: 01, 02, 03...  On: 00, 01, 02...\nTakes already in FMOD then show Rename in the table.')
  setting_label('Block gap (s)', 'Without folder items on the folder track: items closer than this are one take.')
  ImGui.SetNextItemWidth(ctx, 110)
  local c2, g = ImGui.InputDouble(ctx, '##gap', S.cfg.block_gap or 0, 0, 0, '%.2f')
  if c2 then S.cfg.block_gap = math.max(0, g); changed = true; S.rescan = true end

  ImGui.SeparatorText(ctx, 'Render')
  setting_label('Folder', 'Where takes are rendered, relative to the RPP folder (or absolute).')
  ImGui.SetNextItemWidth(ctx, -1)
  local c3, dir = ImGui.InputText(ctx, '##dir', S.cfg.render_dir or 'Render')
  if c3 then S.cfg.render_dir = dir; changed = true end
  ImGui.SetCursorPosX(ctx, LABEL_W)
  ImGui.TextDisabled(ctx, 'WAV 24 bit, the folder track as a stem.')

  -- The project's render defaults: every track renders with them unless it
  -- has a value of its own (no take selected in the panel), and every take
  -- unless it has its own (takes selected).
  ImGui.SeparatorText(ctx, 'Render defaults')
  ImGui.TextDisabled(ctx, 'Project < track (panel, no take selected) < take (panel, takes selected).')
  local pd = render.project_defaults(S.cfg.render_defaults)
  local function set_default(k, v)
    S.cfg.render_defaults = S.cfg.render_defaults or obj()
    if encode(v) == encode(render.defaults()[k]) then S.cfg.render_defaults[k] = nil
    else S.cfg.render_defaults[k] = v end
    if next(S.cfg.render_defaults) == nil then S.cfg.render_defaults = nil end
    changed = true
  end
  setting_label('Channels', 'Auto: the channel count of the folder track. 1 = mono.')
  ImGui.SetNextItemWidth(ctx, 160)
  local function ch_label(c) return c == nil and 'Auto' or (c == 1 and '1 (mono)' or tostring(c)) end
  if ImGui.BeginCombo(ctx, '##def_ch', ch_label(pd.channels)) then
    if ImGui.Selectable(ctx, 'Auto', pd.channels == nil) then set_default('channels', nil) end
    for _, c in ipairs(CHANNELS) do
      if ImGui.Selectable(ctx, ch_label(c), pd.channels == c) then set_default('channels', c) end
    end
    ImGui.EndCombo(ctx)
  end
  setting_label('Sample rate', 'Project: the sample rate of the REAPER project.')
  ImGui.SetNextItemWidth(ctx, 160)
  local function sr_label(v) return v == nil and ('Project (' .. project_srate() .. ' Hz)') or (v .. ' Hz') end
  if ImGui.BeginCombo(ctx, '##def_sr', sr_label(pd.srate)) then
    if ImGui.Selectable(ctx, sr_label(nil), pd.srate == nil) then set_default('srate', nil) end
    for _, v in ipairs(SRATES) do
      if ImGui.Selectable(ctx, v .. ' Hz', pd.srate == v) then set_default('srate', v) end
    end
    ImGui.EndCombo(ctx)
  end
  -- A checkbox and its value: off = nil (tail: 0).
  local function onoff(k, label, help, unit, default, lo, hi, off_value)
    setting_label(label, help)
    local v = pd[k]
    local on = v ~= nil and v ~= off_value
    local c, nv_on = ImGui.Checkbox(ctx, '##def_' .. k .. '_on', on)
    if c then set_default(k, nv_on and default or off_value) end
    ImGui.SameLine(ctx)
    ImGui.BeginDisabled(ctx, not on)
    ImGui.SetNextItemWidth(ctx, 122)
    local c2, nv = ImGui.InputDouble(ctx, unit .. '##def_' .. k, on and v or default, 0.5, 1, '%.2f')
    if c2 and on then set_default(k, math.min(hi, math.max(lo, nv))) end
    ImGui.EndDisabled(ctx)
  end
  onoff('tail', 'Tail', 'Seconds added after the end of each take.', 's', 1, 0, 60, 0)
  setting_label('2nd pass', 'Renders every file twice (needed by some plug-ins).')
  local c4, spv = ImGui.Checkbox(ctx, '##def_second_pass', pd.second_pass == true)
  if c4 then set_default('second_pass', spv) end
  onoff('normalize', 'Normalize', 'Normalizes every file to this integrated loudness (LUFS-I).', 'LUFS-I', -24, -60, 0, nil)
  onoff('limit', 'Limiter', 'Brickwall limiter at this ceiling, after the normalization.', 'dB', 0, -30, 0, nil)

  ImGui.SeparatorText(ctx, 'Diagnostics')
  setting_label('FMOD Studio', 'Text FMOD Studio sent outside the answers to this script.')
  local raw = link.raw()
  ImGui.TextDisabled(ctx, link.error or (link.status == 'online' and 'connected' or 'not connected'))
  ImGui.SetCursorPosX(ctx, LABEL_W)
  if ImGui.SmallButton(ctx, 'Copy what FMOD sent') then ImGui.SetClipboardText(ctx, raw) end
  ImGui.SameLine(ctx)
  -- Read only: what FMOD offers to select files in its browser and to put
  -- them in instruments. Printed in REAPER's console.
  if ImGui.SmallButton(ctx, 'Ask FMOD about instruments') then
    link.request('function keys(o, re) { var out = []; if (!o) { return out; }'
      .. ' for (var k in o) { try { if (re.test(k)) { out.push(k + ":" + typeof o[k]); } } catch (e) {} } return out; }'
      .. ' var r = { window: keys(studio.window, /./), model: keys(studio.project.model, /sound|instrument|module|track/i) };'
      .. ' var sel = null; try { sel = studio.window.editorSelection(); } catch (e) { r.selErr = String(e); }'
      .. ' if (sel) { r.sel = []; for (var i = 0; i < sel.length && i < 5; i++) { r.sel.push(sel[i].entity);'
      .. ' if (i === 0) { r.first = keys(sel[i], /./); } } }'
      .. ' var bs = null; try { bs = studio.window.browserSelection(); } catch (e) { r.bsErr = String(e); }'
      .. ' if (bs) { r.bs = []; for (var j = 0; j < bs.length && j < 5; j++) { r.bs.push(bs[j].entity); } }'
      .. ' return r;', function(v, err)
      local out = { 'FMOD Sync, FMOD instruments probe:' }
      if err then out[#out + 1] = '  error: ' .. tostring(err) end
      for _, k in ipairs({ 'window', 'model', 'sel', 'first', 'bs', 'selErr', 'bsErr' }) do
        local t = type(v) == 'table' and v[k]
        out[#out + 1] = '  ' .. k .. ': ' .. (type(t) == 'table' and table.concat(t, ', ') or tostring(t or '-'))
      end
      reaper.ShowConsoleMsg(table.concat(out, '\n') .. '\n')
    end)
  end

  if changed then save_cfg() end
end

------------------------------------------------------------------------------
-- Window.

-- The gear at the right of the current line: settings in, settings out.
draw_gear = function()
  if MINI then
    -- Mini: the undock icon, then the gear; the settings open in a floating window over the docker.
    align_right(2 * ImGui.GetFrameHeight(ctx) + ITEM_SPACING_X)
    if icon_button('##undock', false, V.paint_undock) then V.dock_request = 'undock' end
    tip('Float the window: the full FMOD Sync, every take of the project.')
    ImGui.SameLine(ctx)
    local open = ImGui.IsPopupOpen(ctx, 'mini_settings')
    if icon_button('##settings', open, paint_gear) then ImGui.OpenPopup(ctx, 'mini_settings') end
    tip('Settings')
    ImGui.SetNextWindowSizeConstraints(ctx, 560, 0, 900, 700)
    if ImGui.BeginPopup(ctx, 'mini_settings') then
      draw_settings()
      ImGui.EndPopup(ctx)
    end
      return
  end
  align_right(ImGui.GetFrameHeight(ctx))
  if icon_button('##settings', S.view == 'settings', paint_gear) then
    S.view = S.view ~= 'settings' and 'settings' or nil
  end
  tip(S.view == 'settings' and 'Close the settings and go back to the takes.' or 'Settings')
end

local FOOTER_SIZE = 12 -- font size of the footer

-- Where FMOD Studio stands: colour, text and tooltip.
footer_status = function()
  local col, text, help
  if link.status ~= 'online' then
    col, text = COL_ERR, 'FMOD Studio not reachable'
    help = (link.error or '') .. '\nStart FMOD Studio with Preferences > Interface > "Enable Script Server" on. '
      .. 'This window connects on its own.'
  elseif not S.fmod_open then
    col, text = COL_DIM, 'FMOD Studio: connecting...'
  elseif fspro_name() and not fmod_has_linked_project() then
    col, text = COL_WARN, 'FMOD Studio has ' .. config.basename(S.fmod_open) .. ' open, not ' .. fspro_name()
    help = 'Open ' .. fspro_name() .. ' in FMOD Studio to compare and sync.'
  elseif S.fmod_err then
    col, text = COL_WARN, 'FMOD Studio: ' .. config.basename(S.fmod_open) .. ' (last request failed)'
    help = S.fmod_err .. '\nAsked again when the mouse comes back over this window.'
  else
    col, text = COL_OK, 'FMOD Studio: ' .. config.basename(S.fmod_open)
    help = S.fmod_open .. '\n' .. (S.audio_total or 0) .. ' audio files'
  end
  return col, text, help
end

-- Footer: where FMOD Studio stands, small.
local function draw_footer()
  local col, text, help = footer_status()
  local full = ImGui.GetFrameHeight(ctx) -- the gear's size, at the normal font
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
  ImGui.TextColored(ctx, col, text)
  tip(help)
  ImGui.PopStyleVar(ctx)
  if font then ImGui.PopFont(ctx) end
  ImGui.SameLine(ctx)
  ImGui.SetCursorScreenPos(ctx, (ImGui.GetCursorScreenPos(ctx)), line_y)
  draw_gear() -- full size: the footer is as tall as it
end

-- Height the footer takes, with the spacing above it.
local function footer_height()
  if font then ImGui.PushFont(ctx, font, FOOTER_SIZE) end
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 6, 1)
  local h = ImGui.GetFrameHeight(ctx)
  ImGui.PopStyleVar(ctx)
  if font then ImGui.PopFont(ctx) end
  return math.max(h, ImGui.GetFrameHeight(ctx)) + 2 * select(2, ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing))
end

-- What must happen before the takes mean anything; true when nothing is missing.
local function draw_notices()
  if S.rpp == '' then
    ImGui.TextColored(ctx, COL_WARN, 'Save the REAPER project first: its link to FMOD is kept in a file next to it.')
    return false
  end
  if S.cfg_err then ImGui.TextColored(ctx, COL_ERR, S.cfg_err) end
  if not S.cfg then return false end
  if not fspro_name() then
    if S.fmod_open then
      ImGui.AlignTextToFramePadding(ctx)
      ImGui.Text(ctx, MINI and 'Not linked to FMOD.' or 'This project is not linked to an FMOD project.')
      ImGui.SameLine(ctx)
      if accent_button('Link to ' .. config.basename(S.fmod_open)) then link_to_open_project() end
    else
      ImGui.TextDisabled(ctx, MINI and 'Not linked: open its FMOD project in FMOD Studio.'
        or 'This project is not linked: open its FMOD project in FMOD Studio to link it.')
    end
  end
  return true
end

-- Docked = Mini, floating = full. Docking leaves full screen and the settings
-- page (Mini has them in the gear's popup); floating again takes the full
-- window's size (V.float_size: next frame, before Begin).
function V.switch_view(docked)
  MINI = docked
  reaper.SetExtState(EXT, 'docked', docked and '1' or '0', true)
  if docked then
    S.view = nil
    S.mini_enter = true
    local fs = fullscreen.main
    if fs then
      fullscreen.main = nil
      local g = fs.back
      reaper.SetExtState(EXT, 'window_main', string.format('%d,%d,%d,%d,0', math.floor(g[1] + 0.5),
        math.floor(g[2] + 0.5), math.floor(g[3] + 0.5), math.floor(g[4] + 0.5)), true)
    end
    fullscreen_back.main, enter_fullscreen.main = nil, nil
    opened_windows.main = nil -- dragged out later: V.float_size gives it the full size
  elseif not opened_windows.main then
    V.float_size = true
  end
end

local function frame()
  -- Follows the active project tab.
  local proj, rpp = reaper.EnumProjects(-1)
  rpp = rpp or ''
  if proj ~= S.proj or rpp ~= S.rpp then load_project(proj, rpp)
  elseif S.rescan or reaper.GetProjectStateChangeCount(proj) ~= S.state_count then
    S.rescan = false
    rescan_assets()
  end

  -- Another run of this script saved the config of this project: read it again.
  local mark = reaper.GetExtState(EXT, 'cfg_saved')
  if mark ~= '' and mark ~= S.cfg_mark then
    S.cfg_mark = mark
    if mark:sub(1, #S.rpp + 1) == S.rpp .. '|' and S.rpp ~= '' then
      local sel, anchor = S.sel, S.anchor
      load_project(S.proj, S.rpp)
      S.sel, S.anchor = sel, anchor
    end
  end

  keep_connected()
  link.poll(json)

  -- Renders run between frames: the render blocks REAPER until it is done.
  if S.render_request then
    local list = S.render_request
    S.render_request = nil
    render_rows(list)
  end

  -- The other action was run while this window is open: dock or undock it.
  local req = reaper.GetExtState(EXT, 'request')
  if req ~= '' then
    reaper.DeleteExtState(EXT, 'request', false)
    V.dock_request = req
  end

  push_style()
  local fs_flags = 0
  if V.dock_request == 'dock' and not MINI then
    -- Into the docker it was in last (ReaImGui: negative ids are REAPER's dockers).
    ImGui.SetNextWindowDockID(ctx, tonumber(reaper.GetExtState(EXT, 'dock_id')) or -1, ImGui.Cond_Always)
  elseif V.dock_request == 'undock' and MINI then
    -- Out of the docker, back where and as large as the full window was.
    ImGui.SetNextWindowDockID(ctx, 0, ImGui.Cond_Always)
    opened_windows.main, V.float_size = nil, nil
    prepare_window('main', 900, 620)
    enter_fullscreen.main = nil
  elseif not MINI then
    if V.float_size then
      -- Dragged out of the docker: the size of the full window (its place is the mouse's).
      local g = saved_geometry('main')
      ImGui.SetNextWindowSize(ctx, g and g[3] >= 100 and g[3] or 900, g and g[4] >= 100 and g[4] or 620, ImGui.Cond_Always)
      V.float_size, opened_windows.main = nil, true
    end
    prepare_window('main', 900, 620)
    fs_flags = prepare_fullscreen('main')
  end
  V.dock_request = nil
  local visible, open = ImGui.Begin(ctx, (MINI and 'FMOD Sync Mini ' or 'FMOD Sync ') .. VERSION .. '###mtt_FmodSync', true,
    ImGui.WindowFlags_NoCollapse | fs_flags)
  if visible then
    -- The view follows the dock (the style of this frame is still the old view's).
    local docked = ImGui.IsWindowDocked(ctx)
    if docked ~= MINI then V.switch_view(docked) end
    if docked then
      local id = ImGui.GetWindowDockID(ctx)
      if id < 0 and tostring(id) ~= reaper.GetExtState(EXT, 'dock_id') then
        reaper.SetExtState(EXT, 'dock_id', tostring(id), true)
      end
    end
    -- FMOD's files are read again when the mouse comes back over this window
    -- (at most every 5 s): what changed in FMOD meanwhile shows without a button.
    local hovered = ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_ChildWindows | ImGui.HoveredFlags_AllowWhenBlockedByPopup)
    if hovered and not S.was_hovered and link.status == 'online'
      and reaper.time_precise() - (S.last_refresh or 0) > 5 then
      S.last_refresh = reaper.time_precise()
      refresh_fmod()
    end
    S.was_hovered = hovered
    if MINI then
      -- A line along the top: the edge between REAPER's arrange (its scrollbar) and the dock.
      local wx, wy = ImGui.GetWindowPos(ctx)
      local ww = ImGui.GetWindowSize(ctx)
      ImGui.DrawList_AddLine(ImGui.GetWindowDrawList(ctx), wx, wy + 0.5, wx + ww, wy + 0.5,
        ImGui.GetColor(ctx, ImGui.Col_Separator), 1)
    end
    if not MINI then
      remember_window('main')
      fullscreen_title_button('main')
      V.dock_title_button()
      title_double_click('main')
    end
    -- Cmd+A (Ctrl+A on Windows) selects every take shown, except while typing.
    if ImGui.IsWindowFocused(ctx, ImGui.FocusedFlags_RootAndChildWindows) and not ImGui.IsAnyItemActive(ctx)
      and ImGui.GetKeyMods(ctx) & ImGui.Mod_Ctrl ~= 0 and ImGui.IsKeyPressed(ctx, ImGui.Key_A, false)
      and S.view ~= 'settings' then
      S.sel = {}
      for _, r in ipairs(S.order or {}) do S.sel[r.key] = true end
      select_time(selected_rows())
    end
    -- Space plays / stops REAPER while this window has the focus, except while typing.
    if ImGui.IsWindowFocused(ctx, ImGui.FocusedFlags_RootAndChildWindows)
      and not ImGui.IsAnyItemActive(ctx) and ImGui.IsKeyPressed(ctx, ImGui.Key_Space, false) then
      reaper.Main_OnCommand(40044, 0) -- Transport: Play/stop
    end
    -- Everything but the footer scrolls in its own child.
    -- Mini has no footer: FMOD's state and the gear are on its top line.
    if ImGui.BeginChild(ctx, 'content', 0, MINI and 0 or -footer_height(), ImGui.ChildFlags_None) then
      if draw_notices() then
        if MINI then draw_mini()
        elseif S.view == 'settings' then draw_settings() else draw_assets() end
      elseif MINI then
        draw_mini_status(ImGui.GetCursorPosY(ctx))
      elseif S.view == 'settings' and S.cfg then
        draw_settings()
      end
      ImGui.EndChild(ctx)
    end
    drag_frame()
    if not MINI then
      ImGui.Separator(ctx)
      draw_footer()
    end
    ImGui.End(ctx)
  end
  pop_style()
  return open
end

-- A script error stops the script and writes where it happened to REAPER's
-- console (ReaImGui's own message then only says which window was left open).
local function loop()
  local ok, open = xpcall(frame, debug.traceback)
  if not ok then
    reaper.ShowConsoleMsg('\n' .. 'FMOD Sync ' .. VERSION .. ' stopped on an error:\n'
      .. tostring(open) .. '\n')
    link.close()
    return
  end
  -- Tells a second run of this script (the other action) that this window is open.
  reaper.SetExtState(EXT, 'alive', tostring(reaper.time_precise()), false)
  if open then reaper.defer(loop) end
end

reaper.atexit(function()
  reaper.DeleteExtState(EXT, 'alive', false)
  link.close()
end)
-- Each action opens the window in its own view (it docks or undocks on the first frame).
if V.open_docked ~= MINI then V.dock_request = V.open_docked and 'dock' or 'undock' end
reaper.defer(loop)
