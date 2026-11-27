-- mtt_TimbreMatch 0.2.0. Pure profile math; no host dependencies.
local M = {}
local log10 = function(x) return math.log(x) / math.log(10) end
local clamp = function(x, a, b) return math.max(a, math.min(b, x)) end
M.clamp = clamp

-- attack_ms: transient hold of the attack/body split; 0 = one static curve (0.1.0 behavior).
-- split: 'auto' (attack + body only when both items are impulsive, see M.impulsive),
-- 'static' (one curve, no detection pass) or 'always'. Ignored when attack_ms is 0.
M.SPLIT_MODES = {auto=true, static=true, always=true}
function M.settings(n, hop_ms, smooth, range, attack_ms, split)
  n, hop_ms, smooth, range = tonumber(n), tonumber(hop_ms), tonumber(smooth), tonumber(range)
  attack_ms = tonumber(attack_ms or 0)
  split = split or 'auto'
  assert(n and n >= 1024 and n <= 32768 and n % 1 == 0 and n & (n - 1) == 0,
    'FFT must be a power of two from 1024 to 32768.')
  assert(hop_ms and hop_ms >= 1 and hop_ms <= 1000, 'Hop must be 1–1000 ms.')
  assert(smooth and smooth >= 0 and smooth <= 2, 'Smoothing must be 0–2 octaves.')
  assert(range and range >= 0 and range <= 48, 'Range must be 0–48 dB.')
  assert(attack_ms and attack_ms >= 0 and attack_ms <= 200, 'Attack hold must be 0–200 ms.')
  assert(M.SPLIT_MODES[split], 'Split must be auto, static or always.')
  if attack_ms == 0 then split = 'static' end
  return {n=n, hop_ms=hop_ms, smooth=smooth, range=range, attack_ms=attack_ms, split=split}
end

-- Transient gate shared with the JSFX (keep both implementations identical).
-- Detector input: mean channel power. Fast/slow one-pole power followers (2/60 ms);
-- a transient is fast > 10 x slow (10 dB) above 1e-6 (-60 dBFS): any onset from silence,
-- or a step of about 17 dB or more from a steady level. 6 dB also fired on
-- speech syllables and on noise fluctuations (ambiences, whooshes); 10 dB does not,
-- while impacts and footsteps keep 70-90% of their energy in the attack part. The gate rises in
-- 2 ms, stays open for attack_ms after the last transient sample and falls in 10 ms.
-- The audio path is delayed 4 ms, so the gate is open when the delayed onset arrives:
-- gate for audio sample t = detector output at sample t + lookahead.
function M.gate_constants(sr, attack_ms)
  local r = function(x) return math.floor(x + 0.5) end
  return {
    fast = 1 - math.exp(-1/(0.002*sr)), slow = 1 - math.exp(-1/(0.060*sr)),
    ratio = 10, floor = 1e-6, hold = r(attack_ms*sr/1000), lookahead = r(0.004*sr),
    rise = 1/math.max(1, r(0.002*sr)), fall = 1/math.max(1, r(0.010*sr)),
  }
end

function M.new_gate(sr, attack_ms)
  local c = M.gate_constants(sr, attack_ms)
  local ef, es, hold, g = 0, 0, 0, 0
  local gate = {lookahead = c.lookahead}
  function gate.step(p)
    ef = ef + c.fast*(p - ef); es = es + c.slow*(p - es)
    if ef > es*c.ratio and ef > c.floor then hold = c.hold
    elseif hold > 0 then hold = hold - 1 end
    if hold > 0 then g = math.min(1, g + c.rise) else g = math.max(0, g - c.fall) end
    return g
  end
  return gate
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

-- Impulsive material: the attack part holds at least 25% of the energy, at least 4x
-- denser than average (energy share / time share). Measured with the 10 dB detector:
-- impacts and footsteps 7-20x with 70-95% of the energy; speech, whooshes and
-- ambiences below 3x and 6%. stats = {duty = mean gate, attack = sum (g x)^2,
-- body = sum ((1-g) x)^2} from the analyzer.
function M.impulsive(stats)
  if not stats then return false, 0, 0 end
  local e = stats.attack + stats.body
  local share = e > 0 and stats.attack / e or 0
  local density = stats.duty > 0 and share / stats.duty or 0
  return share >= 0.25 and density >= 4, share, density
end

local function total(p) local s = 0; for _, v in ipairs(p) do s = s + v end; return s end

-- Body and attack curves from gated profiles. Without measurable energy in both parts
-- of both items (for example a destination without transients), both curves fall back
-- to the static whole-item match; split=false reports that fallback.
-- ref_whole/dst_whole: exact whole-item profiles for the fallback (default: part sums).
function M.match_split(ref_attack, ref_body, dst_attack, dst_body, octaves, limit, ref_whole, dst_whole)
  local ref, dst = ref_whole or {}, dst_whole or {}
  if not ref_whole or not dst_whole then
    ref, dst = {}, {}
    for i = 1, #ref_body do ref[i] = ref_attack[i] + ref_body[i]; dst[i] = dst_attack[i] + dst_body[i] end
  end
  local static = M.match(ref, dst, octaves, limit)
  local ra, rb, da, db = total(ref_attack), total(ref_body), total(dst_attack), total(dst_body)
  local tiny = 1e-6
  if ra <= tiny*(ra+rb) or rb <= tiny*(ra+rb) or da <= tiny*(da+db) or db <= tiny*(da+db) then
    return static, static, false
  end
  return M.match(ref_body, dst_body, octaves, limit), M.match(ref_attack, dst_attack, octaves, limit), true
end
return M
