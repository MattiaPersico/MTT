-- mtt_metadataassistant_flow.lua
-- One item's card, from description to final metadata:
--   idle -> [listening] -> drafting -> questions -> finalizing -> done   (any step -> error)
-- listening only when the model hears audio (settings.model_audio): the clip goes
-- to the model once (file path or base64, OpenAI chat format) and its notes then
-- travel as text. Every request is an OpenAI chat/completions call; text chats are streamed.
-- In "done" every field is editable (set_value); result() recomputes the
-- filename and the metadata from the current values, unless the user typed the
-- file name by hand (set_filename; a field that feeds the name drops that edit).
-- to_card()/from_card()
-- give the table saved in the project. The HTTP call is injected (deps.post),
-- so the whole flow also runs outside REAPER.
-- Pure Lua, no reaper.* calls.

local M = {}

M.CANDIDATES = 15
M.CARD_VERSION = 1

-- deps: ucs, match, index, fields, filename, llm, json,
--       post(url, headers, body, stall_s, callback) -> id | nil, err
--       today() -> "YYYY-MM-DD"
--       measure(s) -> measures_text, clip ({ path = | b64 = } or nil), err   (optional)
-- settings: the table from mtt_metadataassistant_settings.load(); url: its chat_url().
-- item: { guid = string, facts = table from mtt_metadataassistant_item.facts, model_facts = facts_for_model }
function M.new(deps, settings, url, item)
  return {
    deps = deps, settings = settings, url = url, state = "idle",
    guid = item and item.guid, facts = item and item.facts or {},
    model_facts = item and item.model_facts or {}, description = "",
  }
end

local function fail(s, msg)
  s.state = "error"
  s.error = msg
  s.dirty = true
end

