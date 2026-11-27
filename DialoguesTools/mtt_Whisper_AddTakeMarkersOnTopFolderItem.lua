-- mtt_Whisper_AddTakeMarkersOnTopFolderItem.lua
--
-- Transcribes speech with whisper.cpp and writes the text as take markers on every
-- item of the topmost folder track that overlaps the range: the text at the start
-- of the range, END_MARKER at its end.
--
-- Select one item, then run the script:
--   * an item on a track inside a folder (any depth) -> that item's audio is transcribed;
--   * the parent item on a folder track               -> the portions of the child items
--     (tracks inside that folder, any depth) under the range are mixed and transcribed;
--     the parent item's own take is never analyzed, it only receives the markers.
-- Range: the time selection when there is one, otherwise the selected item's bounds.
--
-- The audio is read straight from the takes (no glue, no temporary track, no copy and
-- paste), written as a 16 kHz mono WAV and passed to whisper-cli, which runs in the
-- background: REAPER stays responsive while it works. macOS / Linux only (/bin/sh).

-- ============================================================================
-- Configuration
-- ============================================================================
local WHISPER_DIR = "/Users/mattiapersico/whisper.cpp"
local WHISPER_BIN = WHISPER_DIR .. "/build/bin/whisper-cli"
-- "" = whisper-cli's own default model (resolved inside WHISPER_DIR), or a path,
-- e.g. WHISPER_DIR .. "/models/ggml-large-v3.bin"
local MODEL = ""
-- Spoken language: "auto" to detect it, or "it", "en", ...
local LANGUAGE = "auto"
local END_MARKER = "B"
-- Marker text when whisper hears no speech.
local BLANK_TEXT = " "
-- Longer ranges are refused: the audio is held in memory before it is written.
local MAX_RANGE_S = 1800
-- whisper-cli is stopped when it has not finished after this many seconds.
local MAX_WAIT_S = 600

local TITLE = "mtt_Whisper"
local RATE = 16000 -- whisper.cpp's native input: 16 kHz mono 16-bit PCM
local MIN_FRAMES = math.floor(RATE * 1.1) -- whisper.cpp skips input shorter than 1 s
local SAME_POS_S = 0.001 -- markers closer than this count as the same position

-- ============================================================================
-- Small helpers
-- ============================================================================
local function msg(text)
  reaper.ShowMessageBox(text, TITLE, 0)
end

-- A value inside a sh double-quoted string: \ " $ ` are escaped.
local function sh_quote(s)
  return '"' .. (tostring(s):gsub('[\\"$`]', "\\%0")) .. '"'
end

