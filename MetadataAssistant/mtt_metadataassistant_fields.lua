-- mtt_metadataassistant_fields.lua
-- The metadata written into every rendered file: which fields, where each value
-- comes from, what the model must find out per kind of sound, and the writing
-- rules. Field names are Soundminer's (iXML <USER> block, upper case, as
-- Soundminer itself writes them; the same names as the columns of a Soundminer
-- export). Conventions follow the BOOM Library and Tonsturm reference sheets and
-- BOOM's Soundminer exports: filename CatID_VendorCategory-FXName_CreatorID_SourceID,
-- BOOM-style Description (upper-case tags, then short sentences on action,
-- character, structure, space, notable events), Description mirrored to the BWF
-- description, copyright in the BWF originator, website in the originator
-- reference, TrackYear as the year.
-- Pure Lua, no reaper.* calls.

local M = {}

-- Where a value comes from:
--   ucs     = derived from the chosen UCS entry (never typed, never guessed)
--   ai      = written by the LLM from the description and the answers
--   session = settings, asked once and remembered between runs
--   file    = read from the item's source file
--   auto    = filled by the script
--   manual  = typed by the user in the result
--   item    = chosen per item in the result (Artwork: an image file, not a tag)
-- ixml: field inside the iXML <USER> block ("IXML:USER:<ixml>" in REAPER's
-- render metadata). bwf: also written to that BWF (bext) field, cut to
-- bwf_max bytes. Neither = filename only.
M.FIELDS = {
  { key = "CatID",          ixml = "CATID",          source = "ucs",     required = true },
  { key = "Category",       ixml = "CATEGORY",       source = "ucs",     required = true },
  { key = "SubCategory",    ixml = "SUBCATEGORY",    source = "ucs",     required = true },
  { key = "CategoryFull",   ixml = "CATEGORYFULL",   source = "ucs",     required = true },
  { key = "UserCategory",   ixml = "USERCATEGORY",   source = "ai" },
  { key = "VendorCategory", ixml = "VENDORCATEGORY", source = "ai" },
  { key = "FXName",         ixml = "FXNAME",         source = "ai",      required = true },
  { key = "TrackTitle",     ixml = "TRACKTITLE",     source = "ai",      required = true },
  { key = "Description",    ixml = "DESCRIPTION",    source = "ai",      required = true, long = true,
    bwf = "Description", bwf_max = 256 },
  { key = "Keywords",       ixml = "KEYWORDS",       source = "ai",      required = true, long = true },
  { key = "MicPerspective", ixml = "MICPERSPECTIVE", source = "ai" },
  { key = "Location",       ixml = "LOCATION",       source = "ai" },
  { key = "RecType",        ixml = "RECTYPE",        source = "ai" },
  { key = "Microphone",     ixml = "MICROPHONE",     source = "ai" },      -- model + technique; per item (description or typed)
  { key = "ChannelLayout",  ixml = "CHANNELLAYOUT",  source = "manual" },  -- multichannel only, e.g. L/R/C/Ls/Rs
  { key = "RecMedium",      ixml = "RECMEDIUM",      source = "file" },
  { key = "Designer",       ixml = "DESIGNER",       source = "session", required = true },
  { key = "Recordist",      ixml = "RECORDIST",      source = "session" },  -- mirrors Designer
  { key = "Artist",         ixml = "ARTIST",         source = "session" },  -- mirrors Designer, shown by macOS Finder
  { key = "Manufacturer",   ixml = "MANUFACTURER",   source = "session", required = true },
  { key = "Library",        ixml = "LIBRARY",        source = "session", required = true },
  { key = "ShortID",        ixml = "SHORTID",        source = "session", required = true },  -- = CreatorID in the filename
  { key = "SourceID",                                source = "session", required = true },  -- filename only
  { key = "Show",           ixml = "SHOW",           source = "session" },
  { key = "URL",            ixml = "URL",            source = "session", bwf = "OriginatorReference", bwf_max = 32 },
  { key = "Copyright",                               source = "session", bwf = "Originator", bwf_max = 32 },
  { key = "TrackYear",      ixml = "TRACKYEAR",      source = "auto" },  -- recording year
  { key = "ShootDate",      ixml = "SHOOTDATE",      source = "file" },  -- recording date, when the file has one
  { key = "Notes",          ixml = "NOTES",          source = "auto" },
  -- Not a tag: the image Render embeds as the front cover (render.artwork_metadata).
  -- curator = false: the Overview curator never proposes it.
  { key = "Artwork",                                 source = "item", curator = false },
}

