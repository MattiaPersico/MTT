-- mtt_fmodsync_assets.lua
-- What an asset is, on the REAPER side, and how its files compare with FMOD.
--   asset: a top-level folder track (no parent) that has children.
--   Muted items count for nothing: a folder item over muted items only is no
--   take, and a block is made of unmuted items only (also its time bounds).
--   take:  one file to render. When the folder track has items of its own (the
--          folder items of an nvk render), each of them is a take, numbered by
--          the number at the end of its name ("..._05" = take 5; no number = the
--          next free one) and known by the item's GUID. Otherwise a take is a
--          block of items on its children: items that overlap or are closer than
--          `gap` seconds belong to the same block, numbered 1, 2, 3... in time
--          order and known by "<track GUID>#<number>".
--   file name: the take's name template with its wildcards expanded (M.expand).

local M = {}

-- Name template of a take with no name of its own.
M.DEFAULT_TEMPLATE = '$track_$index'

-- Wildcards known to M.expand, for the UI.
M.WILDCARDS = {
  { '$project', 'the RPP file name, no extension' },
  { '$title', 'Project Settings > Notes > Title' },
  { '$author', 'Project Settings > Notes > Author' },
  { '$track', 'the name of the top-level folder track' },
  { '$item', "the name of the take's folder item (or of its first item)" },
  { '$index', 'the take number, two digits (01, 02..., or 00, 01... with Settings > Numbering); takes marked "Same line" count as one' },
}

