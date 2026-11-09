-- mtt_metadataassistant_settings.lua
-- Script settings: the LLM server, the library identity written into every file
-- and the interface. Global ones live in REAPER's persistent ExtState (section
-- EXT); the ones marked project = true (Library, SourceID, Show) in the current
-- project's ProjExtState (same section), so each project keeps its own.

local M = {}

M.EXT = "mtt_MetadataAssistant"

-- Order = order on screen. page: "Settings" (the gear: global preferences) or
-- "Library" (the books icon: the library identity, used more often);
-- group: the heading it sits under (a new heading where the group changes).
-- kind: "text" | "secret" | "bool" | "int" | "combo" (combo: items, value = 0-based
-- index). tip: tooltip on the label (what the setting is for). project: saved in
-- the project instead of globally. needs: key of a bool setting; off = this one is
-- greyed out, its group heading too when the whole group needs it.
-- Gone in 0.21 (values saved under these keys are ignored): json_mode (response_format
-- is never sent; it was off by default), stall_timeout_s (requests now run until
-- they end or Stop; an unreachable server still fails after 15 s), Microphone and
-- RecMedium (per item now), show_technical (0.22: the Technical details panel is gone),
-- and before them timeout_s.
M.KEYS = {
  -- Settings (gear)
  { key = "endpoint",          page = "Settings", group = "Server", label = "Endpoint", kind = "text", default = "",
    hint = "http://localhost:1234/v1",
    tip = "Base URL of an OpenAI-compatible server (LM Studio, oMLX, OpenAI...). The script calls <endpoint>/chat/completions and <endpoint>/models." },
  { key = "api_key",           page = "Settings", group = "Server", label = "API key", kind = "secret", default = "",
    hint = "optional, local servers usually need none",
    tip = "Sent as 'Authorization: Bearer <key>'. Leave empty for servers without authentication." },
  { key = "model",             page = "Settings", group = "Models", label = "Model", kind = "text", default = "",
    hint = "model name",
    tip = "Model that describes and tags the items. Pick it from the server's list, or type an ID the server does not list." },
  { key = "curator_model",     page = "Settings", group = "Models", label = "Curator model", kind = "text", default = "",
    hint = "Use main model",
    tip = "Model for the Overview curator. Empty: the main model." },
  { key = "question_language", page = "Settings", group = "Models", label = "Questions in", kind = "text", default = "English",
    tip = "Language of the questions the model asks you. Metadata is always written in English." },
  { key = "model_audio",       page = "Settings", group = "Models", label = "Model hears audio", kind = "bool", default = false,
    tip = "Tick when the model accepts audio input. It then listens to a clip of the item before the description is analysed." },
  { key = "audio_mode",        page = "Settings", group = "Audio", label = "Audio sent as", kind = "combo", default = 0,
    items = { "file path (mlx-vlm server)", "base64 (OpenAI style)" }, needs = "model_audio",
    tip = "How the audio clip reaches the model: a local file path (mlx-vlm style servers) or base64 data inside the request (OpenAI style)." },
  -- The measurements always cover the whole item; this only limits the audio clip.
  { key = "listen_max_s",      page = "Settings", group = "Audio", label = "Seconds sent to the model", kind = "int", default = 30,
    needs = "model_audio",
    tip = "Length of the audio clip the model listens to. A longer item sends up to three excerpts where it is active, this many seconds in all. The measurements always cover the whole item." },
  -- Library identity (session values in mtt_metadataassistant_fields.SESSION_KEYS).
  { key = "Designer",          page = "Library", group = "Library identity", label = "Designer / recordist", kind = "text", default = "",
    tip = "Your name: written to Designer, Recordist and Artist in every file." },
  { key = "Manufacturer",      page = "Library", group = "Library identity", label = "Manufacturer", kind = "text", default = "",
    tip = "Company or label that publishes the library (Soundminer Manufacturer column)." },
  { key = "ShortID",           page = "Library", group = "Library identity", label = "CreatorID", kind = "text", default = "",
    tip = "Short code for the creator (ShortID): the CreatorID block of the UCS filename (e.g. B00M)." },
  { key = "URL",               page = "Library", group = "Library identity", label = "Website", kind = "text", default = "",
    hint = "www.example.com (also BWF originator reference)",
    tip = "Website written to the URL field and to the BWF originator reference (32 bytes)." },
  { key = "Copyright",         page = "Library", group = "Library identity", label = "Copyright", kind = "text", default = "",
    hint = "(c) 2026 Your Name (BWF originator, 32 bytes)",
    tip = "Copyright notice written to the BWF originator field (32 bytes)." },
  -- This project's identity (saved in the project, not global).
  { key = "Library",           page = "Library", group = "This project", label = "Library", kind = "text", default = "", project = true,
    tip = "Name of the sound library the files belong to. Saved in this project." },
  { key = "SourceID",          page = "Library", group = "This project", label = "SourceID", kind = "text", default = "", project = true,
    tip = "Short code for the project, library or recording source: the SourceID block of the UCS filename. Saved in this project." },
  { key = "Show",              page = "Library", group = "This project", label = "Show", kind = "text", default = "", project = true,
    tip = "Production or show the sounds were made for, when there is one. Saved in this project." },
  -- Files.
  { key = "render_dir",        page = "Settings", group = "Files", label = "Render folder", kind = "text", default = "Render",
    hint = "Render", browse = true,
    tip = "Where Render writes the files, relative to the project folder (default: Render). An absolute path is also accepted." },
  { key = "name_blocks",       page = "Library", group = "File names", label = "Vendor/UserCategory", kind = "bool", default = true,
    tip = "On: the model may fill UCS's optional name blocks, each joined with a dash: the object family before the FXName (VEHMech_Seatbelt Button-Press And Release) and a UserCategory after the CatID. Off: it leaves both empty and the object goes in the FXName (VEHMech_Seatbelt Button Press And Release). A value typed by hand counts either way. Applies from the next analysis or finalize." },
  -- Timeline.
  { key = "outline_items",     page = "Settings", group = "Timeline", label = "Outline tagged items", kind = "bool", default = true,
    tip = "Outlines on the timeline the items that have a card. Green: reviewed (final metadata). Yellow, blinking: waiting for review. Orange and warm white running around the item: being analyzed or finalized. Needs js_ReaScriptAPI (ReaPack: ReaTeam Extensions)." },
}