-- What each field is for (tooltip on its label).
M.TIPS = {
  CatID = "UCS category ID, the first block of the filename (e.g. DOORWood). Typing a valid one fills Category, SubCategory and CategoryFull.",
  Category = "UCS category name, derived from the CatID.",
  SubCategory = "UCS subcategory name, derived from the CatID.",
  CategoryFull = "Category-SubCategory as Soundminer shows it, derived from the CatID.",
  UserCategory = "Optional extra tag appended to the CatID in the filename after a dash (CatID-UserCategory). Letters and digits only. With Library > Vendor/UserCategory off the model leaves it empty.",
  VendorCategory = "Library-specific grouping placed before the FXName in the filename (e.g. DRY/ROOM version, or the object family). The model's value loses the words the CatID or the FXName already say. With Library > Vendor/UserCategory off the model leaves it empty and the object goes in the FXName.",
  FXName = "Short title of the sound: object, number, action, manner, in Title Case. Second block of the filename; aim for 25 characters or less.",
  TrackTitle = "Longer human title of the sound, shown in Soundminer's title column.",
  Description = "What the sound is and how it behaves: upper-case tags, then short sentences on action, character, structure and space. Also written to the BWF description (256 bytes).",
  Keywords = "Search words, comma separated. Built from the UCS synonyms of the CatID and the description.",
  MicPerspective = "Microphone distance and space, e.g. CU | INT. Distance: CU, MED, DST, VARI. Space: INT, EXT. Special: D/I, CONTACT, HYDRO, OB, EMF.",
  Location = "Where it was recorded: place, region or country.",
  RecType = "Recording technique or stereo format, e.g. XY, MS, ORTF, mono.",
  Microphone = "Microphone model and technique used for this item.",
  ChannelLayout = "Channel order for multichannel files, e.g. L/R/C/Ls/Rs.",
  RecMedium = "Recorder or medium used for this item's recording.",
  Designer = "Person who designed or edited the sound. Set in Library.",
  Recordist = "Person who recorded the sound; mirrors Designer. Set in Library.",
  Artist = "Artist tag shown by macOS Finder; mirrors Designer. Set in Library.",
  Manufacturer = "Company or label that publishes the library. Set in Library.",
  Library = "Name of the sound library. Set in Library (saved in the project).",
  ShortID = "CreatorID: short code for the creator, third block of the filename. Set in Library.",
  SourceID = "Short code for the project or recording source, fourth block of the filename. Set in Library (saved in the project).",
  Show = "Production or show the sound was made for. Set in Library (saved in the project).",
  URL = "Website; also written to the BWF originator reference (32 bytes). Set in Library.",
  Copyright = "Copyright notice; written to the BWF originator (32 bytes). Set in Library.",
  TrackYear = "Year of the recording (the file's date, or today when the file has none).",
  ShootDate = "Recording date, when the source file carries one.",
  Notes = "Free notes. The UCS version used is added automatically.",
  Artwork = "JPEG or PNG embedded as the front cover of this item's rendered file (the WAV's ID3 chunk). Empty: no cover. Browse... picks the file; with several items selected it goes to all of them.",
}

