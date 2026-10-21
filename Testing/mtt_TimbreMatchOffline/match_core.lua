-- MTT Timbre Match Offline 0.1.0. Pure profile math; no host dependencies.
local M = {}
local log10 = function(x) return math.log(x) / math.log(10) end
local clamp = function(x, a, b) return math.max(a, math.min(b, x)) end
M.clamp = clamp

function M.settings(n, hop_ms, smooth, range)
  n, hop_ms, smooth, range = tonumber(n), tonumber(hop_ms), tonumber(smooth), tonumber(range)
  assert(n and n >= 1024 and n <= 32768 and n % 1 == 0 and n & (n - 1) == 0,
    'FFT must be a power of two from 1024 to 32768.')
  assert(hop_ms and hop_ms >= 1 and hop_ms <= 1000, 'Hop must be 1–1000 ms.')
  assert(smooth and smooth >= 0 and smooth <= 2, 'Smoothing must be 0–2 octaves.')
  assert(range and range >= 0 and range <= 48, 'Range must be 0–48 dB.')
  return {n=n, hop_ms=hop_ms, smooth=smooth, range=range}
end

function M.normalize(p)
  local total, out = 0, {}
  for _, v in ipairs(p) do
    assert(v == v and v >= 0 and v < math.huge, 'Invalid spectral power.')
    total = total + v
  end
  assert(total > 1e-18, 'The item is silent or too quiet to analyze.')
  for i, v in ipairs(p) do out[i] = v / total end
  return out
end

-- Constant-octave box smoothing of linear-bin power, using prefix sums.
function M.smooth(p, octaves)
  if octaves == 0 then return p end
  local prefix, out, radius = {[0]=0}, {}, 2^(octaves/2)
  for i, v in ipairs(p) do prefix[i] = prefix[i-1] + v end
  for i = 1, #p do
    local k = i-1
    local lo = math.max(1, math.floor(k/radius)+1)
    local hi = math.min(#p, math.ceil(k*radius)+1)
    out[i] = (prefix[hi] - prefix[lo-1]) / (hi-lo+1)
  end
  return out
end

function M.match(reference, destination, octaves, limit)
  assert(#reference == #destination, 'Profile grids differ.')
  local ref, dst = M.normalize(reference), M.normalize(destination)
  local r, d = M.smooth(ref, octaves), M.smooth(dst, octaves)
  local peakr, peakd = 0, 0
  for i=1,#r do peakr=math.max(peakr,r[i]); peakd=math.max(peakd,d[i]) end
  local raw = {}
  for i=1,#r do
    raw[i] = 10*log10(math.max(r[i],peakr*1e-8)/math.max(d[i],peakd*1e-8))
  end
  -- Solve a common offset before clipping to preserve measured destination energy.
  local lo, hi = -200, 200
  for _=1,48 do
    local mid, energy = (lo+hi)/2, 0
    for i=1,#raw do energy=energy+dst[i]*10^(clamp(raw[i]+mid,-limit,limit)/10) end
    if energy > 1 then hi=mid else lo=mid end
  end
  local curve = {}
  for i=1,#raw do curve[i]=clamp(raw[i]+(lo+hi)/2,-limit,limit) end
  return curve
end
return M
