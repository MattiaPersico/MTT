
local env = reaper.GetSelectedTrackEnvelope(0)
if not env then return end
local n_ai = reaper.CountAutomationItems(env)
local cursorPos = reaper.GetCursorPosition()

local moveAmount = 0
local check = true

for i=0, n_ai-1, 1 do

  local retval = reaper.GetSetAutomationItemInfo(env,i,'D_UISEL', 0, false)
  local autItemPos = reaper.GetSetAutomationItemInfo(env, i, 'D_POSITION', 0, false)
  
  if retval ~= 0 and check then
    
    moveAmount = cursorPos - autItemPos
    
    check = false
    
  end
  
  if retval ~= 0 and check == false then
    reaper.GetSetAutomationItemInfo(env, i, 'D_POSITION', autItemPos + moveAmount, true)
  end

end