-- Merges intervals {s, e, label} (any order) whose distance is <= gap. Returns
-- new intervals in time order, each with the label of its first one. Pure.
function M.merge_blocks(intervals, gap)
  gap = gap or 0
  local sorted = {}
  for i, iv in ipairs(intervals) do sorted[i] = { iv[1], iv[2], label = iv.label } end
  table.sort(sorted, function(a, b) return a[1] < b[1] end)
  local out = {}
  for _, iv in ipairs(sorted) do
    local last = out[#out]
    if last and iv[1] <= last[2] + gap then
      if iv[2] > last[2] then last[2] = iv[2] end
    else
      out[#out + 1] = { iv[1], iv[2], label = iv.label }
    end
  end
  return out
end

-- The folder items {s, e} that overlap at least one of the (unmuted) child
-- items {s, e}. Pure.
function M.with_sound(items, children)
  local out = {}
  for _, it in ipairs(items) do
    for _, c in ipairs(children or {}) do
      if c[1] < it[2] and c[2] > it[1] then out[#out + 1] = it; break end
    end
  end
  return out
end

-- Expands the wildcards of `template` with `vars` (lowercase name -> text).
-- Returns the file name (no extension) and the list of wildcards it does not
-- know, which stay as written. Characters a file name cannot hold become "_";
-- "_" left at either end by an empty wildcard is dropped, and runs of "_"
-- become one. Pure.
function M.expand(template, vars)
  local unknown = {}
  local out = (template or ''):gsub('%$(%a+)', function(w)
    local v = vars[w:lower()]
    if v == nil then unknown[#unknown + 1] = '$' .. w; return nil end
    return tostring(v)
  end)
  out = out:gsub('[/\\:%*%?"<>|%c]', '_'):gsub('__+', '_'):gsub('^[_%s]+', ''):gsub('[_%s]+$', '')
  return out, unknown
end

-- Numbers the folder items {s, e, label, guid}: the number at the end of the
-- label when it is free, else the next free one. Returns blocks in time order
-- with .index. start: the project's first number (1, or 0 with Settings >
-- Numbering): a label number is read in it ("_00" is the first take when it
-- is 0); .index stays 1 for the first take either way. Pure.
function M.number_items(items, start)
  start = start or 1
  local sorted = {}
  for i, it in ipairs(items) do sorted[i] = it end
  table.sort(sorted, function(a, b) return a[1] < b[1] end)
  local used, out, pending = {}, {}, {}
  for _, it in ipairs(sorted) do
    local n = tonumber((it.label or ''):match('_(%d+)%s*$'))
    if n then n = n - start + 1 end
    local b = { it[1], it[2], label = it.label, guid = it.guid }
    if n and n > 0 and not used[n] then b.index = n; used[n] = true else pending[#pending + 1] = b end
    out[#out + 1] = b
  end
  local next_free = 1
  for _, b in ipairs(pending) do
    while used[next_free] do next_free = next_free + 1 end
    b.index = next_free
    used[next_free] = true
  end
  return out
end

-- "a/b/c.wav" -> "a/b", "c" (directory, base name without extension). Pure.
function M.split_asset_path(p)
  local dir, file = p:match('^(.*)/([^/]*)$')
  if not dir then dir, file = '', p end
  return dir, (file:gsub('%.[^.]*$', ''))
end

-- FMOD's asset paths -> {
--   by_dir  = { dir = { base_lower = path } },
--   by_base = { base_lower = { dir, ... } },
--   by_tail = { tail_lower = { {dir, base, path}, ... } }: every file under each
--             "_"-separated tail of its name, to find a take rendered with
--             another prefix. }  Pure.
function M.index_fmod(paths)
  local idx = { by_dir = {}, by_base = {}, by_tail = {} }
  for _, p in ipairs(paths or {}) do
    local dir, base = M.split_asset_path(p)
    local key = base:lower()
    idx.by_dir[dir] = idx.by_dir[dir] or {}
    idx.by_dir[dir][key] = p
    idx.by_base[key] = idx.by_base[key] or {}
    table.insert(idx.by_base[key], dir)
    local pos = 1
    while true do
      local u = key:find('_', pos, true)
      if not u then break end
      local tail = key:sub(u + 1)
      if tail:find('%a') then
        idx.by_tail[tail] = idx.by_tail[tail] or {}
        table.insert(idx.by_tail[tail], { dir = dir, base = base, path = p })
      end
      pos = u + 1
    end
  end
  return idx
end

-- Where a take stands in FMOD. name: its file name, folder: its FMOD folder
-- (nil = none, '' = the Assets root), track_name and index (the number as
-- written in names, 0 or 1 first): to find it under another prefix. Returns one of
--   { kind = 'linked', path }          in its folder
--   { kind = 'found', dir, path }      in one other folder (moved, or not linked yet)
--   { kind = 'ambiguous', places }     in several places: places = { {dir, base}, ... }
--   { kind = 'new' }                   has a folder, not in FMOD yet
--   { kind = 'similar', dir, base, path, prefix, matched }
--        no folder, and one file ends with this name (matched = 'name') or
--        with "<track>_<NN>" ('track'); prefix is what that file has before it
--   { kind = 'none' }                  no folder, nothing found.  Pure.
function M.status(name, folder, track_name, index, idx)
  local key = name:lower()
  if folder ~= nil and idx.by_dir[folder] and idx.by_dir[folder][key] then
    return { kind = 'linked', path = idx.by_dir[folder][key] }
  end
  local dirs = idx.by_base[key]
  if dirs and #dirs == 1 then return { kind = 'found', dir = dirs[1], path = idx.by_dir[dirs[1]][key] } end
  if dirs and #dirs > 1 then
    local places = {}
    for _, d in ipairs(dirs) do places[#places + 1] = { dir = d, base = name } end
    return { kind = 'ambiguous', places = places }
  end
  if folder ~= nil then return { kind = 'new' } end
  local found, seen = {}, {}
  local function add(c, matched, tail_len)
    if seen[c.path] then return end
    seen[c.path] = true
    found[#found + 1] = { dir = c.dir, base = c.base, path = c.path, matched = matched,
      prefix = c.base:sub(1, #c.base - tail_len) }
  end
  for _, c in ipairs(idx.by_tail[key] or {}) do add(c, 'name', #name) end
  local tn = string.format('%s_%02d', track_name or '', index or 0)
  local tkey = tn:lower()
  -- The prefix this take's own name puts before "<track>_<NN>": a file found
  -- by "<track>_<NN>" under another non-empty prefix is another sound for
  -- the same action (Enemies_A_Foley_Walk_01 is not Enemies_B_Foley_Walk_01).
  local own = key:sub(-#tkey) == tkey and key:sub(1, #key - #tkey) or nil
  local function add_track(c)
    local pre = c.base:sub(1, #c.base - #tn):lower()
    if own and own ~= '' and pre ~= '' and pre ~= own then return end
    add(c, 'track', #tn)
  end
  for _, c in ipairs(idx.by_tail[tkey] or {}) do add_track(c) end
  for _, d in ipairs(idx.by_base[tkey] or {}) do
    local p = idx.by_dir[d][tkey]
    local _, b = M.split_asset_path(p)
    add_track({ dir = d, base = b, path = p })
  end
  if #found == 1 then
    found[1].kind = 'similar'
    return found[1]
  end
  if #found > 1 then return { kind = 'ambiguous', places = found } end
  return { kind = 'none' }
end

-- Reads the assets of a project: { { guid, name, track, nchan, blocks,
-- block_source }, ... } in track order, assets with no take left out; each
-- block = { start, end, index, key, label }. gap: seconds between items still
-- counted as one block. start: the first number of $index (see number_items).
function M.scan(proj, gap, start)
  local n = reaper.CountTracks(proj)
  local assets, by_track = {}, {}
  local intervals = {}  -- asset -> list of {s, e, label}
  for i = 0, n - 1 do
    local tr = reaper.GetTrack(proj, i)
    local parent = reaper.GetParentTrack(tr)
    if not parent then
      if reaper.GetMediaTrackInfo_Value(tr, 'I_FOLDERDEPTH') == 1 then
        local _, name = reaper.GetTrackName(tr)
        local a = {
          guid = reaper.GetTrackGUID(tr),
          name = name,
          track = tr,
          nchan = math.floor(reaper.GetMediaTrackInfo_Value(tr, 'I_NCHAN')),
          muted = reaper.GetMediaTrackInfo_Value(tr, 'B_MUTE') == 1,
          blocks = {},
        }
        assets[#assets + 1] = a
        by_track[tr] = a
        intervals[a] = {}
        a.own_items = {}
        for j = 0, reaper.CountTrackMediaItems(tr) - 1 do
          local it = reaper.GetTrackMediaItem(tr, j)
          if reaper.GetMediaItemInfo_Value(it, 'B_MUTE') == 1 then goto next_folder_item end
          local s = reaper.GetMediaItemInfo_Value(it, 'D_POSITION')
          local e = s + reaper.GetMediaItemInfo_Value(it, 'D_LENGTH')
          local take = reaper.GetActiveTake(it)
          local label = take and reaper.GetTakeName(take) or ''
          if label == '' then
            local _, notes = reaper.GetSetMediaItemInfo_String(it, 'P_NOTES', '', false)
            label = (notes or ''):match('^[^\r\n]*') or ''
          end
          local _, iguid = reaper.GetSetMediaItemInfo_String(it, 'GUID', '', false)
          a.own_items[#a.own_items + 1] = { s, e, label = label, guid = iguid }
          ::next_folder_item::
        end
      end
    else
      -- Climb to the top-level ancestor: its asset owns these items.
      local top = parent
      while true do
        local up = reaper.GetParentTrack(top)
        if not up then break end
        top = up
      end
      local a = by_track[top]
      if a then
        for j = 0, reaper.CountTrackMediaItems(tr) - 1 do
          local it = reaper.GetTrackMediaItem(tr, j)
          -- Muted items are not part of any take, nor of its time bounds.
          if reaper.GetMediaItemInfo_Value(it, 'B_MUTE') ~= 1 then
            local s = reaper.GetMediaItemInfo_Value(it, 'D_POSITION')
            local e = s + reaper.GetMediaItemInfo_Value(it, 'D_LENGTH')
            local take = reaper.GetActiveTake(it)
            table.insert(intervals[a], { s, e, label = take and reaper.GetTakeName(take) or '' })
          end
        end
      end
    end
  end
  local out = {}
  for _, a in ipairs(assets) do
    if #a.own_items > 0 then
      -- A folder item over muted items only is no take.
      a.own_items = M.with_sound(a.own_items, intervals[a])
    end
    if #a.own_items > 0 then
      a.blocks, a.block_source = M.number_items(a.own_items, start), 'folder items'
    else
      a.blocks, a.block_source = M.merge_blocks(intervals[a], gap), 'child items'
      for i, b in ipairs(a.blocks) do b.index = i end
    end
    a.own_items = nil
    for _, b in ipairs(a.blocks) do
      b.key = (b.guid and b.guid ~= '') and b.guid or (a.guid .. '#' .. b.index)
    end
    if #a.blocks > 0 then out[#out + 1] = a end
  end
  return out
end

return M
