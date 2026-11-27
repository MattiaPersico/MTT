-- Incremental pre-FX take analysis. One FFT frame per step; memory is O(FFT size),
-- plus the transient gate stored on a ~1 ms grid when the attack/body split is on.
local A = {}

-- An item whose active take holds audio. Returns the take.
function A.check_audio(R, project, item)
  assert(item and R.ValidatePtr2(project,item,'MediaItem*'), 'Select an audio item.')
  local take = R.GetActiveTake(item)
  assert(take and not R.TakeIsMIDI(take), 'The active take must contain audio.')
  return take
end

-- Whether the take plays differently from its source (rate, pitch, stretch markers,
-- channel mode): the accessor is then not trusted, and A.pool renders it first.
function A.needs_render(R, take)
  return R.GetMediaItemTakeInfo_Value(take,'D_PLAYRATE') ~= 1 or R.GetMediaItemTakeInfo_Value(take,'D_PITCH') ~= 0
    or R.GetTakeNumStretchMarkers(take) ~= 0 or R.GetMediaItemTakeInfo_Value(take,'I_CHANMODE') ~= 0
end

-- The checks of A.new, without opening an accessor. Returns the active take.
function A.check(R, project, item)
  local take = A.check_audio(R, project, item)
  assert(R.GetMediaItemTakeInfo_Value(take,'D_PLAYRATE') == 1 and
    R.GetMediaItemTakeInfo_Value(take,'D_PITCH') == 0 and R.GetTakeNumStretchMarkers(take) == 0,
    'Render/glue rate-shifted, pitched or stretched takes before analysis.')
  assert(R.GetMediaItemTakeInfo_Value(take,'I_CHANMODE') == 0,
    'Use the normal take channel mode, or render/glue the take first.')
  local channels = R.GetMediaSourceNumChannels(R.GetMediaItemTake_Source(take))
  assert(channels == 1 or channels == 2, 'Only mono and stereo sources are supported.')
  return take, channels
end