local function decode(def, raw)
  if raw == nil or raw == "" then return def.default end
  if def.kind == "bool" then return raw == "1" end
  if def.kind == "int" or def.kind == "combo" then return math.tointeger(tonumber(raw)) or def.default end
  return raw
end

local function encode(def, value)
  if def.kind == "bool" then return value and "1" or "0" end
  return tostring(value == nil and "" or value)
end

local function read(def)
  if def.project then
    local _, raw = reaper.GetProjExtState(0, M.EXT, def.key)
    return decode(def, raw)
  end
  local raw = reaper.GetExtState(M.EXT, def.key)
  -- "UCS" was the default render folder up to 0.20, saved with every other setting:
  -- it reads as the new default.
  if def.key == "render_dir" and raw == "UCS" then raw = "" end
  return decode(def, raw)
end

-- Every setting, read fresh: global ones from ExtState, project ones from the current project.
function M.load()
  local s = {}
  for _, def in ipairs(M.KEYS) do s[def.key] = read(def) end
  -- A mode saved by an older version (2 = the removed MTT Relay format) falls back to the first one.
  if s.audio_mode ~= 0 and s.audio_mode ~= 1 then s.audio_mode = 0 end
  return s
end

-- The project settings again, from the project now current (after a project switch).
function M.load_project(s)
  for _, def in ipairs(M.KEYS) do
    if def.project then s[def.key] = read(def) end
  end
end

