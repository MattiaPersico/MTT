local major_version = 1
local minor_version = 3

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
for track, items in pairs(track_items) do
    table.sort(items, function(a, b) return a.pos < b.pos end)
end

local ref_items = track_items[highest_track]
track_items[highest_track] = nil  -- rimuovi la traccia di riferimento dal loop

-- Calcola gli start time della traccia di riferimento
for _, t in ipairs(ref_items) do
    t.start_time = reaper.GetMediaItemInfo_Value(t.item, "D_POSITION")
end

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

-- Allinea gli altri item: inizio -> inizio del target
for track, items in pairs(track_items) do
    local count = #items

    for idx, ref in ipairs(ref_items) do
        local source_idx = ((idx-1) % count) + 1
        local t = items[source_idx]

        -- Se oltre quelli originali, crea una copia
        if idx > count then
            local new_item = duplicate_item_on_track(t.item)
            t = { item = new_item }
            table.insert(items, t)
        end

        -- Sposta l’inizio dell’item sullo start del target
        reaper.SetMediaItemInfo_Value(t.item, "D_POSITION", ref.start_time)
    end
end

--reaper.Main_OnCommand(reaper.NamedCommandLookup("_FNG_CLEAN_OVERLAP"), 0)
reaper.UpdateArrange()
reaper.Undo_EndBlock("Allinea inizio item all'inizio degli item della traccia più alta (con duplicati se necessari)", -1)
reaper.PreventUIRefresh(-1)
