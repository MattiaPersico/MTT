
local move_to_play_cursor = 40434 -- View: Move edit cursor to play cursor
local play_stop = 40044 -- Transport: Play/stop
local remove_loop_points = 40634 -- Loop points: Remove (unselect) loop point selection

reaper.GetSetRepeat(0)
reaper.Main_OnCommand(move_to_play_cursor, 0)
reaper.Main_OnCommand(play_stop, 0)
reaper.Main_OnCommand(remove_loop_points, 0)
reaper.GetSetRepeat(0)