-- Library identity from the settings (always applied).
M.SESSION_KEYS = { "Designer", "Recordist", "Artist", "Manufacturer", "Library", "ShortID", "SourceID",
                   "Show", "URL", "Copyright" }

-- Fields the LLM may fill. Anything else in its answer is ignored.
M.AI_KEYS = { "VendorCategory", "FXName", "TrackTitle", "Description", "Keywords",
              "MicPerspective", "Location", "RecType", "Microphone", "UserCategory" }

-- Mic Perspective vocabulary: distance | space, e.g. "CU | INT"; the special
-- terms stand alone.
M.MIC_DISTANCE = { "CU", "MED", "DST", "VARI" }
M.MIC_SPACE = { "INT", "EXT" }
M.MIC_SPECIAL = { "D/I", "CONTACT", "HYDRO", "OB", "EMF" }

-- Kinds of sound. checklist: what a reference library always states for this
-- kind, most important first. The model reports which items the description
-- leaves open and asks about those, in this order.
M.SOUND_TYPES = {
  single = {
    label = "Single source: prop, Foley, impact, destruction, door, mechanism",
    checklist = {
      { "object", "source object and its variant (beer mug, double-glazed pane, kitchen door)" },
      { "action", "what happens (open, slam, drop and break, scrape)" },
      { "material", "materials involved" },
      { "size", "size of the source (small, medium, large, or dimensions)" },
      { "cause", "what caused it: tool or method (hammer hit, thrown, kicked, dropped)" },
      { "surface", "what it hits or lands on (concrete, wooden floor, grass)" },
      { "manner", "intensity or speed (soft, hard, fast, slow)" },
      { "structure", "event structure (single, multiple, followed by, debris tail)" },
      { "character", "sound character (snappy, dull, crispy, resonant, rattling, squeaky)" },
      { "space", "dry or in a room; which room or place; how reverberant" },
      { "perspective", "microphone distance (close, medium, distant)" },
      { "origin", "plain recording or designed/layered" },
    },
  },
  ambience = {
    label = "Ambience, room tone, background",
    checklist = {
      { "place", "kind of place (city street, forest, kitchen, hall)" },
      { "time", "time of day and season" },
      { "elements", "main sound elements, most prominent first" },
      { "density", "density or activity (sparse, busy, dense)" },
      { "events", "notable one-off events and when they happen (mm:ss)" },
      { "loop", "whether it loops seamlessly" },
      { "weather", "weather (wind, rain, calm)" },
      { "perspective", "microphone distance, placement and facing (e.g. facing the entrance)" },
    },
  },
  vehicle = {
    label = "Vehicle: pass-by, onboard, start, idle, specifics",
    checklist = {
      { "vehicle", "make, model, year, engine or fuel, or vehicle type" },
      { "action", "pass-by, onboard drive, start, idle, stop, door, horn" },
      { "speed", "speed or rpm, acceleration" },
      { "perspective", "onboard (engine, interior, exhaust) or exterior, and distance" },
      { "surface", "road surface (asphalt, gravel, wet)" },
      { "space", "environment (street, tunnel, countryside)" },
    },
  },
  designed = {
    label = "Designed or synthetic: whoosh, hit, UI, sci-fi, drone",
    checklist = {
      { "style", "synthesized or processed recording; technique and source material" },
      { "character", "sound character (dark, bright, metallic, distorted, airy)" },
      { "structure", "length, attack, sustain, tail" },
      { "use", "intended use (trailer hit, UI confirm, transition)" },
      { "pitch", "pitch or tonality, rising or falling" },
    },
  },
  vocal = {
    label = "Voice, creature, animal or bird",
    checklist = {
      { "source", "creature, animal, bird or voice: type, size, age, gender" },
      { "vocalization", "kind of sound (roar, growl, bark, chirp, line, breath)" },
      { "emotion", "emotion or intent (angry, calm, pain, attack)" },
      { "structure", "single call, sequence, short or long takes" },
      { "space", "dry, room or outdoor place" },
      { "perspective", "microphone distance" },
      { "origin", "real recording or designed/processed" },
    },
  },
}
M.SOUND_TYPE_ORDER = { "single", "ambience", "vehicle", "designed", "vocal" }

