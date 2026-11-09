-- mtt_metadataassistant_filename.lua
-- UCS filename: CatID[-UserCategory]_[VendorCategory-]FXName_CreatorID_SourceID[_UserData]
-- (VendorCategory as BOOM Library and Tonsturm use it: "DOORAppl_DRY-Appliance
-- Microwave 01 Close Hard_B00M_MBDO", "GLASBrk_Mug Beer-Drop And Break_TSTRM_BrkGlss").
-- Underscores separate the blocks, so no block may contain one; the extension is
-- added by the render, not here.
-- Pure Lua, no reaper.* calls.

local M = {}

-- Soft limit: UCS asks for a short FXName; past this the validator warns, it
-- does not refuse.
M.FXNAME_SOFT_MAX = 25
-- Hard limit of the whole name (macOS/Windows filesystems: 255 bytes), leaving
-- room for ".wav".
M.NAME_MAX = 250

-- Characters illegal in a filename on macOS or Windows, plus the UCS separator.
local ILLEGAL = '[\0-\31/\\:%*%?"<>|_]'

-- One block: illegal characters removed, whitespace collapsed and trimmed.
-- keep_punct = false also removes commas, periods and dashes (FXName rule).
function M.clean_block(s, keep_punct)
  s = tostring(s or ""):gsub(ILLEGAL, " ")
  if not keep_punct then s = s:gsub("[,%.;%-]", " ") end
  s = s:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
  return s
end

-- A whole name typed by hand: control characters and the characters a macOS or
-- Windows filesystem refuses removed (underscores stay: they are the block
-- separator), ".wav" dropped, whitespace trimmed. Pure.
function M.clean_name(s)
  s = tostring(s or ""):gsub('[\0-\31/\\:%*%?"<>|]', " ")
  s = s:gsub("%.[Ww][Aa][Vv]%s*$", "")
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  return s
end

-- Problems of a hand-typed name: empty, too long, not UCS-shaped. Pure.
function M.check_name(name)
  local problems = {}
  if name == "" then
    problems[#problems + 1] = "the file name is empty"
    return problems
  end
  if #name > M.NAME_MAX then
    problems[#problems + 1] = string.format("name is %d bytes (max %d)", #name, M.NAME_MAX)
  end
  if not M.parse(name) then
    problems[#problems + 1] = "the name does not follow CatID_FXName_CreatorID_SourceID"
  end
  return problems
end

-- A name with the take number in its FXName block: "A_B-FX_C_D" -> "A_B-FX 02_C_D".
-- A name without four blocks gets the number at the end. Width: 2 digits, more
-- when count is 100 or more. Pure.
function M.number_name(name, index, count)
  local width = count >= 100 and #tostring(count) or 2
  local num = string.format("%0" .. width .. "d", index)
  local blocks = {}
  for b in (name .. "_"):gmatch("([^_]*)_") do blocks[#blocks + 1] = b end
  if #blocks >= 4 then
    blocks[2] = blocks[2] .. " " .. num
    return table.concat(blocks, "_")
  end
  return name .. " " .. num
end

-- IDs (CreatorID, SourceID, UserCategory): letters and digits only.
function M.clean_id(s)
  return (tostring(s or ""):gsub("[^%w]", ""))
end

-- Word key for the repeat check: lower case, letters and digits only, a final
-- "s" dropped so that "Doors" and "Door" are the same word.
local function word_key(w)
  w = w:lower():gsub("[^%w]", "")
  if #w > 3 then w = w:gsub("s$", "") end
  return w
end

-- The model's VendorCategory without what the rest of the name already says: the
-- words of the CatID's Category and SubCategory ("Door" under VEHDoor = VEHICLES /
-- DOOR), the words the FXName repeats, and a word given twice. The FXName stays
-- as it is: it stands alone in Soundminer's FXName column. An empty result
-- drops the VendorCategory from the name.
-- "Door Handle" + FXName "Car Handle Pull Release" under VEHDoor -> "". Pure.
function M.trim_vendor(vendor, fxname, category, subcategory)
  local said = {}
  local rest = tostring(category or "") .. " " .. tostring(subcategory or "") .. " " .. tostring(fxname or "")
  for w in rest:gmatch("%S+") do said[word_key(w)] = true end
  local kept = {}
  for w in M.clean_block(vendor, false):gmatch("%S+") do
    local k = word_key(w)
    if k ~= "" and not said[k] then
      kept[#kept + 1] = w
      said[k] = true
    end
  end
  return table.concat(kept, " ")
end

-- Builds the name from:
--   catid, fxname, creator_id, source_id (required),
--   user_category, vendor_category, user_data (optional)
-- Returns name, problems (list of strings; empty = valid). A name is returned
-- even with problems, so the preview can show it.
function M.build(p)
  local problems = {}
  local catid = M.clean_id(p.catid)
  local fx = M.clean_block(p.fxname, false)
  local creator = M.clean_id(p.creator_id)
  local source = M.clean_id(p.source_id)
  local ucat = M.clean_id(p.user_category)
  local udata = M.clean_block(p.user_data, true)
  local vendor = M.clean_block(p.vendor_category, false)

  if catid == "" then problems[#problems + 1] = "CatID is empty" end
  if fx == "" then problems[#problems + 1] = "FXName is empty" end
  if creator == "" then problems[#problems + 1] = "CreatorID is empty" end
  if source == "" then problems[#problems + 1] = "SourceID is empty" end
  if #fx > M.FXNAME_SOFT_MAX then
    problems[#problems + 1] = string.format("FXName is %d characters (aim for %d or less)", #fx, M.FXNAME_SOFT_MAX)
  end

  local first = catid
  if ucat ~= "" then first = first .. "-" .. ucat end
  local second = fx
  if vendor ~= "" then second = vendor .. "-" .. fx end
  local parts = { first, second, creator, source }
  if udata ~= "" then parts[#parts + 1] = udata end
  local name = table.concat(parts, "_")

  if #name > M.NAME_MAX then
    problems[#problems + 1] = string.format("name is %d bytes (max %d)", #name, M.NAME_MAX)
  end
  return name, problems
end

-- Splits a UCS name (extension optional) into its blocks; nil when it has fewer
-- than 4 blocks.
function M.parse(name)
  local base = tostring(name or ""):gsub("%.[%w]+$", "")
  local blocks = {}
  for b in (base .. "_"):gmatch("([^_]*)_") do blocks[#blocks + 1] = b end
  if #blocks < 4 then return nil end
  local catid, ucat = blocks[1]:match("^([^%-]+)%-(.+)$")
  local vendor, fx = blocks[2]:match("^([^%-]+)%-(.+)$")
  return {
    catid = catid or blocks[1],
    user_category = ucat,
    vendor_category = vendor,
    fxname = fx or blocks[2],
    creator_id = blocks[3],
    source_id = blocks[4],
    user_data = blocks[5] and table.concat(blocks, "_", 5) or nil,
  }
end

-- Variant numbering for a group of takes of the same sound: "Door Creak" ->
-- "Door Creak 01" ... ; width grows past 99 takes.
function M.variant_fxnames(fxname, count)
  local width = count >= 100 and #tostring(count) or 2
  local out = {}
  for i = 1, count do
    out[i] = string.format("%s %0" .. width .. "d", fxname, i)
  end
  return out
end

-- Makes names unique inside one batch: a repeated name gets " 02", " 03"...
-- appended to its FXName. names: list of build() parameter tables, changed in place.
function M.dedupe(params_list)
  local count = {}
  for _, p in ipairs(params_list) do
    local key = (M.build(p))
    count[key] = (count[key] or 0) + 1
  end
  local seen = {}
  for _, p in ipairs(params_list) do
    local key = (M.build(p))
    if count[key] > 1 then
      seen[key] = (seen[key] or 0) + 1
      p.fxname = string.format("%s %02d", M.clean_block(p.fxname, false), seen[key])
    end
  end
  return params_list
end

return M
