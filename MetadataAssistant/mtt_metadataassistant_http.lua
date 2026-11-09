-- mtt_metadataassistant_http.lua
-- Non-blocking HTTP requests (POST, GET) through curl, so the UI never freezes while a local
-- model answers. Same job pattern as RSC_Plastic/mtt_plastic_lib.lua: the
-- command goes into a temporary shell script that writes its outputs and an
-- exit code to files; ExecProcess(-2) runs it in the background; poll(), called
-- from the defer loop, collects finished jobs.
-- macOS / Linux only for now (/bin/sh + curl).

local M = {}

M.is_windows = reaper.GetOS():find("Win") ~= nil

local job_seq = 0
local jobs = {}

local function read_all(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local c = f:read("a")
  f:close()
  return c
end

local function write_all(path, data)
  local f = io.open(path, "wb")
  if not f then return false end
  f:write(data)
  f:close()
  return true
end

local function file_exists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

local function temp_dir()
  local d = os.getenv("TMPDIR")
  if not d or d == "" then d = reaper.GetResourcePath() end
  return (d:gsub("/+$", ""))
end
M.temp_dir = temp_dir

-- A value inside a sh double-quoted string: \ " $ ` are escaped.
function M.sh_quote(s)
  return '"' .. tostring(s):gsub('[\\"$`]', "\\%0") .. '"'
end

-- Seconds to reach the server; past them the request fails at once.
M.CONNECT_TIMEOUT_S = 15

local function file_size(path)
  local f = io.open(path, "rb")
  if not f then return 0 end
  local size = f:seek("end") or 0
  f:close()
  return size
end

local function curl_path()
  if file_exists("/usr/bin/curl") then return "/usr/bin/curl" end
  return "curl"
end

-- The shell script text for one job (separate so it can be read in tests).
-- files: req, resp, code, err, done.
-- files.req = nil: no request body (GET).
-- stall_s: give up when the server sends nothing for this many seconds (curl's
-- low-speed limit: under 1 byte/s over stall_s); 0 or nil = never. There is no limit on
-- the total time: a streamed answer runs as long as tokens keep arriving, however
-- slow a local server is with several requests at once (a total limit cut answers
-- that were still arriving: "Operation timed out after 180001 milliseconds with
-- 597578 bytes received").
function M.build_script(url, headers, stall_s, files, curl, method)
  local lines = { "#!/bin/sh" }
  local cmd = { curl or curl_path(), "-sS", "--connect-timeout", tostring(M.CONNECT_TIMEOUT_S),
                "-X", method or "POST" }
  local stall = math.tointeger(tonumber(stall_s) or 0) or 0
  if stall > 0 then
    cmd[#cmd + 1] = "--speed-limit 1 --speed-time " .. tostring(stall)
  end
  for _, h in ipairs(headers or {}) do
    cmd[#cmd + 1] = "-H"
    cmd[#cmd + 1] = M.sh_quote(h)
  end
  if files.req then
    cmd[#cmd + 1] = "--data-binary"
    cmd[#cmd + 1] = "@" .. M.sh_quote(files.req)
  end
  cmd[#cmd + 1] = "-o"
  cmd[#cmd + 1] = M.sh_quote(files.resp)
  cmd[#cmd + 1] = "-w"
  cmd[#cmd + 1] = M.sh_quote("%{http_code}")
  cmd[#cmd + 1] = M.sh_quote(url)
  local run = table.concat(cmd, " ") .. " > " .. M.sh_quote(files.code) .. " 2> " .. M.sh_quote(files.err)
  if files.pid then
    -- curl runs in the background so its process id can be written to a file:
    -- cancel() kills it, which also tells the server to stop generating.
    lines[#lines + 1] = run .. " &"
    lines[#lines + 1] = "pid=$!"
    lines[#lines + 1] = "echo $pid > " .. M.sh_quote(files.pid)
    lines[#lines + 1] = "wait $pid"
  else
    lines[#lines + 1] = run
  end
  lines[#lines + 1] = "echo $? > " .. M.sh_quote(files.done)
  return table.concat(lines, "\n") .. "\n"
end

-- Starts a request. body = nil sends none. callback(result) runs from poll() with
--   { ok = bool, status = http status (number or nil), body = string, error = string or nil }
-- Returns the job id, or nil, err when the job could not start.
function M.request(method, url, headers, body, stall_s, callback)
  if M.is_windows then return nil, "Windows is not supported yet" end
  job_seq = job_seq + 1
  -- Time, a random tag and the sequence: two script instances started in the
  -- same second never share a job's files.
  local base = temp_dir() .. "/mtt_metadataassistant_" .. tostring(os.time()) .. "_"
    .. string.format("%08x", math.random(0, 0x7fffffff)) .. "_" .. tostring(job_seq)
  local files = {
    req = body and (base .. ".req.json") or nil, resp = base .. ".resp.json", code = base .. ".code",
    err = base .. ".err", done = base .. ".done", script = base .. ".sh", pid = base .. ".pid",
  }
  if body and not write_all(files.req, body) then return nil, "cannot write " .. files.req end
  if not write_all(files.script, M.build_script(url, headers, stall_s, files, nil, method)) then
    if files.req then os.remove(files.req) end
    return nil, "cannot write " .. files.script
  end
  local now = reaper.time_precise()
  -- Backstop for curl's own limit: the job also fails when its answer file has not
  -- grown for stall + 10 s. stall = 0: no limit.
  local job = {
    id = job_seq, files = files, callback = callback, t0 = now,
    stall = math.max(0, tonumber(stall_s) or 0), size = 0, changed_at = now, checked_at = now,
  }
  jobs[#jobs + 1] = job
  reaper.ExecProcess('/bin/sh "' .. files.script .. '"', -2)
  return job.id
end

function M.post(url, headers, body, stall_s, callback)
  return M.request("POST", url, headers, body, stall_s, callback)
end

function M.get(url, headers, stall_s, callback)
  return M.request("GET", url, headers, nil, stall_s, callback)
end

-- Deletes exactly the files this job created.
local function cleanup(job)
  for _, k in ipairs({ "req", "resp", "code", "err", "done", "script", "pid" }) do
    if job.files[k] then os.remove(job.files[k]) end
  end
end

-- Turns the job's files into the callback result.
function M.collect(files)
  local exit_code = tonumber((read_all(files.done) or ""):match("%-?%d+") or "") or -1
  local status = tonumber((read_all(files.code) or ""):match("%d+") or "")
  local body = read_all(files.resp) or ""
  local err = (read_all(files.err) or ""):gsub("%s+$", "")
  if exit_code ~= 0 then
    return { ok = false, status = status, body = body,
             error = err ~= "" and err or ("curl exit code " .. exit_code) }
  end
  if not status or status < 200 or status >= 300 then
    return { ok = false, status = status, body = body, error = "HTTP " .. tostring(status) }
  end
  return { ok = true, status = status, body = body }
end

-- Kills the curl process of a job, once its process id is known.
local function kill_job(job)
  if job.killed or not job.files.pid then return end
  local pid = tonumber((read_all(job.files.pid) or ""):match("%d+") or "")
  if pid and pid > 1 then
    job.killed = true
    reaper.ExecProcess('/bin/kill ' .. pid, -2)
  end
end

-- Stops a request: its curl process is killed (the server sees the connection
-- close and stops generating) and its callback never fires. The job stays in the
-- list until its script has finished, so that its files are cleaned up.
function M.cancel(id)
  for _, job in ipairs(jobs) do
    if job.id == id and not job.cancelled then
      job.cancelled = true
      job.callback = function() end
      kill_job(job)
    end
  end
end

-- Call every frame. Finished or stalled jobs fire their callback once.
function M.poll()
  local now = reaper.time_precise()
  for i = #jobs, 1, -1 do
    local job = jobs[i]
    if job.cancelled then kill_job(job) end -- the process id may have appeared after cancel()
    if file_exists(job.files.done) then
      table.remove(jobs, i)
      local result = M.collect(job.files)
      cleanup(job)
      job.callback(result)
    elseif job.stall > 0 and not job.cancelled and now - job.checked_at >= 1 then
      job.checked_at = now -- the answer file is looked at once a second
      local size = file_size(job.files.resp)
      if size ~= job.size then
        job.size, job.changed_at = size, now
      elseif now - job.changed_at > job.stall + 10 then
        table.remove(jobs, i)
        kill_job(job)
        cleanup(job)
        job.callback({ ok = false, error = string.format("nothing from the server for %d s", math.floor(now - job.changed_at)) })
      end
    end
  end
end

function M.pending()
  local n = 0
  for _, job in ipairs(jobs) do if not job.cancelled then n = n + 1 end end
  return n
end

-- Seconds since job `id` started, or nil when it is not pending (or was stopped).
function M.elapsed(id)
  for _, job in ipairs(jobs) do
    if job.id == id and not job.cancelled then return reaper.time_precise() - job.t0 end
  end
  return nil
end

-- For atexit: drops pending jobs and their files (the callback never fires).
function M.abandon_all()
  for i = #jobs, 1, -1 do
    kill_job(jobs[i])
    cleanup(jobs[i])
    jobs[i] = nil
  end
end

return M
