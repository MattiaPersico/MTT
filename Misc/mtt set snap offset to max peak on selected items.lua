-- @description MTT set snap offset to max peak on selected items
-- @version 1.0.1
-- @author MTT


for i = 0, reaper.CountSelectedMediaItems(0) - 1, 1 do

    local item = reaper.GetSelectedMediaItem(0, i)
    local _, peak_pos = reaper.NF_GetMediaItemMaxPeakAndMaxPeakPos(item)
    reaper.SetMediaItemInfo_Value(item, "D_SNAPOFFSET", peak_pos)

end