-- mtt_metadataassistant_llm.lua
-- Prompts and answer checking for the LLM passes:
--   0. listen (only for a model that hears audio): the item's clip -> what is
--      heard, as short notes; the audio is sent once, here
--   1. draft: description + listening notes + source-file facts and measures +
--      session + UCS candidates -> sound type, CatID, open checklist items,
--      draft fields, questions
--   2. final: draft + the user's answers + UCS synonyms -> final fields
-- Requests use the OpenAI-compatible chat/completions body, which LM Studio,
-- oMLX and most local servers accept. Sending the request is not done here:
-- this module only builds text and checks answers.
-- Pure Lua, no reaper.* calls. json: the dkjson module.

local M = {}

M.MAX_QUESTIONS = 4
M.UNKNOWN_OPTION = "Unknown"

local function list_lines(prefix, items)
  local out = {}
  for _, s in ipairs(items) do out[#out + 1] = prefix .. s end
  return table.concat(out, "\n")
end

-- "- single (label): object, action, ..." per sound type, then the meaning of
-- each checklist key once.
local function sound_types_text(fields)
  local out, glossary, seen = {}, {}, {}
  for _, k in ipairs(fields.SOUND_TYPE_ORDER) do
    local t = fields.SOUND_TYPES[k]
    local keys = {}
    for _, item in ipairs(t.checklist) do
      keys[#keys + 1] = item[1]
      if not seen[item[1]] then
        seen[item[1]] = true
        glossary[#glossary + 1] = item[1] .. " = " .. item[2]
      end
    end
    out[#out + 1] = string.format("- %s (%s): %s", k, t.label, table.concat(keys, ", "))
  end
  return table.concat(out, "\n") .. "\nChecklist meanings: " .. table.concat(glossary, "; ") .. "."
end

local function candidates_text(candidates)
  local out = {}
  for _, c in ipairs(candidates) do
    local e = c.entry
    out[#out + 1] = string.format("- %s = %s / %s: %s", e.id, e.cat, e.sub, e.expl)
  end
  return table.concat(out, "\n")
end

local function kv_text(t, keys)
  local out = {}
  for _, k in ipairs(keys) do
    local v = t[k]
    if v ~= nil and v ~= "" then out[#out + 1] = string.format("- %s: %s", k, tostring(v)) end
  end
  if #out == 0 then return "- (none)" end
  return table.concat(out, "\n")
end

-- Facts about the audio itself. Item names and file names are never sent: they
-- can be meaningless, so nothing may be deduced from them.
M.FILE_FACT_KEYS = { "Channels", "SampleRate", "Length", "RecordedOn",
                     "RecorderTracks", "ExistingMetadata", "Measured" }

-- The audio content part of a chat message. mode "path": the server reads a
-- local file (mlx-vlm server); mode "base64": OpenAI-style inline WAV data.
function M.audio_part(mode, path, b64)
  if mode == "base64" then
    return { type = "input_audio", input_audio = { data = b64, format = "wav" } }
  end
  return { type = "input_audio", input_audio = path }
end

-- Pass 0: what the model hears. Short prompt, short answer.
function M.listen_messages(fields, ctx, audio_part)
  local kinds = table.concat(fields.SOUND_TYPE_ORDER, "|")
  local text = table.concat({
    "Listen to this sound effect, recorded for a sound library. Describe only what you clearly hear.",
    "Do not guess specific names (species, car models, places) unless they are unmistakable.",
    ctx.description ~= "" and ("The person who recorded it says: " .. ctx.description) or "",
    "Answer with one JSON object only, in English:",
    '{"heard": "<one or two sentences>", "kind": "' .. kinds .. '",',
    ' "sources": ["..."], "materials": ["..."], "actions": ["..."],',
    ' "events": ["<time in s> <what happens>"], "character": ["..."],',
    ' "space": "dry|room|reverberant|outdoor|unclear", "loop": false, "confidence": "low|medium|high"}',
  }, "\n")
  return {
    { role = "user", content = { { type = "text", text = text }, audio_part } },
  }
end

local function str_list(v, max)
  local out = {}
  if type(v) == "table" then
    for _, x in ipairs(v) do
      if type(x) == "string" and x:match("%S") then out[#out + 1] = x end
      if #out >= (max or 8) then break end
    end
  end
  return out
end

-- Listening notes from the pass-0 object: { text = one line for the prompts
-- and the UI, terms = words for the UCS search }.
function M.check_listen(obj)
  local parts, terms = {}, {}
  local heard = type(obj.heard) == "string" and obj.heard or ""
  if heard ~= "" then parts[#parts + 1] = heard; terms[#terms + 1] = heard end
  for _, key in ipairs({ "sources", "materials", "actions", "events", "character" }) do
    local l = str_list(obj[key])
    if #l > 0 then
      parts[#parts + 1] = key .. ": " .. table.concat(l, ", ")
      if key ~= "events" then terms[#terms + 1] = table.concat(l, " ") end
    end
  end
  for _, key in ipairs({ "kind", "space", "confidence" }) do
    if type(obj[key]) == "string" and obj[key] ~= "" then parts[#parts + 1] = key .. ": " .. obj[key] end
  end
  if obj.loop == true then parts[#parts + 1] = "loops seamlessly" end
  return { text = table.concat(parts, "; "), terms = terms }
end

-- System prompt shared by both passes.
function M.system_prompt(fields, opts)
  opts = opts or {}
  local qlang = opts.question_language or "English"
  return table.concat({
    "You tag sound effects for a professional library, in the style of BOOM Library and Tonsturm:",
    "UCS (Universal Category System) filenames and Soundminer metadata.",
    "Answer with one JSON object only, no prose, no code fences.",
    "Rules:",
    list_lines("- ", fields.writing_rules(opts.name_blocks)),
    "- Pick the CatID only from the candidate list you are given; never invent one.",
    "- Questions are written in " .. qlang .. "; metadata always in English.",
    "Kinds of sound and their checklist (what a reference library always states, most important first):",
    sound_types_text(fields),
    "Examples of finished fields:",
    list_lines("", fields.examples(opts.name_blocks)),
  }, "\n")
end

-- The "fields" object the model fills, as JSON text with empty values; it follows
-- the "VendorCategory / UserCategory" setting (opts.name_blocks).
local function fields_shape(fields, opts)
  local parts = {}
  for _, k in ipairs(fields.ai_keys(opts and opts.name_blocks)) do
    parts[#parts + 1] = string.format('"%s": ""', k)
  end
  return "{" .. table.concat(parts, ", ") .. "}"
end

-- Pass 1. ctx:
--   description (string), candidates (match.search result), file_facts (table),
--   session (table), group_size (number of takes sharing this description, >= 1)
function M.draft_messages(fields, ctx, opts)
  local user = table.concat({
    "Sound description from the user (true; it wins over what was heard):",
    ctx.description ~= "" and ctx.description or "(none: start from what was heard and the measures)",
    "",
    "What a listening model heard in the audio (may be wrong; ask when it matters and the user did not say):",
    ctx.heard and ctx.heard ~= "" and ctx.heard or "(not listened)",
    "",
    "Facts read from the source file (true, do not ask about them):",
    kv_text(ctx.file_facts or {}, M.FILE_FACT_KEYS),
    "",
    "Session settings (already known, do not ask):",
    kv_text(ctx.session or {}, fields.SESSION_KEYS),
    "",
    "Device defaults from the settings (already known, never ask about the microphone or the location):",
    kv_text(ctx.devices or {}, fields.DEVICE_KEYS),
    "",
    string.format("Takes sharing this description: %d.", ctx.group_size or 1),
    "",
    "UCS candidates (CatID = Category / SubCategory: explanation):",
    candidates_text(ctx.candidates or {}),
    "",
    "Steps: choose the kind of sound and the CatID; list the checklist items of that kind that the",
    "description and the file facts leave open; draft the fields from what is known; ask about the",
    "open items that matter most, in checklist order.",
    "Return:",
    '{"sound_type": "single|ambience|vehicle|designed|vocal",',
    ' "catid": "<one CatID from the candidates>",',
    ' "missing": ["<open checklist item>", "..."],',
    ' "fields": ' .. fields_shape(fields, opts) .. ',',
    ' "questions": [{"about": "<checklist item>", "text": "<question>", "options": ["<short answer>", "..."]}]}',
    string.format("At most %d questions. Give 2 to 5 short, plausible options per question.", M.MAX_QUESTIONS),
    "Leave unknown fields empty.",
  }, "\n")
  return {
    { role = "system", content = M.system_prompt(fields, opts) },
    { role = "user", content = user },
  }
end

-- Pass 2. draft: the checked pass-1 answer; answers: list of {question=, answer=}
-- (an answer of "" means the user skipped it).
function M.final_messages(fields, ctx, draft, answers, opts)
  local qa = {}
  for _, a in ipairs(answers or {}) do
    local ans = (a.answer and a.answer ~= "") and a.answer or "(skipped: leave it unknown)"
    qa[#qa + 1] = string.format("- %s -> %s", a.question, ans)
  end
  local draft_fields = {}
  for _, k in ipairs(fields.ai_keys(opts and opts.name_blocks)) do
    if draft.fields[k] and draft.fields[k] ~= "" then
      draft_fields[#draft_fields + 1] = string.format("- %s: %s", k, draft.fields[k])
    end
  end
  local synonyms = fields.ucs_synonyms(draft.entry, 40)
  local user = table.concat({
    "Sound description from the user:",
    ctx.description ~= "" and ctx.description or "(none)",
    "",
    "What a listening model heard (may be wrong; the user's words and answers win):",
    ctx.heard and ctx.heard ~= "" and ctx.heard or "(not listened)",
    "",
    "Facts read from the source file (true):",
    kv_text(ctx.file_facts or {}, M.FILE_FACT_KEYS),
    "",
    "Device defaults from the settings (already known; leave Microphone empty unless the user names another one):",
    kv_text(ctx.devices or {}, fields.DEVICE_KEYS),
    "",
    string.format("Your draft: sound type %s, CatID %s (%s / %s).", draft.sound_type, draft.catid,
      tostring(draft.entry and draft.entry.cat or "?"), tostring(draft.entry and draft.entry.sub or "?")),
    #draft_fields > 0 and table.concat(draft_fields, "\n") or "- (no draft fields)",
    "",
    "The user's answers (they override the draft; 'Unknown' means leave it out):",
    #qa > 0 and table.concat(qa, "\n") or "- (no questions were asked)",
    "",
    "UCS synonyms of " .. tostring(draft.catid) .. " (keyword material, use those that apply):",
    #synonyms > 0 and table.concat(synonyms, ", ") or "(none)",
    "",
    "UCS candidates (you may change the CatID only to one of these):",
    candidates_text(ctx.candidates or {}),
    "",
    "Return the final version, without questions:",
    '{"sound_type": "...", "catid": "...", "fields": ' .. fields_shape(fields, opts) .. '}',
  }, "\n")
  return {
    { role = "system", content = M.system_prompt(fields, opts) },
    { role = "user", content = user },
  }
end

-- chat/completions request body as a JSON string.
-- opts: model (string), temperature (default 0.2), json_mode (adds
-- response_format json_object; not every local server accepts it).
function M.request_body(json, messages, opts)
  opts = opts or {}
  local body = {
    model = opts.model or "local-model",
    temperature = opts.temperature or 0.2,
    messages = messages,
    stream = opts.stream == true,
  }
  if opts.json_mode then body.response_format = { type = "json_object" } end
  return json.encode(body)
end

-- Text chats are requested as a stream (OpenAI server-sent events), so a server
-- can see the phases of the request (prompt processing, then generation) as they
-- happen. curl finishes the transfer before the card is updated; the card uses
-- only the assistant's visible content.
local function stream_text(json, body)
  local parts, data = {}, {}
  local finish, done
  body = body:gsub("\r\n", "\n"):gsub("\r", "\n")
  for line in (body .. "\n\n"):gmatch("([^\n]*)\n") do
    if line:sub(1, 5) == "data:" then
      data[#data + 1] = line:sub(6):gsub("^ ", "")
    elseif line == "" and #data > 0 then
      local event = table.concat(data, "\n")
      data = {}
      if event == "[DONE]" then done = true; break end
      local chunk, pos, err = json.decode(event)
      if type(chunk) ~= "table" or event:find("%S", pos) then
        return nil, "invalid chat stream event: " .. tostring(err or "expected one JSON object")
      end
      if chunk.error then
        local message = type(chunk.error) == "table" and chunk.error.message or chunk.error
        return nil, "server error: " .. tostring(message)
      end
      local choice = type(chunk.choices) == "table" and chunk.choices[1]
      if type(choice) == "table" and (choice.index == nil or choice.index == 0) then
        local content = type(choice.delta) == "table" and choice.delta.content
        if type(content) == "string" and content ~= "" then parts[#parts + 1] = content end
        if type(choice.finish_reason) == "string" then finish = choice.finish_reason end
      end
    end
  end
  if not done and not finish then return nil, "chat stream ended before the response was complete" end
  if #parts == 0 then return nil, "no message content in the response" end
  return table.concat(parts), finish
end

-- The model's text from a chat/completions response body (plain JSON or a stream
-- of server-sent events); nil, err otherwise. Second value: the finish reason
-- when the server gives one.
function M.response_text(json, body)
  if body and (body:match("^%s*data:") or body:match("[\r\n]data:")) then
    return stream_text(json, body)
  end
  local obj, _, err = json.decode(body or "")
  if type(obj) ~= "table" then return nil, "response is not JSON: " .. tostring(err) end
  if obj.error then
    local msg = type(obj.error) == "table" and obj.error.message or tostring(obj.error)
    return nil, "server error: " .. tostring(msg)
  end
  local choice = type(obj.choices) == "table" and obj.choices[1]
  local text = type(choice) == "table" and type(choice.message) == "table" and choice.message.content
  if type(text) ~= "string" then return nil, "no message content in the response" end
  return text, choice.finish_reason
end

-- Model text without reasoning blocks (<think>...</think>) and without
-- chat-template tokens that leak from some servers (<|im_start|>, <|im_end|>),
-- trimmed.
function M.clean_text(text)
  text = tostring(text or ""):gsub("<think>.-</think>", "")
  local after = text:match(".*</think>(.*)$")
  if after then text = after end
  text = text:gsub("<|[%w_]+|>", " ")
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local RECOVER_KEYS = { "VendorCategory", "FXName", "TrackTitle", "Description", "Keywords",
                       "MicPerspective", "Location", "RecType", "Microphone", "UserCategory" }

-- Fields read one by one from an answer that is not valid JSON (cut at the
-- token limit, a missing comma...). Questions are not recovered. nil when
-- neither a CatID nor two fields are found.
local function recover(text)
  local function str(key)
    local v = text:match('"' .. key .. '"%s*:%s*"(.-[^\\])"')
    if not v then return nil end
    return (v:gsub('\\"', '"'):gsub("\\n", " "))
  end
  local obj = { fields = {}, _recovered = true }
  obj.sound_type = str("sound_type")
  obj.catid = str("catid")
  local n = 0
  for _, k in ipairs(RECOVER_KEYS) do
    local v = str(k)
    if v then obj.fields[k] = v; n = n + 1 end
  end
  if not obj.catid and n < 2 then return nil end
  return obj
end

-- The JSON object inside the model's text: code fences, reasoning blocks,
-- template tokens and any text around the outermost {...} are tolerated (local
-- models add them despite the prompt); invalid JSON falls back to recover().
function M.extract_object(json, text)
  text = M.clean_text(text)
  local first = text:find("{", 1, true)
  local last
  for i = #text, 1, -1 do
    if text:sub(i, i) == "}" then last = i; break end
  end
  local err = "no JSON object in the answer"
  if first and last and last > first then
    local obj, _, derr = json.decode(text:sub(first, last))
    if type(obj) == "table" then return obj end
    err = "invalid JSON in the answer: " .. tostring(derr)
  end
  local obj = recover(text)
  if obj then return obj end
  return nil, err
end

local function trim(s)
  return (tostring(s):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- True when an option already says "unknown" in some form.
local function is_unknown_option(o)
  local l = o:lower()
  return l:find("unknown", 1, true) or l:find("not sure", 1, true) or l:find("non so", 1, true)
      or l:find("don't know", 1, true) or l:find("n/a", 1, true)
end

-- True for a question about the microphone or the location: those are never
-- asked (the microphone comes from the Settings or the description, the location
-- only from the description), whatever the model decides.
local function is_never_asked(fields, about, text)
  local a, t = tostring(about or ""):lower(), tostring(text or ""):lower()
  for _, k in ipairs(fields.NEVER_ASKED or {}) do
    if a:find(k, 1, true) then return true end
  end
  -- Distance and placement of the microphone (perspective) are still asked.
  for _, p in ipairs({ "which mic", "what mic", "which microphone", "what microphone",
                       "microphone was used", "microphone model", "mic was used",
                       "where was this recorded", "where was it recorded", "location" }) do
    if t:find(p, 1, true) then return true end
  end
  return false
end

-- Checks a pass-1 or pass-2 object against the candidates and the schema.
-- Returns clean, problems: clean holds only known keys with string values;
-- problems lists what was dropped or is wrong. A wrong CatID is a problem, never
-- silently replaced. Every question ends with an "Unknown" option.
function M.check_answer(fields, obj, candidates, expect_questions)
  local problems = {}
  local clean = { fields = {}, questions = {}, missing = {} }
  if obj._recovered then problems[#problems + 1] = "the answer was not valid JSON: fields recovered one by one, no questions" end

  local st = type(obj.sound_type) == "string" and trim(obj.sound_type):lower() or ""
  if fields.SOUND_TYPES[st] then
    clean.sound_type = st
  else
    problems[#problems + 1] = "unknown sound_type: " .. st
  end

  local catid = type(obj.catid) == "string" and trim(obj.catid) or ""
  for _, c in ipairs(candidates or {}) do
    if c.entry.id == catid then clean.catid = catid; clean.entry = c.entry end
  end
  if not clean.catid then problems[#problems + 1] = "CatID not among the candidates: " .. catid end

  if type(obj.fields) == "table" then
    for k, v in pairs(obj.fields) do
      if fields.is_ai_key(k) and type(v) == "string" then
        local s = trim(v)
        if s ~= "" then clean.fields[k] = s end
      elseif v ~= "" then
        problems[#problems + 1] = "ignored field: " .. tostring(k)
      end
    end
  else
    problems[#problems + 1] = "fields missing"
  end

  if clean.fields.MicPerspective then
    local mp = fields.normalize_mic_perspective(clean.fields.MicPerspective)
    if mp then
      clean.fields.MicPerspective = mp
    else
      problems[#problems + 1] = "MicPerspective outside the vocabulary: " .. clean.fields.MicPerspective
      clean.fields.MicPerspective = nil
    end
  end

  if type(obj.missing) == "table" then
    for _, m in ipairs(obj.missing) do
      if type(m) == "string" and trim(m) ~= "" then clean.missing[#clean.missing + 1] = trim(m) end
    end
  end

  if expect_questions and type(obj.questions) == "table" then
    for _, q in ipairs(obj.questions) do
      if #clean.questions >= M.MAX_QUESTIONS then
        problems[#problems + 1] = "more than " .. M.MAX_QUESTIONS .. " questions: extra ones dropped"
        break
      end
      local q_about = type(q) == "table" and (q.about or q.field) or ""
      if type(q) == "table" and type(q.text) == "string" and trim(q.text) ~= ""
         and not is_never_asked(fields, q_about, q.text) then
        local options, has_unknown = {}, false
        if type(q.options) == "table" then
          for _, o in ipairs(q.options) do
            if type(o) == "string" and trim(o) ~= "" then
              options[#options + 1] = trim(o)
              if is_unknown_option(o) then has_unknown = true end
            end
          end
        end
        if not has_unknown then options[#options + 1] = M.UNKNOWN_OPTION end
        local about = type(q.about) == "string" and q.about or (type(q.field) == "string" and q.field) or ""
        clean.questions[#clean.questions + 1] = {
          about = about,
          field = about,
          text = trim(q.text),
          options = options,
        }
      end
    end
  end
  return clean, problems
end

return M