-- Checklist topics the model must never ask the user about. Location is not
-- something the user should have to think about; the microphone comes from the
-- description or is typed per item, and is otherwise left empty. The fields stay filled when the description or the file facts state them.
M.NEVER_ASKED = { "microphone", "location" }

-- Rules shared by both passes (from the reference sheets and the A Sound Effect
-- metadata style guide), in three parts: general, the file name, each field.
local RULES_HEAD = {
  "All metadata in English, whatever language the description is in.",
  "Never invent a fact the user did not give or the file does not show: leave the field empty.",
}

-- The file name rules, by the "VendorCategory / UserCategory" setting. On (the default):
-- UCS's optional VendorCategory-FXName form, the object before the dash and the action
-- after it, as UCS's own "UZI 9mm-Rapid Fire". Off: the model leaves VendorCategory and
-- UserCategory empty, the object goes in the FXName and the name has no dash.
M.NAME_RULES = {
  blocks = {
    "VendorCategory: optional, 1-2 Title Case words for the object family or version (e.g. 'Mug Beer', 'Pane Double', 'Room', 'Dry'). Leave it empty rather than repeat the CatID or the FXName.",
    "FXName: Title Case words separated by spaces, 2 to 6 words: object, action, manner (e.g. 'Pane Break Hammer Hit'). When VendorCategory already names the object, FXName starts from the action ('Mug Beer' + 'Drop And Break'). No punctuation, no take numbers.",
    "The file name reads CatID_VendorCategory-FXName as one line: each word appears in it once, and the object the CatID names is not named again (VEHDoor = VEHICLES / DOOR: no 'Door', no 'Vehicle'). A SubCategory that is the action may stay as the action (GLASBrk with 'Drop And Break'). Write 'VEHDoor_Handle-Pull Release', not 'VEHDoor_Door Handle-Car Handle Pull Release'.",
  },
  plain = {
    "VendorCategory and UserCategory: always empty strings; the user fills them by hand when wanted.",
    "FXName: Title Case words separated by spaces, 2 to 6 words: object, action, manner (e.g. 'Pane Break Hammer Hit'). No punctuation, no dashes, no take numbers.",
    "The file name reads CatID_FXName as one line: each word appears in it once, and the object the CatID names is not named again (VEHDoor = VEHICLES / DOOR: no 'Door', no 'Vehicle'). A SubCategory that is the action may stay as the action (GLASBrk with 'Drop And Break'). Write 'VEHDoor_Handle Pull Release', not 'VEHDoor_Door Handle Car Handle Pull Release'.",
  },
}

local RULES_TAIL = {
  "TrackTitle: 1 to 5 words naming the source and the action.",
  "Description: 2 to 4 UPPER CASE tags (kind, material, size, e.g. 'GLASS BREAK MEDIUM'), then short sentences: source and action first, then character and structure ('followed by', 'ending with'), then space ('Dry.' or 'Reverberant.'). Recording position words are fine ('External, from the side', 'Onboard', 'Facing the entrance'); microphone brand and model names are not. Notable events with their time when the user gives it ('Car pass by at (01:49).'). 'Loop.' when it loops seamlessly. A usage hint when useful ('Use in series with 2-3 s gaps.'). No take numbers.",
  "Keywords: 8 to 15 comma-separated search terms not already in the Description: synonyms (prefer the UCS synonyms given), related materials, uses (e.g. burglary, accident). No generic words (sound, Foley, prop, single, studio, close up).",
  "Location: only the place, broad to specific (country, region, place), and only when the description or the file facts state it; otherwise empty. Never 'Studio' or 'Field'. Never ask about it.",
  "RecType: medium, space, technique, comma-separated (e.g. 'Digital, Studio, Mono'; techniques: Mono, Stereo, MS, XY, ORTF, AB, Ambisonic).",
  "MicPerspective: CU, MED, DST or VARI, then | INT or | EXT (e.g. 'CU | INT').",
  "Microphone: brand, model and technique, when the user's description names a microphone (e.g. 'Schoeps CCM 41 ORTF', 'DPA 4007 AB') or a recorder track name in the file facts is a microphone model (a track called 'QTC50' means the Earthworks QTC50); otherwise leave it empty: the user fills it per item. Never ask about the microphone or the location.",
}

