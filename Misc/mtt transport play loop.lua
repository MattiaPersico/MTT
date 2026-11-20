local clear_latches = 42025 -- Automation: Clear all track envelope latches
local copy_loop_points = 40622 -- Time selection: Move loop points to time selection
local play = 1007 -- Transport: Play

local start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
if start_time == end_time then
    local prepare_loop = reaper.NamedCommandLookup('_RS6c9b970717ae0f7ceb66e4befc07c24216c2b457')
    if prepare_loop == 0 then return end
    reaper.Main_OnCommand(prepare_loop, 0)
else
    reaper.SetEditCurPos(start_time, true, false)
end

reaper.Main_OnCommand(clear_latches, 0)
reaper.Main_OnCommand(copy_loop_points, 0)
reaper.GetSetRepeat(1)
reaper.Main_OnCommand(play, 0)
