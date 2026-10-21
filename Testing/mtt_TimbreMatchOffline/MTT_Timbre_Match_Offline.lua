-- @description MTT Timbre Match Offline
-- @version 0.1.0
-- @author MTT
-- Load this action after manually installing the complete companion effect folder.
local dir=debug.getinfo(1,'S').source:match('^@(.+[\\/])')
local Core=dofile(dir..'match_core.lua')
local Analyzer=dofile(dir..'analyzer.lua')
local R=reaper
local SEGMENT='MTT_Timbre_Match_Offline_v1'
local FX_NAME='JS: MTT Timbre Match Offline'
local cfg=Core.settings(32768,10,1/6,24)
local job, reference, dragging, was_down
local status='Select a reference item, then Analyze reference.'
local progress=0

local function stop_job()
  if job then job:close(); job=nil end
end
local function message(err)
  status=tostring(err):match('[^\n]+'):gsub('^.-:%d+: ','')
end
local function current_sr()
  local sr=R.GetSetProjectInfo(0,'PROJECT_SRATE',0,false)
  if sr<=0 then local ok,value=R.GetAudioDeviceInfo('SRATE'); sr=ok and tonumber(value) or 48000 end
  return math.floor(Core.clamp(sr or 48000,8000,384000)+0.5)
end
local function begin_analysis(item, role)
  if job then return end
  local sr=role=='target' and reference.sr or current_sr()
  local settings=role=='target' and reference.cfg or cfg
  local ok,result=pcall(Analyzer.new,R,item,settings,sr)
  if not ok then message(result); return end
  job=result; job.role=role; job.cfg=settings
  progress=0
  status=role=='reference' and 'Analyzing reference...' or 'Analyzing destination...'
end

local function reserve(curve,n,sr)
  R.gmem_attach(SEGMENT)
  local slot
  for s=0,63 do if R.gmem_read(s*32784)==0 then slot=s; break end end
  assert(slot,'All transfer slots are busy. Close other match actions and retry.')
  local token=0
  for c in R.genGuid():gmatch('.') do token=(token*33+c:byte())%16777214 end
  token=token+1
  local base=slot*32784
  R.gmem_write(base+3,0)
  R.gmem_write(base+1,n); R.gmem_write(base+2,sr)
  for i,value in ipairs(curve) do R.gmem_write(base+15+i,value) end
  R.gmem_write(base,token) -- Publish last; the payload is immutable until acknowledged.
  return slot,token
end

local function insert_match(analysis,curve)
  assert(analysis:valid(),'The destination changed. Analyze again.')
  assert(R.GetMediaItemInfo_Value(analysis.item,'C_LOCK')==0,'The destination item is locked.')
  local slot,token=reserve(curve,analysis.n,analysis.sr)
  local take,fx=analysis.take,-1
  R.Undo_BeginBlock2(analysis.project)
  local ok,err=xpcall(function()
    fx=R.TakeFX_AddByName(take,FX_NAME,-1)
    assert(fx>=0,'Install the complete mtt_timbre_match_offline folder in REAPER Effects first.')
    assert(R.TakeFX_SetParam(take,fx,2,slot),'Cannot set the profile slot.')
    assert(R.TakeFX_SetParam(take,fx,3,token),'Cannot set the profile token.')
    -- Saving a chunk invokes @serialize even if the take has not played yet.
    local saved=R.GetItemStateChunk(analysis.item,'',false)
    assert(saved and R.gmem_read(slot*32784+3)==token,
      'The JSFX did not acknowledge the saved profile. The new effect was removed.')
    -- Accessor samples are pre-FX, so this EQ must be first in the take chain.
    if fx>0 then R.TakeFX_CopyToTake(take,fx,take,0,true); fx=0 end
    R.TakeFX_SetNamedConfigParm(take,fx,'renamed_name','MTT Offline Match - '..reference.name)
    R.UpdateItemInProject(analysis.item)
  end,debug.traceback)
  if not ok and fx>=0 and R.ValidatePtr2(analysis.project,take,'MediaItem_Take*') then
    R.TakeFX_Delete(take,fx)
  end
  R.Undo_EndBlock2(analysis.project,ok and 'MTT: apply offline timbre match' or 'MTT: cancel failed match',-1)
  R.gmem_write(slot*32784,0)
  if not ok then error(err) end
  status='Applied to destination take. Match 100%, output trim -6 dB. Undo available.'
end

local function selected()
  assert(R.CountSelectedMediaItems(0)==1,'Select exactly one audio item.')
  return R.GetSelectedMediaItem(0,0)
end
local function settings()
  local ok,value=R.GetUserInputs('Offline analysis',4,
    'FFT (1024–32768 power of 2),Hop (ms; limited to half window),Smoothing (octaves; 0–2),Max boost/cut (dB; 0–48)',
    string.format('%d,%g,%g,%g',cfg.n,cfg.hop_ms,cfg.smooth,cfg.range))
  if not ok then return end
  local a,b,c,d=value:match('^([^,]+),([^,]+),([^,]+),([^,]+)$')
  cfg=Core.settings(a,b,c,d)
  reference=nil
  status='Settings changed. Analyze the reference again.'
end
local function text(x,y,s,size)
  gfx.setfont(1,'Arial',size or 15); gfx.x=x; gfx.y=y; gfx.drawstr(s)
