local major_version = 1
local minor_version = 7

if reaper.CountSelectedMediaItems(0) < 2 then return end

-- CONFIG ------------------------------------------------------------
local TREAT_CROSSFADED_AS_SINGLE = true
local INCLUDE_TOUCHING = false
---------------------------------------------------------------------

reaper.PreventUIRefresh(1)
reaper.Undo_BeginBlock()

local track_items = {}
local highest_track_num = math.huge
local highest_track = nil
for i = 0, reaper.CountSelectedMediaItems(0)-1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local track = reaper.GetMediaItem_Track(item)
    local track_num = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    if not track_items[track] then track_items[track] = {} end
    table.insert(track_items[track], {item=item, pos=pos})
    if track_num < highest_track_num then highest_track_num = track_num highest_track = track end
end
for track, items in pairs(track_items) do table.sort(items, function(a,b) return a.pos < b.pos end) end

local function build_groups(sorted_items)
    if not TREAT_CROSSFADED_AS_SINGLE then
        local single = {}
        for _, it in ipairs(sorted_items) do
            local pos = reaper.GetMediaItemInfo_Value(it.item, "D_POSITION")
            local len = reaper.GetMediaItemInfo_Value(it.item, "D_LENGTH")
            single[#single+1] = { items={it}, start_pos=pos, end_pos=pos+len }
        end
        return single
    end
    local groups = {}
    local current
    for _, it in ipairs(sorted_items) do
        local pos = reaper.GetMediaItemInfo_Value(it.item, "D_POSITION")
        local len = reaper.GetMediaItemInfo_Value(it.item, "D_LENGTH")
        local item_end = pos + len
        if not current then
            current = { items={it}, start_pos=pos, end_pos=item_end }
        else
            local overlap = INCLUDE_TOUCHING and (pos <= current.end_pos) or (pos < current.end_pos)
            if overlap then
                current.items[#current.items+1] = it
                if item_end > current.end_pos then current.end_pos = item_end end
            else
                groups[#groups+1] = current
                current = { items={it}, start_pos=pos, end_pos=item_end }
            end
        end
    end
    if current then groups[#groups+1] = current end
    return groups
end

local ref_items_raw = highest_track and track_items[highest_track] or {}
if highest_track then track_items[highest_track] = nil end
local ref_groups = build_groups(ref_items_raw)

-- Allineamento: start target -> start ref
for track, items in pairs(track_items) do
    table.sort(items, function(a,b) return a.pos < b.pos end)
    local groups = build_groups(items)
    local group_count = #groups
    for idx, ref_group in ipairs(ref_groups) do
        local source_idx = ((idx-1) % group_count) + 1
        local target_group = groups[source_idx]
        if idx > group_count then
            -- duplica gruppo (reuse prima item duplication logic)
            local new_group = { items = {}, start_pos = math.huge, end_pos = -math.huge }
            for _, it in ipairs(target_group.items) do
                local track_it = reaper.GetMediaItem_Track(it.item)
                local new_item = reaper.AddMediaItemToTrack(track_it)
                local item_props = {"D_LENGTH","D_SNAPOFFSET","D_FADEINLEN","D_FADEOUTLEN","D_FADEINDIR","D_FADEOUTDIR","D_FADEINSHAPE","D_FADEOUTSHAPE","D_VOL","D_PAN","D_PANLAW","C_BEATATTACHMODE","B_LOOPSRC","B_ALLTAKESLPLAY","B_UISEL","C_LOCK","B_MUTE","B_REVERSE","C_FADEIN","C_FADEOUT"}
                for _, prop in ipairs(item_props) do reaper.SetMediaItemInfo_Value(new_item, prop, reaper.GetMediaItemInfo_Value(it.item, prop)) end
                reaper.SetMediaItemInfo_Value(new_item, "I_CUSTOMCOLOR", reaper.GetMediaItemInfo_Value(it.item, "I_CUSTOMCOLOR"))
                local _, item_name = reaper.GetSetMediaItemInfo_String(it.item, "P_NAME", "", false)
                reaper.GetSetMediaItemInfo_String(new_item, "P_NAME", item_name, true)
                local take = reaper.GetActiveTake(it.item)
                local new_take = reaper.AddTakeToMediaItem(new_item)
                if take and new_take then
                    local src = reaper.GetMediaItemTake_Source(take)
                    reaper.SetMediaItemTake_Source(new_take, src)
                    local take_props = {"D_STARTOFFS","D_VOL","D_PAN","D_PANLAW","D_PLAYRATE","D_PITCH","B_PPITCH","I_CHANMODE","I_PITCHMODE","I_STRETCHFLAGS","F_STRETCHFADESIZE"}
                    for _, prop in ipairs(take_props) do reaper.SetMediaItemTakeInfo_Value(new_take, prop, reaper.GetMediaItemTakeInfo_Value(take, prop)) end
                    local fx_count = reaper.TakeFX_GetCount(take)
                    for fx_i = 0, fx_count - 1 do reaper.TakeFX_CopyToTake(take, fx_i, new_take, fx_i, false) end
                end
                if reaper.GetMediaItemNumTakes(new_item) > 1 then
                    local first_take = reaper.GetMediaItemTake(new_item,0)
                    if first_take then reaper.RemoveTake(first_take) end
                end
                local pos = reaper.GetMediaItemInfo_Value(new_item, "D_POSITION")
                local len = reaper.GetMediaItemInfo_Value(new_item, "D_LENGTH")
                if pos < new_group.start_pos then new_group.start_pos = pos end
                if pos + len > new_group.end_pos then new_group.end_pos = pos + len end
                new_group.items[#new_group.items+1] = { item = new_item }
            end
            groups[#groups+1] = new_group
            target_group = new_group
            group_count = #groups
        end
        local offset = ref_group.start_pos - target_group.start_pos
        for _, it in ipairs(target_group.items) do
            local item_pos = reaper.GetMediaItemInfo_Value(it.item, "D_POSITION")
            reaper.SetMediaItemInfo_Value(it.item, "D_POSITION", item_pos + offset)
        end
        target_group.start_pos = target_group.start_pos + offset
        target_group.end_pos = target_group.end_pos + offset
    end

    local needToSetFreeItemPositioningTrue = false
    if reaper.GetMediaTrackInfo_Value(track, "I_FREEMODE") == 1 then
        needToSetFreeItemPositioningTrue = true
        reaper.SetMediaTrackInfo_Value(track, "I_FREEMODE", 0)
    end
    local prev_end = nil
    local EPS = 1e-9
    for _, g in ipairs(groups) do
        if prev_end then
            local overlap = g.start_pos < prev_end - EPS
            if overlap then needToSetFreeItemPositioningTrue = true break end
        end
        prev_end = g.end_pos
    end
    if needToSetFreeItemPositioningTrue then
        local selected_tracks = {}
        for i=0, reaper.CountSelectedTracks(0)-1 do
            selected_tracks[i] = reaper.GetSelectedTrack(0, i)
            reaper.SetTrackSelected(selected_tracks[i], false)
        end
        reaper.SetTrackSelected(track, true)
        reaper.Main_OnCommand(40751, 0)
        for i=0, #selected_tracks-1 do
            reaper.SetTrackSelected(selected_tracks[i], true)
        end
    end
end

reaper.UpdateArrange()
reaper.Undo_EndBlock("Allinea start a start con grouping crossfade", -1)
reaper.PreventUIRefresh(-1)
