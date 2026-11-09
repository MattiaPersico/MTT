-- mtt_metadataassistant_match.lua
-- Local UCS candidate search. Scores every subcategory of the UCS list against a
-- free-text description (Italian or English) so that only a short list of
-- candidates goes to the LLM: a short prompt keeps prefill fast on a local model,
-- and the model can only pick a CatID that really exists.
-- Pure Lua, no reaper.* calls.

local M = {}

-- Field weights: a query word found in the subcategory name says more than one
-- found in the explanation text.
local W_SUB, W_CAT, W_SYN, W_EXPL = 6, 4, 3, 1
-- A prefix match (porta/porte, creak/creaking) counts a bit less than an exact one.
local PREFIX_FACTOR = 0.75
-- Bonus when the description hits both the category and the subcategory.
local BOTH_BONUS = 2
-- Rarity weight: a query word found in many entries ("impatto" is in every
-- material's IMPACT) counts less than one found in few ("vetro"), so common
-- words do not fill the candidate list with look-alikes. Factor per word:
-- ln(N / df) / ln(N), never below MIN_RARITY.
local MIN_RARITY = 0.25
-- The best candidate's category is brought in whole when it is small (GLASS has
-- 8 subcategories): once the category is clear, the LLM chooses the subcategory
-- among all of them, not only those the words happened to hit.
local EXPAND_MAX = 10

-- UTF-8 Latin-1 accented letters -> plain ASCII, so "città" matches "citta".
local ACCENTS = {
  ["\xC3\xA0"] = "a", ["\xC3\xA1"] = "a", ["\xC3\xA2"] = "a", ["\xC3\xA4"] = "a",
  ["\xC3\xA8"] = "e", ["\xC3\xA9"] = "e", ["\xC3\xAA"] = "e", ["\xC3\xAB"] = "e",
  ["\xC3\xAC"] = "i", ["\xC3\xAD"] = "i", ["\xC3\xAE"] = "i", ["\xC3\xAF"] = "i",
  ["\xC3\xB2"] = "o", ["\xC3\xB3"] = "o", ["\xC3\xB4"] = "o", ["\xC3\xB6"] = "o",
  ["\xC3\xB9"] = "u", ["\xC3\xBA"] = "u", ["\xC3\xBB"] = "u", ["\xC3\xBC"] = "u",
  ["\xC3\xA7"] = "c", ["\xC3\xB1"] = "n",
  ["\xC3\x80"] = "a", ["\xC3\x81"] = "a", ["\xC3\x88"] = "e", ["\xC3\x89"] = "e",
  ["\xC3\x8C"] = "i", ["\xC3\x8D"] = "i", ["\xC3\x92"] = "o", ["\xC3\x93"] = "o",
  ["\xC3\x99"] = "u", ["\xC3\x9A"] = "u",
}

-- Words that carry no category information, in both languages.
local STOPWORDS = {}
for w in ([[
  the and with from into onto for that this then very some one two of on in at by to an or
  are was were has have had its it is be as not but out off over under small big large little
  di da del della dello dei degli delle al allo alla ai agli alle dal dalla dai dalle nel nella
  nei nelle sul sulla sui sulle con per tra fra che una uno un il lo la le gli dei non come
  molto poco piu meno anche sono era piccolo piccola grande grandi tipo cosa suono suoni
]]):gmatch("%a+") do STOPWORDS[w] = true end

-- Lowercase, strip accents, keep letters and digits, drop stopwords and words
-- shorter than 3 characters. Returns a list in input order.
function M.tokenize(text)
  local s = tostring(text or ""):gsub("[\xC3][\x80-\xBF]", function(c) return ACCENTS[c] or " " end)
  s = s:lower():gsub("[^%w]", " ")
  local out = {}
  for w in s:gmatch("%w+") do
    if #w >= 3 and not STOPWORDS[w] then out[#out + 1] = w end
  end
  return out
end

-- Two words match exactly, or by a shared prefix long enough to cover simple
-- inflections (porta/porte, cigola/cigolio, door/doors). Words shorter than 4
-- characters only match exactly.
local function prefix_match(a, b)
  if a == b then return true end
  local la, lb = #a, #b
  local shorter = la < lb and la or lb
  if shorter < 4 then return false end
  local need = shorter - 2
  if need < 4 then need = 4 end
  local n = 0
  while n < shorter and a:byte(n + 1) == b:byte(n + 1) do n = n + 1 end
  return n >= need
end

