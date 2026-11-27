-- Toggle mute on the selected tracks, folder-aware.
-- Folder-aware rule applies ONLY to top-level folder parents (depth 0) that are
-- fully collapsed: the toggle goes to that top-level parent alone, and none of
-- its children (selected or not, at any depth) are touched.
-- Everything else works like the native "Track: Toggle mute for selected tracks":
-- each selected track is toggled on its own.

local proj = 0

-- I_FOLDERCOMPACT: 0 = normal, 1 = small, 2 = tiny/hidden children (fully collapsed)
local FULLY_COLLAPSED = 2

-- Returns the top-level (depth 0) ancestor of a track, or the track itself
-- when it is already at the top level.
local function top_level_of(track)
  local top = track
  local parent = reaper.GetParentTrack(track)
  while parent do
    top = parent
    parent = reaper.GetParentTrack(parent)
  end
  return top
end

local function is_fully_collapsed_folder(track)
  return reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1
     and reaper.GetMediaTrackInfo_Value(track, "I_FOLDERCOMPACT") == FULLY_COLLAPSED
end

-- Returns the track that must receive the toggle for a selected track:
-- its top-level parent when that parent is a fully collapsed folder,
-- otherwise the track itself (classic behaviour).
local function resolve_target(track)
  local top = top_level_of(track)
  if is_fully_collapsed_folder(top) then
    return top
  end
  return track
end

local function main()
  local sel_count = reaper.CountSelectedTracks(proj)
  if sel_count == 0 then return end

  -- Pass 1: collect the targets, each one only once (a collapsed top-level
  -- parent selected together with its hidden children toggles a single time).
  local targets, seen = {}, {}
  for i = 0, sel_count - 1 do
    local target = resolve_target(reaper.GetSelectedTrack(proj, i))
    if not seen[target] then
      seen[target] = true
      targets[#targets + 1] = target
    end
  end

  -- Pass 2: toggle each target individually.
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  for _, track in ipairs(targets) do
    local muted = reaper.GetMediaTrackInfo_Value(track, "B_MUTE") ~= 0
    reaper.SetMediaTrackInfo_Value(track, "B_MUTE", muted and 0 or 1)
  end
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("Toggle mute on selected tracks (folder-aware)", -1)
end

main()
