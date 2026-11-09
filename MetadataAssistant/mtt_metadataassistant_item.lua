-- mtt_metadataassistant_item.lua
-- The selected item and the facts its source file gives for free: sample
-- rate, channels, length, recording date and any metadata already embedded
-- (recorder iXML, BWF, an earlier Soundminer pass).

local M = {}

-- The single selected item, or nil and the reason to show.
function M.selected()
  local n = reaper.CountSelectedMediaItems(0)
  if n == 0 then return nil, "Select an item (or several, to edit them together)." end
  if n > 1 then return nil, string.format("%d items selected.", n) end
  return reaper.GetSelectedMediaItem(0, 0)
end

function M.guid(item)
  local _, g = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
  return g
end

-- Sections and reversed sources wrap the file source: walk up to the root.
local function root_source(src)
  local parent = reaper.GetMediaSourceParent(src)
  while parent do
    src = parent
    parent = reaper.GetMediaSourceParent(src)
  end
  return src
end

-- Every metadata identifier the file holds -> value. REAPER lists them when
-- asked with an empty identifier, one per line.
local function read_metadata(src)
  local meta = {}
  local ok, list = reaper.GetMediaFileMetadata(src, "")
  if ok == 0 or not list or list == "" then return meta end
  for id in list:gmatch("[^\r\n]+") do
    local got, value = reaper.GetMediaFileMetadata(src, id)
    if got ~= 0 and value and value ~= "" and value ~= "[Binary data]" then meta[id] = value end
  end
  return meta
end

-- Identifiers searched for a recording date, most reliable first; then any
-- other identifier with "date" in its name.
local DATE_IDS = { "BWF:OriginationDate", "INFO:ICRD", "IXML:USER:RECORDINGDATE", "ID3:TDRC",
                   "IXML:USER:RELEASEDATE" }

-- "YYYY-MM-DD" from the first identifier holding a date, or nil. Pure.
function M.date_from_metadata(meta)
  local function date_of(v)
    local y, m, d = tostring(v or ""):match("(%d%d%d%d)[%-%./:](%d%d)[%-%./:](%d%d)")
    if y then return y .. "-" .. m .. "-" .. d end
    return nil
  end
  for _, id in ipairs(DATE_IDS) do
    local d = date_of(meta[id])
    if d then return d end
  end
  local ids = {}
  for id in pairs(meta) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    if id:lower():find("date", 1, true) then
      local d = date_of(meta[id])
      if d then return d end
    end
  end
  return nil
end

-- Identifiers worth showing to the model: descriptive text a recorder or an
-- earlier tagging pass left in the file. Pure.
local USEFUL = { "USER:", "BWF:Description", "INFO:ICMT", "INFO:IKEY", "IXML:NOTE",
                 "TRACK_LIST", "XMP:dc/description" }