local function read_all(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local content = f:read("a")
  f:close()
  return content
end

local function write_all(path, data)
  local f = io.open(path, "wb")
  if not f then return false end
  local ok = f:write(data)
  local closed = f:close()
  return ok ~= nil and closed == true
end

local function temp_dir()
  local d = os.getenv("TMPDIR")
  if not d or d == "" then d = reaper.GetResourcePath() end
  return (d:gsub("/+$", ""))
end

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- ============================================================================
-- Pure logic (no reaper.* calls)
-- ============================================================================

-- whisper-cli stdout (-nt -np: one line per segment, no timestamps) -> one line of text.
local function clean_transcript(out)
  local lines = {}
  for line in out:gmatch("[^\r\n]+") do
    -- Logs go to stderr; these filters only catch a stray log line on stdout.
    if not line:match("^read_audio_data:") and not line:match("^main:")
        and not line:match("^whisper_") then
      lines[#lines + 1] = trim(line)
    end
  end
  local text = table.concat(lines, " "):gsub("%[BLANK_AUDIO%]", " "):gsub("%s+", " ")
  text = trim(text)
  if text == "" then return BLANK_TEXT end
  return text
end

-- 16-bit PCM mono WAV file contents from samples mono[1..n], padded with silence to
-- at least min_frames. A mix of several items can exceed full scale: it is scaled down.
local function wav_bytes(mono, n, rate, min_frames)
  local peak = 0
  for i = 1, n do
    local a = math.abs(mono[i])
    if a > peak then peak = a end
  end
  local gain = peak > 1 and 1 / peak or 1
  local total = math.max(n, min_frames or 0)
  local parts, ints, chunk = {}, {}, 1024
  local full_fmt = "<" .. string.rep("i2", chunk)
  for i = 1, total, chunk do
    local m = math.min(chunk, total - i + 1)
    for j = 1, m do
      local k = i + j - 1
      local v = k <= n and mono[k] * gain or 0
      ints[j] = math.floor(v * 32767 + 0.5)
    end
    local fmt = m == chunk and full_fmt or ("<" .. string.rep("i2", m))
    parts[#parts + 1] = string.pack(fmt, table.unpack(ints, 1, m))
  end
  local body = table.concat(parts)
  return "RIFF" .. string.pack("<I4", 36 + #body) .. "WAVE"
      .. "fmt " .. string.pack("<I4I2I2I4I4I2I2", 16, 1, 1, rate, rate * 2, 2, 16)
      .. "data" .. string.pack("<I4", #body) .. body
end

-- Marker positions (take source time) on an item at [pos, pos + len) with the given
-- start offset and playrate, for the range [r0, r1), clamped to the item.
-- Returns nil when the item does not overlap the range.
local function marker_positions(pos, len, startoffs, playrate, r0, r1)
  local a, b = math.max(r0, pos), math.min(r1, pos + len)
  if b <= a then return nil end
  return startoffs + (a - pos) * playrate, startoffs + (b - pos) * playrate
end

-- ============================================================================
-- Tracks and items
-- ============================================================================
local function is_folder(track)
  return reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1
end

local function top_ancestor(track)
  local top = track
  while true do
    local parent = reaper.GetParentTrack(top)
    if not parent then return top end
    top = parent
  end
end

local function is_inside(track, folder)
  local parent = reaper.GetParentTrack(track)
  while parent do
    if parent == folder then return true end
    parent = reaper.GetParentTrack(parent)
  end
  return false
end

local function item_bounds(item)
  local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  return pos, pos + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
end

-- The active take when it holds audio, with its channel count.
local function audio_take(item)
  local take = reaper.GetActiveTake(item)
  if not take or reaper.TakeIsMIDI(take) then return nil end
  local source = reaper.GetMediaItemTake_Source(take)
  if not source then return nil end
  local channels = reaper.GetMediaSourceNumChannels(source)
  if channels < 1 then return nil end
  return take, channels
end

-- Items of `track` overlapping [r0, r1).
local function items_in_range(track, r0, r1)
  local out = {}
  for i = 0, reaper.CountTrackMediaItems(track) - 1 do
    local item = reaper.GetTrackMediaItem(track, i)
    local a, b = item_bounds(item)
    if a < r1 and b > r0 then out[#out + 1] = item end
  end
  return out
end

-- Audio items on the tracks inside `folder` (any depth) overlapping [r0, r1): the
-- unmuted ones, or every one when all of them are muted.
local function child_sources(folder, r0, r1)
  local sources, muted = {}, {}
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    if is_inside(tr, folder) then
      for _, it in ipairs(items_in_range(tr, r0, r1)) do
        local tk, ch = audio_take(it)
        if tk then
          local list = reaper.GetMediaItemInfo_Value(it, "B_MUTE") == 0 and sources or muted
          list[#list + 1] = { item = it, take = tk, channels = ch }
        end
      end
    end
  end
  return #sources > 0 and sources or muted
end

-- ============================================================================
-- Audio extraction
-- ============================================================================

-- Adds the source's audio inside the range into mono[1..frames], where mono[1] is
-- the frame at r0. Returns true when the take returned audio, and a line saying
-- what was read (shown when no source gave audio).
local function add_source(src, r0, r1, mono, frames)
  local pos, stop = item_bounds(src.item)
  local _, take_name = reaper.GetSetMediaItemTakeInfo_String(src.take, "P_NAME", "", false)
  local a, b = math.max(r0, pos), math.min(r1, stop)
  if b <= a then return false, take_name .. ": outside the range" end
  -- A muted item is read unmuted (only reached when every child item in the range
  -- is muted); its mute is restored right after, before anything else runs.
  local was_muted = reaper.GetMediaItemInfo_Value(src.item, "B_MUTE") == 1
  if was_muted then reaper.SetMediaItemInfo_Value(src.item, "B_MUTE", 0) end
  local acc = reaper.CreateTakeAudioAccessor(src.take)
  if not acc then
    if was_muted then reaper.SetMediaItemInfo_Value(src.item, "B_MUTE", 1) end
    return false, take_name .. ": no audio accessor"
  end
  -- Take accessor time runs on the item timeline, from its start time.
  local acc_start = reaper.GetAudioAccessorStartTime(acc)
  local first = math.floor((a - r0) * RATE + 0.5) -- 0-based frame
  local last = math.min(frames, math.floor((b - r0) * RATE + 0.5)) -- exclusive
  local block, ch = 4096, src.channels
  local acc_end = reaper.GetAudioAccessorEndTime(acc)
  local buffer = reaper.new_array(block * ch)
  local got_audio = false
  local counts = { [1] = 0, [0] = 0, [-1] = 0 }
  local first_t
  for f = first, last - 1, block do
    local n = math.min(block, last - f)
    buffer.clear()
    local t = acc_start + (r0 + f / RATE - pos)
    first_t = first_t or t
    local status = reaper.GetAudioAccessorSamples(acc, RATE, ch, t, n, buffer)
    counts[status] = (counts[status] or 0) + 1
    if status == 1 then
      got_audio = true
      local s = buffer.table(1, n * ch)
      for i = 1, n do
        local sum, base = 0, (i - 1) * ch
        for c = 1, ch do sum = sum + s[base + c] end
        local k = f + i -- frame f + i - 1, 0-based
        mono[k] = mono[k] + sum / ch
      end
    end
  end
  reaper.DestroyAudioAccessor(acc)
  if was_muted then reaper.SetMediaItemInfo_Value(src.item, "B_MUTE", 1) end
  return got_audio, string.format(
    "%s: %s%d ch, accessor %.3f-%.3f s, read from %.3f s; blocks audio %d / silent %d / error %d",
    take_name, was_muted and "muted, " or "", ch, acc_start, acc_end, first_t or -1,
    counts[1], counts[0], counts[-1])
end

local function render_wav(path, sources, r0, r1)
  local frames = math.floor((r1 - r0) * RATE + 0.5)
  local mono = {}
  for i = 1, frames do mono[i] = 0 end
  local any, report = false, {}
  for _, src in ipairs(sources) do
    local got, line = add_source(src, r0, r1, mono, frames)
    if got then any = true end
    report[#report + 1] = line
  end
  if not any then
    return false, string.format("The takes returned no audio in %.3f-%.3f s.\n\n%s",
      r0, r1, table.concat(report, "\n"))
  end
  if not write_all(path, wav_bytes(mono, frames, RATE, MIN_FRAMES)) then
    return false, "Cannot write the temporary audio file:\n" .. path
  end
  return true
end

-- ============================================================================
-- Take markers
-- ============================================================================

-- Removes the markers at srcpos whose name passes `matches` (a previous run of the
-- same range), so running the script again replaces its markers instead of doubling them.
local function remove_markers_at(take, srcpos, matches)
  for i = reaper.GetNumTakeMarkers(take) - 1, 0, -1 do
    local p, name = reaper.GetTakeMarker(take, i)
    if p >= 0 and math.abs(p - srcpos) < SAME_POS_S and matches(name) then
      reaper.DeleteTakeMarker(take, i)
    end
  end
end

local function write_markers(top_track, r0, r1, text)
  if not reaper.ValidatePtr2(0, top_track, "MediaTrack*") then return 0 end
  local written = 0
  reaper.Undo_BeginBlock()
  for _, item in ipairs(items_in_range(top_track, r0, r1)) do
    local take = reaper.GetActiveTake(item)
    if take then
      local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
      local offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
      local rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
      local s0, s1 = marker_positions(pos, len, offs, rate, r0, r1)
      if s0 then
        -- The start marker of the next line may sit on this line's END_MARKER:
        -- each position only replaces markers of its own kind.
        remove_markers_at(take, s0, function(name) return name ~= END_MARKER end)
        reaper.SetTakeMarker(take, -1, text, s0)
        remove_markers_at(take, s1, function(name) return name == END_MARKER end)
        reaper.SetTakeMarker(take, -1, END_MARKER, s1)
        written = written + 1
      end
    end
  end
  reaper.UpdateArrange()
  reaper.Undo_EndBlock(TITLE .. ": transcription take markers", -1)
  return written
end

-- ============================================================================
-- whisper-cli job (background process, polled from defer)
-- ============================================================================
local job -- { files = {...}, t0 = start time, finished = bool, top = track, r0, r1 }

local function job_files(base)
  return {
    wav = base .. ".wav", out = base .. ".txt", err = base .. ".err", done = base .. ".done",
    pid = base .. ".pid", script = base .. ".sh", cancel = base .. ".cancel",
  }
end

-- Deletes exactly the files this job created.
local function remove_job_files(files)
  for _, k in ipairs({ "wav", "out", "err", "done", "pid", "script", "cancel" }) do
    os.remove(files[k])
  end
end

local function build_script(files)
  local q = {}
  for k, v in pairs(files) do q[k] = sh_quote(v) end
  local cmd = { sh_quote(WHISPER_BIN) }
  if MODEL ~= "" then cmd[#cmd + 1] = "-m " .. sh_quote(MODEL) end
  cmd[#cmd + 1] = "-f " .. q.wav
  cmd[#cmd + 1] = "-nt -np -l " .. sh_quote(LANGUAGE)
  return table.concat({
    "#!/bin/sh",
    -- whisper-cli resolves its default model path from the working directory.
    "cd " .. sh_quote(WHISPER_DIR) .. " || { echo 97 > " .. q.done .. "; exit 97; }",
    table.concat(cmd, " ") .. " > " .. q.out .. " 2> " .. q.err .. " &",
    "pid=$!",
    "echo $pid > " .. q.pid,
    "wait $pid",
    "echo $? > " .. q.done,
    -- The REAPER script was stopped meanwhile: nobody will collect these files.
    "if [ -f " .. q.cancel .. " ]; then rm -f " .. table.concat({
      q.wav, q.out, q.err, q.done, q.pid, q.cancel, q.script }, " ") .. "; fi",
  }, "\n") .. "\n"
end

local function stop_process(files)
  local pid = tonumber((read_all(files.pid) or ""):match("%d+") or "")
  if pid and pid > 1 then reaper.ExecProcess("/bin/kill " .. pid, -2) end
end

local function show_status(text)
  local x, y = reaper.GetMousePosition()
  reaper.TrackCtl_SetToolTip(text, x + 12, y + 12, true)
end

local function clear_status()
  reaper.TrackCtl_SetToolTip("", 0, 0, true)
end

local function last_lines(s, count)
  local lines = {}
  for line in (s or ""):gmatch("[^\r\n]+") do lines[#lines + 1] = line end
  return table.concat(lines, "\n", math.max(1, #lines - count + 1), #lines)
end

local function finish()
  job.finished = true
  clear_status()
  local files = job.files
  local code = tonumber((read_all(files.done) or ""):match("%-?%d+") or "")
  local out, err = read_all(files.out) or "", read_all(files.err) or ""
  remove_job_files(files)
  if code ~= 0 then
    msg("whisper-cli failed (exit code " .. tostring(code) .. ").\n\n" .. last_lines(err, 8))
    return
  end
  local text = clean_transcript(out)
  if write_markers(job.top, job.r0, job.r1, text) == 0 then
    msg("Transcription done, but no item of the top folder track overlaps the range any more:\n\n" .. text)
  end
end

local function poll()
  if job.finished then return end
  if tonumber((read_all(job.files.done) or ""):match("%-?%d+") or "") then
    finish()
    return
  end
  if reaper.time_precise() - job.t0 > MAX_WAIT_S then
    job.finished = true
    clear_status()
    -- The cancel flag goes first: the job's shell script checks it right after whisper-cli exits.
    write_all(job.files.cancel, "")
    stop_process(job.files)
    msg("whisper-cli did not finish within " .. MAX_WAIT_S .. " s and was stopped.")
    return
  end
  reaper.defer(poll)
end

-- Runs when the script ends for any reason, including "terminate" from REAPER.
local function on_exit()
  if job and not job.finished then
    clear_status()
    write_all(job.files.cancel, "")
    stop_process(job.files)
  end
end

-- ============================================================================
-- Main
-- ============================================================================
local function main()
  if reaper.GetOS():find("Win") then
    msg("Windows is not supported (the script runs whisper-cli through /bin/sh).")
    return
  end
  if not reaper.file_exists(WHISPER_BIN) then
    msg("whisper-cli not found:\n" .. WHISPER_BIN .. "\n\nSet WHISPER_DIR at the top of the script.")
    return
  end

  local item = reaper.GetSelectedMediaItem(0, 0)
  if not item then
    msg("Select the item to transcribe: an item inside a folder, or the parent item on the folder track.")
    return
  end
  local track = reaper.GetMediaItem_Track(item)

  -- The track that gets the markers: the topmost ancestor, or the selected item's
  -- own track when it is itself a top-level folder (parent item selected).
  local top = top_ancestor(track)
  if top == track and not is_folder(track) then
    msg("The item must be on a folder track or on a track inside a folder.")
    return
  end

  local r0, r1 = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  if r1 <= r0 then r0, r1 = item_bounds(item) end
  if r1 - r0 > MAX_RANGE_S then
    msg(string.format("The range is %.0f s long; the limit is %d s (MAX_RANGE_S).", r1 - r0, MAX_RANGE_S))
    return
  end
  local i0, i1 = item_bounds(item)
  if not is_folder(track) and (i1 <= r0 or i0 >= r1) then
    msg("The selected item is outside the time selection.")
    return
  end
  if #items_in_range(top, r0, r1) == 0 then
    msg("No item on the top folder track overlaps the range: there is nowhere to write the markers.")
    return
  end

  local base = temp_dir() .. "/mtt_whisper_" .. os.time() .. "_"
      .. string.format("%08x", math.random(0, 0x7fffffff))
  local files = job_files(base)

  -- Parent item on a folder track: the child portions under the range. Item inside
  -- a folder: that item.
  local sources
  if is_folder(track) then
    sources = child_sources(track, r0, r1)
    if #sources == 0 then
      msg("No child item with audio under the range: select a time selection over the child items.")
      return
    end
  else
    local take, channels = audio_take(item)
    if not take then
      msg("The selected item has no audio take (empty or MIDI).")
      return
    end
    sources = { { item = item, take = take, channels = channels } }
  end
  local ok, err = render_wav(files.wav, sources, r0, r1)
  if not ok then
    os.remove(files.wav)
    msg(err)
    return
  end
  if not write_all(files.script, build_script(files)) then
    os.remove(files.wav)
    msg("Cannot write the temporary script:\n" .. files.script)
    return
  end

  job = { files = files, t0 = reaper.time_precise(), finished = false, top = top, r0 = r0, r1 = r1 }
  reaper.atexit(on_exit)
  reaper.ExecProcess("/bin/sh " .. sh_quote(files.script), -2)
  show_status("Whisper: transcribing " .. string.format("%.1f", r1 - r0) .. " s...")
  reaper.defer(poll)
end

main()