-- The writing rules for the "VendorCategory / UserCategory" setting (nil = on).
function M.writing_rules(name_blocks)
  local out = {}
  for _, list in ipairs({ RULES_HEAD, name_blocks == false and M.NAME_RULES.plain or M.NAME_RULES.blocks, RULES_TAIL }) do
    for _, r in ipairs(list) do out[#out + 1] = r end
  end
  return out
end

-- Two examples in the reference style (written for this script, not copied); %s = the
-- name fields, which follow the "VendorCategory / UserCategory" setting.
local EXAMPLE_GLASS = [[{"sound_type":"single","catid":"GLASBrk","fields":{%s,"TrackTitle":"Glass Pane Break","Description":"GLASS BREAK MEDIUM Hammer hit breaking a single glass pane. Sharp crack followed by crispy shards scattering on concrete. Short debris tail. Dry.","Keywords":"shatter, smash, shards, splinters, window, burglary, vandalism, destruction","MicPerspective":"CU | INT","RecType":"Digital, Studio, Mono"}}]]
local EXAMPLE_AMBIENCE = [[{"sound_type":"ambience","catid":"AMBRurl","fields":{%s,"TrackTitle":"Farmyard Night","Description":"AMBIENCE RURAL NIGHT Quiet farmyard at night. Dense crickets, distant dog barks and light wind in trees. Occasional far traffic, dog barking at (01:12). Loop.","Keywords":"countryside, farm, evening, insects, calm, peaceful, village","MicPerspective":"MED | EXT","Location":"Italy, Tuscany, Siena","RecType":"Digital, Field, ORTF","Microphone":"Schoeps CCM 41 ORTF"}}]]

function M.examples(name_blocks)
  local blocks = name_blocks ~= false
  return {
    EXAMPLE_GLASS:format(blocks and '"VendorCategory":"Pane Single","FXName":"Break Hammer Hit"' or '"FXName":"Pane Break Hammer Hit"'),
    EXAMPLE_AMBIENCE:format(blocks and '"VendorCategory":"","FXName":"Farmyard Night Crickets"' or '"FXName":"Farmyard Night Crickets"'),
  }
end

-- Fields the model is asked for: without VendorCategory and UserCategory when the
-- setting is off.
function M.ai_keys(name_blocks)
  if name_blocks ~= false then return M.AI_KEYS end
  local out = {}
  for _, k in ipairs(M.AI_KEYS) do
    if k ~= "VendorCategory" and k ~= "UserCategory" then out[#out + 1] = k end
  end
  return out
end

local function in_list(list, v)
  for _, x in ipairs(list) do if x == v then return true end end
  return false
end

-- Returns the field definition for a key, or nil.
function M.get(key)
  for _, f in ipairs(M.FIELDS) do
    if f.key == key then return f end
  end
  return nil
end

function M.is_ai_key(key) return in_list(M.AI_KEYS, key) end

-- Checklist item keys for a sound type, in priority order.
function M.checklist_keys(sound_type)
  local t = M.SOUND_TYPES[sound_type]
  local out = {}
  for _, item in ipairs(t and t.checklist or {}) do out[#out + 1] = item[1] end
  return out
end

-- "CU | INT", "cu, int", "MED/EXT", "DST INT", "D/I" -> normalized "CU | INT"
-- or "D/I"; nil when outside the vocabulary.
function M.normalize_mic_perspective(value)
  local v = tostring(value or ""):upper():gsub("^%s+", ""):gsub("%s+$", "")
  if in_list(M.MIC_SPECIAL, (v:gsub("%s+", ""))) then return (v:gsub("%s+", "")) end
  local dist, space = v:match("^(%a+)%s*[|,/;%s]%s*(%a+)$")
  if dist and in_list(M.MIC_DISTANCE, dist) and in_list(M.MIC_SPACE, space) then
    return dist .. " | " .. space
  end
  if in_list(M.MIC_DISTANCE, v) then return v end
  return nil
end

-- Fills the "ucs" fields from a UCS entry.
function M.apply_ucs(values, entry)
  values.CatID = entry.id
  values.Category = entry.cat
  values.SubCategory = entry.sub
  values.CategoryFull = entry.cat .. "-" .. entry.sub
  return values
end

-- Fills the "auto" fields only where still empty. recorded_on: "YYYY-MM-DD"
-- from the file, or nil; today: "YYYY-MM-DD". TrackYear is the recording year
-- (today's when the file has no date), ShootDate the recording date if known.
function M.apply_auto(values, recorded_on, today, ucs_version)
  local date = recorded_on or today
  if (values.TrackYear == nil or values.TrackYear == "") and date then
    values.TrackYear = date:sub(1, 4)
  end
  if (values.ShootDate == nil or values.ShootDate == "") and recorded_on then
    values.ShootDate = recorded_on
  end
  if values.Notes == nil or values.Notes == "" then
    values.Notes = "UCS " .. tostring(ucs_version)
  end
  return values
end

-- Session values fill only what is still empty; Artist mirrors Designer.
function M.apply_session(values, session)
  for _, k in ipairs(M.SESSION_KEYS) do
    if (values[k] == nil or values[k] == "") and session[k] and session[k] ~= "" then
      values[k] = session[k]
    end
  end
  for _, k in ipairs({ "Recordist", "Artist" }) do
    if (values[k] == nil or values[k] == "") and values.Designer then values[k] = values.Designer end
  end
  return values
end

-- Required fields still empty, in schema order.
function M.missing_required(values)
  local out = {}
  for _, f in ipairs(M.FIELDS) do
    if f.required and (values[f.key] == nil or values[f.key] == "") then out[#out + 1] = f.key end
  end
  return out
end

-- Cuts a string to max bytes without leaving half a UTF-8 character at the end.
function M.cut_bytes(s, max)
  s = tostring(s)
  if #s <= max then return s end
  return (s:sub(1, max):gsub("[\xC0-\xFF][\x80-\xBF]*$", ""))
end

-- {identifier, value} pairs for REAPER's render metadata, schema order, empty
-- values skipped: the iXML fields first, then the BWF (bext) mirrors, which
-- tools without iXML support read, cut to their bext sizes.
function M.to_render_metadata(values)
  local out, bwf = {}, {}
  for _, f in ipairs(M.FIELDS) do
    local v = values[f.key]
    if v ~= nil and v ~= "" then
      if f.ixml then out[#out + 1] = { "IXML:USER:" .. f.ixml, tostring(v) } end
      if f.bwf then bwf[#bwf + 1] = { "BWF:" .. f.bwf, M.cut_bytes(v, f.bwf_max) } end
    end
  end
  for _, pair in ipairs(bwf) do out[#out + 1] = pair end
  return out
end

-- The first `limit` UCS synonyms of an entry (English), as keyword material.
function M.ucs_synonyms(entry, limit)
  local out = {}
  for s in tostring(entry and entry.syn or ""):gmatch("[^,]+") do
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    if s ~= "" then out[#out + 1] = s end
    if #out >= (limit or 40) then break end
  end
  return out
end

return M
