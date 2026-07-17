local nSelectedMediaItems = reaper.CountSelectedMediaItems(0)

if nSelectedMediaItems == 0 then
    reaper.ShowMessageBox("Selezionare almeno un Media Item", "", 0)
    return
end

for i = 0, nSelectedMediaItems - 1 do

    local selectedItem = reaper.GetSelectedMediaItem(0, i)

    local activeTake = reaper.GetActiveTake(selectedItem)

    local source = reaper.GetMediaItemTake_Source(activeTake)

    local sourceName = reaper.GetMediaSourceFileName(source)

    --if sourceName == "" then
        local track = reaper.GetMediaItem_Track(selectedItem)

        local itemStartPos = reaper.GetMediaItemInfo_Value(selectedItem, "D_POSITION")

        local itemEndPos = reaper.GetMediaItemInfo_Value(selectedItem, "D_LENGTH") + itemStartPos

        local parentTrack = reaper.GetParentTrack(track)

        while true do
            local nextParentTrack = reaper.GetParentTrack(parentTrack)
            if not nextParentTrack then
                break
            end
            parentTrack = nextParentTrack
        end

        local nParentTrackItems = reaper.GetTrackNumMediaItems(parentTrack)

        for j = 0, nParentTrackItems - 1 do
            local parentTrackItem = reaper.GetTrackMediaItem(parentTrack, j)

            local parentItemStartPos = reaper.GetMediaItemInfo_Value(parentTrackItem, "D_POSITION")

            local parentItemEndPos = reaper.GetMediaItemInfo_Value(parentTrackItem, "D_LENGTH") + parentItemStartPos

            if ((parentItemStartPos <= itemStartPos) and (parentItemEndPos >= itemEndPos)) then

                local str = "TimeOffset: " .. tostring(itemStartPos - parentItemStartPos)

                local takeStartOffset = reaper.GetMediaItemTakeInfo_Value(activeTake, "D_STARTOFFS")

                reaper.SetTakeMarker(activeTake, -1, str, 0 + takeStartOffset)

                -- aggiungere controllo che se giá ce ne sta uno uguale (che inizia con TimeOffset: xxxx) lo elimina

            end
        end
    --end

end
