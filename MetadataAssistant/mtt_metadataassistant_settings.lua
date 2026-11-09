-- mtt_metadataassistant_settings.lua
-- Script settings, kept in REAPER's persistent ExtState (section EXT): the LLM
-- server and the library identity written into every file.

local M = {}

M.EXT = "mtt_MetadataAssistant"

-- Order = order in the Settings panel. kind: "text" | "secret" | "bool" | "int" | "combo"
-- (combo: items, value = 0-based index). same_line: drawn next to the previous one.
-- tip: tooltip on the label (what the setting is for).
M.KEYS = {
  { key = "endpoint",          label = "Endpoint",          kind = "text",   default = "",
    hint = "http://localhost:1234/v1",
    tip = "Base URL of an OpenAI-compatible server (LM Studio, oMLX, OpenAI...). The script calls <endpoint>/chat/completions and <endpoint>/models." },
  { key = "model",             label = "Model",             kind = "text",   default = "",
    hint = "model name",
    tip = "Model ID sent in every request. Pick it from the server's list, or type an ID the server does not list." },
  { key = "model_audio",       label = "Model hears audio", kind = "bool",   default = false, same_line = true,
    tip = "Tick when the model accepts audio input. It then listens to a clip of the item before the description is analysed." },
  { key = "curator_model",     label = "Curator model",    kind = "text", default = "",
    hint = "Use main model",
    tip = "Model for Overview conversations on this server. Leave empty to follow the main model." },
  { key = "audio_mode",        label = "Audio sent as",     kind = "combo",  default = 0,
    items = { "file path (mlx-vlm server)", "base64 (OpenAI style)" },
    tip = "How the audio clip reaches the model: a local file path (mlx-vlm style servers) or base64 data inside the request (OpenAI style)." },
  { key = "listen_max_s",      label = "Seconds to listen/analyze", kind = "int", default = 30,
    tip = "Only the first N seconds of the item are measured and sent to the model." },
  { key = "api_key",           label = "API key",           kind = "secret", default = "",
    hint = "optional, local servers usually need none",
    tip = "Sent as 'Authorization: Bearer <key>'. Leave empty for servers without authentication." },
  { key = "question_language", label = "Question language", kind = "text",   default = "English",
    tip = "Language of the questions the model asks you. Metadata is always written in English." },
  { key = "json_mode",         label = "JSON mode (response_format)", kind = "bool", default = false,
    tip = "Adds response_format = json_object to the request. Turn on only if the server supports it." },
  -- Replaces "timeout_s" (a limit on the total time, which cut slow answers that were
  -- still arriving); a value saved under that key is ignored.
  { key = "stall_timeout_s",   label = "Give up after silence (s)", kind = "int", default = 0,
    tip = "Gives up on a model request when the server has sent nothing for this many seconds. 0 = never: a request runs as long as the answer keeps coming, however long it takes (several items analyzed at once wait for each other on a local server); Stop ends it. A server that cannot be reached fails after 15 s either way." },
  { key = "render_dir",        label = "Render folder",     kind = "text",   default = "UCS",
    hint = "UCS", browse = true,
    tip = "Where Render writes the file, relative to the project folder (default: UCS). An absolute path is also accepted." },
  -- Library identity (session values in mtt_metadataassistant_fields.SESSION_KEYS).
  { key = "Designer",          label = "Designer / recordist", kind = "text", default = "",
    tip = "Your name: written to Designer, Recordist and Artist in every file." },
  { key = "Manufacturer",      label = "Manufacturer",      kind = "text",   default = "",
    tip = "Company or label that publishes the library (Soundminer Manufacturer column)." },
  { key = "Library",           label = "Library",           kind = "text",   default = "",
    tip = "Name of the sound library the files belong to." },
  { key = "ShortID",           label = "CreatorID (ShortID)", kind = "text", default = "",
    tip = "Short code for the creator: the CreatorID block of the UCS filename (e.g. B00M)." },
  { key = "SourceID",          label = "SourceID",          kind = "text",   default = "",
    tip = "Short code for the project, library or recording source: the SourceID block of the UCS filename." },
  { key = "Show",              label = "Show",              kind = "text",   default = "",
    tip = "Production or show the sounds were made for, when there is one." },
  { key = "URL",               label = "Website",           kind = "text",   default = "",
    hint = "www.example.com (also BWF originator reference)",
    tip = "Website written to the URL field and to the BWF originator reference (32 bytes)." },
  { key = "Copyright",         label = "Copyright",         kind = "text",   default = "",
    hint = "(c) 2026 Your Name (BWF originator, 32 bytes)",
    tip = "Copyright notice written to the BWF originator field (32 bytes)." },
  -- Applied only to sounds whose file says they were recorded today.
  { key = "Microphone",        label = "Default microphone", kind = "text",  default = "",
    tip = "Microphone and technique used when the file says it was recorded today. Older files get no default, because it would most likely be wrong." },
  { key = "RecMedium",         label = "Default recorder",  kind = "text",   default = "",
    tip = "Recorder used when the file says it was recorded today." },
  -- File names.
  { key = "name_blocks",       label = "VendorCategory / UserCategory", kind = "bool", default = true,
    tip = "On: the model may fill UCS's optional name blocks, each joined with a dash: the object family before the FXName (VEHMech_Seatbelt Button-Press And Release) and a UserCategory after the CatID. Off: it leaves both empty and the object goes in the FXName (VEHMech_Seatbelt Button Press And Release). A value typed by hand counts either way. Applies from the next analysis or finalize." },
  { key = "show_technical", label = "Show technical details", kind = "bool", default = false,
    tip = "Shows source measurements, UCS candidates, the raw model answers and card management." },
  { key = "outline_items",     label = "Outline tagged items on the timeline", kind = "bool", default = true,
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

-- Every setting, read fresh from ExtState.
function M.load()
  local s = {}
  for _, def in ipairs(M.KEYS) do
    s[def.key] = decode(def, reaper.GetExtState(M.EXT, def.key))
  end
  -- A mode saved by an older version (2 = the removed MTT Relay format) falls back to the first one.
  if s.audio_mode ~= 0 and s.audio_mode ~= 1 then s.audio_mode = 0 end
  return s
end

-- Writes every setting, persistent across REAPER restarts.
function M.save(s)
  for _, def in ipairs(M.KEYS) do
    reaper.SetExtState(M.EXT, def.key, encode(def, s[def.key]), true)
  end
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
