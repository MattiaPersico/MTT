-- mtt_metadataassistant_overview.lua
-- Data behind the Overview window: one row per item of the active project that has
-- a card, in timeline order; each row's status; the order the table shows the rows
-- in (sorted by any column, numbers inside text compared as numbers); file names
-- used by more than one row. The window itself is drawn by mtt_MetadataAssistant.lua.
-- Everything above "REAPER side" is pure.

local M = {}

-- Status of a card by its state, for the Status column. kind picks the colour;
-- rank sorts the column in workflow order (an error first, rendered last).
local STATUS = {
  error      = { label = 'Error',        kind = 'err',  rank = 0 },
  idle       = { label = 'Not analyzed', kind = 'dim',  rank = 1 },
  listening  = { label = 'Listening',    kind = 'busy', rank = 2 },
  drafting   = { label = 'Analyzing',    kind = 'busy', rank = 2 },
  questions  = { label = 'To review',    kind = 'warn', rank = 3 },
  finalizing = { label = 'Finalizing',   kind = 'busy', rank = 4 },
  done       = { label = 'Reviewed',     kind = 'ok',   rank = 5 },
}
local RENDERED = { label = 'Rendered', kind = 'ok', rank = 6 }

-- s: a card session (mtt_metadataassistant_flow). A reviewed card rendered since its last
-- edit (flow.set_value clears s.rendered) shows as Rendered.
function M.status(s)
  if s.state == 'done' and s.rendered then return RENDERED end
  return STATUS[s.state] or STATUS.idle
end

-- Whether a card holds anything worth a row: an item only selected once has an
-- empty card and is left out.
function M.has_content(s)
  return (s.description or ''):match('%S') ~= nil or s.draft ~= nil or s.values ~= nil
    or (s.state ~= nil and s.state ~= 'idle')
end

-- a < b, ignoring case, digit runs compared by value ("Hit 2" < "Hit 10"; at equal
-- value the shorter run first, so "1" < "01"). A strict order: safe for table.sort.
function M.natural_less(a, b)
  a, b = a:lower(), b:lower()
  local ia, ib = 1, 1
  while ia <= #a and ib <= #b do
    local da, db = a:match('^%d+', ia), b:match('^%d+', ib)
    if da and db then
      local na, nb = tonumber(da), tonumber(db)
      if na ~= nb then return na < nb end
      if #da ~= #db then return #da < #db end
      ia, ib = ia + #da, ib + #db
    else
      local ca, cb = a:byte(ia), b:byte(ib)
      if ca ~= cb then return ca < cb end
      ia, ib = ia + 1, ib + 1
    end
  end
  return #a - ia < #b - ib
end

-- Sorts rows in place. specs: { { key = column key, asc = bool }, ... }, the first
-- one leading; value(row, key) -> number or string, read once per row and spec.
-- Empty text goes last in both directions; ties keep the timeline order (row.n).
function M.sort_rows(rows, specs, value)
  for _, r in ipairs(rows) do
    local sv = {}
    for i, sp in ipairs(specs) do sv[i] = value(r, sp.key) end
    r.sort_values = sv
  end
  table.sort(rows, function(a, b)
    for i, sp in ipairs(specs) do
      local va, vb = a.sort_values[i], b.sort_values[i]
      if va ~= vb then
        if type(va) == 'number' and type(vb) == 'number' then
          if sp.asc then return va < vb end
          return va > vb
        end
        va, vb = tostring(va), tostring(vb)
        if va == '' then return false end
        if vb == '' then return true end
        if M.natural_less(va, vb) then return sp.asc end
        if M.natural_less(vb, va) then return not sp.asc end
      end
    end
    return a.n < b.n
  end)
  return rows
end

-- names: { row key -> file name or nil (no metadata) } -> { file name -> rows using it }.
function M.name_counts(names)
  local counts = {}
  for _, name in pairs(names) do
    if name and name ~= '' then counts[name] = (counts[name] or 0) + 1 end
  end
  return counts
end

-- Literal substring search across all columns, independent of their visibility.
-- Filtering preserves the sorted order and original row numbers.
function M.filter_rows(rows, query, columns, value)
  query = query:lower()
  if query == '' then return rows end
  local filtered = {}
  for _, row in ipairs(rows) do
    for _, col in ipairs(columns) do
      if tostring(value(row, col.key)):lower():find(query, 1, true) then
        filtered[#filtered + 1] = row
        break
      end
    end
  end
  return filtered
end

-- Rows in the order of the previous frame when the same items are listed in the
-- same timeline order (sig), so editing a value never moves its row; nil when the
-- list changed and the rows have to be sorted again.
function M.keep_order(old_order, old_sig, by_key, sig)
  if not old_order or old_sig ~= sig then return nil end
  local order = {}
  for _, r in ipairs(old_order) do
    local nr = by_key[r.key]
    if not nr then return nil end
    order[#order + 1] = nr
  end
  return order
end

-- The first line of a description, at most max characters (UTF-8 safe), to name a
-- row that has no file name yet.
function M.short_text(text, max)
  local line = tostring(text or ''):match('^%s*([^\r\n]*)') or ''
  if #line <= max then return line end
  return (line:sub(1, max):gsub('[\xC0-\xFF][\x80-\xBF]*$', '')) .. '...'
end

---------------------------------------------------------------- REAPER side

-- Items of the active project that carry a card tag, in timeline order (position,
-- then track, then project order): { item, n }. store: mtt_metadataassistant_store.
function M.tagged_items(store)
  local list = {}
  for i = 0, reaper.CountMediaItems(0) - 1 do
    local item = reaper.GetMediaItem(0, i)
    local _, tag = reaper.GetSetMediaItemInfo_String(item, store.TAG, '', false)
    if store.parse_tag(tag) then
      local track = reaper.GetMediaItem_Track(item)
      list[#list + 1] = {
        item = item, idx = i,
        pos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION'),
        track = track and reaper.GetMediaTrackInfo_Value(track, 'IP_TRACKNUMBER') or 0,
      }
    end
  end
  table.sort(list, function(a, b)
    if a.pos ~= b.pos then return a.pos < b.pos end
    if a.track ~= b.track then return a.track < b.track end
    return a.idx < b.idx
  end)
  for n, e in ipairs(list) do e.n = n end
  return list
end

return M
