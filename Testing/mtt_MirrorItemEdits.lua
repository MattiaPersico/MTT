-- mtt_MirrorItemEdits
-- Specifica lo schema degli item selezionati sulla traccia più alta sugli altri item.
-- Per ogni altra traccia viene usato il primo item selezionato, diviso in quante parti
-- sono gli item di riferimento: ogni parte lunga quanto l'item di riferimento
-- corrispondente e posizionata in corrispondenza di quell'item.

-- Risolve l'indice zero-based di una traccia a partire dal suo puntatore (userdata).
-- GetTrack torna nil per un indice fuori range, quindi il ciclo si arresta in fondo.
local function track_index(proj, tr)
  local i = 0
  while true do
    local t = reaper.GetTrack(proj, i)
    if not t then return nil end
    if t == tr then return i end
    i = i + 1
  end
end

local function main()
  local proj = 0

  -- 1. Raccogli gli item selezionati (sinistra -> destra) con l'indice di traccia.
  local selected = {}
  local count = reaper.CountMediaItems(proj)
  for i = 0, count - 1 do
    local item = reaper.GetMediaItem(proj, i)
    if reaper.IsMediaItemSelected(item) then
      local ti = reaper.GetMediaItem_Track(item)
      if ti then
        selected[#selected + 1] = { item = item, track = ti }
      end
    end
  end

  if #selected == 0 then
    reaper.MB('Nessun item selezionato.', 'Mirror item edits', 0)
    return
  end

  -- 2. La traccia di riferimento è la più alta (indice più basso) tra quelle selezionate.
  --    Le tracce sono userdate: si raggruppano per indirizzo e si risolve l'indice.
  local sel_tracks = {}
  for _, s in ipairs(selected) do
    sel_tracks[s.track] = true
  end
  local ref_track
  local ref_idx = math.maxinteger
  for tr in pairs(sel_tracks) do
    local idx = track_index(proj, tr)
    if idx and idx < ref_idx then
      ref_idx = idx
      ref_track = tr
    end
  end

  -- 3. Raccogli i riferimenti (posizioni + lunghezze) e, per ogni altra traccia, il primo
  --    item selezionato.
  local ref_pos, ref_len = {}, {}
  local others = {}
  local seen = {}
  for _, s in ipairs(selected) do
    if s.track == ref_track then
      ref_pos[#ref_pos + 1] = reaper.GetMediaItemInfo_Value(s.item, "D_POSITION")
      ref_len[#ref_len + 1] = reaper.GetMediaItemInfo_Value(s.item, "D_LENGTH")
    elseif not seen[s.track] then
      seen[s.track] = true
      local tp = reaper.GetMediaItem_Track(s.item)
      others[#others + 1] = { item = s.item, tr = tp }
    end
  end

  if #ref_pos == 0 then
    reaper.MB('Nessun item di riferimento sulla traccia più alta.', 'Mirror item edits', 0)
    return
  end
  if #others == 0 then
    reaper.MB('Nessun item sulle tracce più basse da specularle.', 'Mirror item edits', 0)
    return
  end

  reaper.Undo_BeginBlock2(proj)

  for _, o in ipairs(others) do
    local src = o.item
    local src_take = reaper.GetActiveTake(src)
    if src_take then
      local src_source = reaper.GetMediaItemTake_Source(src_take)
      local src_start_offs = reaper.GetMediaItemTakeInfo_Value(src_take, "D_STARTOFFS")
      local src_vol = reaper.GetMediaItemTakeInfo_Value(src_take, "D_VOL")
      local src_pitch = reaper.GetMediaItemTakeInfo_Value(src_take, "D_PITCH")
      local src_playrate = reaper.GetMediaItemTakeInfo_Value(src_take, "D_PLAYRATE")

      -- Si creano le parti PRIMA di cancellare l'item origine: cancellarlo distruggerebbe la
      -- sorgente PCM che stiamo riallocando su ogni nuovo take.
      local cumulative = 0
      for i = 1, #ref_pos do
        local len = ref_len[i]
        local piece = reaper.AddMediaItemToTrack(o.tr)
        local take = reaper.AddTakeToMediaItem(piece)
        reaper.SetMediaItemTake_Source(take, src_source)
        reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", src_start_offs + cumulative)
        reaper.SetMediaItemInfo_Value(piece, "D_POSITION", ref_pos[i])
        reaper.SetMediaItemInfo_Value(piece, "D_LENGTH", len)
        reaper.SetMediaItemTakeInfo_Value(take, "D_VOL", src_vol)
        reaper.SetMediaItemTakeInfo_Value(take, "D_PITCH", src_pitch)
        reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", src_playrate)
        cumulative = cumulative + len
      end

      reaper.DeleteTrackMediaItem(o.tr, src)
    end
  end

  reaper.Undo_EndBlock("Mirror item edits", -1)
end

main()