local SKIP = { "EMBEDDER", "RATING", "RELEASEDATE", "OPENTIER", "CODING_HISTORY", "VERSION" }
-- Identifiers that hold names, never sent (found anywhere in the identifier, upper
-- case): titles (INFO:INAM, XMP:dc/title, an earlier pass's TRACKTITLE), the recorder's
-- scene, take, tape and project (field recorders name the file after scene and take:
-- "scene CyborgMetal" told the model what the file name says), an earlier pass's
-- FXName and file name. Nothing may be deduced from a name.
local NAME_IDS = { "INAM", "TITLE", "SCENE", "TAKE", "TAPE", "PROJECT", "FXNAME", "FILENAME" }

-- Lower-case words of a text: runs of letters (bytes of accented letters included)
-- and runs of digits, CamelCase split: "DoorSlam_T01" -> door, slam, t, 01. Pure.
local function words(text)
  local s = tostring(text or ""):gsub("(%l)(%u)", "%1 %2"):gsub("(%a)(%d)", "%1 %2"):gsub("(%d)(%a)", "%1 %2")
  local out = {}
  for w in s:lower():gmatch("[%w\128-\255]+") do out[#out + 1] = w end
  return out
end

-- Whether the word list hay holds the words of needle in a row.
local function holds(hay, needle)
  for i = 1, #hay - #needle + 1 do
    local all = true
    for j = 1, #needle do
      if hay[i + j - 1] ~= needle[j] then all = false; break end
    end
    if all then return true end
  end
  return false
end

local function letters(list)
  local n = 0
  for _, w in ipairs(list) do n = n + #w end
  return n
end

-- Whether a value holds one of the names, word for word ("kitchen door slam" holds
-- "Door Slam"), or is a piece of one (the scene "DoorSlam" in "DoorSlam_T01").
-- Names and values shorter than 3 letters are ignored. Pure.
function M.mentions_name(value, names)
  local vw = words(value)
  for _, n in ipairs(names or {}) do
    local nw = words(n)
    if #nw > 0 and letters(nw) >= 3 and holds(vw, nw) then return true end
    if #vw > 0 and letters(vw) >= 3 and holds(nw, vw) then return true end
  end
  return false
end

-- The values of a list that mention none of the names. Pure.
function M.drop_names(list, names)
  local out = {}
  for _, x in ipairs(list or {}) do
    if not M.mentions_name(x, names) then out[#out + 1] = x end
  end
  return out
end

-- The names an item goes by, kept only to keep them away from the model: the take
-- name and the source file's name, without folder and extension ("DoorSlam_T01.wav"),
-- each also without a trailing take number ("DoorSlam"). Pure.
function M.name_variants(take_name, file_path)
  local out, seen = {}, {}
  local function add(n)
    n = n:gsub("^%s+", ""):gsub("%s+$", "")
    if n ~= "" and not seen[n] then seen[n] = true; out[#out + 1] = n end
  end
  local base = tostring(file_path or ""):match("([^/\\]*)$")
  for _, n in ipairs({ tostring(take_name or ""), base }) do
    n = n:gsub("%.%a%w%w?%w?$", "") -- extension (a take name often keeps it); "v1.2" stays
    add(n)
    add((n:gsub("[%s_%-%.]*[Tt]?[Kk]?%d+$", "")))
  end
  return out
end

-- Recorder notes many field recorders (Sound Devices, Zoom, ...) write as
-- "sKEY=value" lines in the BWF description: scene, take, tape, track names
-- (often the microphone), note. nil when the text holds none. Pure.
function M.recorder_notes(desc)
  local t, found = { tracks = {} }, false
  for line in tostring(desc or ""):gmatch("[^\r\n]+") do
    local k, v = line:match("^%s*s([%u%d_]+)=(.-)%s*$")
    if k then
      found = true
      local n = k:match("^TRK(%d+)$")
      if n and v ~= "" then
        t.tracks[#t.tracks + 1] = v
      elseif k == "SCENE" or k == "TAKE" or k == "TAPE" or k == "NOTE" or k == "CIRCLED" then
        t[k:lower()] = v
      end
    end
  end
  if not found then return nil end
  return t
end

-- One line from recorder notes: the track names and the typed note, without what
-- mentions a name; nil when nothing is left. The scene, take and tape are names (the
-- recorder names the file after them): never sent.
local function notes_line(n, names)
  local parts = {}
  local tracks = M.drop_names(n.tracks, names)
  if #tracks > 0 then parts[#parts + 1] = "tracks " .. table.concat(tracks, ", ") end
  if n.note and n.note ~= "" and not M.mentions_name(n.note, names) then parts[#parts + 1] = "note " .. n.note end
  if #parts == 0 then return nil end
  return "recorder: " .. table.concat(parts, ", ")
end

-- The file's metadata as one line for the model, at most max_chars. names: the item's
-- names (M.name_variants); a value that mentions one is left out. Returns the line and
-- the identifiers left out because they are or hold a name (for the diagnostics).
function M.useful_metadata(meta, max_chars, names)
  max_chars = max_chars or 700
  local ids, left_out = {}, {}
  for id in pairs(meta) do
    local up, keep = id:upper(), false
    for _, u in ipairs(USEFUL) do if id:find(u, 1, true) then keep = true end end
    for _, s in ipairs(SKIP) do if up:find(s, 1, true) then keep = false end end
    local is_name = false
    for _, s in ipairs(NAME_IDS) do if up:find(s, 1, true) then is_name = true end end
    if is_name then left_out[#left_out + 1] = id
    elseif keep then ids[#ids + 1] = id end
  end
  table.sort(ids)
  -- Recorder notes are read wherever the recorder put them (some copy them into
  -- INFO:IKEY too); a value already shown is not repeated.
  local parts, used, shown = {}, 0, {}
  for _, id in ipairs(ids) do
    local v = tostring(meta[id])
    local rec = M.recorder_notes(v)
    if rec then
      if rec.scene or rec.take or rec.tape then left_out[#left_out + 1] = id .. " (scene, take)" end
      v = notes_line(rec, names)
    elseif M.mentions_name(v, names) then
      left_out[#left_out + 1] = id
      v = nil
    end
    if v then
      v = v:gsub("%s+", " ")
      if not shown[v] then
        shown[v] = true
        if #v > 160 then v = v:sub(1, 160) .. "..." end
        local part = id .. " = " .. v
        if used + #part > max_chars then break end
        parts[#parts + 1] = part
        used = used + #part + 2
      end
    end
  end
  table.sort(left_out)
  return table.concat(parts, "; "), left_out
end

-- Channels the rendered file gets: the source's, or 1 when the take plays a
-- single channel (take channel mode 2 = downmix, 3 = left, 4 = right).
function M.output_channels(source_channels, chanmode)
  if chanmode == 2 or chanmode == 3 or chanmode == 4 then return 1 end
  return source_channels
end

-- Everything known about the item before any question.
function M.facts(item)
  local f = { meta = {} }
  local take = reaper.GetActiveTake(item)
  f.length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  if not take then
    f.error = "The item has no active take."
    return f
  end
  local src = root_source(reaper.GetMediaItemTake_Source(take))
  -- The names the item goes by: only to keep them away from the model.
  f.names = M.name_variants(reaper.GetTakeName(take), reaper.GetMediaSourceFileName(src))
  f.source_type = reaper.GetMediaSourceType(src)
  if f.source_type == "MIDI" then
    f.error = "MIDI items are not supported."
    return f
  end
  f.samplerate = reaper.GetMediaSourceSampleRate(src)
  f.source_channels = reaper.GetMediaSourceNumChannels(src)
  f.chanmode = math.tointeger(reaper.GetMediaItemTakeInfo_Value(take, "I_CHANMODE")) or 0
  f.channels = M.output_channels(f.source_channels, f.chanmode)
  f.meta = read_metadata(src)
  f.recorded_on = M.date_from_metadata(f.meta)
  return f
end

-- The facts as the model sees them (strings only). The item's name and the
-- source file's name are left out on purpose: they can be anything, and
-- nothing may be deduced from them. So is the file's metadata that is a name or
-- repeats one of them (useful_metadata, f.names).
function M.facts_for_model(f)
  return {
    Channels = f.channels and tostring(f.channels) or nil,
    SampleRate = f.samplerate and (tostring(f.samplerate) .. " Hz") or nil,
    Length = f.length and string.format("%.2f s", f.length) or nil,
    RecordedOn = f.recorded_on,
    RecorderTracks = (function()
      local n = M.recorder_notes((f.meta or {})["BWF:Description"])
      local tracks = n and M.drop_names(n.tracks, f.names) or {}
      return #tracks > 0 and table.concat(tracks, ", ") or nil
    end)(),
    ExistingMetadata = (M.useful_metadata(f.meta or {}, nil, f.names)),
  }
end

return M
