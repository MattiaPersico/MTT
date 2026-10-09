local major_version = 0
local minor_version = 2

-- Sample rate target al quale commutare il progetto prima di registrare.
-- Impostalo una volta: lo script lo applica, lo stop lo ripristina.
local TARGET_SR = 192000

-- File condiviso con mtt_sample_rate_switch_restore: qui lo script ricorda il
-- sample rate da ripristinare.
local TEMP_FILE = reaper.GetResourcePath() .. "/.mtt_sample_rate_switch.txt"

-- Timeout massimo in secondi per il polling del cambio sample rate.
local MAX_TIMEOUT = 3

local proj = 0

-- Sample rate attuale del progetto, da salvare prima di commutare.
local cur_rate = reaper.GetSetProjectInfo(proj, "PROJECT_SRATE", 0, false)

-- Salva lo stato nel file temporaneo prima di commutare.
local file = io.open(TEMP_FILE, "w")
if file then
  file:write(string.format("%d\n", cur_rate))
  file:close()
end

-- Commuta al rate target: imposta il rate, poi forza "usa il rate del progetto"
-- (altrimenti, con USE=0, il progetto continuerebbe a seguire il rate globale).
reaper.GetSetProjectInfo(proj, "PROJECT_SRATE", TARGET_SR, true)
reaper.Audio_Quit()
reaper.Audio_Init()
local start_time = reaper.time_precise()

local function sr_change_polling()
 local retval, current = reaper.GetAudioDeviceInfo('SRATE')

 if tonumber(current) == TARGET_SR then
     reaper.Main_OnCommand(1013, 0) -- Transport: Record
  return
 end

 if reaper.time_precise() - start_time >= MAX_TIMEOUT then
  return
 end

 reaper.defer(sr_change_polling)
end

reaper.defer(sr_change_polling)
