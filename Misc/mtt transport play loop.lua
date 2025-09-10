local time_selection_start_time, time_selection_end_time = reaper.GetSet_LoopTimeRange(false, 0, 0, 0, false)

if time_selection_start_time == time_selection_end_time then -- se non c'é alcuna time selection.

    if reaper.CountSelectedMediaItems(0) > 0 then

        local start_pos = 0
        local end_pos = 0

        for i = 0, reaper.CountSelectedMediaItems(0) - 1 do

            local item = reaper.GetSelectedMediaItem(0, i)
            local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local item_end = item_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")

            if i == 0 then
                start_pos = item_start
                end_pos = item_end
            else
                if item_start < start_pos then
                    start_pos = item_start
                end
                if item_end > end_pos then
                    end_pos = item_end
                end
            end
        end

        reaper.GetSet_LoopTimeRange(true, false, start_pos, end_pos, true)

        local cursor_position = reaper.GetCursorPosition()

        if cursor_position < start_pos or cursor_position > end_pos then
            reaper.SetEditCurPos(start_pos, true, false)
        end
    end
else    -- se invece c'é una time selection
    reaper.SetEditCurPos(time_selection_start_time, true, false)
end

reaper.Main_OnCommand(42025, 0) -- Clear all tracks envelope latches
reaper.Main_OnCommand(40622, 0) -- Move loop points to time selection
--reaper.Main_OnCommand(1068, 0) -- toggle repeat
reaper.GetSetRepeat(1)
reaper.Main_OnCommand(1007,0) -- PLAY ONLY
--reaper.Main_OnCommand(40044, 0) -- Transport: Play/stop



--reaper.ShowConsoleMsg("Loop start time: " .. tostring(time_selection_start_time) .. "\n")
--reaper.ShowConsoleMsg("Loop end time: " .. tostring(time_selection_end_time) .. "\n")
--reaper.ShowConsoleMsg("isLoop: " .. tostring(isLoop) .. "\n")
