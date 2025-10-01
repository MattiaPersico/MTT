local major_version = 1
local minor_version = 6 -- crossfade grouping

-- CONFIG ------------------------------------------------------------
-- Se true: item che si sovrappongono (overlap / crossfade) vengono trattati come un solo blocco
local TREAT_CROSSFADED_AS_SINGLE = true
-- Se true: anche item che solo si toccano (end == start) vengono fusi
local INCLUDE_TOUCHING = false
---------------------------------------------------------------------

-- Selezione insufficiente
if reaper.CountSelectedMediaItems(0) < 2 then return end

reaper.PreventUIRefresh(1)
reaper.Undo_BeginBlock()

-- Costruisci una mappa traccia -> lista item selezionati (ordinati per posizione)
local track_items = {}
local highest_track_num = math.huge
local highest_track = nil

for i = 0, reaper.CountSelectedMediaItems(0)-1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local track = reaper.GetMediaItem_Track(item)
    local track_num = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")

    if not track_items[track] then
        track_items[track] = {}
    end
    table.insert(track_items[track], {item=item, pos=pos})

    if track_num < highest_track_num then
        highest_track_num = track_num
        highest_track = track
    end
end

-- Ordina gli item su ogni traccia in base alla posizione
-- (manteniamo la logica originale, poi ricostruiremo gruppi)
for track, items in pairs(track_items) do
    table.sort(items, function(a, b) return a.pos < b.pos end)
end

