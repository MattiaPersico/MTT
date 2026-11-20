
--   Dispone gli item selezionati su ciascuna traccia in gruppi non crossfadeati.
--   Gli item connessi tramite crossfade sono trattati come blocchi unici.
--   La distanza è aggiunta dopo la fine del gruppo.

local major_version = 1
local minor_version = 2

local spacing = 0.5 -- seconds

local function sort_items_by_position(items)
  table.sort(items, function(a, b)
    return a.pos < b.pos
  end)
end

-- Raggruppa item crossfadeati
local function group_crossfaded_items(items)
  local groups = {}
  local current_group

  for _, item in ipairs(items) do
    -- Gli item adiacenti restano separati; gli overlap annidati no.
    if not current_group or item.pos >= current_group.finish then
      current_group = { start = item.pos, finish = item.finish }
      table.insert(groups, current_group)
    end
    current_group.finish = math.max(current_group.finish, item.finish)
    table.insert(current_group, item)
  end

  return groups
end

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
  local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  table.insert(track_items[track], { handle = item, pos = pos, finish = pos + len })
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

-- Per ogni traccia, ordina gli item, raggruppa gli overlap e sposta
for _, items in pairs(track_items) do
  sort_items_by_position(items)
  local groups = group_crossfaded_items(items)

  -- Posizione iniziale = posizione primo gruppo
  local pos = groups[1].start

  for _, group in ipairs(groups) do
    -- Sposta tutti gli item nel gruppo mantenendo offset interno
    local offset = pos - group.start
    for _, item in ipairs(group) do
      reaper.SetMediaItemPosition(item.handle, item.pos + offset, false)
    end

    pos = pos + (group.finish - group.start) + spacing
  end
end

reaper.UpdateArrange()
reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("Distribuisci item selezionati evitando overlap e preservando crossfade", -1)