-- mtt_metadataassistant_audio.lua
-- The item's audio: read once (take audio accessor, pre-FX), measured with
-- plain DSP (levels, onsets, envelope, stereo, spectral centroid and flatness)
-- for every model, and written as a short mono WAV clip for a model that
-- hears audio. Everything except read_take() is pure Lua.

local M = {}

M.RATE = 16000      -- analysis and clip rate: what audio models such as Qwen3-Omni hear
local BLOCK = 4096  -- frames per accessor read
local FFT_N = 1024  -- spectral frame
local FFT_HOP = 2048
local ENV_WIN = 0.010

local function db(x) return 20 * math.log(x > 1e-12 and x or 1e-12, 10) end

-- Reads up to max_s seconds of the take, `channels` (1 or 2) channels at RATE.
-- Returns { rate, channels, [1] = samples, [2] = samples or nil, duration,
-- total, truncated }.
function M.read_take(take, channels, max_s)
  local acc = reaper.CreateTakeAudioAccessor(take)
  local t0 = reaper.GetAudioAccessorStartTime(acc)
  local t1 = reaper.GetAudioAccessorEndTime(acc)
  local total = t1 - t0
  local dur = math.min(total, max_s)
  local frames = math.floor(dur * M.RATE)
  local sig = { rate = M.RATE, channels = channels, duration = dur, total = total,
                truncated = total > max_s + 0.01 }
  for c = 1, channels do sig[c] = {} end
  local buf = reaper.new_array(BLOCK * channels)
  local pos = 0
  while pos < frames do
    local n = math.min(BLOCK, frames - pos)
    buf.clear()
    reaper.GetAudioAccessorSamples(acc, M.RATE, channels, t0 + pos / M.RATE, n, buf)
    local t = buf.table(1, n * channels)
    for i = 0, n - 1 do
      for c = 1, channels do sig[c][pos + i + 1] = t[i * channels + c] end
    end
    pos = pos + n
  end
  reaper.DestroyAudioAccessor(acc)
  return sig
end

-- Mono mix of a signal table.
function M.mono(sig)
  if sig.channels == 1 then return sig[1] end
  local out, l, r = {}, sig[1], sig[2]
  for i = 1, #l do out[i] = 0.5 * (l[i] + r[i]) end
  return out
end

-- In-place iterative radix-2 FFT on re/im arrays (1-based, length power of 2).
local function fft(re, im, n)
  -- Bit-reversal permutation (0-based j, arrays 1-based).
  local j = 0
  for i = 1, n - 1 do
    local bit = n >> 1
    while j & bit ~= 0 do
      j = j ~ bit
      bit = bit >> 1
    end
    j = j ~ bit
    if i < j then
      re[i + 1], re[j + 1] = re[j + 1], re[i + 1]
      im[i + 1], im[j + 1] = im[j + 1], im[i + 1]
    end
  end
  local len = 2
  while len <= n do
    local ang = -2 * math.pi / len
    local wr, wi = math.cos(ang), math.sin(ang)
    for start = 1, n, len do
      local cr, ci = 1, 0
      for k = 0, len // 2 - 1 do
        local a, b = start + k, start + k + len // 2
        local tr = re[b] * cr - im[b] * ci
        local ti = re[b] * ci + im[b] * cr
        re[b], im[b] = re[a] - tr, im[a] - ti
        re[a], im[a] = re[a] + tr, im[a] + ti
        cr, ci = cr * wr - ci * wi, cr * wi + ci * wr
      end
    end
    len = len * 2
  end
end
M._fft = fft

