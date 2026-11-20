local major_version = 1
local minor_version = 9

local TREAT_CROSSFADED_AS_SINGLE = true
local INCLUDE_TOUCHING = false
local EPS = 1e-9
local UNDO_LABEL = "Align items: start to target peak"

local DUPLICATE = 41295 -- Item: Duplicate items
local RIPPLE_OFF = 40309 -- Set ripple editing off
local RIPPLE_TRACK = 40310 -- Set ripple editing per-track
local RIPPLE_ALL = 40311 -- Set ripple editing all tracks
local GROUPING = 1156 -- Toggle item grouping and track media/razor edit grouping
local AUTO_CROSSFADE = 40041 -- Auto-crossfade media items when editing
local TRIM_BEHIND = 41117 -- Trim content behind media items when editing

local selected_count = reaper.CountSelectedMediaItems(0)
if selected_count < 2 then return end

local selected, track_items = {}, {}
local highest_track, highest_track_num = nil, math.huge
for i = 0, selected_count - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local track = reaper.GetMediaItem_Track(item)
    local track_num = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    selected[#selected + 1] = item
    if not track_items[track] then track_items[track] = {} end
    local items = track_items[track]
    items[#items + 1] = { item = item, pos = pos, len = len }
    if track_num < highest_track_num then
        highest_track, highest_track_num = track, track_num
    end
end

local function build_groups(items)
    table.sort(items, function(a, b) return a.pos < b.pos end)
    local groups, current = {}, nil
    for _, it in ipairs(items) do
        local finish = it.pos + it.len
        local joins = TREAT_CROSSFADED_AS_SINGLE and current and
            (it.pos < current.end_pos or (INCLUDE_TOUCHING and it.pos == current.end_pos))
        if not joins then
            current = { items = {}, start_pos = it.pos, end_pos = finish }
            groups[#groups + 1] = current
        else
            current.end_pos = math.max(current.end_pos, finish)
        end
        -- Immutable geometry: the seed may already have moved when it is reused.
        it.relative_pos = it.pos - current.start_pos
        current.items[#current.items + 1] = it
    end
    return groups
end

local ref_items = track_items[highest_track]
track_items[highest_track] = nil
if not next(track_items) then return end
if not reaper.APIExists("NF_GetMediaItemMaxPeakAndMaxPeakPos") then
    reaper.MB("SWS is required for peak alignment.", UNDO_LABEL, 0)
    return
end

local function peak_offset(group)
    local best_amp, best_offset = -math.huge, 0
    for _, it in ipairs(group.items) do
        local amp, peak = reaper.NF_GetMediaItemMaxPeakAndMaxPeakPos(it.item)
        if amp and peak and amp > best_amp then
            best_amp, best_offset = amp, it.relative_pos + peak
        end
    end
    return best_offset
end
local ref_groups = build_groups(ref_items)
for _, group in ipairs(ref_groups) do group.peak_offset = peak_offset(group) end
local cursor, ripple, switches
local copies = {}
local pending_lock
local undo_open, refresh_held = false, false

local function toggle_state(action)
    return reaper.GetToggleCommandStateEx(0, action)
end

local function prepare_duplication()
    if cursor ~= nil then return end
    local all, per_track, off = toggle_state(RIPPLE_ALL), toggle_state(RIPPLE_TRACK), toggle_state(RIPPLE_OFF)
    local saved_ripple = all == 1 and RIPPLE_ALL or per_track == 1 and RIPPLE_TRACK or off == 1 and RIPPLE_OFF
    assert(saved_ripple, "Cannot determine ripple editing mode.")
    local saved_switches = {}
    for _, action in ipairs({ GROUPING, AUTO_CROSSFADE, TRIM_BEHIND }) do
        local state = toggle_state(action)
        assert(state == 0 or state == 1, "Cannot determine editing option " .. action .. ".")
        saved_switches[#saved_switches + 1] = { action = action, state = state }
    end
    cursor = reaper.GetCursorPosition()
    ripple, switches = saved_ripple, saved_switches
    if ripple ~= RIPPLE_OFF then reaper.Main_OnCommand(RIPPLE_OFF, 0) end
    for _, option in ipairs(switches) do
        if toggle_state(option.action) == 1 then reaper.Main_OnCommand(option.action, 0) end
    end
    assert(toggle_state(RIPPLE_OFF) == 1, "Cannot disable ripple editing.")
    for _, option in ipairs(switches) do
        assert(toggle_state(option.action) == 0, "Cannot disable editing option " .. option.action .. ".")
    end
    reaper.SelectAllMediaItems(0, false)
end

local function cleanup()
    if pending_lock then
        reaper.SetMediaItemInfo_Value(pending_lock.item, "C_LOCK", pending_lock.value)
        pending_lock = nil
    end
    if cursor ~= nil then
        reaper.SelectAllMediaItems(0, false)
        for _, item in ipairs(selected) do reaper.SetMediaItemSelected(item, true) end
        for _, item in ipairs(copies) do reaper.SetMediaItemSelected(item, true) end
        reaper.SetEditCurPos(cursor, false, false)
        for _, option in ipairs(switches) do
            if toggle_state(option.action) ~= option.state then reaper.Main_OnCommand(option.action, 0) end
        end
        if toggle_state(ripple) ~= 1 then reaper.Main_OnCommand(ripple, 0) end
        cursor = nil
    end
    if refresh_held then
        reaper.PreventUIRefresh(-1)
        refresh_held = false
        reaper.UpdateArrange()
    end
    if undo_open then
        reaper.Undo_EndBlock(UNDO_LABEL, -1)
        undo_open = false
    end
end

local function set_item_value(item, field, value)
    assert(reaper.SetMediaItemInfo_Value(item, field, value), "Cannot set item " .. field .. ".")
end

local function duplicate_item(item, track, pos)
    prepare_duplication()
    local count = reaper.CountMediaItems(0)
    local lock = reaper.GetMediaItemInfo_Value(item, "C_LOCK")
    if lock & 1 ~= 0 then
        pending_lock = { item = item, value = lock }
        set_item_value(item, "C_LOCK", lock & ~1)
    end
    -- A single seed makes the mapping unambiguous even for equal start times.
    reaper.SetMediaItemSelected(item, true)
    reaper.Main_OnCommand(DUPLICATE, 0)
    if pending_lock then
        set_item_value(item, "C_LOCK", lock)
        pending_lock = nil
    end
    reaper.SetMediaItemSelected(item, false)
    local copy = reaper.GetSelectedMediaItem(0, 0)
    assert(reaper.CountMediaItems(0) == count + 1 and reaper.CountSelectedMediaItems(0) == 1
        and copy and reaper.GetMediaItem_Track(copy) == track,
        "Native duplication did not return exactly one selected copy on the seed track.")
    copies[#copies + 1] = copy
    reaper.SetMediaItemSelected(copy, false)
    set_item_value(copy, "D_POSITION", pos)
    if lock & 1 ~= 0 then set_item_value(copy, "C_LOCK", lock) end
    return copy
end

local function add_final_span(spans, items)
    local start_pos, end_pos = math.huge, -math.huge
    for _, item in ipairs(items) do
        local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        start_pos, end_pos = math.min(start_pos, pos), math.max(end_pos, pos + len)
    end
    spans[#spans + 1] = { start_pos = start_pos, end_pos = end_pos }
end

local function has_overlap(spans)
    table.sort(spans, function(a, b) return a.start_pos < b.start_pos end)
    local end_pos = -math.huge
    for _, span in ipairs(spans) do
        if span.start_pos < end_pos - EPS then return true end
        end_pos = math.max(end_pos, span.end_pos)
    end
    return false
end

local function align()
    local timeline_changed = false
    for track, items in pairs(track_items) do
        local groups, spans = build_groups(items), {}
        local original_count = #groups
        for idx, ref in ipairs(ref_groups) do
            local group = groups[(idx - 1) % original_count + 1]
            local group_start = ref.start_pos + ref.peak_offset
            local placed = {}
            for _, it in ipairs(group.items) do
                local pos = group_start + it.relative_pos
                if idx > original_count then
                    placed[#placed + 1] = duplicate_item(it.item, track, pos)
                else
                    set_item_value(it.item, "D_POSITION", pos)
                    placed[#placed + 1] = it.item
                end
            end
            add_final_span(spans, placed)
        end
        for idx = #ref_groups + 1, original_count do
            local placed = {}
            for _, it in ipairs(groups[idx].items) do placed[#placed + 1] = it.item end
            add_final_span(spans, placed)
        end
        -- Do not cycle existing free positioning or replace fixed lanes.
        if reaper.GetMediaTrackInfo_Value(track, "I_FREEMODE") == 0 and has_overlap(spans) then
            assert(reaper.SetMediaTrackInfo_Value(track, "I_FREEMODE", 1), "Cannot enable free item positioning.")
            timeline_changed = true
        end
    end
    if timeline_changed then reaper.UpdateTimeline() end
end

reaper.atexit(cleanup)
reaper.Undo_BeginBlock()
undo_open = true
reaper.PreventUIRefresh(1)
refresh_held = true
local ok, err = xpcall(align, debug.traceback)
cleanup()
if not ok then reaper.MB(err .. "\n\nUndo to revert any partial alignment.", UNDO_LABEL, 0) end
