local major_version = 0
local minor_version = 2

-- File condiviso con mtt_sample_rate_switch_rec: contiene il sample rate da
-- ripristinare.
local TEMP_FILE = reaper.GetResourcePath() .. "/.mtt_sample_rate_switch.txt"

local proj = 0

-- Ripristina il sample rate letto dal file temporaneo.
local file = io.open(TEMP_FILE, "r")
if file then
  local content = file:read("*a")
  file:close()
  local rate = tonumber(content:match("(%d+)"))
  if rate then
    local retval, current = reaper.GetAudioDeviceInfo('SRATE')
    if rate ~= tonumber(current) then
      reaper.GetSetProjectInfo(proj, "PROJECT_SRATE", rate, true)
      reaper.Audio_Quit()
      reaper.Audio_Init()
    end
  end
end
