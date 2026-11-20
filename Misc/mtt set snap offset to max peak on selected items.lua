-- @description MTT set snap offset to max peak on selected items
-- @version 1.0.2
-- @author MTT


local count = reaper.CountSelectedMediaItems(0)
if count == 0 then return end

if not reaper.APIExists('NF_GetMediaItemMaxPeakAndMaxPeakPos') then
    reaper.MB('The SWS Extension is required.', 'Set snap offset to max peak', 0)
    return
end

for i = 0, count - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local take = reaper.GetActiveTake(item)
    if take and not reaper.TakeIsMIDI(take) then
        local length = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
        if length > 0 and length < math.huge then
            local _, peak_pos = reaper.NF_GetMediaItemMaxPeakAndMaxPeakPos(item)
            if type(peak_pos) == 'number' and peak_pos >= 0 and peak_pos <= length then
                reaper.SetMediaItemInfo_Value(item, 'D_SNAPOFFSET', peak_pos)
            end
        end
    end
end