-- Builds the per-field word sets once; search() reuses them.
-- entries: the list from mtt_metadataassistant_ucs_data.lua.
function M.build_index(entries)
  local index = {}
  for i = 1, #entries do
    local e = entries[i]
    local function words(...)
      local set, list = {}, {}
      for k = 1, select("#", ...) do
        for _, w in ipairs(M.tokenize(select(k, ...))) do
          if not set[w] then set[w] = true; list[#list + 1] = w end
        end
      end
      return { set = set, list = list }
    end
    index[i] = {
      entry = e,
      fields = {
        { weight = W_SUB, kind = "sub", words = words(e.sub, e.sub_it) },
        { weight = W_CAT, kind = "cat", words = words(e.cat, e.cat_it) },
        { weight = W_SYN, kind = "syn", words = words(e.syn, e.syn_it) },
        { weight = W_EXPL, kind = "expl", words = words(e.expl) },
      },
    }
  end
  -- Entries per category (hash part; #index still counts entries only).
  index.by_cat = {}
  for i = 1, #index do
    local cat = index[i].entry.cat
    index.by_cat[cat] = index.by_cat[cat] or {}
    table.insert(index.by_cat[cat], index[i].entry)
  end
  return index
end

-- Best score of one query word against one field: full weight for an exact
-- match, reduced weight for a prefix match, 0 otherwise.
local function field_score(word, field)
  if field.words.set[word] then return field.weight end
  for _, w in ipairs(field.words.list) do
    if prefix_match(word, w) then return field.weight * PREFIX_FACTOR end
  end
  return 0
end

-- Returns up to `limit` candidates, best first:
--   { entry = <ucs entry>, score = <number>, hits = { word = kind, ... } }
-- extra_terms (optional): more words to search with, e.g. English keywords the
-- LLM derived from an Italian description.
function M.search(index, description, limit, extra_terms)
  limit = limit or 12
  -- Query words: inflections of a word already in the query (wood/woody,
  -- break/breaking) fold into it; a word said several times weighs more
  -- (up to 2x), so repeated notes of a listening model count.
  local query, count = {}, {}
  local function add(text)
    for _, w in ipairs(M.tokenize(text)) do
      local found = nil
      for _, q in ipairs(query) do
        if prefix_match(w, q) then found = q; break end
      end
      if found then
        count[found] = count[found] + 1
      else
        query[#query + 1] = w
        count[w] = 1
      end
    end
  end
  add(description)
  if type(extra_terms) == "table" then
    for _, t in ipairs(extra_terms) do add(t) end
  elseif extra_terms then
    add(extra_terms)
  end
  if #query == 0 then return {} end

  -- Pass 1: best field per (entry, word), and how many entries each word hits.
  local per_entry, df = {}, {}
  for i = 1, #index do
    local item = index[i]
    local row = nil
    for _, word in ipairs(query) do
      local best, best_kind = 0, nil
      for _, field in ipairs(item.fields) do
        local s = field_score(word, field)
        if s > best then best, best_kind = s, field.kind end
      end
      if best > 0 then
        row = row or {}
        row[#row + 1] = { word = word, score = best, kind = best_kind }
        df[word] = (df[word] or 0) + 1
      end
    end
    if row then per_entry[#per_entry + 1] = { item = item, row = row } end
  end

  local n = #index
  local rarity = {}
  for word, hits in pairs(df) do
    local r = n > 1 and math.log(n / hits) / math.log(n) or 1
    r = r < MIN_RARITY and MIN_RARITY or r
    rarity[word] = r * math.min(2, 1 + 0.5 * (count[word] - 1))
  end

  -- Pass 2: weighted sum per entry.
  local results = {}
  for _, pe in ipairs(per_entry) do
    local score, hits, hit_sub, hit_cat = 0, {}, false, false
    for _, h in ipairs(pe.row) do
      score = score + h.score * rarity[h.word]
      hits[h.word] = h.kind
      if h.kind == "sub" then hit_sub = true end
      if h.kind == "cat" then hit_cat = true end
    end
    if hit_sub and hit_cat then score = score + BOTH_BONUS end
    results[#results + 1] = { entry = pe.item.entry, score = score, hits = hits }
  end

  -- Ties broken by CatID so the order is stable between runs.
  local function better(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.entry.id < b.entry.id
  end
  table.sort(results, better)
  if #results == 0 then return {} end

  -- Small top category: every subcategory of it is kept (unhit ones score 0),
  -- the remaining slots go to the best of the rest.
  local keep = {}
  local top_cat = results[1].entry.cat
  local members = index.by_cat and index.by_cat[top_cat] or {}
  if #members <= EXPAND_MAX and #members <= limit then
    local scored = {}
    for _, r in ipairs(results) do
      if r.entry.cat == top_cat then scored[r.entry.id] = r end
    end
    for _, e in ipairs(members) do
      keep[#keep + 1] = scored[e.id] or { entry = e, score = 0, hits = {} }
    end
  end
  local kept = {}
  for _, k in ipairs(keep) do kept[k.entry.id] = true end
  for _, r in ipairs(results) do
    if #keep >= limit then break end
    if not kept[r.entry.id] then
      keep[#keep + 1] = r
      kept[r.entry.id] = true
    end
  end
  table.sort(keep, better)
  return keep
end

-- Looks a CatID up in the list (exact, case-sensitive as UCS spells it).
function M.find_catid(entries, catid)
  for i = 1, #entries do
    if entries[i].id == catid then return entries[i] end
  end
  return nil
end

return M
