-- mtt_metadataassistant_store.lua
-- One card per item, kept in the project (ProjExtState, section EXT, key = the
-- card key): saved with the project, so reopening the project and selecting
-- an item already worked on brings its card back. proj: the project the item
-- belongs to (0 = active); a card is always written to its own project, even
-- if another project tab is active by then.
--
-- The card key is not the item GUID: REAPER gives a pasted item a new GUID, so
-- a cut and paste would lose the card. The key travels with the item in its own
-- extended data (TAG = "<key>|<GUID the item had when it was tagged>", which
-- REAPER copies on cut, copy, paste and split). An item without a tag uses its
-- GUID as key (also how older versions saved cards).

local M = {}

M.EXT = "mtt_MetadataAssistant"
M.TAG = "P_EXT:mtt_metadataassistant"

-- Where UCS Tagger (this script's name before 0.20) kept the same cards. The section
-- is the one its settings used too; the spelling of its item tag is not kept anywhere,
-- so both are tried, and an item without a tag is found by its GUID (the key of a card
-- that never went through a cut and paste).
M.OLD_EXT = "mtt_UCSTagger"
M.OLD_TAGS = { "P_EXT:mtt_ucstagger", "P_EXT:mtt_UCSTagger" }

-- "<key>|<owner guid>" -> key, owner (nil when the tag is empty or malformed). Pure.
function M.parse_tag(tag)
  return tostring(tag or ""):match("^([^|]+)|(.*)$")
end

function M.format_tag(key, owner)
  return key .. "|" .. owner
end

-- Which card an item belongs to. tag: the item's tag, guid: its GUID,
-- owner_exists(guid): whether an item with that GUID is in the project.
-- Returns key, action, source_key:
--   "new"   no tag: the GUID is the key
--   "own"   the item is the one that was tagged
--   "adopt" pasted after a cut (the tagged item is gone): takes over the card
--   "fork"  a copy (the tagged item is still there): its own key (its GUID),
--           the card to start from is source_key
-- Pure.
function M.resolve(tag, guid, owner_exists)
  local key, owner = M.parse_tag(tag)
  if not key then return guid, "new" end
  if owner == guid then return key, "own" end
  if owner_exists(owner) then return guid, "fork", key end
  return key, "adopt"
end

function M.load(json, guid, proj)
  local _, s = reaper.GetProjExtState(proj or 0, M.EXT, guid)
  if not s or s == "" then return nil end
  local card = json.decode(s)
  if type(card) ~= "table" then return nil end
  return card
end

function M.save(json, guid, card, proj)
  reaper.SetProjExtState(proj or 0, M.EXT, guid, json.encode(card))
  reaper.MarkProjectDirty(proj or 0)
end

-- An empty value deletes the key.
function M.delete(guid, proj)
  reaper.SetProjExtState(proj or 0, M.EXT, guid, "")
  reaper.MarkProjectDirty(proj or 0)
end

-- The value most of the cards carry in values[key] ("" when none has one); a tie goes
-- to the value met first. Pure.
function M.most_common(cards, key)
  local count, order = {}, {}
  for _, card in ipairs(cards) do
    local v = type(card.values) == "table" and card.values[key]
    if type(v) == "string" and v ~= "" then
      if not count[v] then order[#order + 1] = v end
      count[v] = (count[v] or 0) + 1
    end
  end
  local best = ""
  for _, v in ipairs(order) do
    if best == "" or count[v] > count[best] then best = v end
  end
  return best
end

-- Moves what UCS Tagger saved in a project to this script's names: every card goes to
-- section EXT under the same key (a card already there under that key is newer and
-- stays: the old one is dropped), every item of a card gets its tag under TAG, and
-- the old cards and tags are emptied, so a project is imported only once.
-- project_keys: the settings saved in the project (Library, SourceID, Show); one that
-- is still empty here takes the value most imported cards carry.
-- Nothing changes until the project is saved. Returns nil when the project holds
-- nothing from UCS Tagger, else { cards = copied, kept = already here,
-- items = items given a tag, unlinked = copied cards no item points to,
-- filled = { setting keys filled } }.
function M.import_ucstagger(json, proj, project_keys)
  -- Read everything first: deleting while enumerating would shift the indices.
  local old = {}
  local idx = 0
  while true do
    local ok, key, val = reaper.EnumProjExtState(proj, M.OLD_EXT, idx)
    if not ok then break end
    old[#old + 1] = { key = key, val = val }
    idx = idx + 1
  end
  if #old == 0 then return nil end

  local r = { cards = 0, kept = 0, items = 0, unlinked = 0, filled = {} }
  local changed = false
  -- Keys compared in upper case: a card key is a GUID, whose case REAPER may not keep.
  local known, copied, imported = {}, {}, {} -- keys with a card in EXT now; copied keys; copied cards
  for _, e in ipairs(old) do
    local card = e.key ~= "" and e.val ~= "" and json.decode(e.val) or nil
    if type(card) == "table" then -- anything else is not a card: left where it is
      local _, here = reaper.GetProjExtState(proj, M.EXT, e.key)
      if here ~= "" then
        r.kept = r.kept + 1
      else
        reaper.SetProjExtState(proj, M.EXT, e.key, e.val) -- the saved text, unchanged
        r.cards = r.cards + 1
        copied[e.key:upper()] = true
        imported[#imported + 1] = card
      end
      known[e.key:upper()] = true
      reaper.SetProjExtState(proj, M.OLD_EXT, e.key, "")
      changed = true
    end
  end

  local linked = {}
  for i = 0, reaper.CountMediaItems(proj) - 1 do
    local item = reaper.GetMediaItem(proj, i)
    local old_tag = nil
    for _, name in ipairs(M.OLD_TAGS) do
      local _, t = reaper.GetSetMediaItemInfo_String(item, name, "", false)
      if t ~= "" then
        old_tag = old_tag or t
        reaper.GetSetMediaItemInfo_String(item, name, "", true)
        changed = true
      end
    end
    local _, tag = reaper.GetSetMediaItemInfo_String(item, M.TAG, "", false)
    if tag == "" then
      local _, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
      local key = M.parse_tag(old_tag)
      -- The old tag as it was ("<key>|<owner>"): a copy not opened yet still forks.
      if key and known[key:upper()] then tag = old_tag
      elseif known[guid:upper()] then tag = M.format_tag(guid, guid) end
      if tag ~= "" then
        reaper.GetSetMediaItemInfo_String(item, M.TAG, tag, true)
        r.items = r.items + 1
      end
    end
    local key = M.parse_tag(tag)
    if key then linked[key:upper()] = true end
  end
  for key in pairs(copied) do
    if not linked[key] then r.unlinked = r.unlinked + 1 end
  end

  for _, k in ipairs(project_keys or {}) do
    local _, here = reaper.GetProjExtState(proj, M.EXT, k)
    local v = M.most_common(imported, k)
    if here == "" and v ~= "" then
      reaper.SetProjExtState(proj, M.EXT, k, v)
      r.filled[#r.filled + 1] = k
      changed = true
    end
  end

  if changed then reaper.MarkProjectDirty(proj) end
  return r
end

return M