function A.new(R, item, cfg, sr, Core)
  local project = R.EnumProjects(-1, '')
  local take, channels = A.check(R, project, item)
  local accessor = R.CreateTakeAudioAccessor(take)
  assert(accessor, 'Cannot create the take audio accessor.')
  local split = (cfg.attack_ms or 0) > 0 and cfg.split ~= 'static'
  assert(not split or Core, 'The attack/body split needs the match core.')
  local self = {R=R, project=project, item=item, take=take, accessor=accessor,
    sr=sr,n=cfg.n, channels=channels, frames=0, window={}, center=0, split=split,
    power={}, power_attack=split and {} or nil, power_body=split and {} or nil}
  local ok, err = pcall(function()
    self.start=R.GetAudioAccessorStartTime(accessor)
    self.finish=R.GetAudioAccessorEndTime(accessor)
    self.samples=math.floor((self.finish-self.start)*sr+0.5)
    assert(self.samples>0,'The item has no readable audio.')
    self.hop=math.min(cfg.n//2, math.max(1,math.floor(cfg.hop_ms*sr/1000+0.5)))
    self.buffer=R.new_array(cfg.n*channels)
    self.fft=R.new_array(cfg.n*2)
    for k=0,cfg.n-1 do self.window[k+1]=0.5-0.5*math.cos(2*math.pi*k/cfg.n) end
    for k=1,cfg.n//2+1 do
      self.power[k]=0
      if split then self.power_attack[k]=0; self.power_body[k]=0 end
    end
    if split then
      -- Detection pass state. grid[k+1] = gate at audio sample k*step (see Core.new_gate).
      self.detector=Core.new_gate(sr,cfg.attack_ms)
      self.step_samples=math.max(1,math.floor(sr/1000+0.5))
      self.grid={}
      self.grid_count=(self.samples-1)//self.step_samples+2
      self.detect_end=(self.grid_count-1)*self.step_samples+self.detector.lookahead+1
      self.detect_pos=0
      self.phase='detect'
      -- Impulsiveness statistics (Core.impulsive): gate duty and gated energies, at audio time.
      self.stats={duty=0,attack=0,body=0}
      self.ring={}
    else
      self.phase='frames'
    end
  end)
  if not ok then R.DestroyAudioAccessor(accessor); error(err) end
  return setmetatable(self,{__index=A})
end

function A:close()
  if self.accessor then self.R.DestroyAudioAccessor(self.accessor); self.accessor=nil end
end

function A:valid()
  local R=self.R
  return R.EnumProjects(-1,'')==self.project and R.ValidatePtr2(self.project,self.item,'MediaItem*')
    and R.GetActiveTake(self.item)==self.take and not R.AudioAccessorStateChanged(self.accessor)
end

-- 0..1 over both passes (detection counts as the first quarter).
function A:progress()
  if self.phase=='detect' then return 0.25*self.detect_pos/self.detect_end end
  local p=math.min(1,self.center/self.samples)
  return self.split and 0.25+0.75*p or p
end

-- Linear interpolation of the gate grid at audio sample s.
function A:gate(s)
  local x=s/self.step_samples
  local k=math.floor(x)
  local a=self.grid[k+1] or 0
  local b=self.grid[k+2] or a
  return a+(b-a)*(x-k)
end

-- One chunk of the transient detector over the mean channel power.
function A:detect_step()
  local n, channels = self.n, self.channels
  local first=self.detect_pos
  local count=math.min(n,self.detect_end-first)
  local readable=math.max(0,math.min(count,self.samples-first))
  self.buffer.clear()
  if readable>0 then
    local rc=self.R.GetAudioAccessorSamples(self.accessor,self.sr,channels,
      self.start+first/self.sr,readable,self.buffer)
    assert(rc>=0,'Audio accessor read failed.')
    if rc==0 then self.buffer.clear() end
  end
  local step, lookahead, grid, detector = self.step_samples, self.detector.lookahead, self.grid, self.detector
  local ring, size, stats, samples = self.ring, lookahead+1, self.stats, self.samples
  for j=0,count-1 do
    local p=0
    if j<readable then
      for ch=1,channels do local v=self.buffer[j*channels+ch]; p=p+v*v end
      p=p/channels
    end
    local g=detector.step(p)
    local t=first+j
    ring[t%size]=p
    local audio=t-lookahead
    if audio>=0 then
      if audio%step==0 then grid[audio//step+1]=g end
      if audio<samples then
        local pa=ring[audio%size]
        stats.duty=stats.duty+g
        stats.attack=stats.attack+g*g*pa
        stats.body=stats.body+(1-g)*(1-g)*pa
      end
    end
  end
  self.detect_pos=first+count
  if self.detect_pos>=self.detect_end then
    stats.duty=stats.duty/samples
    self.ring=nil
    self.phase='frames'
  end
end

function A:accumulate(offset, count, winpower)
  local n, channels = self.n, self.channels
  for ch=1,channels do
    self.fft.clear()
    for j=0,count-1 do
      self.fft[2*(offset+j)+1]=self.buffer[j*channels+ch]*self.window[offset+j+1]
    end
    self.fft.fft(n,true)
    for k=0,n//2 do
      local factor=(k==0 or k==n//2) and 1 or 2
      self.power[k+1]=self.power[k+1]+factor*(self.fft[2*k+1]^2+self.fft[2*k+2]^2)/(n*winpower*channels)
    end
  end
end

-- Attack part g*x, body part (1-g)*x and the whole item from the same two FFTs
-- (the transform is linear: whole = attack + body), so the whole profile is exact.
function A:accumulate_split(offset, count, winpower)
  local n, channels, first = self.n, self.channels, self.center-self.n//2
  local read_first=first+offset
  local gates, ar, ai = {}, {}, {}
  for j=0,count-1 do gates[j]=self:gate(read_first+j) end
  for ch=1,channels do
    self.fft.clear()
    for j=0,count-1 do
      self.fft[2*(offset+j)+1]=self.buffer[j*channels+ch]*self.window[offset+j+1]*gates[j]
    end
    self.fft.fft(n,true)
    for k=0,n//2 do ar[k]=self.fft[2*k+1]; ai[k]=self.fft[2*k+2] end
    self.fft.clear()
    for j=0,count-1 do
      self.fft[2*(offset+j)+1]=self.buffer[j*channels+ch]*self.window[offset+j+1]*(1-gates[j])
    end
    self.fft.fft(n,true)
    local scale=n*winpower*channels
    for k=0,n//2 do
      local factor=(k==0 or k==n//2) and 1 or 2
      local br, bi = self.fft[2*k+1], self.fft[2*k+2]
      self.power_attack[k+1]=self.power_attack[k+1]+factor*(ar[k]^2+ai[k]^2)/scale
      self.power_body[k+1]=self.power_body[k+1]+factor*(br^2+bi^2)/scale
      self.power[k+1]=self.power[k+1]+factor*((ar[k]+br)^2+(ai[k]+bi)^2)/scale
    end
  end
end

function A:step()
  assert(self:valid(),'The item or project changed. Analyze again.')
  if self.phase=='detect' then self:detect_step(); return false end
  local n, channels = self.n, self.channels
  local first = self.center-n//2
  local read_first, read_end=math.max(0,first),math.min(self.samples,first+n)
  local count=read_end-read_first
  self.buffer.clear()
  local rc=self.R.GetAudioAccessorSamples(self.accessor,self.sr,channels,
    self.start+read_first/self.sr,count,self.buffer)
  assert(rc>=0,'Audio accessor read failed.')
  local offset, winpower=read_first-first,0
  for j=0,count-1 do winpower=winpower+self.window[offset+j+1]^2 end
  if rc==1 and winpower>0 then
    if self.split then self:accumulate_split(offset,count,winpower)
    else self:accumulate(offset,count,winpower) end
  end
  self.frames=self.frames+1
  self.center=self.center+self.hop
  if self.center>=self.samples then
    for k=1,#self.power do
      self.power[k]=self.power[k]/self.frames
      if self.split then
        self.power_attack[k]=self.power_attack[k]/self.frames
        self.power_body[k]=self.power_body[k]/self.frames
      end
    end
    self.grid=nil
    return true
  end
  return false
end

------------------------------------------------------------------------------
-- Several items (a montage, or layers) analyzed one after the other and pooled into
-- one profile, without rendering or gluing anything. Frame powers and gate energies
-- are summed over all items before the mean, so every frame weighs the same whatever
-- its item. Only the profile's shape is used (Core.normalize), so items in a row and
-- overlapping uncorrelated layers both give their energy-weighted spectrum; a
-- crossfade region counts both of its items. One accessor is open at a time.
-- Exposes the fields the action reads from a single analysis (power, power_attack,
-- power_body, stats, sr, n, frames, split, project, item/take of the first item) plus
-- items = {{item=, take=, length=, read_item=, read_take=}, ...}: item/take are the
-- user's, read_item/read_take what is analyzed (a temporary render, see below).
local Pool = {}

------------------------------------------------------------------------------
-- Temporary render of takes that play differently from their source (A.needs_render).
-- Each such item is copied, without its take FX chain, onto a new hidden and (after
-- the render) muted track at the end of the project, and rendered there with REAPER's
-- "Apply track/take FX to items": that track has no FX, so the new take is the take
-- as it plays (rate, pitch, stretch markers, channel mode), pre-FX, as the EQ inserted
-- first in the take chain will receive it. The user's items are never changed. The
-- whole setup is one undo point; release() takes it back with Undo when it is still
-- the last one (nothing left in the history but a redo entry), otherwise deletes the
-- track in a second undo point, then deletes the rendered files.
local RENDER_ACTION = 40209
local RENDER_ACTION_NAME = 'Item: Apply track/take FX to items'
local RENDER_UNDO = 'mtt_TimbreMatch: temporary render for analysis'
local RENDER_REMOVE_UNDO = 'mtt_TimbreMatch: remove temporary render'
local IDENTITY = {GUID=true, IGUID=true, IID=true, FXID=true, EGUID=true}

-- The item chunk for the temporary copy: no <TAKEFX chain (no plugin is instantiated,
-- the render is pre-FX) and no identity lines (REAPER creates new ones).
function A.temp_chunk(chunk)
  local out, depth = {}, 0
  for line in (chunk .. '\n'):gmatch('([^\n]*)\n') do
    local key = line:match('^%s*(%S+)')
    if depth > 0 then
      if key == '>' then depth = depth - 1 elseif key and key:sub(1, 1) == '<' then depth = depth + 1 end
    elseif key == '<TAKEFX' then depth = 1
    elseif not IDENTITY[key] then out[#out + 1] = line end
  end
  return table.concat(out, '\n')
end

local Render = {}

-- entries: pool entries to render; sets their read_item/read_take.
function A.render(R, project, entries)
  -- The ID is checked by its name (variants end in "(mono output)" etc.).
  local action = R.kbd_getTextFromCmd(RENDER_ACTION, R.SectionFromUniqueID(0)) or ''
  assert(action:find(RENDER_ACTION_NAME, 1, true) == 1 and not action:find('(', 1, true),
    'REAPER\'s "' .. RENDER_ACTION_NAME .. '" action was not found: glue rate-shifted, pitched or stretched takes first.')
  local self = setmetatable({R=R, project=project, files={}}, {__index=Render})
  local selection = {}
  for i = 0, R.CountSelectedMediaItems(project) - 1 do selection[#selection + 1] = R.GetSelectedMediaItem(project, i) end
  R.PreventUIRefresh(1)
  R.Undo_BeginBlock2(project)
  local ok, err = pcall(function()
    R.InsertTrackAtIndex(R.CountTracks(project), false) -- false: no default FX or template
    local track = R.GetTrack(project, R.CountTracks(project) - 1)
    self.track = track
    R.GetSetMediaTrackInfo_String(track, 'P_NAME', 'mtt_TimbreMatch temporary render', true)
    R.SetMediaTrackInfo_Value(track, 'B_SHOWINTCP', 0)
    R.SetMediaTrackInfo_Value(track, 'B_SHOWINMIXER', 0)
    for _, e in ipairs(entries) do
      local copy = R.AddMediaItemToTrack(track)
      local got, chunk = R.GetItemStateChunk(e.item, '', false)
      assert(got and R.SetItemStateChunk(copy, A.temp_chunk(chunk), false), 'Cannot copy an item for the temporary render.')
      e.read_item, e.read_take = copy, R.GetActiveTake(copy)
    end
    R.SelectAllMediaItems(project, false)
    for _, e in ipairs(entries) do R.SetMediaItemSelected(e.read_item, true) end
    R.Main_OnCommand(RENDER_ACTION, 0) -- Item: Apply track/take FX to items (new active take)
    for _, e in ipairs(entries) do
      local rendered = R.GetActiveTake(e.read_item)
      assert(rendered and rendered ~= e.read_take, 'The temporary render did not create a take.')
      e.read_take = rendered
      local file = R.GetMediaSourceFileName(R.GetMediaItemTake_Source(rendered))
      if file and file ~= '' then self.files[#self.files + 1] = file end
    end
    R.SetMediaTrackInfo_Value(track, 'B_MUTE', 1) -- silent if the project plays meanwhile
  end)
  R.SelectAllMediaItems(project, false)
  for _, item in ipairs(selection) do
    if R.ValidatePtr2(project, item, 'MediaItem*') then R.SetMediaItemSelected(item, true) end
  end
  R.Undo_EndBlock2(project, RENDER_UNDO, -1)
  R.PreventUIRefresh(-1)
  R.UpdateArrange()
  if not ok then self:release(); error(err, 0) end
  return self
end

-- Removes the temporary track and its rendered files. A project closed meanwhile, or
-- a track already removed by the user's Undo, keeps its files (a saved project may use them).
function Render:release()
  if self.released then return end
  self.released = true
  local R, project = self.R, self.project
  if not self.track or not R.ValidatePtr2(project, self.track, 'MediaTrack*') then return end
  if R.EnumProjects(-1, '') == project and R.Undo_CanUndo2(project) == RENDER_UNDO then
    R.Undo_DoUndo2(project)
  end
  if R.ValidatePtr2(project, self.track, 'MediaTrack*') then
    R.Undo_BeginBlock2(project)
    R.DeleteTrack(self.track)
    R.Undo_EndBlock2(project, RENDER_REMOVE_UNDO, -1)
  end
  R.UpdateArrange()
  for _, file in ipairs(self.files) do os.remove(file); os.remove(file .. '.reapeaks') end
end

function A.pool(R, items, cfg, sr, Core)
  assert(#items > 0, 'Select one or more audio items.')
  local project = R.EnumProjects(-1, '')
  local list, total, pending = {}, 0, {}
  for i, item in ipairs(items) do
    local ok, take = pcall(A.check_audio, R, project, item)
    local render = ok and A.needs_render(R, take)
    if ok and not render then ok, take = pcall(A.check, R, project, item) end
    if not ok then
      if #items == 1 then error(take, 0) end
      local name = R.ValidatePtr2(project, item, 'MediaItem*') and R.GetActiveTake(item)
        and R.GetTakeName(R.GetActiveTake(item)) or ''
      error(string.format('Item %d of %d%s: %s', i, #items,
        name ~= '' and (' (' .. name .. ')') or '', (tostring(take):gsub('^.-:%d+: ', ''))), 0)
    end
    local length = R.GetMediaItemInfo_Value(item, 'D_LENGTH')
    list[i] = {item=item, take=take, length=length, read_item=item, read_take=take}
    if render then pending[#pending + 1] = list[i] end
    total = total + length
  end
  local self = setmetatable({R=R, project=project, items=list, cfg=cfg, sr=sr, n=cfg.n, Core=Core,
    split=(cfg.attack_ms or 0) > 0 and cfg.split ~= 'static', index=0, done_length=0,
    total_length=math.max(total, 1e-9), frames=0, samples=0, power={},
    item=list[1].item, take=list[1].take, rendered=#pending}, {__index=Pool})
  if self.split then
    self.power_attack, self.power_body = {}, {}
    self.stats = {duty=0, attack=0, body=0}
  end
  if #pending > 0 then self.render = A.render(R, project, pending) end
  local ok, err = pcall(self.open_next, self)
  if not ok then self:close(); error(err, 0) end
  return self
end

function Pool:open_next()
  self.index = self.index + 1
  local t = self.items[self.index]
  self.current = A.new(self.R, t.read_item, self.cfg, self.sr, self.Core)
end

-- Adds a finished item analysis (its means times its frame count: back to sums).
function Pool:add(a)
  local f = a.frames
  for k = 1, #a.power do
    self.power[k] = (self.power[k] or 0) + a.power[k]*f
    if self.split then
      self.power_attack[k] = (self.power_attack[k] or 0) + a.power_attack[k]*f
      self.power_body[k] = (self.power_body[k] or 0) + a.power_body[k]*f
    end
  end
  if self.split then -- a.stats.duty is a mean over a.samples; attack/body are energies
    self.stats.duty = self.stats.duty + a.stats.duty*a.samples
    self.stats.attack = self.stats.attack + a.stats.attack
    self.stats.body = self.stats.body + a.stats.body
  end
  self.frames = self.frames + f
  self.samples = self.samples + a.samples
end

function Pool:step()
  local current = self.current
  if not current:step() then return false end
  self:add(current)
  current:close()
  self.current = nil
  self.done_length = self.done_length + self.items[self.index].length
  if self.index < #self.items then self:open_next(); return false end
  if self.render then self.render:release() end -- before the action adds its own undo point
  for k = 1, #self.power do
    self.power[k] = self.power[k]/self.frames
    if self.split then
      self.power_attack[k] = self.power_attack[k]/self.frames
      self.power_body[k] = self.power_body[k]/self.frames
    end
  end
  if self.split then self.stats.duty = self.stats.duty/math.max(1, self.samples) end
  return true
end

-- 0..1 over all items, weighted by item length.
function Pool:progress()
  local now = self.done_length
  if self.current then now = now + self.current:progress()*self.items[self.index].length end
  return math.min(1, now/self.total_length)
end

-- Every item still in the current project with the same active take, and the open
-- accessor unchanged.
function Pool:valid()
  local R = self.R
  if R.EnumProjects(-1, '') ~= self.project then return false end
  for _, t in ipairs(self.items) do
    if not R.ValidatePtr2(self.project, t.item, 'MediaItem*') or R.GetActiveTake(t.item) ~= t.take then
      return false
    end
  end
  return not self.current or self.current:valid()
end

function Pool:close()
  if self.current then self.current:close(); self.current = nil end
  if self.render then self.render:release() end
end
return A
