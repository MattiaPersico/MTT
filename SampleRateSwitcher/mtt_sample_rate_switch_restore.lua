local major_version = 0
local minor_version = 2

-- File condiviso con mtt_sample_rate_switch_rec: contiene il sample rate da
-- ripristinare.
local TEMP_FILE = reaper.GetResourcePath() .. "/.mtt_sample_rate_switch.txt"

local proj = 0

-- Legge il file temporaneo per recuperare il sample rate salvato.
local file = io.open(TEMP_FILE, "r")
if file then
  -- Legge tutto il contenuto del file.
  local content = file:read("*a")
  -- Chiude il file dopo la lettura.
  file:close()
  -- Estrae il numero (sample rate) dal contenuto del file.
  local rate = tonumber(content:match("(%d+)"))
  if rate then
    -- Ottiene il sample rate corrente del dispositivo audio.
    local _retval, current = reaper.GetAudioDeviceInfo('SRATE')
    -- Verifica se il rate letto dal file è diverso da quello corrente.
    if rate ~= tonumber(current) then
      -- Aggiorna l'informazione del progetto con il nuovo sample rate.
      reaper.GetSetProjectInfo(proj, "PROJECT_SRATE", rate, true)
      -- Riavvia il motore audio per applicare le modifiche.
      reaper.Audio_Quit()
      reaper.Audio_Init()
    end
  end
end