-- Utility per costruire gruppi di item sovrapposti
local function build_groups(sorted_items)
    if not TREAT_CROSSFADED_AS_SINGLE then
        local single = {}
        for _, it in ipairs(sorted_items) do
            local pos = reaper.GetMediaItemInfo_Value(it.item, "D_POSITION")
            local len = reaper.GetMediaItemInfo_Value(it.item, "D_LENGTH")
            single[#single+1] = { items = {it}, start_pos = pos, end_pos = pos + len }
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
            current = { items = {it}, start_pos = pos, end_pos = item_end }
        else
            local overlap
            if INCLUDE_TOUCHING then overlap = pos <= current.end_pos else overlap = pos < current.end_pos end
            if overlap then
                current.items[#current.items+1] = it
                if item_end > current.end_pos then current.end_pos = item_end end
            else
                groups[#groups+1] = current
                current = { items = {it}, start_pos = pos, end_pos = item_end }
            end
        end
    end
    if current then groups[#groups+1] = current end
    return groups
end

local function compute_group_peaks(groups)
    for _, g in ipairs(groups) do
        local best_amp = -math.huge
        local best_time = g.start_pos
        for _, it in ipairs(g.items) do
            local amp, peak_pos = reaper.NF_GetMediaItemMaxPeakAndMaxPeakPos(it.item)
            if amp and peak_pos then
                if amp > best_amp then
                    best_amp = amp
                    local item_pos = reaper.GetMediaItemInfo_Value(it.item, "D_POSITION")
                    best_time = item_pos + peak_pos
                end
            end
        end
        g.peak_time = best_time
        g.peak_amp = best_amp
        g.rel_peak_offset = best_time - g.start_pos
    end
end

local ref_items = nil -- evitiamo uso accidentale
local ref_items_raw = track_items[highest_track]
track_items[highest_track] = nil
local ref_groups = build_groups(ref_items_raw)
compute_group_peaks(ref_groups)

-- Funzione di duplicazione migliorata
local function duplicate_item_on_track(item)
    local track = reaper.GetMediaItem_Track(item)
    local new_item = reaper.AddMediaItemToTrack(track)

    -- Copia le proprietà dell'item
    local item_props = {
        "D_LENGTH", "D_SNAPOFFSET", "D_FADEINLEN", "D_FADEOUTLEN",
        "D_FADEINDIR", "D_FADEOUTDIR", "D_FADEINSHAPE", "D_FADEOUTSHAPE",
        "D_VOL", "D_PAN", "D_PANLAW", "C_BEATATTACHMODE",
        "B_LOOPSRC", "B_ALLTAKESLPLAY", "B_UISEL", "C_LOCK", "B_MUTE",
        "B_REVERSE", "C_FADEIN", "C_FADEOUT"
    }
    for _, prop in ipairs(item_props) do
        local val = reaper.GetMediaItemInfo_Value(item, prop)
        reaper.SetMediaItemInfo_Value(new_item, prop, val)
    end

    local color = reaper.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR")
    reaper.SetMediaItemInfo_Value(new_item, "I_CUSTOMCOLOR", color)

    local _, item_name = reaper.GetSetMediaItemInfo_String(item, "P_NAME", "", false)
    reaper.GetSetMediaItemInfo_String(new_item, "P_NAME", item_name, true)

    -- Take
    local take = reaper.GetActiveTake(item)
    local new_take = reaper.AddTakeToMediaItem(new_item)
    if take and new_take then
        local src = reaper.GetMediaItemTake_Source(take)
        reaper.SetMediaItemTake_Source(new_take, src)

        local take_props = {
            "D_STARTOFFS", "D_VOL", "D_PAN", "D_PANLAW", "D_PLAYRATE",
            "D_PITCH", "B_PPITCH", "I_CHANMODE", "I_PITCHMODE",
            "I_STRETCHFLAGS", "F_STRETCHFADESIZE"
        }
        for _, prop in ipairs(take_props) do
            local val = reaper.GetMediaItemTakeInfo_Value(take, prop)
            reaper.SetMediaItemTakeInfo_Value(new_take, prop, val)

        end

        -- Copia FX
        local fx_count = reaper.TakeFX_GetCount(take)
        for fx_i = 0, fx_count - 1 do
            reaper.TakeFX_CopyToTake(take, fx_i, new_take, fx_i, false)
        end
    end

    -- Rimuovi take di default
    if reaper.GetMediaItemNumTakes(new_item) > 1 then
        reaper.RemoveTake(reaper.GetMediaItemTake(new_item, 0))
    end

    reaper.SetMediaItemSelected(new_item, true)
    return new_item
end

-- Nuova funzione duplicazione gruppo
local function duplicate_group_on_track(group)
    local new_group = { items = {}, start_pos = math.huge, end_pos = -math.huge }
    for _, it in ipairs(group.items) do
        local new_item = duplicate_item_on_track(it.item)
        local pos = reaper.GetMediaItemInfo_Value(new_item, "D_POSITION")
        local len = reaper.GetMediaItemInfo_Value(new_item, "D_LENGTH")
        if pos < new_group.start_pos then new_group.start_pos = pos end
        if pos + len > new_group.end_pos then new_group.end_pos = pos + len end
        new_group.items[#new_group.items+1] = { item = new_item }
    end
    new_group.rel_peak_offset = group.rel_peak_offset
    new_group.peak_time = new_group.start_pos + (group.rel_peak_offset or 0)
    return new_group
end

for track, items in pairs(track_items) do
    table.sort(items, function(a,b) return a.pos < b.pos end)
    local groups = build_groups(items)
    compute_group_peaks(groups)
    local group_count = #groups

    for idx, ref_group in ipairs(ref_groups) do
        local source_idx = ((idx-1) % group_count) + 1
        local target_group = groups[source_idx]

        if idx > group_count then
            local new_group = duplicate_group_on_track(target_group)
            groups[#groups+1] = new_group
            target_group = new_group
            group_count = #groups
        end

        local offset = ref_group.peak_time - target_group.peak_time
        for _, it in ipairs(target_group.items) do
            local item_pos = reaper.GetMediaItemInfo_Value(it.item, "D_POSITION")
            reaper.SetMediaItemInfo_Value(it.item, "D_POSITION", item_pos + offset)
        end
        target_group.start_pos = target_group.start_pos + offset
        target_group.end_pos   = target_group.end_pos + offset
        target_group.peak_time = target_group.peak_time + offset
    end

    -- Free item positioning logic basata sui gruppi: consideriamo solo sovrapposizioni TRA gruppi
    local needToSetFreeItemPositioningTrue = false
    -- Se la traccia è già in free mode la riportiamo a normal ma memorizziamo che andrà riattivata se necessario
    if reaper.GetMediaTrackInfo_Value(track, "I_FREEMODE") == 1 then
        needToSetFreeItemPositioningTrue = true -- manteniamo lo stato precedente
        reaper.SetMediaTrackInfo_Value(track, "I_FREEMODE", 0)
    end

    -- Epsilon per considerare piccoli errori floating (es. 1 microsecondo)
    local EPS = 1e-9
    local prev_end = nil
    for i, g in ipairs(groups) do
        if prev_end then
            local overlap
            if INCLUDE_TOUCHING then
                overlap = g.start_pos < prev_end - EPS -- se si toccano perfetto, nessun overlap: richiediamo meno di end
            else
                overlap = g.start_pos < prev_end - EPS -- stesso criterio, ma senza includere contatto
            end
            if overlap then
                needToSetFreeItemPositioningTrue = true
                break
            end
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



--reaper.Main_OnCommand(reaper.NamedCommandLookup("_FNG_CLEAN_OVERLAP"), 0)
reaper.UpdateArrange()
reaper.Undo_EndBlock("Allinea picchi agli item della traccia più alta (con duplicati se necessari)", -1)
reaper.PreventUIRefresh(-1)