local function headers(settings)
  local h = { "Content-Type: application/json" }
  if settings.api_key and settings.api_key ~= "" then
    h[#h + 1] = "Authorization: Bearer " .. settings.api_key
  end
  return h
end

local function llm_opts(settings)
  return {
    model = settings.model,
    question_language = settings.question_language,
    name_blocks = settings.name_blocks,
  }
end

-- With the "VendorCategory / UserCategory" setting off, the model's values for them
-- are dropped: the prompt no longer asks for them, but a model may send them anyway.
local function drop_name_blocks(s, f)
  if s.settings and s.settings.name_blocks == false then f.VendorCategory, f.UserCategory = nil, nil end
end

-- The server's own error text when there is one, else the transport error.
local function transport_error(s, res)
  local d = s.deps
  if res.body and res.body ~= "" then
    local _, err = d.llm.response_text(d.json, res.body)
    if err and err:find("^server error") then return err .. " (" .. tostring(res.error) .. ")" end
  end
  return tostring(res.error or "request failed")
end

-- Model answer -> checked object, or nil after setting the error state.
local function read_answer(s, res, expect_questions)
  local d = s.deps
  if not res.ok then fail(s, transport_error(s, res)); return nil end
  local text, info = d.llm.response_text(d.json, res.body)
  if not text then fail(s, info); return nil end
  local finish = info
  s.raw_text = text
  local obj, err = d.llm.extract_object(d.json, text)
  if not obj then fail(s, err); return nil end
  local clean, problems = d.llm.check_answer(d.fields, obj, s.candidates, expect_questions)
  if finish == "length" then problems[#problems + 1] = "reply cut at the token limit" end
  return clean, problems
end

-- Text chats are streamed (stream = true), so the server sees the request's
-- phases; with audio the reply is not streamed. A server that rejects streaming
-- gets the same request again without it.
function M.send(s, messages, on_result)
  local d = s.deps
  local opts = llm_opts(s.settings)
  local gen = s.gen or 0
  local function post_chat(stream)
    opts.stream = stream
    local body = d.llm.request_body(d.json, messages, opts)
    -- No silence limit: a request runs until it ends or Stop (http: unreachable fails after 15 s).
    local id, err = d.post(s.url, headers(s.settings), body, 0, function(res)
      if (s.gen or 0) ~= gen then return end -- stopped by the user: the answer is dropped
      s.job = nil
      if stream and (res.status == 400 or res.status == 422) then
        local message = transport_error(s, res):lower()
        if message:find("stream", 1, true) and
           (message:find("support", 1, true) or message:find("must be false", 1, true)) then
          post_chat(false)
          return
        end
      end
      on_result(res)
    end)
    s.job = id
    if not id then fail(s, err) end
  end
  post_chat(not s.settings.model_audio)
end

local function context(s)
  return {
    description = s.description,
    heard = s.heard,
    candidates = s.candidates,
    file_facts = s.model_facts or {},
    session = s.session or {},
    group_size = 1,
  }
end

-- Pass 1 (after pass 0 when the model hears audio).
local function start_draft(s, extra_terms)
  local d = s.deps
  s.candidates = d.match.search(d.index, s.description, M.CANDIDATES, extra_terms)
  if #s.candidates == 0 then
    fail(s, "No UCS candidates: describe the object, material or action.")
    return
  end
  s.state = "drafting"
  M.send(s, d.llm.draft_messages(d.fields, context(s), llm_opts(s.settings)), function(res)
    local clean, problems = read_answer(s, res, true)
    if not clean then return end
    if not clean.catid then
      fail(s, "The model chose a CatID outside the candidates (" .. table.concat(problems, "; ") .. ").")
      return
    end
    drop_name_blocks(s, clean.fields)
    s.draft, s.problems = clean, problems
    s.answers = {}
    for i, q in ipairs(clean.questions) do
      s.answers[i] = { question = q.text, about = q.about, answer = "" }
    end
    s.state = "questions"
    s.dirty = true
  end)
end

local function measured(s, measures, clip, merr)
  local d = s.deps
  s.measures_text = measures
  s.model_facts = s.model_facts or {}
  s.model_facts.Measured = measures
  if merr and not measures then fail(s, tostring(merr)); return end
  if not s.settings.model_audio then
    if clip and clip.path then os.remove(clip.path) end
    start_draft(s, nil)
    return
  end
  if not clip then
    if s.description:match("%S") then
      s.listen_error = "no audio clip: " .. tostring(merr)
      start_draft(s, nil)
    else
      fail(s, "Could not prepare the audio clip: " .. tostring(merr))
    end
    return
  end

  s.state = "listening"
  s.clip_path = clip.path
  local part = d.llm.audio_part(clip.b64 and "base64" or "path", clip.path, clip.b64)
  M.send(s, d.llm.listen_messages(d.fields, { description = s.description, mapping = clip.mapping }, part), function(res)
    if clip.path then os.remove(clip.path) end
    s.clip_path = nil
    local obj, err = nil, nil
    if res.ok then
      local text
      text, err = d.llm.response_text(d.json, res.body)
      if text then
        s.raw_listen = text
        obj, err = d.llm.extract_object(d.json, text)
        -- A plain-text description is still a useful listening note; an
        -- answer made only of template tokens or reasoning is not.
        if not obj then
          local plain = d.llm.clean_text(text)
          if plain ~= "" then
            obj = { heard = plain:sub(1, 600) }
          else
            err = "the model returned no listening notes"
          end
        end
      end
    else
      err = transport_error(s, res)
    end
    if obj then
      local notes = d.llm.check_listen(obj)
      s.heard = notes.text
      start_draft(s, notes.terms)
    elseif s.description:match("%S") then
      s.listen_error = "listening failed: " .. tostring(err)
      start_draft(s, nil)
    else
      fail(s, "Listening failed: " .. tostring(err))
    end
  end)
  -- The request never started: the clip is not needed any more.
  if s.state == "error" and clip.path then os.remove(clip.path) end
end

-- Resume one audio job per UI frame. Closing a suspended thread also releases
-- its take accessor through the resource guard in survey_take.
local pending = {}
function M.measure_count() return #pending end

function M.poll_measurements()
  local s = table.remove(pending,1)
  if not s then return end
  local thread = s.measure_thread
  local ok, measures, clip, err = coroutine.resume(thread)
  if ok and coroutine.status(thread) == "suspended" then
    pending[#pending+1] = s
    return
  end
  coroutine.close(thread)
  s.measure_thread, s.measure_start = nil, nil
  if not ok then fail(s,tostring(measures)); return end
  measured(s,measures,clip,err)
end

function M.stop_measurements()
  while #pending > 0 do M.cancel(pending[#pending]) end
end

-- Starts the analysis: measures, then pass 0 (if the model hears audio) and
-- pass 1; the card moves to "questions" or "error" when the answers arrive.
-- Starting again drops the previous draft, answers and values.
function M.analyze(s, description, session_values)
  if M.busy(s) then return end
  local d = s.deps
  s.description = tostring(description or "")
  s.session = session_values or {}
  s.error, s.draft, s.values, s.problems, s.raw_text, s.answers = nil, nil, nil, nil, nil, nil
  s.heard, s.listen_error, s.rendered, s.filename_edit = nil, nil, nil, nil
  s.measures_text, s.model_facts.Measured = nil, nil
  s.cancelled = nil
  s.dirty = true
  if not s.url then fail(s, "Set a valid endpoint (http://...) in Settings."); return end
  if not s.settings.model or s.settings.model == "" then fail(s, "Set the model name in Settings."); return end
  local hears = s.settings.model_audio
  if not hears and not s.description:match("%S") then
    fail(s, "Describe the sound, or tick 'Model hears audio' in Settings if the model can listen.")
    return
  end

  if d.defer_measure and d.measure then
    s.state = "measuring"
    s.measure_thread = coroutine.create(function() return d.measure(s) end)
    pending[#pending+1] = s
  elseif d.measure then
    measured(s,d.measure(s))
  else
    measured(s)
  end
end

-- Values from a checked answer: UCS fields, the model's fields, library
-- identity, recording date.
function M.build_values(s, answer)
  local d = s.deps
  local values = {}
  d.fields.apply_ucs(values, answer.entry)
  for k, v in pairs(answer.fields) do values[k] = v end
  drop_name_blocks(s, values)
  -- Only the model's value is trimmed: a VendorCategory typed later is kept as typed.
  if type(values.VendorCategory) == "string" and values.VendorCategory ~= "" then
    values.VendorCategory = d.filename.trim_vendor(values.VendorCategory, values.FXName,
      answer.entry.cat, answer.entry.sub)
  end
  d.fields.apply_session(values, s.session or {})
  d.fields.apply_auto(values, s.facts.recorded_on, d.today(), d.ucs.version)
  return values
end

-- Pass 2, with the answers in s.answers (answer "" = skipped). Can run again
-- after "done" or a failed pass 2: the values are rebuilt, manual edits go.
function M.finalize(s)
  local d = s.deps
  if M.busy(s) or not s.draft then return end
  s.state = "finalizing"
  s.error = nil
  s.cancelled = nil
  M.send(s, d.llm.final_messages(d.fields, context(s), s.draft, s.answers, llm_opts(s.settings)), function(res)
    local clean, problems = read_answer(s, res, false)
    if not clean then return end
    -- A final CatID outside the candidates keeps the draft's choice.
    if not clean.catid then
      clean.catid, clean.entry = s.draft.catid, s.draft.entry
      problems[#problems + 1] = "kept the draft CatID " .. s.draft.catid
    end
    s.sound_type = clean.sound_type or s.draft.sound_type
    s.problems = problems
    s.values = M.build_values(s, clean)
    s.rendered, s.filename_edit = nil, nil
    s.state = "done"
    s.dirty = true
  end)
end

-- Fields that make up the file name: editing one of them drops a name typed by hand.
local NAME_KEYS = { CatID = true, UserCategory = true, VendorCategory = true, FXName = true,
                    ShortID = true, SourceID = true }
M.NAME_KEYS = NAME_KEYS

-- Manual edit of one field. A valid CatID also rewrites Category, SubCategory
-- and CategoryFull.
function M.set_value(s, key, value)
  if not s.values or s.values[key] == value then return end
  s.values[key] = value
  if key == "CatID" then
    local entry = s.deps.match.find_catid(s.deps.ucs.entries, value)
    if entry then s.deps.fields.apply_ucs(s.values, entry) end
  end
  if NAME_KEYS[key] then s.filename_edit = nil end
  s.rendered = nil
  s.dirty = true
end

-- The file name typed by hand (no extension). Returns what was kept. A name
-- equal to the one the fields give, or an empty one, goes back to automatic.
function M.set_filename(s, text)
  if not s.values then return nil end
  local name = s.deps.filename.clean_name(text)
  local auto = M.auto_filename(s)
  if name == "" or name == auto then
    if s.filename_edit == nil then return auto end
    s.filename_edit = nil
  else
    if s.filename_edit == name then return name end
    s.filename_edit = name
  end
  s.rendered = nil
  s.dirty = true
  return s.filename_edit or auto
end

-- The name the fields give.
function M.auto_filename(s)
  local v = s.values or {}
  return (s.deps.filename.build({
    catid = v.CatID,
    user_category = v.UserCategory,
    vendor_category = v.VendorCategory,
    fxname = v.FXName,
    creator_id = v.ShortID,
    source_id = v.SourceID,
  }))
end

-- Filename, problems and metadata from the current values.
function M.result(s)
  local d = s.deps
  local v = s.values or {}
  local auto, name_problems = d.filename.build({
    catid = v.CatID,
    user_category = v.UserCategory,
    vendor_category = v.VendorCategory,
    fxname = v.FXName,
    creator_id = v.ShortID,
    source_id = v.SourceID,
  })
  local name = auto
  local problems = {}
  if s.filename_edit then
    name = s.filename_edit
    name_problems = d.filename.check_name(name)
  end
  for _, p in ipairs(name_problems) do problems[#problems + 1] = p end
  if v.CatID and v.CatID ~= "" and not d.match.find_catid(d.ucs.entries, v.CatID) then
    problems[#problems + 1] = "CatID " .. v.CatID .. " is not in the UCS list"
  end
  local missing = d.fields.missing_required(v)
  return {
    filename = name,
    auto_filename = auto,
    edited = s.filename_edit ~= nil,
    problems = problems,
    missing = missing,
    metadata = d.fields.to_render_metadata(v),
    renderable = #missing == 0 and name ~= "" and d.match.find_catid(d.ucs.entries, v.CatID or "") ~= nil,
  }
end

-- Stops the request in progress (listening, drafting or finalizing): the curl
-- call is killed, a late answer is dropped, the temporary audio clip is removed.
-- Analysis goes back to "idle" (the description is kept); finalizing goes back to
-- where it started from, the questions or the finished card.
function M.cancel(s)
  if not M.busy(s) then return end
  if s.measure_thread then
    for i,queued in ipairs(pending) do
      if queued == s then table.remove(pending,i); break end
    end
    coroutine.close(s.measure_thread)
    s.measure_thread, s.measure_start = nil,nil
  end
  s.gen = (s.gen or 0) + 1
  if s.job and s.deps.cancel then s.deps.cancel(s.job) end
  s.job = nil
  if s.clip_path then os.remove(s.clip_path); s.clip_path = nil end
  if s.state == "finalizing" then
    s.state = s.values and "done" or "questions"
  else
    s.state = "idle"
  end
  s.last_state = s.state -- the window keeps the view it is on
  s.error = nil
  s.cancelled = true
  s.dirty = true
end

function M.busy(s) return s.state == "measuring" or s.state == "listening" or s.state == "drafting" or s.state == "finalizing" end

-- The card saved in the project: plain data only.
function M.to_card(s)
  local cands = {}
  for _, c in ipairs(s.candidates or {}) do cands[#cands + 1] = c.entry.id end
  local draft = nil
  if s.draft then
    draft = {
      sound_type = s.draft.sound_type, catid = s.draft.catid, fields = s.draft.fields,
      missing = s.draft.missing, questions = s.draft.questions,
    }
  end
  return {
    v = M.CARD_VERSION,
    description = s.description,
    heard = s.heard,
    measures = s.measures_text,
    candidates = cands,
    draft = draft,
    answers = s.answers,
    sound_type = s.sound_type,
    values = s.values,
    filename_edit = s.filename_edit,
    rendered = s.rendered,
  }
end

-- Restores a saved card into a fresh session (same item).
function M.from_card(s, card)
  local d = s.deps
  s.description = card.description or ""
  s.heard = card.heard
  s.measures_text = card.measures
  if s.measures_text then
    s.model_facts = s.model_facts or {}
    s.model_facts.Measured = s.measures_text
  end
  s.candidates = {}
  for _, id in ipairs(card.candidates or {}) do
    local e = d.match.find_catid(d.ucs.entries, id)
    if e then s.candidates[#s.candidates + 1] = { entry = e, score = 0, hits = {} } end
  end
  if card.draft and card.draft.catid then
    local e = d.match.find_catid(d.ucs.entries, card.draft.catid)
    if e then
      s.draft = {
        sound_type = card.draft.sound_type, catid = card.draft.catid, entry = e,
        fields = card.draft.fields or {}, missing = card.draft.missing or {},
        questions = card.draft.questions or {},
      }
    end
  end
  s.answers = card.answers or {}
  s.sound_type = card.sound_type
  s.values = card.values
  s.filename_edit = card.filename_edit
  s.rendered = card.rendered
  if s.values then s.state = "done" elseif s.draft then s.state = "questions" else s.state = "idle" end
  s.dirty = false
  return s
end

return M