-- One setting's stored text: global ones persistent across REAPER restarts,
-- project ones into the current project (saved with it).
local function write(def, text)
  if def.project then
    reaper.SetProjExtState(0, M.EXT, def.key, text)
  else
    reaper.SetExtState(M.EXT, def.key, text, true)
  end
end

-- Every setting as the text it is stored as (key -> text): two of these compared
-- tell what changed.
function M.encoded(s)
  local out = {}
  for _, def in ipairs(M.KEYS) do out[def.key] = encode(def, s[def.key]) end
  return out
end

-- Settings save themselves: writes only the settings whose text differs from
-- `before` (a table from M.encoded), so an unchanged project is not marked as
-- modified. Returns the new table to compare against next time.
function M.save_changed(s, before)
  local now = M.encoded(s)
  for _, def in ipairs(M.KEYS) do
    if now[def.key] ~= before[def.key] then write(def, now[def.key]) end
  end
  return now
end

-- "http://host:1234/v1", ".../v1/", ".../v1/chat/completions" -> the
-- chat/completions URL; nil when the value is not an http(s) URL.
function M.chat_url(endpoint)
  local e = tostring(endpoint or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if not e:match("^https?://[^%s]+$") then return nil end
  e = e:gsub("/+$", "")
  if e:match("/chat/completions$") then return e end
  return e .. "/chat/completions"
end

-- The server's model list (OpenAI GET /v1/models) from the same endpoint setting.
function M.models_url(endpoint)
  local chat = M.chat_url(endpoint)
  if not chat then return nil end
  return (chat:gsub("/chat/completions$", "")) .. "/models"
end

-- Whether a /v1/models entry says the model takes audio input: true, false,
-- or nil when the entry says nothing. Plain OpenAI entries carry no modalities;
-- these extensions are read: OpenRouter-style architecture.input_modalities,
-- input_modalities / modalities lists, capabilities as a list ("audio") or as
-- flags ({audio = true}). Pure.
function M.audio_capability(m)
  if type(m) ~= "table" then return nil end
  local function has_audio(list)
    if type(list) ~= "table" then return nil end
    local any = false
    for k, v in pairs(list) do
      any = true
      if v == "audio" or (k == "audio" and v == true) or (k == "audio_input" and v == true) then return true end
    end
    if any then return false end
    return nil
  end
  local found = nil
  local lists = { type(m.architecture) == "table" and m.architecture.input_modalities or nil,
                  m.input_modalities, m.modalities, m.capabilities }
  for i = 1, 4 do
    local r = has_audio(lists[i])
    if r == true then return true end
    if r == false then found = false end
  end
  return found
end

-- Model IDs from a /v1/models reply: OpenAI {"data": [{"id"}]} or
-- {"models": [{"id"} | {"name"}]}; sorted, duplicates dropped; second value:
-- id -> audio capability (true/false) for the entries that state it. nil, err
-- when the reply holds no list. Pure (json: the dkjson module).
function M.parse_models(json, body)
  local obj = json.decode(body or "")
  if type(obj) ~= "table" then return nil, "the model list is not JSON" end
  local list = type(obj.data) == "table" and obj.data or type(obj.models) == "table" and obj.models or nil
  if not list then return nil, "no model list in the reply" end
  local ids, seen, audio = {}, {}, {}
  for _, m in ipairs(list) do
    local id = type(m) == "table" and (m.id or m.name) or (type(m) == "string" and m) or nil
    if type(id) == "string" and id ~= "" and not seen[id] then
      seen[id] = true
      ids[#ids + 1] = id
      audio[id] = M.audio_capability(m)
    end
  end
  table.sort(ids)
  return ids, audio
end

-- The session values (library identity) the fields module expects.
function M.session_values(s)
  local out = {}
  for _, def in ipairs(M.KEYS) do
    if def.key:match("^%u") and s[def.key] ~= "" then out[def.key] = s[def.key] end
  end
  return out
end

return M
