-- mtt_metadataassistant_audio.lua
-- Pre-FX item analysis. Take I/O is confined to survey_take below.
local M = {}
M.RATE = 16000 -- listening WAV
local ENV_WIN = 0.010
local function db(x) return 20 * math.log(math.max(x, 1e-12), 10) end

-- Use a real channel when folding the excerpt to mono would lose most of its energy.
function M.mono(sig, pause)
  if sig.channels == 1 then return sig[1] end
  local out, l, r = {}, sig[1], sig[2]
  local window = math.max(1, math.floor(sig.rate * ENV_WIN))
  local previous, fade = nil, math.max(1, math.floor(sig.rate * 0.002))
  for first = 1, #l, window do
    local last = math.min(#l, first + window - 1)
    local sum, left, right = 0, 0, 0
    for i = first, last do
      sum = sum + (l[i] + r[i])^2
      left, right = left + l[i]^2, right + r[i]^2
    end
    -- Equal-energy opposing channels can alternate in dominance from rounding.
    -- Prefer left on a near tie to prevent polarity flips in the listening clip.
    local mix = 0.5
    if sum < 0.2 * (left + right) then mix = left >= right*0.9 and 1 or 0 end
    for i = first, last do
      local w = mix + ((previous or mix) - mix) * math.max(0, 1 - (i-first+1)/fade)
      out[i] = l[i]*w + r[i]*(1-w)
    end
    previous = mix
    if pause then pause() end
  end
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

-- Keep levels in channel power. Opposite polarities carry just as much energy.
local function envelope(sig, step, pause)
  local frames, peak, energy, ll, rr, lr = {}, 0, 0, 0, 0, 0
  local left, right = sig[1], sig[2] or sig[1]
  for start = 1, #left, step do
    local last = math.min(start + step - 1, #left)
    local l2, r2, cross = 0, 0, 0
    for i = start, last do
      local l, r = left[i], right[i]
      peak = math.max(peak, math.abs(l), math.abs(r))
      l2, r2, cross = l2 + l*l, r2 + r*r, cross + l*r
    end
    local power, count = (l2 + r2) * 0.5, last - start + 1
    frames[#frames + 1] = { level = db(math.sqrt(power/count)), power = power, count = count,
      pan = (r2-l2) / math.max(r2+l2, 1e-24),
      side = (r2+l2-2*cross) / math.max(2*(r2+l2), 1e-24) }
    ll, rr, lr, energy = ll+l2, rr+r2, lr+cross, energy+power
    if pause then pause() end
  end
  return frames, peak, energy, ll, rr, lr
end

-- A Hann window centered on each envelope frame also covers short files and both ends.
-- Combine channel spectra in power; a narrow dominant peak is a resonance estimate.
local function spectrum(sig, frames, step, floor, identical, pause)
  local size = sig.rate > 24000 and 2048 or 1024
  local upper, window, band = size//2, {}, {}
  for i = 1, size do window[i] = 0.5 - 0.5 * math.cos(2*math.pi*(i-1)/(size-1)) end
  for k = 2, upper do
    band[k] = math.max(1, math.min(12, 1 + math.floor(math.log((k-1)*sig.rate/size/50, 2))))
  end
  local real, imag, powers = {}, {}, {}
  local weight, center, flatness = 0, 0, 0
  for j, f in ipairs(frames) do
    if f.level > floor then
      local start = (j-1)*step + f.count//2 - size//2 + 1
      for c = 1, identical and 1 or sig.channels do
        local samples = sig[c]
        for i = 1, size do real[i], imag[i] = (samples[start+i-1] or 0)*window[i], 0 end
        fft(real, imag, size)
        for k = 2, upper do
          local p = real[k]^2 + imag[k]^2
          powers[k] = c == 1 and p or powers[k] + p
        end
      end
      local bands = {}
      for i = 1, 12 do bands[i] = 0 end
      local total, logs, mag, weighted, best = 0, 0, 0, 0, 2
      for k = 2, upper do
        local p = powers[k]
        local a = math.sqrt(p)
        total, logs = total+p, logs+math.log(math.max(p,1e-30))
        mag, weighted = mag+a, weighted+a*(k-1)
        bands[band[k]] = bands[band[k]] + p
        if p > powers[best] then best = k end
      end
      if total > 0 then
        f.bands = bands
        local prev = frames[j-2]
        f.flux = 0
        for i, p in ipairs(bands) do
          bands[i] = p/total
          if prev and prev.bands then f.flux = f.flux + math.max(0,bands[i]-prev.bands[i]) end
        end
        f.centroid = weighted/mag*sig.rate/size
        f.flat = math.min(1, math.exp(logs/(upper-1)) / (total/(upper-1)))
        if best > 2 and best < upper and powers[best]/total > 0.24
          and (powers[best-1]+powers[best]+powers[best+1])/total > 0.68 then
          local a,b,c = math.log(powers[best-1]+1e-30), math.log(powers[best]+1e-30), math.log(powers[best+1]+1e-30)
          local delta = a-2*b+c
          f.tone = (best-1 + (delta < 0 and 0.5*(a-c)/delta or 0)) * sig.rate/size
        end
        weight, center, flatness = weight+f.power, center+f.power*f.centroid, flatness+f.power*f.flat
      end
    end
    if pause then pause() end
  end
  if weight > 0 then return center/weight, flatness/weight end
end

local function phase(frames, first, last)
  local power, pan, side, pitched, tones, tone_hz, bright, flat = 0,0,0,0,0,0,0,0
  local low, high = 0, 0
  for i = first, last do
    local f = frames[i]
    if f.centroid then
      power, pan, side = power+f.power, pan+f.power*f.pan, side+f.power*f.side
      bright, flat = bright+f.power*f.centroid, flat+f.power*f.flat
      low = low + f.power * (f.bands[1] + f.bands[2])
      for band = 7, 12 do high = high + f.power * f.bands[band] end
      if f.tone then
        pitched, tones, tone_hz = pitched+f.power, tones+1, tone_hz+f.tone*f.power
      end
    end
  end
  if power <= 0 then return {} end
  local band
  if low > power*0.65 then band = "low"
  elseif high > power*0.65 then band = "high"
  elseif power-low-high > power*0.65 then band = "mid" end
  return { band = band, pan = pan/power, side = side/power, center = bright/power, flat = flat/power,
    tone = tones >= 3 and pitched/power > 0.65 and tone_hz/pitched or nil }
end

local function summarize_event(frames, first, last, dt, duration)
  local peak = first
  for i = first+1, last do
    if frames[i].level > frames[peak].level then peak = i end
  end
  -- First crossing near the local maximum avoids calling a steady tone a slow attack.
  local rise = first
  while frames[rise].level < frames[peak].level-3 do rise = rise+1 end
  local third = math.max(1,(last-first+1)//3)
  local e = { start = (first-1)*dt, stop = math.min(duration,last*dt), attack = (rise-first)*dt,
    head = phase(frames,first,first+third-1), tail = phase(frames,last-third+1,last) }
  if last-first >= 5 then e.body = phase(frames,first+third,last-third) end
  -- Last crossing: a temporary dip followed by another loud passage is not a decay.
  local above = last
  while above > peak and frames[above].level <= frames[peak].level-12 do above = above-1 end
  if above < last then e.decay = (above+1-peak)*dt end
  return e
end

function M.analyze(sig, pause)
  local n, rate = #sig[1], sig.rate
  local m = { duration = n/rate, truncated = sig.truncated, channels = sig.channels, onsets = {}, events = {} }
  if n == 0 then m.silent = true; return m end
  local step = math.max(1, math.floor(rate*ENV_WIN+0.5))
  local dt = step/rate
  local frames, peak, energy, ll, rr, lr = envelope(sig,step,pause)
  m.peak_db, m.rms_db = db(peak), db(math.sqrt(energy/n))
  if peak == 0 then m.silent = true; return m end
  if sig.channels == 2 then
    m.correlation = ll*rr > 0 and lr/math.sqrt(ll*rr) or 0
    m.dual_mono = m.correlation > 0.999 and math.abs(db(math.sqrt(ll))-db(math.sqrt(rr))) < 0.5
  end
  local loudest = 1
  for i, f in ipairs(frames) do if f.level > frames[loudest].level then loudest = i end end
  local floor = math.max(frames[loudest].level-40,-100)
  if frames[loudest].level <= floor then m.below_floor = true; return m end
  m.centroid_hz, m.flatness = spectrum(sig,frames,step,floor,ll == rr and ll == lr,pause)
  local first, last, power, count = nil,nil,0,0
  local rising = false
  for i, f in ipairs(frames) do
    if f.level > floor then
      power, count = power+f.power,count+f.count
      local prev = frames[math.max(1,i-2)]
      local rise = f.level-prev.level > 8
      local renewed = (rise and not rising) or (f.flux or 0) > 0.48
      if not first or i-last > 2 or (i-first >= 3 and renewed and f.level > floor+9) then
        if first then m.events[#m.events+1] = summarize_event(frames,first,last,dt,m.duration) end
        first = i
        m.onsets[#m.onsets+1] = (i-1)*dt
      end
      last = i
      rising = rise or first == i
    end
  end
  m.events[#m.events+1] = summarize_event(frames,first,last,dt,m.duration)
  m.active_from, m.active_to = m.onsets[1], m.events[#m.events].stop
  m.active_seconds, m.peak_at = count/rate, (loudest-1)*dt
  m.active_rms_db = db(math.sqrt(power/count))
  m.crest_db, m.attack = m.peak_db-m.active_rms_db,m.events[1].attack
  return m
end

-- offset: seconds added to the event times (the segment's start on the item).
local function event_text(e, stereo, offset)
  offset = offset or 0
  local parts = { string.format("%.3f-%.3f s (attack %.0f ms", e.start+offset,e.stop+offset,e.attack*1000) }
  if e.decay then parts[#parts+1] = string.format("12 dB decay %.0f ms", e.decay*1000) end
  local h,t = e.head,e.tail
  if e.body and h.band and e.body.band and t.band and (h.band ~= e.body.band or e.body.band ~= t.band) then
    parts[#parts+1] = string.format("dominant bands attack/body/tail %s/%s/%s", h.band, e.body.band, t.band)
  end
  if t.tone then
    if h.tone and math.abs(math.log(t.tone/h.tone,2)) > 0.15 then
      parts[#parts+1] = string.format("resonance %.0f to %.0f Hz",h.tone,t.tone)
    else parts[#parts+1] = string.format("tonal tail near %.0f Hz",t.tone) end
  end
  if h.center and t.center and e.stop-e.start >= 0.06 then
    if t.center > h.center*1.5 then parts[#parts+1] = "brighter tail"
    elseif h.center > t.center*1.5 then parts[#parts+1] = "darker tail" end
    if h.flat > 0.25 and t.flat < 0.08 then parts[#parts+1] = "noisy attack, tonal tail" end
    if stereo then
      if t.pan-h.pan > 0.65 then parts[#parts+1] = "moves right"
      elseif h.pan-t.pan > 0.65 then parts[#parts+1] = "moves left" end
      if t.side-h.side > 0.22 then parts[#parts+1] = "wider tail"
      elseif h.side-t.side > 0.22 then parts[#parts+1] = "narrower tail" end
    end
  end
  return table.concat(parts,", ")..")"
end

-- offset: where the analyzed segment starts on the item; event times are given on
-- the item's timeline.
function M.describe(m, offset)
  if not m then return nil end
  if m.silent then return "silent" end
  if m.below_floor then return string.format("very quiet (peak %.1f dBFS), no measurable event",m.peak_db) end
  local parts = { string.format("peak %.1f dBFS, RMS %.1f dBFS, active RMS %.1f dBFS, active crest %.1f dB, active %.2f of %.2f s",
    m.peak_db,m.rms_db,m.active_rms_db,m.crest_db,m.active_seconds,m.duration) }
  if m.centroid_hz then parts[#parts+1] = string.format("spectral centroid %.1f kHz, flatness %.2f",m.centroid_hz/1000,m.flatness) end
  if m.dual_mono then parts[#parts+1] = "dual mono"
  elseif m.correlation then parts[#parts+1] = string.format("stereo, L/R correlation %.2f",m.correlation) end
  local rhythm = ""
  if #m.events >= 3 then
    local mean = (m.onsets[#m.events]-m.onsets[1])/(#m.events-1)
    local sum = 0
    for i = 2,#m.events do sum = sum + (m.onsets[i]-m.onsets[i-1]-mean)^2 end
    rhythm = math.sqrt(sum/(#m.events-1))/mean < 0.15 and ", evenly spaced" or ", unevenly spaced"
  end
  parts[#parts+1] = string.format("%d estimated event%s%s (item times)",#m.events,#m.events == 1 and "" or "s",rhythm)
  for i = 1,math.min(4,#m.events) do parts[#parts+1] = event_text(m.events[i],m.channels == 2,offset) end
  if m.truncated then parts[#parts+1] = string.format("first %.0f s analyzed",m.duration) end
  return table.concat(parts,"; ")
end

-- Listening excerpts from one coarse power value per 100 ms of a long take. If
-- activity fits inside the budget (seconds sent to the model), keep it contiguous.
-- Otherwise choose up to three chronological excerpts.
local function excerpts(bins, span, total, budget, pause)
  local maximum, first, last = 0, nil, nil
  for _, p in ipairs(bins) do maximum = math.max(maximum,p) end
  local gate = maximum*1e-4
  for i, p in ipairs(bins) do
    if p > gate then first, last = first or i,i end
  end
  if not first then return {{ start = 0, length = budget }} end
  local begin, finish = (first-1)*span, math.min(total,last*span)
  if finish-begin <= budget then
    return {{ start = math.max(0,math.min(total-budget,(begin+finish-budget)/2)), length = budget }}
  end
  local groups = {}
  for part = 1,3 do
    local a = first + math.floor((last-first+1)*(part-1)/3)
    local b = first + math.floor((last-first+1)*part/3)-1
    local loud, active = a,0
    for i = a,b do
      if bins[i] > bins[loud] then loud = i end
      if bins[i] > gate then active = active+1 end
    end
    if active > 0 then
      local chosen = loud
      if active >= (b-a+1)*0.7 then
        -- For sustained beds choose a typical energy near the middle, so a
        -- passing impact does not represent an entire third of an ambience.
        local mean = 0
        for i = a,b do mean = mean+bins[i] end
        mean = mean/(b-a+1)
        if bins[loud] < mean*10 then
          local best = math.huge
          for i = a,b do
            if bins[i] > gate then
              local cost = math.abs(math.log(bins[i]/mean)) + math.abs(2*i-a-b)/(b-a+1)
              if cost < best then best,chosen = cost,i end
            end
          end
        end
      end
      groups[#groups+1] = (chosen-0.5)*span
    end
    if pause then pause() end
  end
  local result, length = {},budget/#groups
  for _, center in ipairs(groups) do
    local start = math.max(0,math.min(total-length,center-length/2))
    local previous = result[#result]
    if previous and start <= previous.start + previous.length then
      previous.length = start+length-previous.start
    else result[#result+1] = {start = start,length = length} end
  end
  return result
end

local function read_blocks(acc, t0, rate, channels, count, visit, pause)
  local block = 4096
  local buffer = reaper.new_array(block*channels)
  for pos = 0,count-1,block do
    local n = math.min(block,count-pos)
    buffer.clear()
    local status = reaper.GetAudioAccessorSamples(acc,rate,channels,t0+pos/rate,n,buffer)
    if status == -1 then error("Could not read the take audio.",0) end
    visit(buffer.table(1,n*channels),n,pos)
    if pause then pause() end
  end
end

local function read_signal(acc, start, rate, channels, n, pause)
  local sig = { rate = rate, channels = channels, [1] = {}, [2] = channels == 2 and {} or nil }
  read_blocks(acc,start,rate,channels,n,function(samples, count, pos)
    for i = 1,count do
      for c = 1,channels do sig[c][pos+i] = samples[(i-1)*channels+c] end
    end
  end,pause)
  return sig
end

-- The detailed analysis covers the whole item, in consecutive equal segments of
-- at most SEGMENT_S seconds: only one segment's samples are held at a time (30 s
-- of 48 kHz stereo is about 2.9 M numbers), and each segment gets its own line.
M.SEGMENT_S = 30
-- Lines sent to the model at most; a longer item shows this many segments, evenly
-- spaced, and says so (every segment is still analyzed).
M.MAX_SEGMENT_LINES = 12

-- Indices 1..n reduced to at most max, evenly spaced, first and last kept. Pure.
function M.spread(n, max)
  local out = {}
  if n <= max then
    for i = 1, n do out[i] = i end
    return out
  end
  for k = 1, max do out[k] = 1 + math.floor((k - 1) * (n - 1) / (max - 1) + 0.5) end
  return out
end

-- listen_s: seconds of audio sent to the model (only with listen); up to three
-- excerpts where the item is active when the item is longer. The measurements
-- do not depend on it.
function M.survey_take(take, channels, source_rate, listen_s, listen, pause)
  local acc = assert(reaper.CreateTakeAudioAccessor(take),"Could not open the take audio.")
  local guard <close> = setmetatable({}, {__close = function() reaper.DestroyAudioAccessor(acc) end})
  local t0 = reaper.GetAudioAccessorStartTime(acc)
  local total = math.max(0,reaper.GetAudioAccessorEndTime(acc)-t0)
  local rate = math.floor(math.min(48000,(source_rate or 0) > 0 and source_rate or 48000)+0.5)
  local check = pause and function()
    if pause() and reaper.AudioAccessorStateChanged(acc) then error("Take audio changed during analysis. Analyze again.",0) end
  end

  -- Measurements: every segment of the item.
  local count = math.max(1, math.ceil(total / M.SEGMENT_S - 1e-9))
  local length = total / count
  local lines, peak, energy = {}, nil, 0
  for k = 1, count do
    local start = (k-1)*length
    local first, last = math.floor(start*rate+0.5), math.floor(k*length*rate+0.5)
    local m = M.analyze(read_signal(acc,t0+start,rate,channels,last-first,check),check)
    lines[k] = string.format("Item %.3f-%.3f s: %s",start,start+length,M.describe(m,start))
    if m.peak_db then
      peak = math.max(peak or m.peak_db, m.peak_db)
      energy = energy + 10^(m.rms_db/10)*m.duration
    end
  end
  local summary = {}
  if count > 1 then
    summary[1] = string.format("Whole item %.2f s, analyzed in %d segments of %.1f s, peak %.1f dBFS, RMS %.1f dBFS. Event times are on the item timeline; an event crossing a segment boundary is split.",
      total,count,length,peak or -240,10*math.log(math.max(energy/math.max(total,1e-9),1e-24),10))
  end
  local shown = M.spread(count, M.MAX_SEGMENT_LINES)
  if #shown < count then
    summary[#summary+1] = string.format("%d of the %d segments shown, evenly spaced.",#shown,count)
  end
  for _, k in ipairs(shown) do summary[#summary+1] = lines[k] end

  if not listen then return table.concat(summary,"\n") end
  -- Listening clip: the whole item when it fits, else excerpts where it is active,
  -- found on 100 ms power bins of the whole item.
  local ranges = {{start = 0,length = total}}
  if total > listen_s then
    local bins, in_bin, bin_sum = {},0,0
    local bin_size, frames = math.max(1,math.floor(rate/10)),math.ceil(total*rate)
    read_blocks(acc,t0,rate,channels,frames,function(samples,n)
      for i = 1,n do
        local l = samples[(i-1)*channels+1]
        local r = samples[i*channels]
        bin_sum,in_bin = bin_sum+(l*l+r*r)*0.5,in_bin+1
        if in_bin == bin_size then
          bins[#bins+1] = bin_sum/in_bin
          bin_sum,in_bin = 0,0
        end
      end
    end,check)
    if in_bin > 0 then bins[#bins+1] = bin_sum/in_bin end
    ranges = excerpts(bins,bin_size/rate,total,listen_s,check)
  end
  local clip, map, clip_frames = {},{},0
  for _,range in ipairs(ranges) do
    local proxy = read_signal(acc,t0+range.start,M.RATE,channels,math.floor(range.length*M.RATE+0.5),check)
    local mono = M.mono(proxy,check)
    map[#map+1] = string.format("clip %.3f-%.3f s = item %.3f-%.3f s",clip_frames/M.RATE,(clip_frames+#mono)/M.RATE,range.start,range.start+range.length)
    for i,v in ipairs(mono) do clip[clip_frames+i] = v end
    clip_frames = clip_frames+#mono
  end
  return table.concat(summary,"\n"),M.wav_bytes(clip,M.RATE,check),table.concat(map,"; ")
end

-- 16-bit PCM mono WAV file contents.
function M.wav_bytes(samples, rate, pause)
  local n = #samples
  local data = {}
  for i = 1, n do
    local v = samples[i]
    if v > 1 then v = 1 elseif v < -1 then v = -1 end
    data[i] = string.pack("<i2", math.floor(v * 32767 + 0.5))
    if pause and i % 4096 == 0 then pause() end
  end
  local body = table.concat(data)
  return "RIFF" .. string.pack("<I4", 36 + #body) .. "WAVE"
      .. "fmt " .. string.pack("<I4I2I2I4I4I2I2", 16, 1, 1, rate, rate * 2, 2, 16)
      .. "data" .. string.pack("<I4", #body) .. body
end

function M.write_file(path, bytes)
  local f = io.open(path, "wb")
  if not f then return false end
  local written = f:write(bytes)
  local closed = f:close()
  if written and closed then return true end
  os.remove(path)
  return false
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
function M.base64(s, pause)
  local out = {}
  for i = 1, #s, 3 do
    if pause and (i-1) % 12288 == 0 then pause() end
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
