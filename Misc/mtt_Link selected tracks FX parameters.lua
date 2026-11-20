-- my variant of the original spk77 script
local major_version = 1
local minor_version = 3

local function GetSourceUpdates(track, fx, param, val, raw_val, fx_name)
  local pro_q = fx_name == "VST3: Pro-Q 3 (FabFilter)" or fx_name == "VST3: Pro-Q 4 (FabFilter)"
  local surround = fx_name == "VST: ReaSurroundPan (Cockos)"
  if not pro_q and not surround then return {{ param, val }} end

  local _, param_name = reaper.TrackFX_GetParamName(track, fx, param)
  local band = pro_q and param_name:match("^Band (%d+)")
  local channel = surround and param_name:match("^(in %d+) [gainXYZLFE]+$")
  if pro_q and not band then return {{ param, val }} end
  if surround and not channel then return {} end

  local updates = {}
  for p = 0, reaper.TrackFX_GetNumParams(track, fx) - 1 do
    local name = param_name
    if p ~= param then
      local _, other_name = reaper.TrackFX_GetParamName(track, fx, p)
      name = other_name
    end
    if pro_q and name:match("^Band (%d+)") == band then
      local src_val = p == param and raw_val or reaper.TrackFX_GetParam(track, fx, p)
      updates[#updates + 1] = { p, src_val }
    elseif surround then
      local ch, subparam = name:match("^(in %d+) ([gainXYZLFE]+)$")
      if ch == channel then
        local src_val = p == param and raw_val or reaper.TrackFX_GetParam(track, fx, p)
        if subparam == "X" then src_val = 1 - src_val end
        updates[#updates + 1] = { p, src_val }
      end
    end
  end
  return updates
end

local function SetButtonState(set)
  local _, _, sec, cmd = reaper.get_action_context()
  reaper.SetToggleCommandState(sec, cmd, set or 0)
  reaper.RefreshToolbar2(sec, cmd)
end

-- Lock the starting project's track selection, independent of track order.
local project = reaper.EnumProjects(-1)
local locked_tracks = {}
local locked_count = reaper.CountSelectedTracks(project)
for i = 0, locked_count - 1 do
  locked_tracks[reaper.GetSelectedTrack(project, i)] = true
end

local unselect_all_tracks = 40297 -- Track: Unselect (clear selection of) all tracks
local last_track, last_guid, last_fx, last_param, last_val

local function main()
  reaper.defer(main)
  if reaper.EnumProjects(-1) ~= project then return end

  local selected_count = reaper.CountSelectedTracks(project)
  local mismatch = selected_count ~= locked_count
  if not mismatch then
    for i = 0, selected_count - 1 do
      if not locked_tracks[reaper.GetSelectedTrack(project, i)] then
        mismatch = true
        break
      end
    end
  end
  if mismatch then
    reaper.Main_OnCommand(unselect_all_tracks, 0)
    for tr in pairs(locked_tracks) do
      if reaper.ValidatePtr2(project, tr, "MediaTrack*") then
        reaper.SetTrackSelected(tr, true)
      else
        locked_tracks[tr] = nil
        locked_count = locked_count - 1
      end
    end
  end

  local ret, trk_num, fx_idx, param_idx = reaper.GetLastTouchedFX()
  -- The high word is a take FX's item index, not part of the track ID.
  if not ret or trk_num >> 16 ~= 0 then return end

  local track = reaper.CSurf_TrackFromID(trk_num, false)
  if not track then return end
  local guid = reaper.TrackFX_GetFXGUID(track, fx_idx)
  if not guid or guid == "" then return end

  local raw_val = reaper.TrackFX_GetParam(track, fx_idx, param_idx)
  local val = math.floor(raw_val * 1e7 + 0.5) / 1e7
  if track == last_track and guid == last_guid and fx_idx == last_fx
      and param_idx == last_param and val == last_val then return end
  last_track, last_guid, last_fx, last_param, last_val = track, guid, fx_idx, param_idx, val

  local src_ok, src_fx_name = reaper.TrackFX_GetFXName(track, fx_idx)
  if not src_ok then return end
  local updates
  for tr in pairs(locked_tracks) do
    if tr ~= track and reaper.ValidatePtr2(project, tr, "MediaTrack*") then
      -- Keep matching by slot and exact FX name.
      local dest_ok, dest_fx_name = reaper.TrackFX_GetFXName(tr, fx_idx)
      if dest_ok and dest_fx_name == src_fx_name then
        updates = updates or GetSourceUpdates(track, fx_idx, param_idx, val, raw_val, src_fx_name)
        for _, update in ipairs(updates) do
          reaper.TrackFX_SetParam(tr, fx_idx, update[1], update[2])
        end
      end
    end
  end
end

reaper.atexit(function() SetButtonState(0) end)
SetButtonState(1)
main()
