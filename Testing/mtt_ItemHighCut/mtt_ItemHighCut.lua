-- mtt_ItemHighCut.lua - Adds a gentle high cut (mtt_ItemHighCut.jsfx) to the active take
-- of every selected item and shows the take envelope of its cutoff, ready to draw.
-- An item that already has the filter is not given a second one: its envelope is shown.

local JSFX_FILE = "mtt_ItemHighCut.jsfx"
local SEP = reaper.GetOS():find("Win") and "\\" or "/"
local FX_NAME = "MTT/" .. JSFX_FILE -- path relative to <resource>/Effects
local CUTOFF_PARAM = 0              -- slider1 of the JSFX

for _, name in ipairs({ "TakeFX_GetEnvelope", "TakeFX_GetNamedConfigParm" }) do
  if not reaper.APIExists(name) then
    reaper.MB("This script needs a newer REAPER (missing " .. name .. ").", "Item High Cut", 0)
    return
  end
end

local function script_dir()
  local src = debug.getinfo(1, "S").source:sub(2)
  return src:match("^(.*)[/\\]") or "."
end

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("a")
  f:close()
  return s
end

-- The JSFX lives beside this script (one source of truth). It is copied into
-- <resource>/Effects/MTT/ when missing or changed, so no separate install is needed.
-- Instances already loaded keep the old code until the project is reloaded.
local function install_jsfx()
  local dst_dir = reaper.GetResourcePath() .. SEP .. "Effects" .. SEP .. "MTT"
  local dst = dst_dir .. SEP .. JSFX_FILE
  local src = read_file(script_dir() .. SEP .. JSFX_FILE)
  if not src then return reaper.file_exists(dst) end -- no source here: use an installed copy
  if read_file(dst) == src then return true end
  reaper.RecursiveCreateDirectory(dst_dir, 0)
  local f = io.open(dst, "wb")
  if not f then return false end
  f:write(src)
  f:close()
  return true
end

-- Index of this filter in the take's FX chain, or -1. Matched on the file name in
-- fx_ident, so a renamed instance is still found.
local function find_fx(take)
  for i = 0, reaper.TakeFX_GetCount(take) - 1 do
    local ok, ident = reaper.TakeFX_GetNamedConfigParm(take, i, "fx_ident")
    if ok and ident:find(JSFX_FILE, 1, true) then return i end
  end
  return -1
end

local function show_envelope(env)
  reaper.GetSetEnvelopeInfo_String(env, "ACTIVE", "1", true)
  if reaper.GetSetEnvelopeInfo_String(env, "VISIBLE", "1", true) then return end
  -- Fallback for builds without the VISIBLE attribute: first field of the VIS line.
  local ok, chunk = reaper.GetEnvelopeStateChunk(env, "", false)
  if ok then
    local new_chunk = (chunk:gsub("\nVIS %d+", "\nVIS 1", 1))
    reaper.SetEnvelopeStateChunk(env, new_chunk, false)
  end
end

local count = reaper.CountSelectedMediaItems(0)
if count == 0 then return end

if not install_jsfx() then
  reaper.MB("Could not find or install " .. JSFX_FILE .. ".", "Item High Cut", 0)
  return
end

local takes = {}
for i = 0, count - 1 do
  local take = reaper.GetActiveTake(reaper.GetSelectedMediaItem(0, i))
  if take then takes[#takes + 1] = take end
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)
local failed = false
for _, take in ipairs(takes) do
  local fx = find_fx(take)
  if fx < 0 then fx = reaper.TakeFX_AddByName(take, FX_NAME, -1) end
  if fx < 0 then
    failed = true
  else
    local env = reaper.TakeFX_GetEnvelope(take, fx, CUTOFF_PARAM, true)
    if env then show_envelope(env) end
  end
end
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock("MTT: add high cut with cutoff envelope", -1)

if failed then
  reaper.MB("REAPER could not load " .. FX_NAME .. " on some items.", "Item High Cut", 0)
end
