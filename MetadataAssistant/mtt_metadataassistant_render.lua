-- mtt_metadataassistant_render.lua
-- Renders one item to its own WAV: the item's sample rate, 24-bit PCM, the
-- item's channel count, the card's UCS name, the card's metadata embedded.
-- Every project render setting it touches, the render metadata and the item
-- selection are read first and put back afterwards, also when the render fails.
--
-- Render settings used (GetSetProjectInfo / GetSetProjectInfo_String):
--   RENDER_SETTINGS   32 (selected media items) | 512 (embed metadata)
--   RENDER_BOUNDSFLAG 4 (selected media items)
--   RENDER_SRATE / RENDER_CHANNELS from the item
--   RENDER_TAILFLAG 0, RENDER_ADDTOPROJ 0, RENDER_NORMALIZE 0 (no post-processing)
--   RENDER_FILE / RENDER_PATTERN = output folder / UCS name (REAPER adds .wav)
--   RENDER_FORMAT  WAV24 below, RENDER_FORMAT2 "" (no secondary format)
-- Artwork (optional, the item's Artwork field): a JPEG or PNG written as the front cover into the WAV's
-- ID3 chunk (ID3:APIC_FILE + ID3:APIC_TYPE 3). The same keys and WAV24 string
-- were checked with exiftool on REAPER 7.80 by Amorfx/reaper-release-exporter
-- (docs/reaper-api-notes.md): the WAV carries an ID3v2.4 chunk with the cover.

local M = {}

-- 'evaw' sink: 24-bit PCM, write BWF (bext) chunk, auto WAV/RF64 for large files.
-- Byte layout: RENDER_How_RenderCFG-Base64-strings_are_encoded.txt (Ultraschall docs).
M.WAV24 = "ZXZhdxgAAQ=="

local ACTION_RENDER = 41824 -- File: Render project, using the most recent render settings

local NUM_KEYS = { "RENDER_SETTINGS", "RENDER_BOUNDSFLAG", "RENDER_SRATE", "RENDER_CHANNELS",
                   "RENDER_TAILFLAG", "RENDER_ADDTOPROJ", "RENDER_NORMALIZE" }
local STR_KEYS = { "RENDER_FILE", "RENDER_PATTERN", "RENDER_FORMAT", "RENDER_FORMAT2" }

M.SEP = reaper.GetOS():find("Win") and "\\" or "/"

M.DEFAULT_SUBDIR = "Render"

-- The project's folder (the recording path when the project was never saved).
function M.project_dir()
  local _, projfn = reaper.EnumProjects(-1)
  local dir = projfn and projfn:match("^(.*)[/\\][^/\\]*$")
  if not dir or dir == "" then dir = reaper.GetProjectPathEx(0) end
  return (dir:gsub("[/\\]+$", ""))
end

local function is_absolute(path)
  return path:match("^[/\\]") ~= nil or path:match("^%a:[/\\]") ~= nil
end

-- Folder components, "." dropped; ".." kept. Pure.
local function components(path)
  local out = {}
  for part in path:gmatch("[^/\\]+") do
    if part ~= "." then out[#out + 1] = part end
  end
  return out
end

-- Folder to write to. setting is relative to the project folder ("Render",
-- "renders/ucs", "../shared"); empty = DEFAULT_SUBDIR. An absolute setting
-- (what older versions saved) is used as it is. project_dir: for tests;
-- default = the current project's folder. Pure when project_dir is given.
function M.output_dir(setting, project_dir)
  local s = tostring(setting or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if s == "" then s = M.DEFAULT_SUBDIR end
  if is_absolute(s) then return (s:gsub("[/\\]+$", "")) end
  local base = project_dir or M.project_dir()
  local parts = components(base)
  local lead = base:match("^[/\\]+") or ""
  local drive = base:match("^%a:") or ""
  if drive ~= "" then table.remove(parts, 1) end
  for _, c in ipairs(components(s)) do
    if c == ".." then
      if #parts > 0 then table.remove(parts) end
    else
      parts[#parts + 1] = c
    end
  end
  return drive .. lead .. table.concat(parts, M.SEP)
end

-- A folder the user picked, as a setting: relative to the project folder when
-- it lies below or beside it ("UCS", "../shared"), else the absolute path.
-- Pure.
function M.relative_setting(picked, project_dir)
  local p = tostring(picked or ""):gsub("[/\\]+$", "")
  if p == "" then return "" end
  if not project_dir or project_dir == "" then return p end
  local a, b = components(project_dir), components(p)
  local da, db = project_dir:match("^%a:") or "", p:match("^%a:") or ""
  if da:lower() ~= db:lower() then return p end
  if da ~= "" then table.remove(a, 1); table.remove(b, 1) end
  local common = 0
  while common < #a and common < #b and a[common + 1] == b[common + 1] do common = common + 1 end
  if common == 0 then return p end -- nothing shared: keep it absolute
  local out = {}
  for _ = 1, #a - common do out[#out + 1] = ".." end
  for i = common + 1, #b do out[#out + 1] = b[i] end
  if #out == 0 then return "." end
  return table.concat(out, "/")
end

-- The artwork setting as a path: spaces and surrounding quotes dropped (a
-- pasted "/path/cover.jpg"). Pure.
function M.artwork_path(setting)
  local s = tostring(setting or ""):gsub("^%s+", ""):gsub("%s+$", "")
  return (s:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1"))
end

-- Why this artwork cannot be embedded, or nil (also nil when there is none).
function M.artwork_problem(setting)
  local path = M.artwork_path(setting)
  if path == "" then return nil end
  local ext = (path:match("%.([^./\\]+)$") or ""):lower()
  if ext ~= "jpg" and ext ~= "jpeg" and ext ~= "png" then
    return "Artwork must be a JPEG or PNG file: " .. path
  end
  if not reaper.file_exists(path) then return "Artwork not found: " .. path end
  return nil
end

-- {identifier, value} pairs that embed the artwork as the front cover; empty
-- when there is no artwork. Pure.
function M.artwork_metadata(setting)
  local path = M.artwork_path(setting)
  if path == "" then return {} end
  return { { "ID3:APIC_TYPE", "3" }, { "ID3:APIC_FILE", path } } -- 3 = front cover
end

function M.target_path(dir, name)
  return dir .. M.SEP .. name .. ".wav"
end

local function snapshot()
  local s = { num = {}, str = {}, meta = {}, meta_ids = {}, selected = {} }
  for _, k in ipairs(NUM_KEYS) do s.num[k] = reaper.GetSetProjectInfo(0, k, 0, false) end
  for _, k in ipairs(STR_KEYS) do
    local _, v = reaper.GetSetProjectInfo_String(0, k, "", false)
    s.str[k] = v
  end
  local _, ids = reaper.GetSetProjectInfo_String(0, "RENDER_METADATA", "", false)
  for id in tostring(ids or ""):gmatch("[^;]+") do
    local _, v = reaper.GetSetProjectInfo_String(0, "RENDER_METADATA", id, false)
    s.meta_ids[#s.meta_ids + 1] = id
    s.meta[id] = v
  end
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    s.selected[#s.selected + 1] = reaper.GetSelectedMediaItem(0, i)
  end
  return s
end

local function set_metadata(id, value)
  reaper.GetSetProjectInfo_String(0, "RENDER_METADATA", id .. "|" .. value, true)
end

local function restore(s, written_ids)
  for _, k in ipairs(NUM_KEYS) do reaper.GetSetProjectInfo(0, k, s.num[k], true) end
  for _, k in ipairs(STR_KEYS) do reaper.GetSetProjectInfo_String(0, k, s.str[k], true) end
  -- Our identifiers go; the project's own come back with their values.
  for _, id in ipairs(written_ids) do
    if s.meta[id] == nil then set_metadata(id, "") end
  end
  for _, id in ipairs(s.meta_ids) do set_metadata(id, s.meta[id]) end
  reaper.SelectAllMediaItems(0, false)
  for _, it in ipairs(s.selected) do reaper.SetMediaItemSelected(it, true) end
  reaper.UpdateArrange()
end

-- plan: dir, name (no extension), samplerate, channels, metadata ({id, value} pairs),
-- artwork (the item's Artwork field: image path or "").
-- overwrite: delete an existing file at the target path first (only that path).
-- Returns path, or nil, err.
function M.render_item(item, plan, overwrite)
  local art_err = M.artwork_problem(plan.artwork)
  if art_err then return nil, art_err end -- checked first: no file is touched
  local path = M.target_path(plan.dir, plan.name)
  if reaper.file_exists(path) then
    if not overwrite then return nil, "exists" end
    os.remove(path)
  end
  reaper.RecursiveCreateDirectory(plan.dir, 0)

  local s = snapshot()
  local written = {}
  local ok, err = pcall(function()
    reaper.SelectAllMediaItems(0, false)
    reaper.SetMediaItemSelected(item, true)
    reaper.GetSetProjectInfo(0, "RENDER_SETTINGS", 32 | 512, true)
    reaper.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", 4, true)
    reaper.GetSetProjectInfo(0, "RENDER_SRATE", plan.samplerate, true)
    reaper.GetSetProjectInfo(0, "RENDER_CHANNELS", plan.channels, true)
    reaper.GetSetProjectInfo(0, "RENDER_TAILFLAG", 0, true)
    reaper.GetSetProjectInfo(0, "RENDER_ADDTOPROJ", 0, true)
    reaper.GetSetProjectInfo(0, "RENDER_NORMALIZE", 0, true)
    reaper.GetSetProjectInfo_String(0, "RENDER_FILE", plan.dir, true)
    reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", plan.name, true)
    reaper.GetSetProjectInfo_String(0, "RENDER_FORMAT", M.WAV24, true)
    reaper.GetSetProjectInfo_String(0, "RENDER_FORMAT2", "", true)
    for _, id in ipairs(s.meta_ids) do set_metadata(id, "") end
    local pairs_out = {}
    for _, pair in ipairs(plan.metadata) do pairs_out[#pairs_out + 1] = pair end
    for _, pair in ipairs(M.artwork_metadata(plan.artwork)) do pairs_out[#pairs_out + 1] = pair end
    for _, pair in ipairs(pairs_out) do
      set_metadata(pair[1], pair[2])
      written[#written + 1] = pair[1]
    end
    reaper.Main_OnCommand(ACTION_RENDER, 0)
  end)
  restore(s, written)
  if not ok then return nil, "render failed: " .. tostring(err) end
  if not reaper.file_exists(path) then
    return nil, "render finished but " .. path .. " is not there (render cancelled?)"
  end
  return path
end

return M
