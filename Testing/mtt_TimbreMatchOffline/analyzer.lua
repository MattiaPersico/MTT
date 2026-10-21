-- Incremental pre-FX take analysis. One FFT frame per step; memory is O(FFT size).
local A = {}

function A.new(R, item, cfg, sr)
  local project = R.EnumProjects(-1, '')
  assert(item and R.ValidatePtr2(project,item,'MediaItem*'), 'Select an audio item.')
  local take = R.GetActiveTake(item)
  assert(take and not R.TakeIsMIDI(take), 'The active take must contain audio.')
  assert(R.GetMediaItemTakeInfo_Value(take,'D_PLAYRATE') == 1 and
    R.GetMediaItemTakeInfo_Value(take,'D_PITCH') == 0 and R.GetTakeNumStretchMarkers(take) == 0,
    'Render/glue rate-shifted, pitched or stretched takes before analysis.')
  assert(R.GetMediaItemTakeInfo_Value(take,'I_CHANMODE') == 0,
    'Use the normal take channel mode, or render/glue the take first.')
  local channels = R.GetMediaSourceNumChannels(R.GetMediaItemTake_Source(take))
  assert(channels == 1 or channels == 2, 'Only mono and stereo sources are supported.')
  local accessor = R.CreateTakeAudioAccessor(take)
  assert(accessor, 'Cannot create the take audio accessor.')
  local self = {R=R, project=project, item=item, take=take, accessor=accessor,
    sr=sr,n=cfg.n, channels=channels, frames=0, power={}, window={}, center=0}
  local ok, err = pcall(function()
    self.start=R.GetAudioAccessorStartTime(accessor)
    self.finish=R.GetAudioAccessorEndTime(accessor)
    self.samples=math.floor((self.finish-self.start)*sr+0.5)
    assert(self.samples>0,'The item has no readable audio.')
    self.hop=math.min(cfg.n//2, math.max(1,math.floor(cfg.hop_ms*sr/1000+0.5)))
    self.buffer=R.new_array(cfg.n*channels)
    self.fft=R.new_array(cfg.n*2)
    for k=0,cfg.n-1 do self.window[k+1]=0.5-0.5*math.cos(2*math.pi*k/cfg.n) end
    for k=1,cfg.n//2+1 do self.power[k]=0 end
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

function A:step()
  assert(self:valid(),'The item or project changed. Analyze again.')
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
  self.frames=self.frames+1
  self.center=self.center+self.hop
  if self.center>=self.samples then
    for k=1,#self.power do self.power[k]=self.power[k]/self.frames end
    return true
  end
  return false
end
return A
