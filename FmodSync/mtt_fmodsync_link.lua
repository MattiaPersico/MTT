-- mtt_fmodsync_link.lua
-- The connection to FMOD Studio's scripting terminal: TCP on 127.0.0.1:3663.
-- FMOD Studio evaluates whatever it receives as JavaScript and sends back text
-- (on connect it sends "log(): Connected to FMOD Studio on ..."; what
-- studio.system.print writes comes back too). Nothing in that text marks where
-- one answer ends, so every request is wrapped (M.wrap) to print its value between two
-- markers carrying the request id, URI-encoded so that quotes or escaping added
-- by the terminal cannot break it. Requests are asynchronous: M.request queues a
-- callback, M.poll (called every frame from the defer loop) reads what arrived
-- without blocking and calls the callbacks whose answer is complete.

local M = {}

M.HOST = '127.0.0.1'
M.PORT = 3663
M.TIMEOUT = 15            -- seconds a request may wait for its answer
M.status = 'offline'      -- 'offline' | 'online'
M.error = nil             -- last connection error, for the UI
M.other = ''              -- text received outside any answer (last 4000 chars), for debugging

local core              -- LuaSocket's socket.core, given by M.init
local sock
local buf = ''
local next_id = 1
local pending = {}      -- id -> { cb = function(value, err), t = time sent }

function M.init(socket_core)
  core = socket_core
end

-- URI-decoding of the payload. The JavaScript side escapes (encodeURIComponent)
-- only what is not printable ASCII, plus "@" (the markers) and "%": the rest
-- stays as it is, so the answer printed in FMOD's console stays short. Pure.
function M.uri_decode(s)
  return (s:gsub('%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end))
end

-- The JavaScript sent for request `id`: `body` is the body of a function that
-- returns the value wanted. The markers are split in the source ("@@MTT" + "FS")
-- so that an echo of the request can never be mistaken for its answer. Newlines
-- become spaces: the terminal is not documented to accept multi-line input, so
-- bodies must not use // comments. Pure.
function M.wrap(id, body)
  return (('(function(){var r;try{r={ok:true,v:(function(){' .. body .. '})()};}'
    .. 'catch(e){r={ok:false,err:String(e)};}'
    .. 'studio.system.print("@@MTT"+"FS' .. id .. '@@"+JSON.stringify(r).replace(/[\\uD800-\\uDBFF][\\uDC00-\\uDFFF]|[^ -$&-?A-~]/g,encodeURIComponent)+"@@MTT"+"END' .. id .. '@@");})();')
    :gsub('[\r\n]+', ' '))
end

-- Takes every complete answer out of `text`. Returns the answers as
-- { {id = n, payload = decoded json text}, ... }, the text left to wait for more
-- data, and the text that was not part of any answer. Pure.
function M.extract(text)
  local answers, other = {}, {}
  while true do
    local s, e, id, payload = text:find('@@MTTFS(%d+)@@(.-)@@MTTEND%1@@')
    if not s then break end
    other[#other + 1] = text:sub(1, s - 1)
    answers[#answers + 1] = { id = tonumber(id), payload = M.uri_decode(payload) }
    text = text:sub(e + 1)
  end
  -- Keep only from an unfinished answer on; the rest is not an answer.
  local open = text:find('@@MTTFS%d+@@')
  if open then
    other[#other + 1] = text:sub(1, open - 1)
    text = text:sub(open)
  else
    other[#other + 1] = text
    text = ''
  end
  return answers, text, table.concat(other)
end

function M.close(reason)
  if sock then sock:close() end
  sock, buf = nil, ''
  local waiting = pending
  pending = {}
  M.status = 'offline'
  if reason then M.error = reason end
  for _, p in pairs(waiting) do p.cb(nil, reason or 'connection closed') end
end

-- Blocks for at most 0.5 s: called on a button press, never every frame.
-- A refused connection on localhost returns at once.
-- Tries IPv4 first, then IPv6 (::1), in case FMOD Studio listens on only one.
function M.connect()
  M.close()
  local tries = { { core.tcp, M.HOST } }
  if core.tcp6 then tries[#tries + 1] = { core.tcp6, '::1' } end
  local errs = {}
  for _, t in ipairs(tries) do
    local s = t[1]()
    if s then
      s:settimeout(0.5)
      local ok, err = s:connect(t[2], M.PORT)
      if ok then
        s:settimeout(0)
        sock, M.status, M.error = s, 'online', nil
        M.host_used = t[2]
        return true
      end
      s:close()
      errs[#errs + 1] = t[2] .. ': ' .. tostring(err)
    end
  end
  M.error = 'FMOD Studio does not answer on port ' .. M.PORT .. ' (' .. table.concat(errs, ', ') .. ').'
    .. ' Is "Enable Script Server" on in FMOD Preferences > Interface (needs a restart of FMOD)?'
  return false
end

-- cb(value, err): value is what the body returned (decoded from JSON), err a
-- string when the JavaScript threw, the connection dropped or the time ran out.
function M.request(body, cb)
  if not sock then cb(nil, 'FMOD Studio is not connected'); return end
  local id = next_id
  next_id = next_id + 1
  local code = M.wrap(id, body)
  sock:settimeout(2) -- a large request may not fit the send buffer at once
  -- The newline ends the input: a terminal that evaluates line by line waits for it.
  local sent, err = sock:send(code .. '\n')
  sock:settimeout(0)
  if not sent then M.close('send failed: ' .. tostring(err)); cb(nil, M.error); return end
  pending[id] = { cb = cb, t = reaper.time_precise() }
end

-- For the UI: text outside answers, then what waits for the end of an answer.
function M.raw()
  if buf == '' then return M.other end
  return M.other .. '\n[unfinished] ' .. buf:sub(1, 4000)
end

function M.busy()
  return next(pending) ~= nil
end

-- Called every frame. Reads what arrived, never waits.
local last_poll

function M.poll(json)
  if not sock then return end
  -- REAPER does not call us while it renders: that time does not count
  -- against the requests waiting for an answer.
  local now = reaper.time_precise()
  if last_poll and now - last_poll > 1 then
    for _, p in pairs(pending) do p.t = p.t + (now - last_poll) end
  end
  last_poll = now
  -- Everything that arrived, not just one chunk: a long answer may come in many.
  local err
  for _ = 1, 64 do
    local data, e, partial = sock:receive(65536)
    local chunk = data or partial
    if chunk and chunk ~= '' then buf = buf .. chunk end
    err = e
    if not data then break end
  end

  local answers, rest, other = M.extract(buf)
  buf = rest
  if other ~= '' then M.other = (M.other .. other):sub(-4000) end
  for _, a in ipairs(answers) do
    local p = pending[a.id]
    if p then
      pending[a.id] = nil
      local r = json.decode(a.payload)
      if type(r) ~= 'table' then p.cb(nil, 'unreadable answer: ' .. a.payload:sub(1, 200))
      elseif r.ok then p.cb(r.v, nil)
      else p.cb(nil, tostring(r.err)) end
    end
  end

  -- Expired ones are collected first: a callback may send a new request, and
  -- adding keys to `pending` while pairs() walks it is undefined in Lua.
  local expired = {}
  for id, p in pairs(pending) do
    if now - p.t > M.TIMEOUT then expired[#expired + 1] = id end
  end
  for _, id in ipairs(expired) do
    local p = pending[id]
    pending[id] = nil
    p.cb(nil, 'no answer from FMOD Studio after ' .. M.TIMEOUT .. ' s')
  end

  if err == 'closed' then M.close('FMOD Studio closed the connection') end
end

return M
