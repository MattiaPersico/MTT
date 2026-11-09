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

return M
