-- Toggle mute on the selected tracks, folder-aware.
-- A selected track hidden inside a fully collapsed folder is not muted itself:
-- the toggle goes to its outermost fully collapsed ancestor, once per folder.

local proj = 0

-- I_FOLDERCOMPACT: 0 = normal, 1 = small, 2 = tiny/hidden children (fully collapsed)
local FULLY_COLLAPSED = 2

-- Returns the track that must receive the toggle for a selected track:
-- its outermost fully collapsed ancestor, or the track itself when it is visible.
local function resolve_target(track)
  local target = track
  local parent = reaper.GetParentTrack(track)
  while parent do
    if reaper.GetMediaTrackInfo_Value(parent, "I_FOLDERCOMPACT") == FULLY_COLLAPSED then
      target = parent
    end
    parent = reaper.GetParentTrack(parent)
  end
  return target
end

local function main()
  local sel_count = reaper.CountSelectedTracks(proj)
  if sel_count == 0 then return end

  -- Pass 1: collect the targets, each one only once (several hidden children
  -- of the same folder must toggle the folder a single time).
  local targets, seen = {}, {}
  for i = 0, sel_count - 1 do
    local target = resolve_target(reaper.GetSelectedTrack(proj, i))
    if not seen[target] then
      seen[target] = true
      targets[#targets + 1] = target
    end
  end

  -- Pass 2: toggle each target, like the native "Track: Toggle mute for selected tracks".
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
