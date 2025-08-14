
-- my variant of the original spk77 script
local major_version = 1
local minor_version = 1

function HandlePluginException(source_track, source_fx_index, source_param_index, dest_track, dest_fx_index, val)
  local _, fx_name = reaper.TrackFX_GetFXName(source_track, source_fx_index, "")
  local _, param_name = reaper.TrackFX_GetParamName(source_track, source_fx_index, source_param_index, "")

  -- FabFilter Pro-Q 3 / 4 update all n band params when one change to handle band points movement
  if fx_name == "VST3: Pro-Q 3 (FabFilter)" or fx_name == "VST3: Pro-Q 4 (FabFilter)" then
    local band_prefix = param_name:match("^(Band %d+)")
    if band_prefix then
      for p = 0, reaper.TrackFX_GetNumParams(source_track, source_fx_index) - 1 do
        local _, src_name = reaper.TrackFX_GetParamName(source_track, source_fx_index, p, "")
        if src_name:match("^" .. band_prefix) then
          local src_val = reaper.TrackFX_GetParam(source_track, source_fx_index, p)
          reaper.TrackFX_SetParam(dest_track, dest_fx_index, p, src_val)
        end
      end
      return true
    end
  end

-- ReaSurroundPan: update only channel gains, X, Y, Z, LFE
if fx_name == "VST: ReaSurroundPan (Cockos)" then
  local ch_prefix, suffix = param_name:match("^(in %d+) ([gainXYZLFE]+)$")
  if ch_prefix and suffix then
    for p = 0, reaper.TrackFX_GetNumParams(source_track, source_fx_index) - 1 do
      local _, name = reaper.TrackFX_GetParamName(source_track, source_fx_index, p, "")
      local ch_match, subparam = name:match("^(in %d+) ([gainXYZLFE]+)$")
      if ch_match == ch_prefix and subparam and subparam:match("^[gainXYZLFE]+$") then
        local src_val = reaper.TrackFX_GetParam(source_track, source_fx_index, p)

        -- if param is X and its not the manually controlled track then invert
        if subparam == "X" and dest_track ~= source_track then
          src_val = 1 - src_val
        end

        reaper.TrackFX_SetParam(dest_track, dest_fx_index, p, src_val)
      end
    end
    return true
  else
    return true
  end
end

  return false
end

function SetButtonState(set)
  local _, _, sec, cmd = reaper.get_action_context()
  reaper.SetToggleCommandState(sec, cmd, set or 0)
  reaper.RefreshToolbar2(sec, cmd)
end

-- lock track selection
local locked_tracks = {}
for i = 0, reaper.CountSelectedTracks(0) - 1 do
  locked_tracks[i + 1] = reaper.GetSelectedTrack(0, i)
end

local last_param = -1
local last_val = -1

function main()
  -- re-select tracks if track selection changed
  local mismatch = false
  if reaper.CountSelectedTracks(0) ~= #locked_tracks then
    mismatch = true
  else
    for i = 0, #locked_tracks - 1 do
      if reaper.GetSelectedTrack(0, i) ~= locked_tracks[i + 1] then
        mismatch = true
        break
      end
    end
  end
  if mismatch then
    reaper.Main_OnCommand(40297, 0) -- unselect all tracks
    for _, tr in ipairs(locked_tracks) do
      reaper.SetTrackSelected(tr, true)
    end
  end

  local ret, trk_num, fx_idx, param_idx = reaper.GetLastTouchedFX()
  if not ret then reaper.defer(main) return end

  local track = reaper.CSurf_TrackFromID(trk_num, false)
  if not track then reaper.defer(main) return end

  local val = reaper.TrackFX_GetParam(track, fx_idx, param_idx)
  val = math.floor(val * 1e7 + 0.5) / 1e7

  if param_idx == last_param and val == last_val then
    reaper.defer(main)
    return
  end

  last_param = param_idx
  last_val = val

  for _, tr in ipairs(locked_tracks) do
    if tr ~= track then
      local dest_fx_name = select(2, reaper.TrackFX_GetFXName(tr, fx_idx, ""))
      if dest_fx_name then
        local handled = HandlePluginException(track, fx_idx, param_idx, tr, fx_idx, val)
        if not handled then
          reaper.TrackFX_SetParam(tr, fx_idx, param_idx, val)
        end
      end
    end
  end

  reaper.defer(main)
end

SetButtonState(1)
main()
reaper.atexit(function() SetButtonState(0) end)



