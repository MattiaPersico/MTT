
--   Dispone gli item selezionati su ciascuna traccia in gruppi non crossfadeati.
--   Gli item connessi tramite crossfade sono trattati come blocchi unici.
--   La distanza è aggiunta dopo la fine del gruppo.

local major_version = 1
local minor_version = 1

local spacing = 0.5 -- seconds

local function sort_items_by_position(items)
  table.sort(items, function(a, b)
    return reaper.GetMediaItemInfo_Value(a, "D_POSITION") < reaper.GetMediaItemInfo_Value(b, "D_POSITION")
  end)
end

-- Raggruppa item crossfadeati
local function group_crossfaded_items(items)
  local groups = {}
  local current_group = {}

  for i, item in ipairs(items) do
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local item_end = pos + len

    if #current_group == 0 then
      table.insert(current_group, item)
    else
      local last = current_group[#current_group]
      local last_pos = reaper.GetMediaItemInfo_Value(last, "D_POSITION")
      local last_len = reaper.GetMediaItemInfo_Value(last, "D_LENGTH")
      local last_end = last_pos + last_len

      -- Se questo item inizia prima che il precedente finisca, è crossfadeato
      if pos < last_end then
        table.insert(current_group, item)
      else
        table.insert(groups, current_group)
        current_group = { item }
      end
    end
  end

  if #current_group > 0 then
    table.insert(groups, current_group)
  end

  return groups
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local selected_items_count = reaper.CountSelectedMediaItems(0)
if selected_items_count == 0 then
  reaper.ShowMessageBox("Nessun item selezionato.", "Errore", 0)
  return
end

-- Mappa traccia -> lista di item selezionati
local track_items = {}

for i = 0, selected_items_count - 1 do
  local item = reaper.GetSelectedMediaItem(0, i)
  local track = reaper.GetMediaItem_Track(item)
  if not track_items[track] then
    track_items[track] = {}
  end
  table.insert(track_items[track], item)
end

-- Per ogni traccia, ordina gli item, raggruppa crossfade e sposta
for track, items in pairs(track_items) do
  sort_items_by_position(items)
  local groups = group_crossfaded_items(items)

  -- Posizione iniziale = posizione primo gruppo
  local pos = reaper.GetMediaItemInfo_Value(groups[1][1], "D_POSITION")

  for _, group in ipairs(groups) do
    -- Trova inizio e fine del gruppo
    local group_start = math.huge
    local group_end = -math.huge

    for _, item in ipairs(group) do
      local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
      group_start = math.min(group_start, item_pos)
      group_end = math.max(group_end, item_pos + item_len)
    end

    -- Sposta tutti gli item nel gruppo mantenendo offset interno
    local offset = pos - group_start
    for _, item in ipairs(group) do
      local old_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      reaper.SetMediaItemPosition(item, old_pos + offset, false)
    end

    -- Calcola nuova posizione per il prossimo gruppo
    pos = pos + (group_end - group_start) + spacing
  end
end

reaper.UpdateArrange()
reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("Distribuisci item selezionati evitando overlap e preservando crossfade", -1)