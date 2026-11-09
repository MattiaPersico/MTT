-- mtt_MetadataAssistant.lua
-- Describe a sound in plain words; the script picks the UCS category, writes the
-- UCS filename and rich Soundminer metadata, asks only what it cannot infer, and
-- renders the item to its own tagged file.
--
-- Works on the one selected item. Its card (description, draft, answers, final
-- values) is kept in the project under a key stored in the item itself, so
-- selecting the item again brings it back for editing or a fresh analysis, also
-- after a cut and paste (a copy gets its own copy of the card). Final fields are
-- editable; Render writes a 24-bit WAV at the item's sample rate and channel
-- count with the metadata (and the item's artwork, when set) embedded.
-- 0.4: fields aligned with BOOM Library's Soundminer exports (Recordist,
-- ChannelLayout, ShootDate, URL, copyright in the BWF originator, TrackYear as
-- the year, Microphone from the answers).
-- 0.5: measures of the item's audio for every model; with "Model hears audio"
-- the same model first listens to a clip of the item and can start a card
-- without a description.
-- 0.7: model picker filled from the server's GET /v1/models.
-- 0.9: staged editing workspace with separate settings.
-- 0.10: rounded window and Half-Life orange accent; text boxes wrap visually;
-- the view (Describe / Review / Metadata) stays when the selected item changes;
-- Play button; tooltips on labels; the final file name can be edited; Render
-- button next to the Metadata tab, into a folder relative to the project
-- (Settings); nothing is deduced from item or file names; OpenAI-format servers
-- only (MTT Relay options removed). Softer orange, font 15. Several items
-- selected = multi-edit: a field typed once goes to every item; names are numbered.
-- The card follows an item through cut and paste (its key is kept in the item's
-- extended data); a copy or a split gets its own copy of the card.
-- Layout: model at the left and Settings at the right of the top row, Render at the right of the tab row; Review
-- and Metadata open only once the step before them is done. Copy (next to the tabs) takes an
-- item's metadata and file name; with several items selected, hovering a field or the file
-- name previews the copied value, a click puts it in all of them, Paste all puts everything.
-- 0.11: file names without repeated words: the model is told not to say a word
-- twice nor name again what the CatID names, and its VendorCategory loses the
-- words the CatID and the FXName already say.
-- 0.12: the Review tab pulses while the item on screen waits for review and
-- another page is shown. Timeline outlines (Settings > Interface; needs
-- js_ReaScriptAPI): green = reviewed, blinking yellow = waiting for review, orange,
-- warm white and blue running around = being analyzed or finalized. Selecting an item opens
-- the page of its step (Metadata, Review or Describe). Model requests have no total
-- time limit any more, only an optional one on silence. What the model is doing
-- shows on the top row, next to its name. Settings > Library >
-- VendorCategory / UserCategory (on by default) can make the model leave UCS's
-- optional dashed name blocks empty. Multi-edit: the copied file name can be
-- pasted like a field; the list of the items' file names is gone; a click that
-- pastes no longer trips ReaImGui's InputText assertion.
-- 0.13: Overview button (left of Render) opens a table of every item of the project
-- that has a card: status, file name and every metadata field, editable in place and
-- sortable by any column; a click on a row's number selects that item. The model no
-- longer gets the source file's metadata that is a name (title, the recorder's scene,
-- take, tape and project, an earlier pass's FXName or title) or that repeats the take
-- name or the file name; Technical details show what is sent and what is left out.

-- 0.14: Overview global text search across every column, including hidden fields;
-- Play/Stop beside each row number uses the existing item playback.

-- 0.15: project-wide curator chat and previewed metadata edits in Overview.
-- 0.16: copy a field in Overview and paste its value across the entire column.
-- 0.17: reopen floating over REAPER so a saved dock or disconnected screen
-- cannot hide the workspace; fit the initial windows to REAPER's work area.
-- 0.18: the windows are no longer dockable into each other (NoDocking).
-- 0.19: blue runs around the analyzed items with the orange and the warm white.
-- 0.20: renamed from UCS Tagger to Metadata Assistant (files, modules, window
-- titles, ExtState section and item tag) and moved from Testing/ to MetadataAssistant/.
-- 0.21: full screen icon in the title bar of the main window and of the Overview,
-- left of the close button: the window fills the work area of the display it is
-- on; the icon again puts it back. No collapse arrow in the title bars. Two icons
-- at the right of the top row: a table (opens the Overview, which no longer has a
-- button next to Render) and a gear (the settings, shown inside the main window,
-- no separate Settings window); a double click on a title bar toggles full screen.
-- The Overview shows the table and the curator side by side, with a draggable
-- border; at its right edge an arrow hides the curator, or "< Curator" brings it
-- back. Artwork per item (Metadata page, last group; Browse...): a JPEG
-- or PNG embedded as the front cover in the rendered file. Settings: Library,
-- SourceID and Show are saved in the project, the rest stays global; labels on the
-- left, grouped (Server, Models, Audio / Library identity, This project, Files /
-- Diagnostics, Timeline); Render folder moved to Library and defaults to Render;
-- JSON mode, Give up after silence and the default microphone / recorder removed
-- (Microphone and RecMedium are per item only).
-- 0.22: full-item survey, representative listening excerpts and time-resolved
-- event, timbre and stereo measurements. Stop also cancels local audio analysis.
-- Settings save themselves on every change (no Save settings button). The library
-- identity has its own view (books icon, next to the Overview's); the gear shows
-- every other setting on one page (no tabs), Render folder included. The item's
-- phases read Describe . . . Clarify . . . Review (text only, the current one in the
-- accent and underlined; Clarify pulses while it waits for the user); Play and Copy
-- are icons, Copy only in Review. Settings > Diagnostics and its Technical details
-- panel (measures, UCS candidates, raw answers, Delete this card) are gone. The measurements cover the whole item in
-- segments of up to 30 s; "Seconds sent to the model" only limits the audio clip.
-- 0.23: Overview: Play is an icon; the fixed columns (#, Status, File name) have a tinted
-- header and cells and a line after the last one, so they read apart from the columns that
-- scroll. While an item is analyzed or finalized, a coloured light sweeps back and forth over
-- the dots between the two phases. An answer that is not valid JSON is asked for again,
-- up to twice, without the user doing anything.
-- 0.24: Overview: the # and Status columns are gone; the one fixed column holds the play icon and
-- the file name, coloured by the item's status. A click on a cell selects the item in REAPER, a
-- double click edits it. The horizontal scrollbar sits under the scrolling columns only.
local major_version = 0
local minor_version = 24

local name = 'Metadata Assistant ' .. tostring(major_version) .. '.' .. tostring(minor_version)

if not reaper.APIExists('ImGui_GetBuiltinPath') then
  reaper.MB('ReaImGui is required (ReaPack: ReaTeam Extensions).', 'Missing dependency', 0)
  return
end
package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'

-- Modules live next to this file.
local info = debug.getinfo(1, 'S')
local script_path = info.source:match[[^@?(.*[\/])[^\/]-$]]
local function load_module(file)
  return dofile(script_path .. file)
end

local json = load_module('dkjson.lua')
local ucs = load_module('mtt_metadataassistant_ucs_data.lua')
local match = load_module('mtt_metadataassistant_match.lua')
local fields = load_module('mtt_metadataassistant_fields.lua')
local filename = load_module('mtt_metadataassistant_filename.lua')
local llm = load_module('mtt_metadataassistant_llm.lua')
local settings_mod = load_module('mtt_metadataassistant_settings.lua')
local http = load_module('mtt_metadataassistant_http.lua')
local flow = load_module('mtt_metadataassistant_flow.lua')
local item_mod = load_module('mtt_metadataassistant_item.lua')
local store = load_module('mtt_metadataassistant_store.lua')
local render = load_module('mtt_metadataassistant_render.lua')
local audio = load_module('mtt_metadataassistant_audio.lua')
local wrap = load_module('mtt_metadataassistant_wrap.lua')
local outline = load_module('mtt_metadataassistant_outline.lua')
local overview_mod = load_module('mtt_metadataassistant_overview.lua')

local curator = load_module('mtt_metadataassistant_curator.lua')
local chat = { history = {}, input = '' }

local index = match.build_index(ucs.entries)
local ctx = ImGui.CreateContext(name)

-- Recover each window on its first opening in this run, before Begin restores
-- a saved off-screen position or dock. Later frames leave moves/resizes alone.
-- Keep all geometry in ReaImGui coordinates, including on Retina displays.
local opened_windows = {}
local function prepare_window(key, width, height)
  if opened_windows[key] then return end
  local viewport = ImGui.GetMainViewport(ctx)
  local x, y = ImGui.Viewport_GetWorkPos(viewport)
  local w, h = ImGui.Viewport_GetWorkSize(viewport)
  if w <= 0 or h <= 0 then return end -- retry when the main viewport is ready
  ImGui.SetNextWindowDockID(ctx, 0, ImGui.Cond_Always)
  ImGui.SetNextWindowCollapsed(ctx, false, ImGui.Cond_Always)
  ImGui.SetNextWindowPos(ctx, x + w / 2, y + h / 2, ImGui.Cond_Always, 0.5, 0.5)
  ImGui.SetNextWindowSize(ctx, math.min(width, math.max(1, w - 32)),
    math.min(height, math.max(1, h - 32)), ImGui.Cond_Always)
  opened_windows[key] = true
end

local COL_ERR = 0xFF6464FF
local COL_WARN = 0xE6B43CFF
local COL_OK = 0x78D278FF
local COL_DIM = 0x9A9A9AFF
-- Accent: Half-Life orange, toned down (the HEV HUD amber is 0xFFA000).
local COL_ACCENT = 0xE89B3CFF
local COL_SELECTED = 0x9A6322FF
local COL_PREVIEW = 0x5C4521FF -- background of a field showing the copied value
local COL_SELECTED_HOVER = 0xAE7229FF
local COL_SELECTED_ACTIVE = 0x84541AFF
local COL_BUTTON = 0x303435FF
-- Pulse of a tab that asks for attention: from COL_BUTTON towards COL_ACCENT and back.
local BLINK_PERIOD = 1.2 -- seconds per cycle
local BLINK_DEPTH = 1 -- 1 = full accent at the peak of the pulse
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

local ITEM_SPACING_X = 8 -- also lines up the buttons at the right end of a row
-- Rounded window, popups, children, scrollbars and controls.
local style_vars = {
  { ImGui.StyleVar_WindowRounding, 12 }, { ImGui.StyleVar_ChildRounding, 8 },
  { ImGui.StyleVar_PopupRounding, 8 }, { ImGui.StyleVar_ScrollbarRounding, 12 },
  { ImGui.StyleVar_GrabRounding, 5 }, { ImGui.StyleVar_FrameRounding, 5 },
  { ImGui.StyleVar_WindowPadding, 16, 14 }, { ImGui.StyleVar_ItemSpacing, ITEM_SPACING_X, 7 },
  { ImGui.StyleVar_FramePadding, 9, 5 },
}
local FRAME_PAD_X = 9

-- Text larger than ReaImGui's default (13).
local FONT_SIZE = 15
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

-- width: optional; -1 fills the row.
local function accent_button(label, width)
  ImGui.PushStyleColor(ctx, ImGui.Col_Button, COL_SELECTED)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, COL_SELECTED_HOVER)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, COL_SELECTED_ACTIVE)
  local clicked = ImGui.Button(ctx, label, width or 0)
  ImGui.PopStyleColor(ctx, 3)
  return clicked
end

local mix_color = outline.mix_color -- colour between a and b (0xRRGGBBAA), k from 0 to 1

-- Text colour of a pulsing phase label at time t (seconds): a smooth pulse from
-- dim to the accent, so the defer loop's redraw rate does not matter.
local function blink_color(t)
  local phase = (t % BLINK_PERIOD) / BLINK_PERIOD
  return mix_color(COL_DIM, COL_ACCENT, BLINK_DEPTH * (0.5 - 0.5 * math.cos(2 * math.pi * phase)))
end

-- Width of a button with this label.
local function button_width(label)
  return ImGui.CalcTextSize(ctx, label) + 2 * FRAME_PAD_X
end

-- On the line being drawn (after a SameLine), moves the cursor so that an item
-- of this width ends at the right edge; never to the left of where the cursor is.
local function align_right(width)
  local avail = ImGui.GetContentRegionAvail(ctx)
  if avail > width then ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + avail - width) end
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

-- Tooltip for the item just drawn (a label, a button). Also while it is disabled.
local function tip(text)
  if text and text ~= '' and ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
    if ImGui.BeginTooltip(ctx) ~= false then
      ImGui.PushTextWrapPos(ctx, ImGui.GetFontSize(ctx) * 28)
      ImGui.Text(ctx, text)
      ImGui.PopTextWrapPos(ctx)
      ImGui.EndTooltip(ctx)
    end
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
  local icons_x = wx + ww - pad_x - 2 * sz - inner_x -- the full screen icon and the close cross
  local title_h = ImGui.GetTextLineHeight(ctx) + 2 * pad_y
  if my >= wy and my < wy + title_h and mx >= wx and mx < icons_x then toggle_fullscreen(key) end
end