end
local function hit(x,y,w,h)
  return gfx.mouse_x>=x and gfx.mouse_x<x+w and gfx.mouse_y>=y and gfx.mouse_y<y+h
end
local function button(x,y,w,label,click,enabled)
  gfx.set(enabled and 0.18 or 0.10,0.23,0.27,1); gfx.rect(x,y,w,32,1)
  gfx.set(enabled and 0.9 or 0.45,0.92,0.94,1); text(x+10,y+8,label,14)
  return enabled and click and hit(x,y,w,32)
end

local function draw()
  gfx.set(0.055,0.065,0.08,1); gfx.rect(0,0,gfx.w,gfx.h,1)
  gfx.set(0.9,0.94,0.98,1); text(18,16,'MTT Timbre Match Offline',22)
  text(18,48,'Mean spectrum • offline reference + destination analysis',14)
  local down=gfx.mouse_cap&1~=0
  local click=down and not was_down
  if button(18,78,175,'Analyze reference',click,not job) then begin_analysis(selected(),'reference') end
  if button(205,78,120,'Settings',click,not job) then settings() end
  if button(337,78,210,'Apply to selected item',click,reference~=nil and not job) then
    begin_analysis(selected(),'target')
  end
  if button(559,78,105,'Cancel',click,job~=nil) then stop_job(); status='Analysis cancelled.' end
  local active=reference and reference.cfg or cfg
  local sr=reference and reference.sr or current_sr()
  gfx.set(0.65,0.72,0.79,1)
  text(18,122,string.format('FFT %d • %.2f Hz/bin • window %.1f ms • hop %.1f ms • smoothing %.3g oct',
    active.n,sr/active.n,active.n/sr*1000,math.min(active.hop_ms,active.n/sr*500),active.smooth),13)
  local gx,gy,gw,gh=18,154,math.max(100,gfx.w-36),180
  gfx.set(0.1,0.15,0.18,1); gfx.rect(gx,gy,gw,gh,1)
  if reference then
    local peak=0
    for _,v in ipairs(reference.power) do peak=math.max(peak,v) end
    local px,py
    gfx.set(0.25,0.85,0.70,1)
    for x=0,math.floor(gw-1) do
      local hz=20*(math.min(20000,reference.sr/2)/20)^(x/(gw-1))
      local k=math.min(#reference.power,math.floor(hz*reference.n/reference.sr)+1)
      local db=10*math.log(math.max(1e-10,reference.power[k]/peak))/math.log(10)
      local y=gy+20-Core.clamp(db,-80,0)*(gh-40)/80
      if px then gfx.line(px,py,gx+x,y) end
      px=gx+x; py=y
    end
    gfx.set(0.9,0.95,0.97,1)
    text(gx+12,gy+10,reference.name,14)
    text(gx+12,gy+gh-24,dragging and 'Release over a destination item in the arrange view' or
      'Drag this spectrum onto another item',14)
    if click and not job and hit(gx,gy,gw,gh) then dragging=true end
  else
    gfx.set(0.65,0.72,0.79,1); text(gx+16,gy+70,'Analyze an audio item to create a draggable reference.',16)
  end
  if dragging and not down then
    dragging=false
    local x,y=R.GetMousePosition()
    local item=R.GetItemFromPoint(x,y,false)
    if item then begin_analysis(item,'target') else status='Drop over an unlocked audio item, or use Apply to selected item.' end
  end
  gfx.set(0.8,0.87,0.92,1); text(18,352,status,13)
  if job then
    gfx.set(0.25,0.85,0.70,1); gfx.rect(18,380,(gfx.w-36)*progress,5,1)
  end
  gfx.set(0.55,0.63,0.7,1)
  text(18,400,'Pre-FX mono/stereo • static EQ • no playback required • reference stays unchanged',12)
  was_down=down
end

local function tick()
  local key=gfx.getchar()
  if key<0 or key==27 then stop_job(); gfx.quit(); return end
  local ok,err=xpcall(function()
    local deadline=R.time_precise()+0.02
    while job and R.time_precise()<deadline do
      local done=job:step()
      progress=math.min(1,job.center/job.samples)
      if done then
        if job.role=='reference' then
          Core.normalize(job.power) -- Reject silence before displaying or accepting a drop.
          reference={power=job.power,sr=job.sr,n=job.n,cfg=job.cfg,
            name=R.GetTakeName(job.take),frames=job.frames}
          status=string.format('Reference ready (%d frames). Drag the spectrum onto a destination.',job.frames)
        else
          local curve=Core.match(reference.power,job.power,reference.cfg.smooth,reference.cfg.range)
          insert_match(job,curve)
        end
        stop_job()
      end
    end
    draw()
  end,debug.traceback)
  if not ok then stop_job(); dragging=false; was_down=gfx.mouse_cap&1~=0; message(err); gfx.set(1,0.6,0.5,1); text(18,352,status,12) end
  gfx.update()
  R.defer(tick)
end
R.atexit(function() stop_job(); gfx.quit() end)
gfx.init('MTT Timbre Match Offline',820,430)
-- Running the action with exactly one selected item starts capture immediately.
if R.CountSelectedMediaItems(0)==1 then begin_analysis(R.GetSelectedMediaItem(0,0),'reference') end
tick()
