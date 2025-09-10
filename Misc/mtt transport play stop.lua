
reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_UNSETREPEAT"), 0)
reaper.Main_OnCommand(40434, 0) -- move edit cursor to play cursor
reaper.Main_OnCommand(40044,0)
reaper.Main_OnCommand(40634, 0) -- Move edit cursor to start of time selection

reaper.GetSetRepeat(0)
local time_selection_start_time, time_selection_end_time = reaper.GetSet_LoopTimeRange(false, 0, 0, 0, false)

--reaper.ShowConsoleMsg("Loop start time: " .. tostring(time_selection_start_time) .. "\n")
--reaper.ShowConsoleMsg("Loop end time: " .. tostring(time_selection_end_time) .. "\n")