-- A square button, one frame tall, drawn by paint(dl, x, y, h, col, under): col is
-- the text colour (the accent while active), under the colour beneath the icon
-- (hover colour or the opaque window background), for holes.
local icons = {} -- icons.button and its painters (one local: the main chunk is near Lua's 200-local limit)
function icons.button(id, active, paint)
  local h = ImGui.GetFrameHeight(ctx)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local clicked = ImGui.InvisibleButton(ctx, id, h, h)
  local hovered, held = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
  local dl = ImGui.GetWindowDrawList(ctx)
  local under = ImGui.GetColor(ctx, ImGui.Col_WindowBg)
  if hovered then
    under = ImGui.GetColor(ctx, held and ImGui.Col_ButtonActive or ImGui.Col_ButtonHovered)
    ImGui.DrawList_AddRectFilled(dl, x, y, x + h, y + h, under, 5)
  end
  paint(dl, math.floor(x), math.floor(y), h, active and COL_ACCENT or ImGui.GetColor(ctx, ImGui.Col_Text), under)
  return clicked
end

-- Six-tooth gear in a 1 px outline, with a 1 px round hole: a line icon, light
-- at 1x. Centred on a pixel centre so the strokes stay sharp (PathStroke does not
-- shift by half a pixel the way AddLine does).
function icons.gear(dl, x, y, h, col)
  local GEAR_TEETH = 6
  local cx, cy = math.floor(x + h / 2) + 0.5, math.floor(y + h / 2) + 0.5
  local r_out, r_in, r_hole = h * 0.27, h * 0.20, h * 0.093
  local pitch = 2 * math.pi / GEAR_TEETH
  ImGui.DrawList_PathClear(dl)
  for i = 0, GEAR_TEETH - 1 do
    local a = i * pitch - math.pi / 2
    -- Each tooth: base on the body circle, narrower top on the outer circle.
    for _, p in ipairs({ { a - pitch * 0.21, r_in }, { a - pitch * 0.11, r_out },
                         { a + pitch * 0.11, r_out }, { a + pitch * 0.21, r_in } }) do
      ImGui.DrawList_PathLineTo(dl, cx + math.cos(p[1]) * p[2], cy + math.sin(p[1]) * p[2])
    end
  end
  ImGui.DrawList_PathStroke(dl, col, ImGui.DrawFlags_Closed, 1)
  ImGui.DrawList_AddCircle(dl, cx, cy, r_hole, col, 0, 1)
end

-- A small table in 1 px lines on whole pixels: frame, header line, one row line,
-- one column line. AddRect and AddLine both add the half pixel themselves
-- (imgui_draw.cpp), so every coordinate here is a whole number.
function icons.table(dl, x, y, h, col)
  local w, th = 16, 13                       -- frame, in pixels
  local head, col_x = 4, 6                   -- header line row, column line, from the frame's corner
  local x0, y0 = x + math.floor((h - w) / 2), y + math.floor((h - th) / 2)
  ImGui.DrawList_AddRect(dl, x0, y0, x0 + w, y0 + th, col, 0, 0, 1)
  local row = head + math.floor((th - 1 - head) / 2) -- halfway between header and bottom
  ImGui.DrawList_AddLine(dl, x0, y0 + head, x0 + w - 1, y0 + head, col, 1)
  ImGui.DrawList_AddLine(dl, x0, y0 + row, x0 + w - 1, y0 + row, col, 1)
  ImGui.DrawList_AddLine(dl, x0 + col_x, y0 + head, x0 + col_x, y0 + th - 1, col, 1)
end

-- Three upright books in 1 px lines on whole pixels, different heights, each with
-- a band near its top. AddRect and AddLine add the half pixel themselves.
local LIBRARY_BOOKS = { { 0, 5, 2 }, { 6, 5, 0 }, { 12, 4, 3 } } -- x offset, width, top offset
function icons.library(dl, x, y, h, col)
  local x0 = x + math.floor((h - 16) / 2)
  local top = y + math.floor((h - 14) / 2)
  local bottom = top + 13 -- last pixel row
  for _, b in ipairs(LIBRARY_BOOKS) do
    local bx, by = x0 + b[1], top + b[3]
    ImGui.DrawList_AddRect(dl, bx, by, bx + b[2], bottom + 1, col, 0, 0, 1)
    ImGui.DrawList_AddLine(dl, bx, by + 3, bx + b[2] - 1, by + 3, col, 1)
  end
end

-- Play: a small filled triangle pointing right.
function icons.play(dl, x, y, h, col)
  local x0, y0 = x + math.floor((h - 8) / 2) + 1, y + math.floor((h - 10) / 2)
  ImGui.DrawList_AddTriangleFilled(dl, x0, y0, x0, y0 + 10, x0 + 8, y0 + 5, col)
end

-- Stop: a small filled square.
function icons.stop(dl, x, y, h, col)
  local x0, y0 = x + math.floor((h - 8) / 2), y + math.floor((h - 8) / 2)
  ImGui.DrawList_AddRectFilled(dl, x0, y0, x0 + 8, y0 + 8, col, 1)
end

-- The dots between two phases while the model works on the step that leads from one
-- to the other: a light sweeps back and forth over them, with a short trail, slow at
-- both ends. Its colour moves through the colours of the timeline outline (orange, amber,
-- warm white, blue), one step per sweep. Time based, so the redraw rate does not matter.
-- (cx, cy): the middle of the three dots; t: seconds.
icons.SCAN_PALETTE = { 0xFF6A00FF, 0xFFA53CFF, 0xFFF3DEFF, 0x33ADFFFF }
icons.SCAN_SWEEP = 0.9   -- seconds for one way
icons.SCAN_SPAN = 20     -- pixels from the middle to each end
icons.SCAN_TRAIL = 6     -- circles behind the head
icons.STATE_GAP = { measuring = 1, listening = 1, drafting = 1, finalizing = 2 } -- state -> gap between phases
function icons.scan(dl, cx, cy, t)
  local u = (t % (2 * icons.SCAN_SWEEP)) / (2 * icons.SCAN_SWEEP)
  local pos = -math.cos(2 * math.pi * u)                    -- -1 .. 1 .. -1
  local dir = math.sin(2 * math.pi * u) >= 0 and 1 or -1    -- the way the head moves
  local pal = icons.SCAN_PALETTE
  local c = (t / icons.SCAN_SWEEP) % #pal
  local i0 = math.floor(c)
  local head = mix_color(pal[i0 + 1], pal[(i0 + 1) % #pal + 1], c - i0)
  for k = icons.SCAN_TRAIL, 0, -1 do                       -- the trail first, the head on top
    local p = math.max(-1, math.min(1, pos - dir * k * 0.09))
    local a = 1 - k / (icons.SCAN_TRAIL + 1)
    ImGui.DrawList_AddCircleFilled(dl, cx + p * icons.SCAN_SPAN, cy, 1.2 + 1.5 * a,
      (head & 0xFFFFFF00) | math.floor(255 * a * a))
  end
end

-- Copy: two overlapping sheets in 1 px lines on whole pixels; only the visible
-- edges of the back sheet are drawn.
function icons.copy(dl, x, y, h, col)
  local x0, y0 = x + math.floor((h - 13) / 2), y + math.floor((h - 14) / 2)
  ImGui.DrawList_AddRect(dl, x0, y0 + 4, x0 + 10, y0 + 14, col, 0, 0, 1)   -- front sheet
  ImGui.DrawList_AddLine(dl, x0 + 3, y0, x0 + 12, y0, col, 1)              -- back sheet: top
  ImGui.DrawList_AddLine(dl, x0 + 12, y0, x0 + 12, y0 + 10, col, 1)        -- right
  ImGui.DrawList_AddLine(dl, x0 + 3, y0, x0 + 3, y0 + 3, col, 1)           -- left, above the front
  ImGui.DrawList_AddLine(dl, x0 + 10, y0 + 10, x0 + 12, y0 + 10, col, 1)   -- bottom, right of the front
end

-- Multiline text box whose lines wrap to the window width on screen only: the
-- text it returns has no line breaks that the user did not type. ReaImGui 0.10
-- has no native word-wrap flag; the text shown has a "\n" in place of the space where a line wraps
-- (mtt_metadataassistant_wrap.lua); the wrap is applied when the box gets focus and
-- when it loses it, because the box ignores outside changes while it has focus
-- (a long line scrolls sideways until then).
local current = nil   -- session of the selected item (one item selected)
local own_windows = {} -- this frame's script windows {x1, y1, x2, y2}: the timeline outlines skip them
local multi = nil     -- several items selected: { sig, items, with_values, ... }, see track_selection
local wrap_state = {}   -- widget id -> { prev = text the box holds, active = bool }
local measure_cache, measure_cache_size = {}, 0

local function text_width(str)
  local w = measure_cache[str]
  if not w then
    w = ImGui.CalcTextSize(ctx, str)
    if measure_cache_size > 4000 then measure_cache, measure_cache_size = {}, 0 end
    measure_cache[str] = w
    measure_cache_size = measure_cache_size + 1
  end
  return w
end

-- Returns changed, text. height in pixels; id must be unique in the window.
-- width: pixels, or nil for the rest of the line.
local function wrapped_editor(id, value, height, flags, width)
  flags = flags or 0
  local avail = width or ImGui.GetContentRegionAvail(ctx)
  local key = tostring(current and current.guid or multi and multi.sig or '') .. id
  local st = wrap_state[key]
  if not st then st = { active = false }; wrap_state[key] = st end
  local shown = wrap.wrap(value, avail - 2 * FRAME_PAD_X - 18, text_width)
  if not st.active then st.prev = shown end
  local changed, v = ImGui.InputTextMultiline(ctx, id, shown, width or -1, height, flags)
  st.active = ImGui.IsItemActive(ctx)
  if changed then
    local text = wrap.apply_edit(value, st.prev, v)
    st.prev = v
    return true, text
  end
  return false, value
end

local function editor(label, value, lines)
  return wrapped_editor(label, value, ImGui.GetTextLineHeight(ctx) * lines + 12)
end

-- Lines a text needs at the given width (at least min_lines): the box grows
-- with its text instead of scrolling sideways.
local function lines_for(value, width, min_lines)
  local shown = wrap.wrap(value, width - 2 * FRAME_PAD_X - 18, text_width)
  local n = 1
  for _ in shown:gmatch('\n') do n = n + 1 end
  return math.max(min_lines or 1, n)
end

local SOURCE_HINT = { ucs = 'from the UCS category', ai = 'written by the model', session = 'from Library (the books icon)',
                      file = 'from the source file', auto = 'automatic', manual = 'multichannel only, e.g. L/R/C/Ls/Rs',
                      item = 'chosen for this item' }

local settings = settings_mod.load()
-- What is stored right now (settings_mod.encoded): a change made in the settings
-- (or by picking a model) is saved as soon as no input box is being edited.
local settings_saved = settings_mod.encoded(settings)
local main_view = nil -- what the main window shows below the top row: nil = the item, 'settings' or 'library'

-- Overview window (draw_overview). rows: { key, n, item, session } in timeline order;
-- order: the rows as the table shows them; specs: its sort columns; counts: file
-- name -> rows using it; tally: status label -> rows.
local overview = { open = false, rows = {}, by_key = {}, order = nil, sig = nil, specs = nil, need_sort = true,
  proj = nil, count = nil, at = 0, counts = {}, tally = {}, names_at = 0, search = '',
  -- Curator panel at the right of the table: shown or not, and its width (kept in ExtState).
  show_curator = reaper.GetExtState(settings_mod.EXT, 'overview_curator_hidden') ~= '1',
  curator_w = tonumber(reaper.GetExtState(settings_mod.EXT, 'overview_curator_width')) or 400 }
local clipper = ImGui.CreateListClipper(ctx) -- the Overview table draws only the rows on screen
ImGui.Attach(ctx, clipper)

-- Models the server lists (GET /v1/models): fetched when the window opens and
-- on Refresh. With a list, Model is a menu ("Type" switches to a text field
-- for IDs the server does not list). When the server says whether a model takes
-- audio, choosing it sets "Model hears audio".
local models = { ids = nil, audio = {}, error = nil, loading = false, manual = false }

-- The server's word on the current model: true, false or nil (unknown).
local function server_hears(id)
  return models.audio and models.audio[id]
end

local function choose_model(id)
  settings.model = id
  local hears = server_hears(id)
  if hears ~= nil then settings.model_audio = hears end
end

local function fetch_models()
  local url = settings_mod.models_url(settings.endpoint)
  if not url then models.ids, models.error = nil, 'set a valid endpoint first'; return end
  local h = {}
  if settings.api_key and settings.api_key ~= '' then h[1] = 'Authorization: Bearer ' .. settings.api_key end
  models.loading, models.error = true, nil
  local id, err = http.get(url, h, 15, function(res)
    models.loading = false
    if not res.ok then models.error = tostring(res.error); return end
    local ids, audio_or_err = settings_mod.parse_models(json, res.body)
    if ids then
      models.ids, models.audio, models.error = ids, audio_or_err or {}, nil
      local hears = server_hears(settings.model)
      if hears ~= nil then settings.model_audio = hears end
    else
      models.ids, models.audio, models.error = nil, {}, audio_or_err
    end
  end)
  if not id then models.loading, models.error = false, err end
end

-- Cards of the items visited while the window is open, by GUID: a request
-- still running finishes on its own card even after the selection changes.
local sessions = {}
local project_sessions, project_chats, active_project = {}, {}, nil
local current_item = nil   -- the selected MediaItem
local item_reason = nil    -- why there is no current card
local last_save = 0
local pending_render = nil -- { overwrite = bool, targets = { cards } }, run at the start of the next frame
local confirm_overwrite = false
local render_msg = nil     -- { text, color }
local view_page = 'Describe' -- Describe | Review | Metadata: set by the item selected (page_for), then free
local playing = nil        -- { item, stop_at, cursor } while the Play button's playback runs

-- The item's audio: measures for the model, and a mono clip when the model
-- hears audio (a temporary WAV the request deletes, or base64 data).
local function measure(s)
  if not s.item or (s.proj and not reaper.ValidatePtr(s.proj, 'ReaProject*'))
      or not reaper.ValidatePtr2(s.proj or 0, s.item, 'MediaItem*') then
    return nil, nil, 'the item no longer exists'
  end
  local take = reaper.GetActiveTake(s.item)
  if not take then return nil, nil, 'no active take' end
  s.facts = item_mod.facts(s.item)
  if s.facts.error then return nil, nil, s.facts.error end
  s.model_facts = item_mod.facts_for_model(s.facts)
  local channels = (s.facts.channels or s.facts.source_channels or 2) == 1 and 1 or 2
  s.measure_start = reaper.time_precise()
  local deadline = s.measure_start + 0.008
  local function pause()
    if reaper.time_precise() < deadline then return false end
    coroutine.yield()
    if (s.proj and not reaper.ValidatePtr(s.proj, 'ReaProject*'))
        or not reaper.ValidatePtr2(s.proj or 0, s.item, 'MediaItem*') or reaper.GetActiveTake(s.item) ~= take then
      error('The active take changed during analysis. Analyze again.', 0)
    end
    deadline = reaper.time_precise() + 0.008
    return true
  end
  local text, bytes, mapping = audio.survey_take(take, channels, s.facts.samplerate,
    math.max(1, settings.listen_max_s or 30), settings.model_audio, pause)
  if not bytes then return text end
  if settings.audio_mode == 1 then return text, { b64 = audio.base64(bytes, pause), mapping = mapping } end
  local path = http.temp_dir() .. '/mtt_metadataassistant_clip_' .. tostring(os.time()) .. '_' .. tostring(math.random(1, 999999)) .. '.wav'
  if not audio.write_file(path, bytes) then return text, nil, 'cannot write ' .. path end
  return text, { path = path, mapping = mapping }
end

local function deps()
  return {
    ucs = ucs, match = match, index = index, fields = fields, filename = filename,
    llm = llm, json = json, post = http.post, cancel = http.cancel, measure = measure, defer_measure = true,
    today = function() return os.date('%Y-%m-%d') end,
  }
end

local function new_session(item, guid)
  local facts = item_mod.facts(item)
  local s = flow.new(deps(), settings, settings_mod.chat_url(settings.endpoint),
    { guid = guid, facts = facts, model_facts = item_mod.facts_for_model(facts) })
  s.proj = reaper.EnumProjects(-1)
  s.item = item
  return s
end

-- Writes the card key into the item (only when it differs), so a cut and paste
-- finds the card again. guid: the item's current GUID.
local function write_tag(item, key, guid)
  if not item or not reaper.ValidatePtr2(0, item, 'MediaItem*') then return end
  local tag = store.format_tag(key, guid)
  local _, old = reaper.GetSetMediaItemInfo_String(item, store.TAG, '', false)
  if old ~= tag then reaper.GetSetMediaItemInfo_String(item, store.TAG, tag, true) end
end

-- Changed cards go to the project at most once a second (and always on exit).
local function save_dirty(force)
  local now = reaper.time_precise()
  if not force and now - last_save < 1 then return end
  last_save = now
  local foreground = reaper.EnumProjects(-1)
  for project, cards in pairs(project_sessions) do
    if project == foreground or reaper.ValidatePtr(project, 'ReaProject*') then
      for key, s in pairs(cards) do
        if s.dirty then
          store.save(json, key, flow.to_card(s), project)
          if s.item and reaper.ValidatePtr2(project, s.item, 'MediaItem*') then write_tag(s.item, key, item_mod.guid(s.item)) end
          s.dirty = false
        end
      end
    else
      for _, s in pairs(cards) do flow.cancel(s) end
      project_sessions[project], project_chats[project] = nil, nil
    end
  end
end

local function item_guid_exists(guid)
  for i = 0, reaper.CountMediaItems(0) - 1 do
    if item_mod.guid(reaper.GetMediaItem(0, i)) == guid then return true end
  end
  return false
end

-- The card key of an item (store.resolve). A pasted item takes over the card
-- of the item it was cut from, or starts from a copy of the card of the item it
-- was copied from; the tag is rewritten at once so this happens only once.
local function card_key(item)
  local guid = item_mod.guid(item)
  local _, tag = reaper.GetSetMediaItemInfo_String(item, store.TAG, '', false)
  local key, action, from = store.resolve(tag, guid, item_guid_exists)
  if action == 'fork' then
    save_dirty(true) -- the source card may have unsaved edits
    local proj = reaper.EnumProjects(-1)
    local card = store.load(json, from, proj)
    if card then store.save(json, key, card, proj) end
    write_tag(item, key, guid)
  elseif action == 'adopt' then
    write_tag(item, key, guid)
  end
  return key
end

-- The card of an item: the one kept while the window is open, else the saved
-- one, else a new one.
local function session_for(item, key)
  key = key or card_key(item)
  local s = sessions[key]
  if not s then
    s = new_session(item, key)
    local card = store.load(json, key, s.proj)
    if card then
      flow.from_card(s, card)
      write_tag(item, key, item_mod.guid(item)) -- cards saved by older versions get their tag now
    end
    sessions[key] = s
  end
  s.item = item
  return s
end

local overwrite_targets = nil -- cards whose file exists, waiting for "Overwrite"

-- The page an item opens on when it is selected: Metadata once it has final values
-- (reviewed), Review while its draft waits, Describe before that (also while a new
-- analysis runs, which drops the draft and the values).
local function page_for(s)
  if s.values then return 'Metadata' end
  if s.draft then return 'Review' end
  return 'Describe'
end

local function track_selection()
  local count = reaper.CountSelectedMediaItems(0)
  -- Library identity filled in after an item was finalized reaches its empty fields (flow.refresh_session).
  local identity = settings_mod.session_values(settings)
  if count > 1 then
    -- Several items: multi-edit. Items in timeline order (selection order breaks ties).
    local list = {}
    for i = 0, count - 1 do
      local it = reaper.GetSelectedMediaItem(0, i)
      list[#list + 1] = { item = it, pos = reaper.GetMediaItemInfo_Value(it, 'D_POSITION'), idx = i }
    end
    table.sort(list, function(a, b) if a.pos ~= b.pos then return a.pos < b.pos end return a.idx < b.idx end)
    local guids, sessions_in_order = {}, {}
    for _, e in ipairs(list) do
      local sess = session_for(e.item)
      flow.refresh_session(sess, identity)
      sessions_in_order[#sessions_in_order + 1] = sess
      guids[#guids + 1] = sess.guid
    end
    local sig = table.concat(guids, ',')
    if not multi or multi.sig ~= sig then
      multi = { sig = sig, overrides = {} }
      confirm_overwrite, render_msg, overwrite_targets = false, nil, nil
    end
    multi.items, multi.with_values, multi.no_values, multi.unsupported = sessions_in_order, {}, 0, 0
    for _, sess in ipairs(sessions_in_order) do
      if sess.facts.error then multi.unsupported = multi.unsupported + 1
      elseif sess.values then multi.with_values[#multi.with_values + 1] = sess
      else multi.no_values = multi.no_values + 1 end
    end
    current, current_item, item_reason = nil, nil, nil
    return
  end
  multi = nil
  local item, reason = item_mod.selected()
  if not item then
    current, current_item, item_reason = nil, nil, reason
    return
  end
  local key = card_key(item)
  current_item, item_reason = item, nil
  if current and current.guid == key then flow.refresh_session(current, identity); return end
  confirm_overwrite, render_msg, overwrite_targets = false, nil, nil
  local s = session_for(item, key)
  flow.refresh_session(s, identity)
  -- Selecting an item opens the page of its step; while it stays selected, the page
  -- moves only when one of its steps completes (draw_workspace).
  view_page = page_for(s)
  s.last_state = s.state
  current = s
end

-- Render jobs: pending_render = { overwrite = bool, targets = { cards } } becomes
-- a batch, one item per frame so the window stays alive.
local batch = nil

local function do_pending_render()
  if pending_render then
    local job = pending_render
    pending_render = nil
    batch = { queue = {}, overwrite = job.overwrite, total = #job.targets, done = 0, exists = {}, errors = {} }
    for _, sess in ipairs(job.targets) do batch.queue[#batch.queue + 1] = sess end
    confirm_overwrite, render_msg, overwrite_targets = false, nil, nil
  end
  if not batch then return end
  local sess = table.remove(batch.queue, 1)
  if sess then
    local r = flow.result(sess)
    local f = sess.facts
    if not reaper.ValidatePtr2(sess.proj or 0, sess.item, 'MediaItem*') then
      batch.errors[#batch.errors + 1] = r.filename .. ': the item no longer exists'
    else
      local path, err = render.render_item(sess.item, {
        dir = render.output_dir(settings.render_dir),
        name = r.filename,
        samplerate = f.samplerate,
        channels = f.channels,
        metadata = r.metadata,
        artwork = (sess.values or {}).Artwork,
      }, batch.overwrite)
      if path then
        sess.rendered = { path = path, at = os.date('%Y-%m-%d %H:%M') }
        sess.dirty = true
        batch.done = batch.done + 1
      elseif err == 'exists' then
        batch.exists[#batch.exists + 1] = sess
      else
        batch.errors[#batch.errors + 1] = r.filename .. ': ' .. tostring(err)
      end
    end
  end
  if #batch.queue == 0 then
    local b = batch
    batch = nil
    overwrite_targets = #b.exists > 0 and b.exists or nil
    confirm_overwrite = #b.exists > 0
    if #b.errors > 0 then
      render_msg = { table.concat(b.errors, '\n'), COL_ERR }
    elseif b.total > 1 and b.done > 0 then
      render_msg = { string.format('Rendered %d of %d files.', b.done, b.total), COL_OK }
    end
  end
end

-- Text in a color, wrapped to the window width.
local function wrapped(text, color)
  if color then ImGui.PushStyleColor(ctx, ImGui.Col_Text, color) end
  ImGui.TextWrapped(ctx, text)
  if color then ImGui.PopStyleColor(ctx) end
end

-- File dialog for the artwork; returns the picked path or nil. REAPER's own
-- dialog (without js_ReaScriptAPI) filters on one extension only: every file
-- shows and render.artwork_problem rejects the wrong ones.
local function pick_image(current_path)
  local start = render.artwork_path(current_path):match('^(.*)[/\\][^/\\]*$') or render.project_dir()
  if reaper.APIExists('JS_Dialog_BrowseForOpenFiles') then
    local rv, path = reaper.JS_Dialog_BrowseForOpenFiles('Artwork', start, '',
      'Images (JPEG, PNG)\0*.jpg;*.jpeg;*.png\0\0', false)
    if rv == 1 and path and path ~= '' then return path end
    return nil
  end
  local ok, path = reaper.GetUserFileNameForRead('', 'Artwork', 'jpg')
  if ok and path ~= '' then return path end
  return nil
end

-- Settings label column: as wide as the longest label of the page on screen plus
-- a gap. Measured from where the row starts (SameLine's offset counts from the
-- window edge, so draw_setting adds the row's start).
local function settings_label_width(page)
  local w = 0
  for _, def in ipairs(settings_mod.KEYS) do
    if def.page == page then
      local tw = ImGui.CalcTextSize(ctx, def.label)
      if tw and tw > w then w = tw end
    end
  end
  return w + 3 * ITEM_SPACING_X
end

-- The model list row under Model: pick from the list or type, refresh, count.
local function draw_model_list_row(label_w)
  ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + label_w)
  if models.ids and #models.ids > 0 then
    if ImGui.SmallButton(ctx, models.manual and 'Pick from list' or 'Type an ID') then models.manual = not models.manual end
    ImGui.SameLine(ctx)
  end
  ImGui.BeginDisabled(ctx, models.loading)
  if ImGui.SmallButton(ctx, 'Refresh') then fetch_models() end
  ImGui.EndDisabled(ctx)
  tip('Asks the server again for its model list.')
  ImGui.SameLine(ctx)
  if models.loading then
    ImGui.TextDisabled(ctx, 'loading...')
  elseif models.error then
    ImGui.TextColored(ctx, COL_WARN, 'models: ' .. models.error)
  else
    local n = #(models.ids or {})
    ImGui.TextDisabled(ctx, n == 1 and '1 model on the server' or string.format('%d models on the server', n))
  end
end

-- One setting: label on the left, its control filling the rest of the row.
local function draw_setting(def, label_w)
  local row_x = ImGui.GetCursorPosX(ctx) -- the window padding
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx, def.label)
  tip(def.tip)
  ImGui.SameLine(ctx, row_x + label_w)
  local id = '##' .. def.key
  local width = ImGui.GetContentRegionAvail(ctx)
  if def.browse and reaper.APIExists('JS_Dialog_BrowseForFolder') then
    width = width - button_width('Browse...') - ITEM_SPACING_X
  end
  if def.kind == 'combo' then
    ImGui.SetNextItemWidth(ctx, width)
    local _, v = ImGui.Combo(ctx, id, settings[def.key], table.concat(def.items, '\0') .. '\0')
    settings[def.key] = v
  elseif def.kind == 'bool' then
    local _, v = ImGui.Checkbox(ctx, id, settings[def.key])
    settings[def.key] = v
    if def.key == 'model_audio' then
      local hears = server_hears(settings.model)
      if hears ~= nil then
        ImGui.SameLine(ctx)
        ImGui.TextDisabled(ctx, hears and 'the server says this model takes audio' or 'the server says this model is text only')
      end
    end
  elseif def.kind == 'int' then
    ImGui.SetNextItemWidth(ctx, 120)
    local _, v = ImGui.InputInt(ctx, id, settings[def.key])
    settings[def.key] = v
  elseif (def.key == 'model' or def.key == 'curator_model') and models.ids and #models.ids > 0 and not models.manual then
    local ids, labels, selected = {}, {}, settings[def.key]
    if def.key == 'curator_model' then ids[1], labels[1] = '', 'Use main model' end
    local listed = false
    for _, mid in ipairs(models.ids) do
      ids[#ids + 1], labels[#labels + 1] = mid, mid
      if selected == mid then listed = true end
    end
    if selected ~= '' and not listed then ids[#ids + 1], labels[#labels + 1] = selected, selected end
    local idx = -1
    for i, mid in ipairs(ids) do if mid == selected then idx = i - 1 end end
    ImGui.SetNextItemWidth(ctx, width)
    local changed, v = ImGui.Combo(ctx, id, idx, table.concat(labels, '\0') .. '\0')
    if changed then
      if def.key == 'model' then choose_model(ids[v + 1])
      else settings.curator_model = ids[v + 1] end
    end
  else
    ImGui.SetNextItemWidth(ctx, width)
    local _, v = ImGui.InputTextWithHint(ctx, id, def.hint or '', settings[def.key],
      def.kind == 'secret' and ImGui.InputTextFlags_Password or 0)
    settings[def.key] = v
  end
  if def.browse and reaper.APIExists('JS_Dialog_BrowseForFolder') then
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, 'Browse...') then
      local ok, folder = reaper.JS_Dialog_BrowseForFolder('Render folder', render.output_dir(settings.render_dir))
      if ok == 1 and folder and folder ~= '' then
        settings.render_dir = render.relative_setting(folder, render.project_dir())
      end
    end
    tip('Pick the folder; it is stored relative to the project folder when it is inside or next to it.')
  end
  if def.browse then
    ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + label_w)
    ImGui.TextDisabled(ctx, 'Files go to: ' .. render.output_dir(settings.render_dir))
    tip('For the current project.')
  end
  if def.key == 'model' then draw_model_list_row(label_w) end
  if def.key == 'outline_items' and not outline.available() then
    ImGui.TextColored(ctx, COL_WARN, 'Needs js_ReaScriptAPI (ReaPack: ReaTeam Extensions): no outlines without it.')
  end
end

-- One settings page: its groups under headings, one row per setting.
local function draw_settings_page(page)
  local label_w = settings_label_width(page)
  local group = nil
  for _, def in ipairs(settings_mod.KEYS) do
    if def.page == page then
      if def.group ~= group then
        group = def.group
        ImGui.Spacing(ctx)
        -- Disable the heading when all rows in the group are disabled.
        local all_off = true
        for _, other in ipairs(settings_mod.KEYS) do
          if other.page == page and other.group == group
              and (other.needs == nil or settings[other.needs]) then all_off = false end
        end
        ImGui.BeginDisabled(ctx, all_off)
        ImGui.SeparatorText(ctx, group)
        ImGui.EndDisabled(ctx)
      end
      ImGui.PushID(ctx, def.key)
      ImGui.BeginDisabled(ctx, def.needs ~= nil and not settings[def.needs])
      draw_setting(def, label_w)
      ImGui.EndDisabled(ctx)
      ImGui.PopID(ctx)
    end
  end
end

-- Playback of the selected item from its start to its end, started by the Play
-- button. The edit cursor is put back where it was when the playback ends.
local function play_item(item)
  if not reaper.ValidatePtr2(0, item, 'MediaItem*') then return end
  local pos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
  local len = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
  local cursor = playing and playing.cursor or reaper.GetCursorPosition()
  if reaper.GetPlayState() & 1 ~= 0 then
    reaper.SetEditCurPos(pos, false, true)   -- already playing: jump to the item
  else
    reaper.SetEditCurPos(pos, false, false)
    reaper.OnPlayButton()
  end
  playing = { item = item, stop_at = pos + len, cursor = cursor }
end

local function stop_item()
  reaper.OnStopButton()
end

-- Every frame: ends the item playback at the end of the item, and restores the
-- edit cursor once the transport has stopped.
local function watch_playing()
  if not playing then return end
  local state = reaper.GetPlayState()
  if state & 3 == 0 then
    reaper.SetEditCurPos(playing.cursor, false, false)
    playing = nil
  elseif state & 2 == 0 and reaper.GetPlayPosition() >= playing.stop_at then
    reaper.OnStopButton()
  end
end

local function draw_item()
  if not current or current.facts.error then
    ImGui.AlignTextToFramePadding(ctx)
    if current then ImGui.TextColored(ctx, COL_ERR, current.facts.error)
    else ImGui.TextColored(ctx, COL_WARN, item_reason or 'Select one item.') end
    return false
  end
  local f = current.facts
  local is_playing = playing ~= nil and playing.item == current_item
  if icons.button('##play', is_playing, is_playing and icons.stop or icons.play) then
    if is_playing then stop_item() else play_item(current_item) end
  end
  tip(is_playing and 'Stop.' or 'Plays the selected item from its start to its end; click again to stop. The edit cursor goes back to where it was.')
  ImGui.SameLine(ctx)
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.TextDisabled(ctx, string.format('%d Hz  -  %d ch  -  %.2f s  -  recorded %s',
    f.samplerate or 0, f.channels or 0, f.length or 0, f.recorded_on or 'date unknown'))
  tip('Sample rate, channel count and length of the item, and the recording date when the file carries one. The render keeps the sample rate and channel count.')
  return true
end

-- Header when several items are selected.
local function draw_multi_header()
  ImGui.TextDisabled(ctx, string.format('%d items selected: a field typed in Review goes to all of them', #multi.items))
  tip('Multi-edit. Items are taken in timeline order. A value typed once replaces that field in every selected item that already has metadata; file names are numbered 01, 02, 03... '
    .. 'Copy an item first (the copy icon in its Review) to preview its values by hovering the fields.')
end

local function draw_description()
  ImGui.SeparatorText(ctx, 'Sound description')
  local configured = settings_mod.chat_url(settings.endpoint) and settings.model ~= ''
  if not configured then
    ImGui.TextColored(ctx, COL_WARN, 'Open Settings: set Endpoint and Model.')
  end
  local busy = flow.busy(current)
  wrapped(settings.model_audio and 'Describe what you recorded, or let the model listen.'
    or 'Describe what you recorded and how it sounds, in Italian or English.', COL_DIM)
  -- While the model works the text cannot be changed but it can still be selected
  -- and copied (read-only, not disabled); a darker background shows the difference.
  -- The box fills the window down to the button row under it (one frame tall,
  -- one item spacing above it).
  local _, available = ImGui.GetContentRegionAvail(ctx)
  local _, spacing_y = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing)
  local height = math.max(ImGui.GetTextLineHeight(ctx) * 6, available - ImGui.GetFrameHeight(ctx) - spacing_y)
  if busy then ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, 0x232526FF) end
  ImGui.PushID(ctx, current.guid)
  local changed, v = wrapped_editor('##description', current.description, height,
    busy and ImGui.InputTextFlags_ReadOnly or 0)
  ImGui.PopID(ctx)
  if busy then ImGui.PopStyleColor(ctx) end
  if changed and not busy then
    current.description = v
    current.dirty = true
  end
  -- One full-width button: Analyze, or Stop while the model works.
  if busy then
    if ImGui.Button(ctx, 'Stop', -1) then flow.cancel(current) end
    tip('Interrupts the request: the model server is told to stop generating and the description becomes editable again.')
    return
  end
  ImGui.BeginDisabled(ctx, not configured or (not settings.model_audio and current.description:match('^%s*$') ~= nil))
  if accent_button(current.draft and 'Analyze again (new draft)' or 'Analyze', -1) then
    current.settings = settings
    current.url = settings_mod.chat_url(settings.endpoint)
    confirm_overwrite, render_msg = false, nil
    flow.analyze(current, current.description, settings_mod.session_values(settings))
  end
  ImGui.EndDisabled(ctx)
  tip('Sends the description to the model: it picks the UCS category and drafts the fields, then may ask a few questions. Only what you wrote, the audio measurements and the metadata inside the file are sent; the item and file names are not.')
end

-- Errors of the selected item, under the tabs (what the model is doing goes on the
-- top row, next to its name: status_line).
local function draw_status()
  if current.state == 'error' then
    wrapped('Error: ' .. tostring(current.error), COL_ERR)
  end
  if current.listen_error then wrapped('Without listening: ' .. current.listen_error, COL_WARN) end
end

local function draw_draft()
  local d = current.draft
  if not d or current.state == 'drafting' then return end
  ImGui.SeparatorText(ctx, 'Suggested category')
  ImGui.Text(ctx, string.format('%s  -  %s = %s / %s', d.sound_type or '?', d.catid, d.entry.cat, d.entry.sub))
  if current.heard then wrapped('Heard: ' .. current.heard, COL_DIM) end
  for _, p in ipairs(current.problems or {}) do wrapped(p, COL_WARN) end
end

local function draw_questions()
  if not current.draft or current.state == 'drafting' then return end
  ImGui.SeparatorText(ctx, 'Questions')
  if #current.answers == 0 then
    ImGui.TextDisabled(ctx, 'No questions: the description was enough.')
  end
  for i, q in ipairs(current.draft.questions) do
    local a = current.answers[i]
    ImGui.PushID(ctx, current.guid .. ':' .. i)
    wrapped(q.text)
    local row_width = ImGui.GetContentRegionAvail(ctx)
    local used = 0
    for j, opt in ipairs(q.options) do
      local width = ImGui.CalcTextSize(ctx, opt) + 18
      if used > 0 and used + 8 + width <= row_width then
        ImGui.SameLine(ctx)
        used = used + 8
      else
        used = 0
      end
      used = used + width
      local selected = a.answer == opt
      if selected then ImGui.PushStyleColor(ctx, ImGui.Col_Button, COL_SELECTED) end
      local clicked = ImGui.Button(ctx, opt .. '##opt' .. j)
      if selected then ImGui.PopStyleColor(ctx) end
      if clicked then
        a.answer = selected and '' or opt
        current.dirty = true
      end
    end
    ImGui.TextDisabled(ctx, 'Your answer (optional)')
    tip('Type the answer in your own words, or click one of the suggestions above. Leave it empty to skip the question.')
    local changed, v = editor('##answer', a.answer, 3)
    if changed then
      a.answer = v
      current.dirty = true
    end
    ImGui.PopID(ctx)
    ImGui.Spacing(ctx)
  end
  ImGui.BeginDisabled(ctx, flow.busy(current))
  if accent_button(current.values and 'Finalize again (replaces metadata)' or 'Finalize') then
    current.settings = settings
    current.url = settings_mod.chat_url(settings.endpoint)
    flow.finalize(current)
  end
  ImGui.EndDisabled(ctx)
  tip('Sends your answers to the model, which writes the final metadata. Every field can then be edited by hand.')
end

-- Field key hovered in the multi view (it shows the copied value): last frame, this frame.
local paste_hover, paste_hover_seen = nil, nil

-- Label column of the metadata fields (as wide as the longest field name).
local label_w = nil
local function label_width()
  if not label_w then
    local w = 0
    for _, def in ipairs(fields.FIELDS) do w = math.max(w, text_width(def.key)) end
    label_w = w + 30
  end
  return label_w
end

local FILENAME_TIP = 'The file name Render will write, without ".wav": CatID_VendorCategory-FXName_CreatorID_SourceID. '
  .. 'It follows the fields below; type here to name the file by hand (editing one of the fields that make up the name goes back to the automatic name).'

local FILENAME_TIP_MULTI = 'Type a name to give it to every selected item, numbered 01, 02, 03... in timeline order '
  .. '(the number goes at the end of the FXName block). Empty goes back to each item\'s automatic name.'

local GROUPS = { CatID = 'Classification', FXName = 'Sound metadata', MicPerspective = 'Recording',
  Designer = 'Library credits', TrackYear = 'Dates and notes', Artwork = 'Artwork' }

-- The metadata fields, grouped. get(key) -> text; set(key, text); mixed(key) ->
-- true when the selected items hold different values (multi-edit);
-- extra_tip(key) -> text appended to the tooltip; paste = { get(key) -> copied text or
-- nil, apply(key), tip(key) } (multi-edit): hovering a box with a copied value shows
-- that value, highlighted; a left click applies it.
local function draw_fields(scope, get, set, mixed, extra_tip, paste)
  local expanded
  for _, def in ipairs(fields.FIELDS) do
    if GROUPS[def.key] then
      if def.key == 'FXName' then ImGui.SetNextItemOpen(ctx, true, ImGui.Cond_Once) end
      expanded = ImGui.CollapsingHeader(ctx, GROUPS[def.key])
    end
    if expanded then
      ImGui.PushID(ctx, scope .. def.key)
      local value = get(def.key)
      local multiline = def.long or def.key == 'Notes'
      local pasted = paste and paste.get(def.key) or nil
      local previewing = pasted ~= nil and paste_hover == def.key
      local is_mixed = mixed and mixed(def.key)
      ImGui.AlignTextToFramePadding(ctx)
      if previewing then ImGui.TextColored(ctx, COL_ACCENT, def.key) else ImGui.Text(ctx, def.key) end
      if is_mixed then
        ImGui.SameLine(ctx, 0, 4)
        ImGui.TextColored(ctx, COL_ACCENT, '*')
      end
      local source = SOURCE_HINT[def.source]
      tip((fields.TIPS[def.key] or def.key) .. (source and ('\n\nValue: ' .. source .. '.') or '')
        .. (is_mixed and '\n\n* The selected items have different values here; typing replaces them all.' or '')
        .. (extra_tip and extra_tip(def.key) or ''))
      ImGui.SameLine(ctx, label_width())
      local width = ImGui.GetContentRegionAvail(ctx)
      local browse_image = def.key == 'Artwork' and not previewing
      if browse_image then width = width - button_width('Browse...') - ITEM_SPACING_X end
      local min_lines = def.key == 'Description' and 5 or (multiline and 3 or 1)
      local lines = lines_for(value, width, min_lines)
      -- The box keeps its height while previewing, or it would move away from the mouse.
      if pasted ~= nil then lines = math.max(lines, lines_for(pasted, width, min_lines)) end
      -- Single-value fields take Enter as "done" (Ctrl+Enter would add a break, which is removed).
      local flags = multiline and 0 or ImGui.InputTextFlags_CtrlEnterForNewLine
      if previewing then
        flags = flags | ImGui.InputTextFlags_ReadOnly -- a click applies the value, it does not edit
        ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, COL_PREVIEW)
      end
      -- The preview is a widget of its own (another ID), always read-only: a click
      -- activates it, and an input box made editable while active after being
      -- activated read-only has no text copy (Dear ImGui asserts
      -- "state->TextA[state->TextLen] == 0" when it is released).
      local changed, v = wrapped_editor((previewing and '##preview' or '##value') .. def.key,
        previewing and pasted or value, ImGui.GetTextLineHeight(ctx) * lines + 12, flags, width)
      if previewing then ImGui.PopStyleColor(ctx) end
      if changed then
        if not multiline then v = v:gsub('[\r\n]+', ' ') end
        set(def.key, v)
      end
      if browse_image then
        ImGui.SameLine(ctx)
        if ImGui.Button(ctx, 'Browse...') then
          local picked = pick_image(value)
          if picked then set(def.key, picked) end
        end
        tip('Pick a JPEG or PNG file. With several items selected it goes to all of them.')
        local problem = render.artwork_problem(value)
        if problem then
          ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + label_width())
          wrapped(problem .. ' (Render stops for this item until it is fixed or cleared)', COL_WARN)
        end
      end
      if pasted ~= nil then
        -- Hover is known after the box is drawn: it takes effect on the next frame.
        if ImGui.IsItemHovered(ctx) then paste_hover_seen = def.key end
        local clicked = previewing and ImGui.IsItemClicked(ctx, 0)
        if previewing then tip(paste.tip(def.key)) end
        if clicked then paste.apply(def.key) end
      end
      ImGui.PopID(ctx)
    end
  end
end

-- Warnings first, in orange; or the green line when everything is fine.
local function draw_name_status(problems, missing)
  if #problems == 0 and #missing == 0 then
    ImGui.TextColored(ctx, COL_OK, 'The name is valid and the required fields are filled.')
    return
  end
  for _, p in ipairs(problems) do wrapped(p, COL_WARN) end
  if #missing > 0 then
    wrapped('Missing: ' .. table.concat(missing, ', ') .. ' (set in Library, the books icon)', COL_WARN)
  end
end

local function draw_result()
  if not current.values then
    ImGui.TextDisabled(ctx, 'No metadata for this item yet: describe it, analyze, answer and finalize.')
    return
  end
  ImGui.SeparatorText(ctx, 'Output file')
  local r = flow.result(current)
  draw_name_status(r.problems, r.missing)
  ImGui.Text(ctx, 'File name')
  tip(FILENAME_TIP)
  if r.edited then
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, 'Back to automatic') then
      flow.set_filename(current, '')
      r = flow.result(current)
    end
    tip('Drops the name you typed and builds it from the fields again.')
  end
  do
    local width = ImGui.GetContentRegionAvail(ctx)
    ImGui.PushID(ctx, current.guid)
    local lines = lines_for(r.filename, width, 2)
    local changed, v = wrapped_editor('##filename', r.filename,
      ImGui.GetTextLineHeight(ctx) * lines + 12, ImGui.InputTextFlags_CtrlEnterForNewLine)
    ImGui.PopID(ctx)
    if changed then flow.set_filename(current, v) end
  end
  draw_fields(current.guid,
    function(key) return current.values[key] or '' end,
    function(key, v) flow.set_value(current, key, v) end)
end

---------------------------------------------------------------- multi-edit

-- The value every item with metadata holds for a field, or nil when they differ.
local function multi_common(get)
  local common
  for i, sess in ipairs(multi.with_values) do
    local v = get(sess)
    if i == 1 then common = v elseif v ~= common then return nil end
  end
  return common
end

-- FXName override: the text numbered 01, 02, 03... one per item.
local function numbered_fx(text, index, count)
  if text == '' or count < 2 then return text end
  return filename.variant_fxnames(text, count)[index]
end

local function multi_set(key, text)
  multi.overrides[key] = text
  local n = #multi.with_values
  for i, sess in ipairs(multi.with_values) do
    flow.set_value(sess, key, key == 'FXName' and numbered_fx(text, i, n) or text)
  end
end

local FILENAME_KEY = '#filename'

-- What Copy took from an item: { values = { key = text }, name = its file name,
-- name_typed = true when that name was typed by hand }. In multi-edit, hovering a
-- field or the file name shows its copied value and a click puts it in every
-- selected item (as typing it would); Paste all does it for everything copied.
local copied = nil

local function copy_item(sess)
  local values = {}
  for _, def in ipairs(fields.FIELDS) do
    local v = sess.values[def.key]
    if v ~= nil then values[def.key] = v end
  end
  local r = flow.result(sess)
  copied = { values = values, name = r.filename, name_typed = r.edited }
end

local function multi_paste(key)
  local v = copied and copied.values[key]
  if v == nil then return end
  multi_set(key, v)
  -- A field that makes up the file name drops the names typed by hand (set_value does it).
  if flow.NAME_KEYS[key] then multi.overrides[FILENAME_KEY] = nil end
end

local function multi_set_filename(text)
  multi.overrides[FILENAME_KEY] = text
  local clean = filename.clean_name(text)
  local n = #multi.with_values
  for i, sess in ipairs(multi.with_values) do
    flow.set_filename(sess, (clean ~= '' and n > 1) and filename.number_name(clean, i, n) or clean)
  end
end

-- Fields in the order of fields.FIELDS: CatID first, because it rewrites Category,
-- SubCategory and CategoryFull, which the copied values then overwrite. The file
-- name last, and only when it was typed by hand on the copied item: an automatic
-- one already follows from the pasted fields (FXName numbered as the name would be).
local function multi_paste_all()
  for _, def in ipairs(fields.FIELDS) do multi_paste(def.key) end
  if copied and copied.name_typed then multi_set_filename(copied.name) end
end

local function draw_multi_result()
  paste_hover, paste_hover_seen = paste_hover_seen, nil
  ImGui.SeparatorText(ctx, 'Output files')
  local n = #multi.with_values
  if multi.no_values > 0 then
    wrapped(string.format('%d of the selected items have no metadata yet and are left out: describe and finalize each of them first.',
      multi.no_values), COL_WARN)
  end
  if multi.unsupported > 0 then
    wrapped(string.format('%d selected items cannot be tagged (no audio take) and are left out.', multi.unsupported), COL_WARN)
  end
  if n == 0 then
    ImGui.TextDisabled(ctx, 'None of the selected items has metadata yet.')
    return
  end
  -- Warnings first.
  local names, duplicated, with_problems = {}, false, 0
  for _, sess in ipairs(multi.with_values) do
    local r = flow.result(sess)
    if names[r.filename] then duplicated = true end
    names[r.filename] = true
    if #r.problems > 0 or #r.missing > 0 then with_problems = with_problems + 1 end
  end
  if duplicated then
    wrapped('Several items would get the same file name: type a file name or an FXName below and they are numbered.', COL_WARN)
  end
  if with_problems > 0 then
    wrapped(string.format('%d of %d items have a file name problem or a missing field: select one of them to see it.',
      with_problems, n), COL_WARN)
  elseif not duplicated then
    ImGui.TextColored(ctx, COL_OK, 'All names are valid and the required fields are filled.')
  end

  -- The file name box previews and pastes the copied name like the fields below do.
  local pasted = copied and copied.name or nil
  local previewing = pasted ~= nil and paste_hover == FILENAME_KEY
  if previewing then ImGui.TextColored(ctx, COL_ACCENT, 'File name') else ImGui.Text(ctx, 'File name') end
  tip(FILENAME_TIP_MULTI)
  local width = ImGui.GetContentRegionAvail(ctx)
  local typed = multi.overrides[FILENAME_KEY]
  local shown = typed
  if shown == nil then
    shown = multi_common(function(sess) return flow.result(sess).filename end) or ''
  end
  local lines = lines_for(shown, width, 2)
  -- The box keeps its height while previewing, or it would move away from the mouse.
  if pasted ~= nil then lines = math.max(lines, lines_for(pasted, width, 2)) end
  local flags = ImGui.InputTextFlags_CtrlEnterForNewLine
  if previewing then
    flags = flags | ImGui.InputTextFlags_ReadOnly -- a click applies the name, it does not edit
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, COL_PREVIEW)
  end
  ImGui.PushID(ctx, 'multi')
  -- Its own read-only widget while previewing, as in draw_fields.
  local changed, v = wrapped_editor(previewing and '##filename_preview' or '##filename', previewing and pasted or shown,
    ImGui.GetTextLineHeight(ctx) * lines + 12, flags)
  ImGui.PopID(ctx)
  if previewing then ImGui.PopStyleColor(ctx) end
  if changed then multi_set_filename(v) end
  if pasted ~= nil then
    -- Hover is known after the box is drawn: it takes effect on the next frame.
    if ImGui.IsItemHovered(ctx) then paste_hover_seen = FILENAME_KEY end
    local clicked = previewing and ImGui.IsItemClicked(ctx, 0)
    if previewing then
      tip(string.format('Copied file name, from %s. Click to give it to the %d selected items, numbered 01, 02, 03... in timeline order.',
        copied.name, n))
    end
    if clicked then multi_set_filename(pasted) end
  end

  draw_fields('multi',
    function(key)
      local o = multi.overrides[key]
      if o ~= nil then return o end
      return multi_common(function(sess) return sess.values[key] or '' end) or ''
    end,
    multi_set,
    function(key)
      return multi.overrides[key] == nil
        and multi_common(function(sess) return sess.values[key] or '' end) == nil
    end,
    function(key)
      return key == 'FXName' and '\n\nWith several items the text is numbered 01, 02, 03... one per item.' or ''
    end,
    copied and {
      get = function(key) return copied.values[key] end,
      apply = multi_paste,
      tip = function() return string.format('Copied value, from %s. Click to put it in the %d selected items.', copied.name, n) end,
    } or nil)
end

---------------------------------------------------------------- overview

-- The Overview window: every item of the project that has a card (overview_mod lists
-- them), one row each with its status, file name and every metadata field, editable
-- in place and sortable by any column (click a header; Shift-click adds a column).
-- Rows keep their place while a value is edited: they are sorted again when a header
-- is clicked or the items listed change. ReaImGui keeps the column widths, order,
-- visibility and sort with the window settings.
local OVERVIEW_COLS = { { key = 'File name' } }
for _, def in ipairs(fields.FIELDS) do OVERVIEW_COLS[#OVERVIEW_COLS + 1] = { key = def.key } end
local OVERVIEW_FROZEN = 1 -- File name (with the play icon) stays in view while scrolling sideways
local OVERVIEW_WIDTHS = { ['File name'] = 380, CategoryFull = 170, UserCategory = 110,
  VendorCategory = 140, FXName = 200, TrackTitle = 200, Description = 380, Keywords = 300, Location = 150,
  Microphone = 160, Manufacturer = 130, Library = 140, URL = 160, Copyright = 160, Notes = 160 }
local OVERVIEW_DEFAULT_WIDTH = 104
local OVERVIEW_TIPS = {
  ['File name'] = FILENAME_TIP .. '\n\nThe colour of the name is the item\'s status: grey not analyzed, orange being analyzed, yellow to review, green reviewed, blue rendered, red error. '
    .. 'A red cell: the name has a problem or a required field is empty (hover the cell). An orange cell: another item has the same name.'
    .. '\n\nClick a row to select its item in REAPER (Cmd/Ctrl- or Shift-click adds it to the selection or takes it out); double-click a cell to edit it. The play icon plays the item from start to end (a square stops it).',
}
local OVERVIEW_FLAGS = ImGui.TableFlags_Resizable | ImGui.TableFlags_Reorderable | ImGui.TableFlags_Hideable
  | ImGui.TableFlags_Sortable | ImGui.TableFlags_SortMulti | ImGui.TableFlags_RowBg
  | ImGui.TableFlags_BordersInnerV | ImGui.TableFlags_BordersOuter
  | ImGui.TableFlags_ScrollX | ImGui.TableFlags_ScrollY | ImGui.TableFlags_SizingFixedFit
local OVERVIEW_RESCAN_S = 2 -- the items are listed again at least this often
local STATUS_COLORS = { ok = COL_OK, warn = COL_WARN, busy = COL_ACCENT, dim = COL_DIM, err = COL_ERR, rendered = 0x66C2E0FF }
local TALLY_ORDER = { 'Rendered', 'Reviewed', 'To review', 'Finalizing', 'Analyzing', 'Listening', 'Measuring', 'Not analyzed', 'Error' }
local COL_CELL_ERR = 0x6E2A2AFF  -- file name with a problem or a required field missing
local COL_CELL_DUP = 0x5C4521FF  -- file name another item has too
local COL_ROW_SELECTED = 0x9A632255 -- item selected in REAPER
-- The fixed columns (OVERVIEW_FROZEN) against the ones that scroll: a cool tint on their header and
-- cells, and a line after the last one.
local FROZEN = { cell = 0x9DB4CC20, head = 0x9DB4CC3C, line = 0x9DB4CCCC }
local FROZEN_TIP = '\n\nFixed column: it stays in view when the table scrolls sideways; the columns to its right scroll.' 
local FLT_MIN = ImGui.NumericLimits_Float()

-- Lists the project's items with a card again when the project or its state change, or
-- every OVERVIEW_RESCAN_S seconds. Each row is the item's card session (session_for), so
-- an edit here takes the same path as on the Metadata page; a copied item gets its own
-- card here, as when it is selected. Two items holding the same card key get one row
-- (the first on the timeline).
local function overview_refresh(force)
  local proj = reaper.EnumProjects(-1)
  local count = reaper.GetProjectStateChangeCount(proj)
  local now = reaper.time_precise()
  if not force and proj == overview.proj and count == overview.count and now - overview.at < OVERVIEW_RESCAN_S then return end
  if proj ~= overview.proj then overview.paste_status = nil end
  overview.proj, overview.count, overview.at = proj, count, now
  local rows, by_key, keys = {}, {}, {}
  local identity = settings_mod.session_values(settings)
  for _, e in ipairs(overview_mod.tagged_items(store)) do
    local key = card_key(e.item)
    if not by_key[key] then
      local s = session_for(e.item, key)
      flow.refresh_session(s, identity)
      if overview_mod.has_content(s) then
        local row = { key = key, item = e.item, session = s, n = #rows + 1 }
        rows[#rows + 1] = row
        by_key[key] = row
        keys[#keys + 1] = key
      end
    end
  end
  local sig = table.concat(keys, ',')
  overview.order = overview_mod.keep_order(overview.order, overview.sig, by_key, sig)
  overview.need_sort = overview.order == nil
  overview.rows, overview.by_key, overview.sig = rows, by_key, sig
  overview.names_at = 0
end

-- How many rows use each file name, and how many rows have each status: at most twice
-- a second, and right after an edit here.
local function overview_count()
  local now = reaper.time_precise()
  if now - overview.names_at < 0.5 then return end
  overview.names_at = now
  local names, tally, kinds = {}, {}, {}
  for _, row in ipairs(overview.rows) do
    local s = row.session
    names[row.key] = s.values and flow.result(s).filename or nil
    local st = overview_mod.status(s)
    tally[st.label] = (tally[st.label] or 0) + 1
    kinds[st.label] = st.kind
  end
  overview.counts, overview.tally, overview.tally_kind = overview_mod.name_counts(names), tally, kinds
end

-- What a column sorts by.
local function overview_value(row, key)
  local s = row.session
  if not s.values then return '' end
  if key == 'File name' then return flow.result(s).filename end
  return s.values[key] or ''
end

-- Search the full text of every column, including hidden fields and the description
-- shown in place of a file name while a card has no final metadata yet.
local function overview_search_value(row, key)
  if key == 'File name' then
    local status = overview_mod.status(row.session).label
    if not row.session.values then return status .. ' ' .. (row.session.description or '') end
    return status .. ' ' .. overview_value(row, key)
  end
  return overview_value(row, key)
end

-- An edit typed in the table: the same calls as the Metadata page. The multi-edit view
-- shows the text typed there (multi.overrides) instead of the items' values: it is
-- dropped for that field, so the main window shows the new values.
local function overview_set(s, key, v)
  if key == 'File name' then
    flow.set_filename(s, v)
    if multi then multi.overrides[FILENAME_KEY] = nil end
  else
    flow.set_value(s, key, v)
    if multi then
      multi.overrides[key] = nil
      if flow.NAME_KEYS[key] then multi.overrides[FILENAME_KEY] = nil end
    end
  end
  overview.names_at = 0
end

-- Always use all project rows, irrespective of selection, sorting and filtering.
-- Like typing in a cell, a column paste uses the literal value (even for FXName).
local function paste_column(key, value)
  overview_refresh(true)
  local applied = 0
  for _, row in ipairs(overview.rows) do
    if row.session.values and not flow.busy(row.session) then
      overview_set(row.session, key, value)
      applied = applied + 1
    end
  end
  overview.paste_status = string.format('%s pasted to %d rows (%d skipped).', key, applied, #overview.rows - applied)
end

local function column_menu(key, value)
  if not ImGui.BeginPopupContextItem(ctx) then return end
  local copy_field, _ = ImGui.MenuItem(ctx, 'Copy field')
  if copy_field then
    ImGui.SetClipboardText(ctx, value)
    overview.copied_field = {key = key, value = value}
    overview.paste_status = nil
  end
  local text = ImGui.GetClipboardText(ctx)
  local paste_text, _ = ImGui.MenuItem(ctx, 'Paste clipboard to entire ' .. key .. ' column', nil, nil, text ~= '')
  if paste_text then
    paste_column(key, text)
  end
  if copied then
    local from_item = key == 'File name' and copied.name or copied.values[key] or ''
    local paste_item, _ = ImGui.MenuItem(ctx, 'Paste ' .. key .. ' from copied item to entire column')
    if paste_item then
      paste_column(key, from_item)
    end
  end
  ImGui.EndPopup(ctx)
end

-- Selects the row's item in REAPER (the main window follows the selection); add:
-- toggles it in the current selection instead.
local function overview_select(item, add)
  if add then
    reaper.SetMediaItemSelected(item, not reaper.IsMediaItemSelected(item))
  else
    reaper.SelectAllMediaItems(0, false)
    reaper.SetMediaItemSelected(item, true)
  end
  reaper.UpdateArrange()
end

-- What the status says, for the tooltip of a row's file name cell.
local function overview_status_note(s, st)
  if s.state == 'error' then return 'Error: ' .. tostring(s.error) end
  if s.state == 'done' and s.rendered then return 'Rendered ' .. tostring(s.rendered.at) .. ': ' .. tostring(s.rendered.path) end
  if s.state == 'questions' then return 'To review: select the item, check the category, answer the questions and finalize in Clarify.' end
  if s.state == 'idle' then return 'Not analyzed: select the item and analyze its description on Describe.' end
  return st.label .. '.'
end

-- One cell: text (a click selects the row's item in REAPER, a double click edits it) or, while
-- it is being edited, the input box. color: colour of the text. Returns true when the edit box
-- was changed.
function overview.cell(row, key, value, color, item_ok)
  local s = row.session
  local id = row.key .. '|' .. key
  if overview.editing == id then
    if flow.busy(s) then
      overview.editing = nil -- the model is writing this card: its answer would replace the edit
    else
      ImGui.SetNextItemWidth(ctx, -FLT_MIN)
      if overview.focus then ImGui.SetKeyboardFocusHere(ctx); overview.focus = false end
      local changed, v = ImGui.InputText(ctx, '##edit', value)
      if changed then overview_set(s, key, v) end
      if ImGui.IsItemDeactivated(ctx) then overview.editing = nil end
      return changed
    end
  end
  -- One line per cell: line breaks show as spaces (an edit keeps the spaces).
  local shown = value
  if shown:find('[\r\n]') then shown = (shown:gsub('%s*[\r\n]+%s*', ' ')) end
  shown = (shown:gsub('##', '# #'))
  ImGui.AlignTextToFramePadding(ctx)
  if color then ImGui.PushStyleColor(ctx, ImGui.Col_Text, color) end
  local clicked = ImGui.Selectable(ctx, shown .. '##cell', false, ImGui.SelectableFlags_AllowDoubleClick)
  if color then ImGui.PopStyleColor(ctx) end
  if clicked then
    if ImGui.IsMouseDoubleClicked(ctx, 0) then
      if s.values and not flow.busy(s) then overview.editing, overview.focus = id, true end
    elseif item_ok then
      local mods = ImGui.GetKeyMods(ctx)
      overview_select(row.item, mods & (ImGui.Mod_Ctrl | ImGui.Mod_Super | ImGui.Mod_Shift) ~= 0)
    end
  end
  return false
end

local function overview_row(row, row_h)
  local s = row.session
  local item_ok = reaper.ValidatePtr2(0, row.item, 'MediaItem*')
  ImGui.TableNextRow(ctx, 0, row_h)
  if item_ok and reaper.IsMediaItemSelected(row.item) then
    ImGui.TableSetBgColor(ctx, ImGui.TableBgTarget_RowBg1, COL_ROW_SELECTED)
  end
  local st = overview_mod.status(s)
  if ImGui.TableSetColumnIndex(ctx, 0) then
    ImGui.TableSetBgColor(ctx, ImGui.TableBgTarget_CellBg, FROZEN.cell) -- the problem / duplicate colours below replace it
    local is_playing = playing ~= nil and playing.item == row.item
    ImGui.BeginDisabled(ctx, not item_ok)
    if icons.button('##play', is_playing, is_playing and icons.stop or icons.play) then
      if is_playing then stop_item() else play_item(row.item) end
    end
    ImGui.EndDisabled(ctx)
    tip(is_playing and 'Stop.' or 'Plays this item from start to end; click again to stop. The edit cursor returns to its original position.')
    ImGui.SameLine(ctx)
    local color = STATUS_COLORS[st.kind] or COL_DIM
    if s.values then
      local r = flow.result(s)
      local dup = (overview.counts[r.filename] or 0) > 1
      local notes = { overview_status_note(s, st) }
      local problems = {}
      for _, p in ipairs(r.problems) do problems[#problems + 1] = p end
      if #r.missing > 0 then problems[#problems + 1] = 'Missing: ' .. table.concat(r.missing, ', ') .. ' (set in Library, the books icon)' end
      if #problems > 0 then ImGui.TableSetBgColor(ctx, ImGui.TableBgTarget_CellBg, COL_CELL_ERR)
      elseif dup then ImGui.TableSetBgColor(ctx, ImGui.TableBgTarget_CellBg, COL_CELL_DUP) end
      for _, p in ipairs(problems) do notes[#notes + 1] = p end
      if dup then notes[#notes + 1] = string.format('%d items have this file name.', overview.counts[r.filename]) end
      if r.edited then notes[#notes + 1] = 'Typed by hand: editing CatID, UserCategory, VendorCategory, FXName, ShortID or SourceID goes back to the automatic name.' end
      local changed = overview.cell(row, 'File name', r.filename, color, item_ok)
      tip(table.concat(notes, '\n'))
      column_menu('File name', changed and flow.result(s).filename or r.filename)
    else
      -- No file name yet: the start of the description tells which item it is.
      local text = s.description:match('%S') and overview_mod.short_text(s.description, 70) or '(no description)'
      overview.cell(row, 'File name', text, color, item_ok)
      tip(overview_status_note(s, st))
    end
  end
  if s.values then
    for ci = OVERVIEW_FROZEN + 1, #OVERVIEW_COLS do
      if ImGui.TableSetColumnIndex(ctx, ci - 1) then -- false for a hidden column or one scrolled out of view
        local key = OVERVIEW_COLS[ci].key
        overview.cell(row, key, s.values[key] or '', nil, item_ok)
        column_menu(key, s.values[key] or '')
      end
    end
  end
end

-- The table sits in a child that cuts off the table's own horizontal scrollbar (the table is
-- taller than the child by the bar's height), because that bar spans the fixed column too and
-- the fixed column never scrolls. A bar drawn under the scrolling columns only replaces it, and
-- scrolls the table (overview.set_scroll_x, applied inside the table in the next frame).
local function overview_table()
  local sb = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ScrollbarSize)
  local table_x, table_y = ImGui.GetCursorScreenPos(ctx)
  local avail_w, avail_h = ImGui.GetContentRegionAvail(ctx)
  local clip_h = math.max(avail_h - sb, 80)
  local scroll_x, scroll_max, v_scroll = 0, 0, false
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, 0x00000000) -- cells read as text until edited
  local child = ImGui.BeginChild(ctx, 'overview_clip', avail_w, clip_h, ImGui.ChildFlags_None,
    ImGui.WindowFlags_NoScrollbar | ImGui.WindowFlags_NoScrollWithMouse)
  if child and ImGui.BeginTable(ctx, 'overview', #OVERVIEW_COLS, OVERVIEW_FLAGS, 0, clip_h + (overview.hscroll and sb or 0)) then
    if overview.set_scroll_x then ImGui.SetScrollX(ctx, overview.set_scroll_x); overview.set_scroll_x = nil end
    for i, col in ipairs(OVERVIEW_COLS) do
      local flags = ImGui.TableColumnFlags_WidthFixed
      -- The frozen column stays first and visible (a field dragged before it would be frozen instead).
      if i <= OVERVIEW_FROZEN then flags = flags | ImGui.TableColumnFlags_NoHide | ImGui.TableColumnFlags_NoReorder end
      ImGui.TableSetupColumn(ctx, col.key, flags, OVERVIEW_WIDTHS[col.key] or OVERVIEW_DEFAULT_WIDTH, i)
    end
    ImGui.TableSetupScrollFreeze(ctx, OVERVIEW_FROZEN, 1)
    -- The header row by hand, for the tooltips (as TableHeadersRow does it: TableHeader
    -- still sorts, drags and opens the column menu on right-click).
    ImGui.TableNextRow(ctx, ImGui.TableRowFlags_Headers)
    for i, col in ipairs(OVERVIEW_COLS) do
      if ImGui.TableSetColumnIndex(ctx, i - 1) then
        ImGui.PushID(ctx, i)
        if i <= OVERVIEW_FROZEN then ImGui.TableSetBgColor(ctx, ImGui.TableBgTarget_CellBg, FROZEN.head) end
        ImGui.TableHeader(ctx, col.key)
        if i == OVERVIEW_FROZEN then overview.frozen_right = (ImGui.GetItemRectMax(ctx)) end -- where the fixed column ends on screen
        local tip_text = OVERVIEW_TIPS[col.key] or fields.TIPS[col.key]
        tip(i <= OVERVIEW_FROZEN and ((tip_text or col.key) .. FROZEN_TIP) or tip_text)
        ImGui.PopID(ctx)
      end
    end
    local need, has_specs = ImGui.TableNeedSort(ctx)
    if need then
      local specs = {}
      if has_specs then
        for id = 0, #OVERVIEW_COLS - 1 do
          local ok, _, user_id, dir = ImGui.TableGetColumnSortSpecs(ctx, id)
          if not ok then break end
          local col = OVERVIEW_COLS[user_id]
          if col then specs[#specs + 1] = { key = col.key, asc = dir ~= ImGui.SortDirection_Descending } end
        end
      end
      overview.specs, overview.need_sort = specs, true
    end
    if overview.need_sort or not overview.order then
      local order = {}
      for i, row in ipairs(overview.rows) do order[i] = row end
      if overview.specs and #overview.specs > 0 then overview_mod.sort_rows(order, overview.specs, overview_value) end
      overview.order, overview.need_sort = order, false
    end
    local visible_rows = overview_mod.filter_rows(overview.order, overview.search, OVERVIEW_COLS, overview_search_value)
    local row_h = ImGui.GetFrameHeight(ctx) -- every row as tall as an input box: the clipper needs equal rows
    ImGui.ListClipper_Begin(clipper, #visible_rows)
    while ImGui.ListClipper_Step(clipper) do
      local first, last = ImGui.ListClipper_GetDisplayRange(clipper)
      for i = first + 1, last do
        local row = visible_rows[i]
        ImGui.PushID(ctx, row.key)
        overview_row(row, row_h)
        ImGui.PopID(ctx)
      end
    end
    scroll_x, scroll_max = ImGui.GetScrollX(ctx), ImGui.GetScrollMaxX(ctx)
    v_scroll = ImGui.GetScrollMaxY(ctx) > 0
    ImGui.EndTable(ctx)
  end
  ImGui.EndChild(ctx)
  ImGui.PopStyleColor(ctx)
  overview.hscroll = scroll_max > 0

  local fr = overview.frozen_right and math.floor(overview.frozen_right)
  if not fr then return end
  local strip_y = table_y + clip_h
  local dl = ImGui.GetWindowDrawList(ctx)
  -- The strip under the table: the fixed column's tint, and the bar under the scrolling columns.
  ImGui.DrawList_AddRectFilled(dl, table_x, strip_y, fr, strip_y + sb, FROZEN.cell)
  local x1 = table_x + avail_w - (v_scroll and sb or 0)
  local w = x1 - fr
  if scroll_max > 0 and w > 24 then
    ImGui.DrawList_AddRectFilled(dl, fr, strip_y, x1, strip_y + sb, ImGui.GetStyleColor(ctx, ImGui.Col_ScrollbarBg))
    local thumb = math.min(w, math.max(24, w * w / (w + scroll_max)))
    local range = w - thumb
    local thumb_x = fr + (scroll_x / scroll_max) * range
    ImGui.SetCursorScreenPos(ctx, fr, strip_y)
    ImGui.InvisibleButton(ctx, '##hscroll', w, sb)
    local mouse_x = (ImGui.GetMousePos(ctx))
    if ImGui.IsItemActivated(ctx) then
      -- grabbed on the thumb: it follows from there; on the track: its middle goes to the mouse
      overview.grab = (mouse_x >= thumb_x and mouse_x <= thumb_x + thumb) and (mouse_x - thumb_x) or thumb / 2
    end
    local active = ImGui.IsItemActive(ctx)
    if active and range > 0 then
      local frac = (mouse_x - (overview.grab or thumb / 2) - fr) / range
      overview.set_scroll_x = math.max(0, math.min(1, frac)) * scroll_max
    end
    local col = ImGui.Col_ScrollbarGrab
    if active then col = ImGui.Col_ScrollbarGrabActive elseif ImGui.IsItemHovered(ctx) then col = ImGui.Col_ScrollbarGrabHovered end
    ImGui.DrawList_AddRectFilled(dl, thumb_x, strip_y + 1, thumb_x + thumb, strip_y + sb - 1, ImGui.GetStyleColor(ctx, col), 4)
  end
  -- A line after the fixed column over the whole table and the strip. The foreground list, cut
  -- to the table: the table's own windows draw above this window's list.
  local fg = ImGui.GetForegroundDrawList(ctx)
  ImGui.DrawList_PushClipRect(fg, table_x, table_y, table_x + avail_w, strip_y + sb, true)
  ImGui.DrawList_AddLine(fg, fr, table_y, fr, strip_y + sb, FROZEN.line, 2)
  ImGui.DrawList_PopClipRect(fg)
end

local curator_deps = deps()
curator_deps.flow, curator_deps.overview = flow, overview_mod

local function send_curator()
  local question = chat.input:match('^%s*(.-)%s*$')
  local url, model = settings_mod.chat_url(settings.endpoint), curator.model(settings)
  if not url or model == '' then
    chat.error = 'Choose an endpoint and model in Settings (the gear).'
    return
  end
  overview_refresh(true)
  local messages, cards = curator.messages(curator_deps, overview.rows, chat.history, question, settings)
  local request = {deps = curator_deps, url = url, settings = {
    model = model, api_key = settings.api_key,
  }}
  local conversation = chat
  conversation.request, conversation.error = request, nil
  flow.send(request, messages, function(res)
    conversation.request = nil
    local text, info = llm.response_text(json, res.body)
    if not res.ok then
      conversation.error = tostring(res.error or 'Request failed') .. (res.body and res.body ~= '' and info and (' (' .. info .. ')') or '')
      return
    end
    if not text or info == 'length' then
      conversation.error = info == 'length' and 'Reply cut short. Ask for a smaller group of edits.' or info
      return
    end
    local clean = llm.clean_text(text):gsub('^```%w*%s*',''):gsub('%s*```$','')
    local obj, pos, err = json.decode(clean, 1, json.null)
    if err and clean:match('%S') and not clean:find('[%[%]{}]') then
      -- Some text models answer a discussion directly despite the JSON prompt.
      obj, err = {reply = clean, edits = {}}, nil
      clean = json.encode(obj)
      pos = #clean + 1
    end
    if err or clean:find('%S', pos) then
      conversation.error = 'Incomplete or invalid JSON. Send again to retry.'
      return
    end
    local plan, reason = curator.proposal(curator_deps, obj, cards)
    if not plan then
      conversation.error = reason
      if type(obj) == 'table' and type(obj.reply) == 'string' then
        conversation.error = obj.reply .. '\n' .. reason
      end
      return
    end
    local turn = {question = question, reply = obj.reply, response = clean, plan = plan,
      status = #plan > 0 and 'Proposed' or 'Discussion'}
    conversation.history[#conversation.history + 1] = turn
    if #plan > 0 then
      if conversation.pending then conversation.pending.status = 'Superseded' end
      conversation.pending = turn
    end
    conversation.input, conversation.scroll = '', true
  end)
end

local function draw_curator()
  local model = curator.model(settings)
  ImGui.TextDisabled(ctx, string.format('%d cards  |  %s', #overview.rows, model ~= '' and model or 'Choose a model in Settings'))
  if ImGui.BeginChild(ctx, 'curator-transcript', 0, -130) then
    if #chat.history == 0 then
      wrapped('Ask which items belong in a numbered series, or what needs fixing before render.', COL_DIM)
    end
    for _, turn in ipairs(chat.history) do
      ImGui.SeparatorText(ctx, 'You')
      wrapped(turn.question)
      ImGui.SeparatorText(ctx, 'Curator')
      wrapped(turn.reply)
      for _, group in ipairs(turn.plan) do
        wrapped(string.format('#%d  %s', group.card.row, group.card.filename), COL_ACCENT)
        for _, edit in ipairs(group.preview) do
          wrapped(string.format('%s: %s  →  %s', edit.key,
            edit.old ~= '' and edit.old or '(empty)', edit.new ~= '' and edit.new or '(empty)'))
        end
      end
      if #turn.plan > 0 then wrapped(turn.status, COL_DIM) end
    end
    if chat.scroll then ImGui.SetScrollHereY(ctx, 1); chat.scroll = nil end
    ImGui.EndChild(ctx)
  end
  local req = chat.request
  if req and req.error then chat.error, chat.request, req = req.error, nil, nil end
  ImGui.BeginDisabled(ctx, req ~= nil)
  local _, input = editor('##curator-question', chat.input, 2)
  chat.input = input
  ImGui.BeginDisabled(ctx, not input:match('%S') or #overview.rows == 0)
  if ImGui.Button(ctx, 'Send') then send_curator() end
  ImGui.EndDisabled(ctx)
  local pending = chat.pending
  if pending then
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, 'Apply changes') then
      overview_refresh(true)
      local ok, err = curator.apply(curator_deps, pending.plan, overview.by_key, overview_set)
      pending.status = ok and 'Applied' or 'Outdated'
      chat.error, chat.pending = err, nil
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, 'Discard') then pending.status, chat.pending = 'Discarded', nil end
  end
  ImGui.EndDisabled(ctx)
  if req then
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, 'Stop curator') then
      req.gen = (req.gen or 0) + 1
      if req.job then http.cancel(req.job) end
      chat.request = nil
    end
    ImGui.SameLine(ctx)
    ImGui.TextDisabled(ctx, 'Reviewing the cards...')
  end
  if chat.error then wrapped(chat.error, COL_WARN) end
end

-- The table side of the Overview: search, counts, column paste, the table.
local function draw_overview_table(n)
  if n == 0 then
    ImGui.TextDisabled(ctx, 'No item in this project has a card yet: select an item and describe it.')
    return
  end
  ImGui.SetNextItemWidth(ctx, 320)
  local _, search = ImGui.InputText(ctx, 'Search all columns', overview.search)
  overview.search = search
  tip('Shows only rows containing this text in any column, including hidden columns. Ignores letter case. Clear the text to show all rows.')
  ImGui.SameLine(ctx)
  ImGui.TextDisabled(ctx, 'Right-click a cell to copy or paste a column.')
  ImGui.TextDisabled(ctx, n == 1 and '1 item:' or (n .. ' items:'))
  tip('Every item of this project that has a card. Click a row to select its item in REAPER, double-click a cell to edit it; click a header to sort, '
    .. 'Shift-click another to sort by it too; right-click a header to show or hide columns; drag a header to move its column.')
  for _, label in ipairs(TALLY_ORDER) do
    local c = overview.tally[label]
    if c then
      ImGui.SameLine(ctx)
      ImGui.TextColored(ctx, STATUS_COLORS[overview.tally_kind[label]] or COL_DIM, string.format('%d %s', c, label:lower()))
      tip('File names in this colour: ' .. label:lower() .. '.')
    end
  end
  local shared = 0
  for _, c in pairs(overview.counts) do if c > 1 then shared = shared + c end end
  if shared > 0 then
    ImGui.SameLine(ctx)
    ImGui.TextColored(ctx, COL_WARN, string.format('%d items share their file name with another one.', shared))
  end
  local field = overview.copied_field
  if field then
    if ImGui.Button(ctx, 'Paste ' .. field.key .. ' to entire column') then paste_column(field.key, field.value) end
    tip('Pastes the field copied in Overview into every editable row, including rows hidden by the search.')
  end
  if overview.paste_status then ImGui.TextDisabled(ctx, overview.paste_status) end
  overview_table()
end

-- The Overview's curator panel: sizes and helpers in one table (the main chunk is
-- near Lua's limit of 200 locals). SPLIT_W: the draggable border between the
-- table and the curator; ARROW_W: the column at the right edge holding the arrow.
local curator_panel = { SPLIT_W = 12, ARROW_W = 16, MIN_W = 260, TABLE_MIN_W = 320, TAB_LABEL = 'Curator' }
do
local P = curator_panel

function P.save_layout()
  reaper.SetExtState(settings_mod.EXT, 'overview_curator_width', tostring(math.floor(overview.curator_w)), true)
  reaper.SetExtState(settings_mod.EXT, 'overview_curator_hidden', overview.show_curator and '0' or '1', true)
end

-- The border between the table and the curator: dragging it moves it; the width
-- is saved when the drag ends.
function P.splitter(height)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  ImGui.InvisibleButton(ctx, '##curator-split', P.SPLIT_W, height)
  local hovered, held = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
  if hovered or held then ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeEW) end
  if held then
    local dx = ImGui.GetMouseDelta(ctx)
    overview.curator_w = overview.curator_w - dx -- the curator is on the right: dragging left widens it
  end
  if ImGui.IsItemDeactivated(ctx) then P.save_layout() end
  local line = ImGui.GetColor(ctx, held and ImGui.Col_SeparatorActive
    or (hovered and ImGui.Col_SeparatorHovered or ImGui.Col_Separator))
  ImGui.DrawList_AddLine(ImGui.GetWindowDrawList(ctx), x + P.SPLIT_W / 2, y, x + P.SPLIT_W / 2, y + height,
    line, (held or hovered) and 2 or 1)
end

-- A small filled triangle, always the same size and on whole pixels: 6 px long,
-- 8 px tall, from x (left edge of its box), centred on cy. dir 1 = right, -1 = left.
local function paint_arrow(dl, x, cy, dir, col)
  x, cy = math.floor(x), math.floor(cy)
  if dir > 0 then ImGui.DrawList_AddTriangleFilled(dl, x, cy - 4, x, cy + 4, x + 6, cy, col)
  else ImGui.DrawList_AddTriangleFilled(dl, x + 6, cy - 4, x + 6, cy + 4, x, cy, col) end
end

-- The curator toggle at the right edge of the Overview, top row. Shown: a lone
-- arrow pointing right (hide). Hidden: an arrow pointing left followed by the word
-- "Curator", so it reads as what it opens. Its width: P.tab_width.
function P.tab_width()
  if overview.show_curator then return P.ARROW_W end
  return P.ARROW_W + ImGui.CalcTextSize(ctx, P.TAB_LABEL) + 6
end

function P.arrow()
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local h = ImGui.GetFrameHeight(ctx)
  local w = P.tab_width()
  if ImGui.InvisibleButton(ctx, '##curator-toggle', w, h) then
    overview.show_curator = not overview.show_curator
    P.save_layout()
  end
  local hovered = ImGui.IsItemHovered(ctx)
  local col = ImGui.GetColor(ctx, hovered and ImGui.Col_Text or ImGui.Col_TextDisabled)
  local dl = ImGui.GetWindowDrawList(ctx)
  local cy = y + h / 2
  if overview.show_curator then
    paint_arrow(dl, x + (P.ARROW_W - 6) / 2, cy, 1, col)
    tip('Hide the curator: the table takes the whole width.')
  else
    paint_arrow(dl, x + 4, cy, -1, col)
    ImGui.DrawList_AddText(dl, x + P.ARROW_W, math.floor(y + (h - ImGui.GetTextLineHeight(ctx)) / 2), col, P.TAB_LABEL)
    tip('Show the curator next to the table: talk about the collection while you look at it.')
  end
end
end

local function draw_overview()
  prepare_window('overview', 1320, 600)
  local fs_flags = prepare_fullscreen('overview')
  local visible, open = ImGui.Begin(ctx, 'Metadata Assistant Overview', true,
    ImGui.WindowFlags_NoDocking | ImGui.WindowFlags_NoCollapse | fs_flags)
  overview.open = open
  if not visible then return end
  fullscreen_title_button('overview')
  title_double_click('overview')
  overview_refresh()
  overview_count()
  local n = #overview.rows
  -- Table and curator side by side, filling the window:
  -- table | draggable border | curator | arrow column at the right edge.
  local avail_w, avail_h = ImGui.GetContentRegionAvail(ctx)
  local P = curator_panel
  local free = avail_w - P.tab_width()
  local cw, split = 0, 0
  if overview.show_curator then
    split = P.SPLIT_W
    cw = math.max(P.MIN_W, math.min(overview.curator_w, free - P.TABLE_MIN_W - P.SPLIT_W))
    overview.curator_w = cw
  end
  if ImGui.BeginChild(ctx, 'overview-table-pane', math.max(1, free - cw - split), avail_h) then
    draw_overview_table(n)
    ImGui.EndChild(ctx)
  end
  if overview.show_curator then
    ImGui.SameLine(ctx, 0, 0)
    P.splitter(avail_h)
    ImGui.SameLine(ctx, 0, 0)
    if ImGui.BeginChild(ctx, 'overview-curator-pane', cw, avail_h) then
      ImGui.SeparatorText(ctx, 'Curator')
      draw_curator()
      ImGui.EndChild(ctx)
    end
  end
  ImGui.SameLine(ctx, 0, 0)
  P.arrow()
  own_windows[#own_windows + 1] = window_rect()
  ImGui.End(ctx)
end

-- The three phases of an item: internal page name, label on screen.
local PAGES = { { 'Describe', 'Describe' }, { 'Review', 'Clarify' }, { 'Metadata', 'Review' } }

-- Render button, next to the tabs. targets: the cards that would be rendered
-- (renderable ones only); r: the file's result when one item is selected.
local function draw_render_button(targets, r)
  local can = #targets > 0 and not (current and flow.busy(current)) and not confirm_overwrite and not batch
  local again = current and current.rendered
  local label = multi and 'Render all' or (again and 'Render again' or 'Render')
  -- Render at the right end of the tab row (which has just ended with a SameLine).
  align_right(button_width(label))
  ImGui.BeginDisabled(ctx, not can)
  if accent_button(label) then
    pending_render = { overwrite = false, targets = targets }
  end
  ImGui.EndDisabled(ctx)
  local dir = render.output_dir(settings.render_dir)
  local embedded = multi and 'the metadata (and each item\'s artwork, where set)'
    or (current and current.values and render.artwork_path(current.values.Artwork) ~= '' and 'the metadata and the artwork')
    or 'the metadata'
  if #targets == 0 then
    if multi then tip('Nothing to render yet: the selected items need finalized metadata.')
    elseif not r then tip('Nothing to render yet: finalize the metadata first.')
    else tip('Fill the missing fields first' .. (#r.missing > 0 and (': ' .. table.concat(r.missing, ', ')) or '') .. '.') end
  elseif multi then
    tip(string.format('Renders %d items into %s\n24 bit, each at its own sample rate and channel count, with %s embedded. The project\'s render settings are restored afterwards.',
      #targets, dir, embedded))
  else
    local f = current.facts
    tip(string.format('Renders this item to %s\n%d Hz, 24 bit, %d ch, with %s embedded. The project\'s render settings are restored afterwards.',
      render.target_path(dir, r.filename), f.samplerate or 0, f.channels or 0, embedded))
  end
end

-- Result of the last render, and the overwrite question.
local function draw_render_status()
  if current and current.rendered then
    wrapped('Rendered ' .. tostring(current.rendered.at) .. ': ' .. tostring(current.rendered.path), COL_OK)
  end
  if batch then
    ImGui.TextDisabled(ctx, string.format('Rendering... %d of %d', batch.done + #batch.exists + #batch.errors, batch.total))
  end
  if confirm_overwrite and overwrite_targets then
    ImGui.TextColored(ctx, COL_WARN, #overwrite_targets == 1 and 'A file with this name exists.'
      or string.format('%d files with these names exist.', #overwrite_targets))
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, 'Overwrite') then pending_render = { overwrite = true, targets = overwrite_targets } end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, 'Cancel') then confirm_overwrite, overwrite_targets = false, nil end
  end
  if render_msg then wrapped(render_msg[1], render_msg[2]) end
end

local PAGE_TIPS = {
  Describe = 'Describe the sound and analyze it.',
  Review = 'Clarify: the suggested category and the model\'s questions.',
  Metadata = 'Review: the final file name and every metadata field, all editable. With several items selected it edits them all.',
}

-- locked[page] = why the page cannot be opened yet (nil: it can). The page on
-- screen is never locked: it stays marked, with its note, as the view is shared by all items.
-- attention[page] = why the page waits for the user (nil: it does not): its tab
-- blinks while another page is on screen; hovering it shows the plain hover colour.
-- working: the gap (1 = Describe/Clarify, 2 = Clarify/Review) whose dots show the model
-- at work, or nil.
local function draw_tabs(locked, attention, working)
  attention = attention or {}
  local h = ImGui.GetFrameHeight(ctx)
  local line_h = ImGui.GetTextLineHeight(ctx)
  local dl = ImGui.GetWindowDrawList(ctx)
  for i, p in ipairs(PAGES) do
    local page, label = p[1], p[2]
    if i > 1 then
      -- Three spaced dots between two phases.
      ImGui.SameLine(ctx, 0, 0)
      local dx, dy = ImGui.GetCursorScreenPos(ctx)
      ImGui.Dummy(ctx, 48, h)
      for k = -1, 1 do
        ImGui.DrawList_AddCircleFilled(dl, math.floor(dx + 24 + k * 8) + 0.5, math.floor(dy + h / 2) + 0.5, 1, ImGui.GetColor(ctx, ImGui.Col_TextDisabled))
      end
      if working == i - 1 then icons.scan(dl, math.floor(dx + 24) + 0.5, math.floor(dy + h / 2) + 0.5, reaper.time_precise()) end
      ImGui.SameLine(ctx, 0, 0)
    end
    -- A phase: text only, no background. Current: accent and underlined; open:
    -- dim, bright on hover; locked: disabled; waiting for the user: pulsing.
    local x, y = ImGui.GetCursorScreenPos(ctx)
    local w = ImGui.CalcTextSize(ctx, label) + 8
    local clicked = ImGui.InvisibleButton(ctx, '##phase-' .. page, w, h)
    local hovered = ImGui.IsItemHovered(ctx)
    local current_page, is_locked = view_page == page, locked[page] ~= nil
    local blink = not current_page and not is_locked and attention[page] ~= nil
    local col
    if current_page then col = COL_ACCENT
    elseif is_locked then col = ImGui.GetColor(ctx, ImGui.Col_TextDisabled)
    elseif hovered then col = ImGui.GetColor(ctx, ImGui.Col_Text)
    elseif blink then col = blink_color(reaper.time_precise())
    else col = COL_DIM end
    local ty = math.floor(y + (h - line_h) / 2)
    ImGui.DrawList_AddText(dl, x + 4, ty, col, label)
    if current_page then
      ImGui.DrawList_AddLine(dl, x + 4, ty + line_h + 1, x + w - 4, ty + line_h + 1, col, 1)
    end
    if clicked and not is_locked then view_page = page end
    tip(locked[page] or (blink and attention[page]) or PAGE_TIPS[page])
  end
  ImGui.SameLine(ctx)
end

-- Next to the tabs. One item: Copy takes its metadata. Several: Paste all puts every
-- copied field in all the selected items that have metadata.
local function draw_copy_buttons()
  if multi then
    local can = copied ~= nil and #multi.with_values > 0
    ImGui.BeginDisabled(ctx, not can)
    if ImGui.Button(ctx, 'Paste all') then multi_paste_all() end
    ImGui.EndDisabled(ctx)
    if can then tip(string.format('Puts every field copied from %s, and its file name, in all the selected items that have metadata. Hover a field or the file name to do it for that one only.', copied.name))
    elseif not copied then tip('Nothing copied yet: select one item with metadata and use the copy icon in Review.')
    else tip('None of the selected items has metadata yet.') end
  else
    -- The copy icon shows only on the Review phase, where the metadata is.
    if view_page ~= 'Metadata' then return end
    local can = current.values ~= nil and not flow.busy(current)
    ImGui.BeginDisabled(ctx, not can)
    if icons.button('##copy', false, icons.copy) then copy_item(current) end
    ImGui.EndDisabled(ctx)
    tip(can and 'Copy: takes the file name and every metadata field of this item. Select several items, open Review and hover a field or the file name to preview the copied value; click it to put it in all of them, or use Paste all.'
      or 'Nothing to copy yet: this item has no metadata.')
  end
  ImGui.SameLine(ctx)
end

local function draw_workspace()
  -- A step that completes for the item on screen moves the view; selecting
  -- another item never does (track_selection syncs last_state).
  if current.last_state ~= current.state then
    if current.state == 'done' then view_page = 'Metadata'
    elseif current.state == 'questions' then view_page = 'Review'
    elseif not current.draft then view_page = 'Describe' end
    current.last_state = current.state
  end
  local r = current.values and flow.result(current) or nil
  draw_tabs({
    Review = not current.draft and 'Analyze the description first: there is nothing to clarify yet.' or nil,
    Metadata = not current.values and 'Finalize in Clarify first: there is no metadata to review yet.' or nil,
  }, {
    Review = current.state == 'questions'
      and 'This item waits for you in Clarify: check the suggested category, answer the questions and finalize.' or nil,
  }, icons.STATE_GAP[current.state])
  draw_copy_buttons()
  draw_render_button((r and r.renderable) and { current } or {}, r)
  draw_render_status()
  draw_status()
  if view_page == 'Describe' then draw_description()
  elseif view_page == 'Review' then
    if current.draft then draw_draft(); draw_questions()
    else ImGui.TextDisabled(ctx, 'Nothing to clarify for this item yet: analyze its description first.') end
  else draw_result() end
end

local function draw_multi_workspace()
  local targets = {}
  for _, sess in ipairs(multi.with_values) do
    if flow.result(sess).renderable then targets[#targets + 1] = sess end
  end
  draw_tabs({
    Review = 'Describing and clarifying work on one item at a time: select a single item.',
    Metadata = #multi.with_values == 0
      and 'None of the selected items has metadata yet: describe and finalize each of them first.' or nil,
  })
  draw_copy_buttons()
  draw_render_button(targets, nil)
  draw_render_status()
  if view_page == 'Metadata' then
    draw_multi_result()
  else
    wrapped('Describing and clarifying work on one item at a time. Select a single item for that, or review the metadata of all the selected ones.', COL_DIM)
    ImGui.BeginDisabled(ctx, #multi.with_values == 0)
    if accent_button('Review all') then view_page = 'Metadata' end
    ImGui.EndDisabled(ctx)
  end
end

-- What the model is doing, for the top row next to its name: text, true when the
-- selected item's request runs (then the Stop button goes next to it); nil when
-- nothing runs. Requests of other items (several analyzed at once) are counted.
local DOING = { measuring = 'Measuring audio', listening = 'Listening', drafting = 'Analyzing', finalizing = 'Finalizing' }
local function status_line()
  local parts, own = {}, false
  if current and flow.busy(current) then
    own = true
    local elapsed = current.measure_start and (reaper.time_precise()-current.measure_start) or http.elapsed(current.job)
    parts[1] = string.format('%s... %d s', DOING[current.state] or 'Working', math.floor(elapsed or 0))
    if current.retry then
      parts[1] = parts[1] .. string.format(' (invalid answer, retry %d of %d)', current.retry, flow.MAX_RETRIES)
    end
  elseif current and current.cancelled then
    parts[1] = 'Stopped'
  end
  local others = http.pending() + flow.measure_count() - (own and (current.job or current.measure_thread) and 1 or 0)
  if others > 0 then
    parts[#parts + 1] = #parts > 0 and string.format('%d more running', others)
      or (others == 1 and '1 request running' or string.format('%d requests running', others))
  end
  if #parts == 0 then return nil end
  return table.concat(parts, ', '), own
end

local safe_loop -- loop wrapped in xpcall, defined after loop
local function loop()
  own_windows = {}
  local project = reaper.EnumProjects(-1)
  if project ~= active_project then
    if chat.request then
      chat.request.gen = (chat.request.gen or 0) + 1
      if chat.request.job then http.cancel(chat.request.job) end
      chat.request, chat.error = nil, 'Request stopped when the project changed.'
    end
    chat = project_chats[project] or {history = {}, input = ''}
    project_chats[project] = chat
    current, multi, active_project = nil, nil, project
    settings_mod.load_project(settings) -- Library, SourceID and Show belong to the project
    settings_saved = settings_mod.encoded(settings) -- just read: nothing to write back
    sessions = project_sessions[project] or {}
    project_sessions[project] = sessions
    pending_render, batch, confirm_overwrite, overwrite_targets = nil, nil, false, nil
  end
  flow.poll_measurements()
  http.poll()
  track_selection()
  do_pending_render()
  watch_playing()
  push_style()
  prepare_window('main', 800, 680)
  local fs_flags = prepare_fullscreen('main')
  -- The windows are floating only: they cannot be docked into each other.
  -- No collapse arrow in the title bar.
  local visible, open = ImGui.Begin(ctx, name, true,
    ImGui.WindowFlags_NoDocking | ImGui.WindowFlags_NoCollapse | fs_flags)
  if visible then
    fullscreen_title_button('main')
    title_double_click('main')
    local model_text = settings.model ~= '' and ('Model: ' .. settings.model) or 'No model selected'
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.TextDisabled(ctx, model_text)
    local doing, own = status_line()
    if doing then
      ImGui.SameLine(ctx, 0, 0)
      ImGui.TextDisabled(ctx, ' - ')
      ImGui.SameLine(ctx, 0, 0)
      ImGui.TextColored(ctx, own and COL_ACCENT or COL_DIM, doing)
      if own and view_page ~= 'Describe' then -- on Describe the Stop button sits next to Analyze
        ImGui.SameLine(ctx)
        if ImGui.SmallButton(ctx, 'Stop') then flow.cancel(current) end
        tip('Interrupts the request to the model.')
      end
    end
    ImGui.SameLine(ctx)
    align_right(3 * ImGui.GetFrameHeight(ctx) + 2 * ITEM_SPACING_X)
    if icons.button('##overview', overview.open, icons.table) then overview.open = not overview.open end
    tip(overview.open and 'Close the Overview.' or 'Overview: a table of every item of this project that has a card: status, file name and all the metadata, editable in place and sortable by any column.')
    ImGui.SameLine(ctx)
    if icons.button('##library', main_view == 'library', icons.library) then
      main_view = main_view ~= 'library' and 'library' or nil
    end
    tip(main_view == 'library' and 'Close the library and go back to the item.'
      or 'Library: designer, manufacturer, CreatorID, website, copyright, and this project\'s Library, SourceID and Show.')
    ImGui.SameLine(ctx)
    if icons.button('##settings', main_view == 'settings', icons.gear) then
      main_view = main_view ~= 'settings' and 'settings' or nil
    end
    tip(main_view == 'settings' and 'Close the settings and go back to the item.' or 'Settings')
    if main_view then -- settings or library in the item's place; changes save themselves
      ImGui.Spacing(ctx)
      draw_settings_page(main_view == 'settings' and 'Settings' or 'Library')
    else
      ImGui.SeparatorText(ctx, multi and 'Selected items' or 'Selected item')
      if multi then
        draw_multi_header()
        draw_multi_workspace()
      elseif draw_item() then
        draw_workspace()
      end
    end
    own_windows[#own_windows + 1] = window_rect()
    ImGui.End(ctx)
  end
  if open and overview.open then draw_overview() end
  pop_style()
  if open and settings.outline_items and outline.available() then
    outline.draw(ctx, ImGui, outline.items(sessions, store, json), reaper.time_precise(), own_windows)
  end
  -- A text box saves when it is left (Enter, Tab or a click elsewhere); checkboxes,
  -- menus and numbers right away.
  if not ImGui.IsAnyItemActive(ctx) then settings_saved = settings_mod.save_changed(settings, settings_saved) end
  save_dirty(false)
  if open then reaper.defer(safe_loop) end
end

-- An error still stops the script, but its line and call chain go to the console
-- first: REAPER's dialog shows only the message when it comes from inside a C
-- function (math.max, table.sort...), which says nothing about where it happened.
safe_loop = function()
  local ok, err = xpcall(loop, debug.traceback)
  if not ok then
    reaper.ShowConsoleMsg('Metadata Assistant ' .. major_version .. '.' .. minor_version .. ' error:\n' .. tostring(err) .. '\n')
    error(err, 0)
  end
end

fetch_models()

-- On close: every changed card goes to the project; pending requests and their
-- temporary files are dropped; an item playback started here is stopped.
reaper.atexit(function()
  settings_saved = settings_mod.save_changed(settings, settings_saved) -- a box still being typed in
  flow.stop_measurements()
  save_dirty(true)
  http.abandon_all()
  if playing then
    reaper.OnStopButton()
    reaper.SetEditCurPos(playing.cursor, false, false)
  end
end)
reaper.defer(safe_loop)