-- Measures of a signal table. Thresholds relative to the loudest 10 ms window.
function M.analyze(sig)
  local rate = sig.rate
  local x = M.mono(sig)
  local n = #x
  local m = { duration = sig.duration or n / rate, truncated = sig.truncated, channels = sig.channels }
  if n == 0 then m.silent = true; return m end

  local peak, sum2 = 0, 0
  for c = 1, sig.channels do
    for i = 1, #sig[c] do local a = math.abs(sig[c][i]); if a > peak then peak = a end end
  end
  for i = 1, n do sum2 = sum2 + x[i] * x[i] end
  m.peak_db = db(peak)
  m.rms_db = db(math.sqrt(sum2 / n))
  m.crest_db = m.peak_db - m.rms_db
  if peak < 1e-5 then m.silent = true; return m end

  -- Stereo: identical channels = dual mono.
  if sig.channels == 2 then
    local ll, rr, lr = 0, 0, 0
    local l, r = sig[1], sig[2]
    for i = 1, #l do ll = ll + l[i] * l[i]; rr = rr + r[i] * r[i]; lr = lr + l[i] * r[i] end
    local corr = (ll > 0 and rr > 0) and lr / math.sqrt(ll * rr) or 0
    m.correlation = corr
    m.dual_mono = corr > 0.999 and math.abs(db(math.sqrt(ll)) - db(math.sqrt(rr))) < 0.5
  end

  -- 10 ms RMS envelope.
  local w = math.max(1, math.floor(ENV_WIN * rate))
  local env = {}
  for s = 1, n, w do
    local acc, cnt = 0, 0
    for i = s, math.min(n, s + w - 1) do acc = acc + x[i] * x[i]; cnt = cnt + 1 end
    env[#env + 1] = db(math.sqrt(acc / cnt))
  end
  local env_peak, env_peak_i = -999, 1
  for i, v in ipairs(env) do if v > env_peak then env_peak, env_peak_i = v, i end end
  local floor = math.max(env_peak - 40, -70)
  local first, last = nil, nil
  for i, v in ipairs(env) do
    if v > floor then first = first or i; last = i end
  end
  m.active_from = (first - 1) * ENV_WIN
  m.active_to = last * ENV_WIN
  m.peak_at = (env_peak_i - 1) * ENV_WIN
  m.attack = m.peak_at - m.active_from

  -- Onsets: a rise of more than 9 dB within 20 ms, above the floor, 80 ms apart.
  local onsets, last_on = {}, -1
  for i = 3, #env do
    if env[i] - env[i - 2] > 9 and env[i] > floor + 10 then
      local t = (i - 1) * ENV_WIN
      if last_on < 0 or t - last_on > 0.08 then onsets[#onsets + 1] = t; last_on = t end
    end
  end
  m.onsets = onsets

  -- Spectrum: energy-weighted centroid and flatness of the frames above the floor.
  local wsum, csum, fsum = 0, 0, 0
  local hann = {}
  for i = 1, FFT_N do hann[i] = 0.5 * (1 - math.cos(2 * math.pi * (i - 1) / (FFT_N - 1))) end
  local half = FFT_N // 2
  for s = 1, n - FFT_N + 1, FFT_HOP do
    local re, im, e = {}, {}, 0
    for i = 1, FFT_N do
      local v = x[s + i - 1]
      e = e + v * v
      re[i] = v * hann[i]; im[i] = 0
    end
    if db(math.sqrt(e / FFT_N)) > floor then
      fft(re, im, FFT_N)
      local num, den, logsum, psum = 0, 0, 0, 0
      for k = 2, half do
        local p = re[k] * re[k] + im[k] * im[k]
        local mag = math.sqrt(p)
        local f = (k - 1) * rate / FFT_N
        num = num + f * mag; den = den + mag
        logsum = logsum + math.log(p + 1e-20); psum = psum + p
      end
      if den > 0 then
        local bins = half - 1
        local flat = math.exp(logsum / bins) / (psum / bins)
        csum = csum + e * (num / den)
        fsum = fsum + e * flat
        wsum = wsum + e
      end
    end
  end
  if wsum > 0 then
    m.centroid_hz = csum / wsum
    m.flatness = fsum / wsum
  end
  return m
end

local function fmt_list(t, max)
  local out = {}
  for i = 1, math.min(#t, max) do out[i] = string.format("%.2f", t[i]) end
  local s = table.concat(out, ", ")
  if #t > max then s = s .. string.format(" (+%d more)", #t - max) end
  return s
end

-- One line of plain words for the model and the UI.
function M.describe(m)
  if not m then return nil end
  if m.silent then return "silent" end
  local parts = {}
  local dyn = m.crest_db > 20 and "very impulsive" or m.crest_db > 14 and "transient"
           or m.crest_db < 8 and "steady" or "moderate dynamics"
  parts[#parts + 1] = string.format("peak %.1f dBFS, RMS %.1f dBFS, crest %.0f dB (%s)",
    m.peak_db, m.rms_db, m.crest_db, dyn)
  if #m.onsets > 0 then
    parts[#parts + 1] = string.format("%d onset%s at %s s", #m.onsets, #m.onsets == 1 and "" or "s",
      fmt_list(m.onsets, 8))
  else
    parts[#parts + 1] = "no clear onsets"
  end
  parts[#parts + 1] = string.format("sound from %.2f to %.2f s, loudest at %.2f s", m.active_from, m.active_to, m.peak_at)
  if m.dual_mono then
    parts[#parts + 1] = "dual mono (left = right)"
  elseif m.correlation then
    parts[#parts + 1] = string.format("stereo, L/R correlation %.2f", m.correlation)
  end
  if m.centroid_hz then
    local b = m.centroid_hz < 1000 and "dark" or m.centroid_hz < 3000 and "balanced" or "bright"
    local t = m.flatness > 0.3 and "noisy" or m.flatness < 0.05 and "tonal" or "mixed tonal/noisy"
    parts[#parts + 1] = string.format("spectral centroid %.1f kHz (%s), flatness %.2f (%s)",
      m.centroid_hz / 1000, b, m.flatness, t)
  end
  local s = table.concat(parts, "; ")
  if m.truncated then s = s .. string.format("; first %.0f s analyzed", m.duration) end
  return s
end

-- The first n samples of a list (the whole list when it is shorter).
function M.head(samples, n)
  if #samples <= n then return samples end
  local out = {}
  for i = 1, n do out[i] = samples[i] end
  return out
end

-- 16-bit PCM mono WAV file contents.
function M.wav_bytes(samples, rate)
  local n = #samples
  local data = {}
  for i = 1, n do
    local v = samples[i]
    if v > 1 then v = 1 elseif v < -1 then v = -1 end
    data[i] = string.pack("<i2", math.floor(v * 32767 + 0.5))
  end
  local body = table.concat(data)
  return "RIFF" .. string.pack("<I4", 36 + #body) .. "WAVE"
      .. "fmt " .. string.pack("<I4I2I2I4I4I2I2", 16, 1, 1, rate, rate * 2, 2, 16)
      .. "data" .. string.pack("<I4", #body) .. body
end

function M.write_file(path, bytes)
  local f = io.open(path, "wb")
  if not f then return false end
  f:write(bytes)
  f:close()
  return true
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
function M.base64(s)
  local out = {}
  for i = 1, #s, 3 do
    local a, b, c = s:byte(i, i + 2)
    local v = (a << 16) | ((b or 0) << 8) | (c or 0)
    local q = {}
    for k = 3, 0, -1 do q[#q + 1] = B64:sub(((v >> (6 * k)) & 63) + 1, ((v >> (6 * k)) & 63) + 1) end
    if not b then q[3], q[4] = "=", "=" elseif not c then q[4] = "=" end
    out[#out + 1] = table.concat(q)
  end
  return table.concat(out)
end

return M
