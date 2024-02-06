
-- AUDIOGUIDE DEFAULT OPTION FILE

local defaultOptionFile = [[
TARGET = tsf(
)

CORPUS_GLOBAL_ATTRIBUTES = {
}

CORPUS = [
]

SEARCH = [
]

SUPERIMPOSE = si()

CSOUND_RENDER_FILEPATH = None
CSOUND_PLAY_RENDERED_FILE = False

OUTPUTEVENT_ALIGN_PEAKS = False

RPP_FILEPATH = ''
RPP_INCLUDE_TARGET = False
RPP_CPSTRACK_METHOD = 'cpsidx'
RPP_AUTOLAUNCH = False
]]

SPASS_STRING_LIST = 'closest\0closest_percent\0farthest\0farthest_percent\0'
DESCRIPTORS_STRING_LIST = 'effDur-seg\0power\0power-delta\0centroid\0centroid-delta\0mfccs\0mfccs-delta\0kurtosis\0kurtosis-delta\0'

-- Path Segmentazione
agSegmentationFile = AG_path .. '/agSegmentSf.py'
agDefaultsFile = AG_path .. '/audioguide/defaults.py'

-- Path Concatenazione
option_file = AG_path .. '/reaper_ag_options.py'
concatenate_path = AG_path .. '/agConcatenate.py'

NUMBER_OF_SEGMENTS = 0

local mgf = {}
if reaper.file_exists(reaper.GetResourcePath().."/Scripts/MTT/ReAG/mtt_global_functions.lua") then
  mgf = require(reaper.GetResourcePath().."/Scripts/MTT/ReAG/mtt_global_functions")
else
  mgf = require(reaper.GetResourcePath().."/Scripts/MTT_Scripts/ReAG/mtt_global_functions")
end

local magf = {}



-- ALGORITMI DI INDIVIDUAZIONE E SOSTITUZIONE STRINGHE

function magf.replaceSearch(originalString, newSearchContent)
  -- Pattern che trova il contenuto tra le parentesi quadre dopo 'SEARCH ='
  local pattern = "(SEARCH = %b[])"

  -- La nuova stringa che sostituirà il vecchio contenuto tra le parentesi quadre
  local replacement = "SEARCH = [" .. newSearchContent .. "]"

  -- Sostituisci il vecchio contenuto con il nuovo
  local resultString = string.gsub(originalString, pattern, replacement)

  --reaper.ShowMessageBox(newSearchContent,'',0)

  return resultString
end

function magf.replaceTarget(originalString, newTargetContent)
  -- Pattern che trova il contenuto tra le parentesi dopo 'TARGET ='
  local pattern = "(TARGET = tsf%b())"

  -- La nuova stringa che sostituirà il vecchio contenuto tra le parentesi
  local replacement = "TARGET = tsf(" .. newTargetContent .. ')'

  -- Sostituisci il vecchio contenuto con il nuovo
  local resultString = string.gsub(originalString, pattern, replacement)

  return resultString
end

function magf.replaceOutputEventAlignPeaks(originalString, newValue)
  -- Pattern che trova il valore dopo 'OUTPUTEVENT_ALIGN_PEAKS ='
  local pattern = "(OUTPUTEVENT_ALIGN_PEAKS = )[%a]+"

  -- La nuova stringa che sostituirà il vecchio valore
  local replacement = "%1" .. newValue

  -- Sostituisci il vecchio valore con il nuovo
  local resultString = string.gsub(originalString, pattern, replacement)

  return resultString
end

function magf.replaceCorpusGlobalAttributes(originalString, newAttributesContent)
  -- Pattern che trova il contenuto tra le parentesi graffe dopo 'CORPUS_GLOBAL_ATTRIBUTES ='
  local pattern = "(CORPUS_GLOBAL_ATTRIBUTES = %b{})"

  -- La nuova stringa che sostituirà il vecchio contenuto tra le parentesi graffe
  local replacement = "CORPUS_GLOBAL_ATTRIBUTES = {" .. newAttributesContent .. '}'

  -- Sostituisci il vecchio contenuto con il nuovo
  local resultString = string.gsub(originalString, pattern, replacement)

  return resultString
end

function magf.replaceCorpus(originalString, newCorpusContent)
  -- Pattern che trova il contenuto tra le parentesi quadre dopo 'CORPUS ='
  local pattern = "(CORPUS = %b[])"

  -- La nuova stringa che sostituirà il vecchio contenuto tra le parentesi quadre
  local replacement = "CORPUS = [" .. newCorpusContent .. "]"

  -- Sostituisci il vecchio contenuto con il nuovo
  local resultString = string.gsub(originalString, pattern, replacement)

  return resultString
end

function magf.replaceOutputRpp(content, newText)
  -- Pattern che trova la riga con 'RPP_FILEPATH =', seguito da qualsiasi carattere fino alla fine della riga
  local pattern = "(RPP_FILEPATH = ).*"

  -- La nuova stringa che sostituirà il vecchio valore, inclusi gli apici singoli
  local replacement = "%1'" .. newText .. "'"

  -- Sostituisci il vecchio valore con il nuovo
  local resultString = string.gsub(content, pattern, replacement)

  return resultString
end

function magf.replaceSuperimpose(content, si_sequence)
  -- Pattern che trova il contenuto tra le parentesi dopo 'SUPERIMPOSE = s'
  local pattern = "(SUPERIMPOSE = si%b())"

  -- La nuova stringa che sostituirà il vecchio contenuto tra le parentesi
  local replacement = "SUPERIMPOSE = si(" .. si_sequence .. ')'

  -- Sostituisci il vecchio contenuto con il nuovo
  local resultString = string.gsub(content, pattern, replacement)

  return resultString
end

function magf.replaceOutputCSR(content, newText)
  return content:gsub('CSOUND_RENDER_FILEPATH = \'([^\']+)\'', 'CSOUND_RENDER_FILEPATH = \'' .. newText .. '\'')
end

function magf.getAGPathFromFile(filePath)
  local agPath = nil

  -- Apri il file in modalità lettura
  local file = io.open(filePath, "r")
  if not file then
      --print("Impossibile aprire il file: " .. filePath)
      return nil
  end

  -- Leggi il file riga per riga
  for line in file:lines() do
      -- Cerca la riga che inizia con 'AG_path ='
      if line:match("^AG_path%s*=") then
          -- Estrai il percorso dopo l'uguale
          agPath = line:match("= '(.+)'")
          break
      end
  end

  file:close()  -- Chiudi il file dopo aver finito di leggerlo
  return agPath
end

function magf.getPython3PathFromFile(filePath)
  local agPath = nil

  -- Apri il file in modalità lettura
  local file = io.open(filePath, "r")
  if not file then
      --print("Impossibile aprire il file: " .. filePath)
      return nil
  end

  -- Leggi il file riga per riga
  for line in file:lines() do
      -- Cerca la riga che inizia con 'AG_path ='
      if line:match("^python%s*=") then
          -- Estrai il percorso dopo l'uguale
          agPath = line:match("= '(.+)'")
          break
      end
  end

  file:close()  -- Chiudi il file dopo aver finito di leggerlo
  return agPath
end

function magf.getReaAGEnvPathFromFile(filePath)
  local agPath = nil

  -- Apri il file in modalità lettura
  local file = io.open(filePath, "r")
  if not file then
      --print("Impossibile aprire il file: " .. filePath)
      return nil
  end

  -- Leggi il file riga per riga
  for line in file:lines() do
      -- Cerca la riga che inizia con 'Rea_AG_env_path ='
      if line:match("^Rea_AG_env_path%s*=") then
          -- Estrai il percorso dopo l'uguale
          agPath = line:match("= '(.+)'")
          break
      end
  end

  file:close()  -- Chiudi il file dopo aver finito di leggerlo
  return agPath
end


-- PREFERENCES

function magf.findFolderName(path, prefix)
  local p = io.popen('ls -l "' .. path .. '" | grep ^d')  -- Comando per elencare directory in Unix/MacOS
    for entry in p:lines() do
        local filename = entry:match("%S+$")  -- Estrae l'ultimo token, che dovrebbe essere il nome della directory
        if filename and filename:match("^" .. prefix) then
            p:close()
            return filename
        end
    end
    p:close()
  return ' ' -- Nessuna cartella trovata con quel prefisso
end

function magf.setEnvironmentPath(environment_path, mtt_audioguide_paths)
  if magf.validateEnvironmentPath(environment_path) == true then
    magf.updateReaAGEnvPath(mtt_audioguide_paths .. '.lua', environment_path)
    return true
  else
    return false
  end
end

function magf.setAudioGuidePath(ag_path, mtt_audioguide_paths)
  if magf.validateAudioGuidePath(ag_path) == true then
    magf.updateAudioGuidePath(mtt_audioguide_paths .. '.lua', ag_path)
    magf.refreshGlobalPaths(mtt_audioguide_paths)
    magf.setAudioguideVerbosity(agSegmentationFile, agDefaultsFile , false)
    magf.makeAgOptionFileIfNeeded(ag_path)
    return true
  else
    return false
  end
end

function magf.setPython3Path(python3_path, mtt_audioguide_paths)
  if magf.validatePython3Path(python3_path) then
    magf.updatePythonPath(mtt_audioguide_paths .. '.lua', python3_path)
    return true
 else
   return false
 end
end

function magf.updateReaAGEnvPath(paths_file, new_Rea_AG_env_path_value)
  local file_content = {}
  local Rea_AG_env_path_line_number = nil

  -- Apri il file in modalità di lettura
  local file = io.open(paths_file, "r")
  if not file then
      --print("Impossibile aprire il file.")
      return false
  end

  -- Leggi il file riga per riga e cerca la riga che contiene 'Rea_AG_env_path ='
  for line in file:lines() do
      table.insert(file_content, line)
      if string.find(line, "Rea_AG_env_path =") then
          Rea_AG_env_path_line_number = #file_content
          -- Sostituisci il vecchio valore di Rea_AG_env_path con il nuovo
          file_content[Rea_AG_env_path_line_number] = "Rea_AG_env_path = '" .. new_Rea_AG_env_path_value .. "'"
      end
  end

  file:close()

  -- Se 'Rea_AG_env_path =' è stato trovato, sostituisci il valore
  if Rea_AG_env_path_line_number then
      -- Apri lo stesso file in modalità di scrittura per sovrascrivere
      local file = io.open(paths_file, "w")
      for _, line in ipairs(file_content) do
          file:write(line, "\n")
      end

      file:close()
      --print("Valore 'Rea_AG_env_path' aggiornato con successo.")
      return true
  else
      --print("Non è stato possibile trovare 'Rea_AG_env_path =' nel file.")
      return false
  end
end

function magf.updateAudioGuidePath(paths_file, new_AG_path_value) -- aggiorna la root di Audio Guide nel paths_file mtt_audioguide_path.lua

  local file_content = {}
  local AG_path_line_number = nil

  -- Apri il file in modalità di lettura
  local file = io.open(paths_file, "r")
  if not file then
      --print("Impossibile aprire il file.")
      return false
  end

  -- Leggi il file riga per riga e cerca la riga che contiene 'AG_path ='
  for line in file:lines() do
      table.insert(file_content, line)
      if string.find(line, "AG_path =") then
          AG_path_line_number = #file_content
          -- Sostituisci il vecchio valore di AG_path con il nuovo
          file_content[AG_path_line_number] = "AG_path = '" .. new_AG_path_value .. "'"
      end
  end

  file:close()

  -- Se 'AG_path =' è stato trovato, sostituisci il valore
  if AG_path_line_number then
      -- Apri lo stesso file in modalità di scrittura per sovrascrivere
      local file = io.open(paths_file, "w")
      for _, line in ipairs(file_content) do
          file:write(line, "\n")
      end

      file:close()
      --print("Valore 'AG_path' aggiornato con successo.")
      return true
  else
      --print("Non è stato possibile trovare 'AG_path =' nel file.")
      return false
  end

end

function magf.validateEnvironmentPath(environment_path)
  local audioguideExists = false
  local ag_p3envExists = false

  local p = io.popen('find "' .. environment_path .. '" -type d') -- Esegue il comando find
  for directory in p:lines() do
      if directory:match("^" .. environment_path .. "/audioguide") then
          audioguideExists = true
      elseif directory:match("^" .. environment_path .. "/AG_P3Env_") then
          ag_p3envExists = true
      end
  end
  p:close()

  return audioguideExists and ag_p3envExists
end

function magf.validateAudioGuidePath(base_path) -- verifica che il path di AudioGuide sia corretto (per ora verifica solo la presenza di parte dei file necessari senza entrare troppo nel dettaglio)

  local is_path_valid = true

  local files_and_folders = {
      "agConcatenate.py",
      "agGetSfDescriptors.py",
      "agGranulateSf.py",
      "agSegmentSf.py",
      "audioguide"
  }

  for _, name in ipairs(files_and_folders) do
      local full_path = base_path .. "/" .. name

      if name:match("^.+(%..+)$") then -- Se ha un'estensione, è un file
          if mgf.file_exists(full_path) then
              --reaper.ShowMessageBox("Il file " .. name .. " esiste.", 'SI', 0)
          else
              --reaper.ShowMessageBox("Il file " .. name .. " non esiste.", 'NO', 0)
              is_path_valid = false
          end
      else -- Altrimenti, assumi sia una directory
          if mgf.directory_exists(full_path) then
            --reaper.ShowMessageBox("Il folder " .. name .. " esiste.", 'SI', 0)
          else
            is_path_valid = false
            --reaper.ShowMessageBox("Il folder " .. name .. " non esiste.", 'NO', 0)
          end
      end
  end
  --reaper.ShowMessageBox(tostring(is_path_valid), 'is path valid', 0)
  return is_path_valid

end

function magf.makeAgOptionFileIfNeeded(ag_path) -- verifica se l'option file esiste e se non esiste lo genera

  local optionsFilePath = ag_path..'/reaper_ag_options.py'

  mgf.makeFile(optionsFilePath, defaultOptionFile)


end

function magf.validatePython3Path(python3_path) -- verifica se la versione di python selezionata è corretta
    -- Esegue il comando pythonPath con l'opzione '--version' e cattura l'output
    local command = '"' .. python3_path .. '" --version'
    local handle = io.popen(command, 'r')
    local output = handle:read('*a')
    handle:close()

    if output:match("Python 3") then

      local filename = python3_path:match("([^/]+)$")
      
      if filename == "python3" or filename:find("^python3%.") then
        return true
    else
        return false
    end
    else
        --print("Python 3 is not available at " .. pythonPath)
        return false
    end
end

function magf.updatePythonPath(paths_file, new_python_path) -- aggiorna il path python nel file mtt_audioguide_paths.lua
  local lines = {}
  local foundPythonLine = false

  -- Legge il file e memorizza le linee
  for line in io.lines(paths_file) do
      if line:match("^python%s*=") then
          -- Sostituisce il percorso di Python con il nuovo percorso
          line = "python = '" .. new_python_path .. "'"
          foundPythonLine = true
      end
      table.insert(lines, line)
  end

  if not foundPythonLine then
      --print("Non è stata trovata nessuna linea che inizia con 'python =' nel file.")
      return false
  end

  -- Riscrive il file con la linea modificata
  local file = io.open(paths_file, "w")
  for i, line in ipairs(lines) do
      file:write(line .. "\n")
  end

  file:close()

  --print("Il percorso di Python è stato aggiornato con successo!")
  return true
end

function magf.isNumpyInstalled(python_path) -- NON TESTATO controlla se NumPy è installato per la versione selezionata di python 
  -- Esegue un comando Python che tenta di importare numpy
  local command = '"' .. python_path .. '" -c "import numpy"'
  local handle = io.popen(command .. " 2>&1", 'r')  -- Redireziona stderr a stdout per catturare gli errori
  local output = handle:read("*a")
  handle:close()

  if output:match("No module named numpy") or output:match("ImportError") then
      return false  -- Numpy non è installato, restituisce false e l'output
  else
      return true   -- Numpy è installato, restituisce true e l'output
  end
end

function magf.ensureNumpy(python_path) -- NON TESTATO prova a installare NumPy per la versione selezionata di python se non fosse installato
  local isInstalled = magf.isNumpyInstalled(python_path)

  if not isInstalled then
      reaper.ShowMessageBox('NumPy is not installed. Attempting to install...', 'Alert', 0)
      -- Costruisce il comando per installare NumPy usando pip
      local installCommand = '"' .. python_path .. '" -m pip install numpy'
      local handle = io.popen(installCommand, 'r')
      local result = handle:read("*a")
      handle:close()

      --print("Risultato dell'installazione: " .. result)

      -- Verifica nuovamente se NumPy è stato installato correttamente
      isInstalled = magf.isNumpyInstalled(python_path)
      if isInstalled then
          reaper.ShowMessageBox('NumPy has been successfully installed.', 'Success', 0)
          return true
      else
          reaper.ShowMessageBox('Installation of NumPy failed.', 'Error', 0)
          return false
      end
  else
      print("NumPy è già installato.")
      return true
  end
end

function magf.refreshGlobalPaths(mtt_audioguide_paths) -- aggiorna il foglio mtt_audioguide_paths.lua con i valori dei path globali selezionati nella corrente instanza dello script

  Rea_AG_env_path = magf.getReaAGEnvPathFromFile(mtt_audioguide_paths .. '.lua')
  AG_path = magf.getAGPathFromFile(mtt_audioguide_paths .. '.lua')
  python = magf.getPython3PathFromFile(mtt_audioguide_paths .. '.lua')

  agSegmentationFile = AG_path .. '/agSegmentSf.py'
  agDefaultsFile = AG_path .. '/audioguide/defaults.py'

  option_file = AG_path .. '/reaper_ag_options.py'
  concatenate_path = AG_path .. '/agConcatenate.py'

end



-- PREPARAZIONE AUDIOGUIDE

function magf.setVerbositySegmentationFile(filepath, new_verbosity_value) -- scrive il parametro Verbosity nel file agSegmentSf.py 
  local file_content = {}
  local verbosity_line = nil
  local verbosity_line_number = nil

  -- Apri il file in modalità di lettura
  local file = io.open(filepath, "r")
  if not file then
      print("Impossibile aprire il file.")
      return false
  end

  -- Leggi il file riga per riga e cerca la riga che contiene 'VERBOSITY'
  for line in file:lines() do
      table.insert(file_content, line)
      if string.find(line, "'VERBOSITY':") then
          verbosity_line = line
          verbosity_line_number = #file_content
      end
  end

  file:close()

  -- Se 'VERBOSITY' è stato trovato, sostituisci il valore
  if verbosity_line and verbosity_line_number then
      -- Sostituisci il vecchio valore di verbosity con il nuovo
      local modified_line = string.gsub(verbosity_line, "%d+", tostring(new_verbosity_value))
      file_content[verbosity_line_number] = modified_line

      -- Apri lo stesso file in modalità di scrittura per sovrascrivere
      local file = io.open(filepath, "w")
      for _, line in ipairs(file_content) do
          file:write(line, "\n")
      end

      file:close()
      print("Valore 'VERBOSITY' aggiornato con successo.")
      return true
  else
      print("Non è stato possibile trovare 'VERBOSITY' nel file.")
      return false
  end
end


function magf.setVerbosityDefaultsFile(filepath, new_verbosity_value) -- scrive il parametro VERBOSITY nel file defaults.py 
  local file_content = {}
  local verbosity_line = nil
  local verbosity_line_number = nil

  -- Apri il file in modalità di lettura
  local file = io.open(filepath, "r")
  if not file then
    reaper.ShowMessageBox('Non sono riuscito ad aprire il file in read', 'setVerbosityDefaultsFile', 0)
      return false
  end

  -- Leggi il file riga per riga e cerca la riga che contiene 'VERBOSITY ='
  for line in file:lines() do
      table.insert(file_content, line)
      if string.find(line, "VERBOSITY =") then
          verbosity_line = line
          verbosity_line_number = #file_content
      end
  end

  file:close()

  -- Se 'VERBOSITY =' è stato trovato, sostituisci il valore
  if verbosity_line and verbosity_line_number then
      -- Sostituisci il vecchio valore di verbosity con il nuovo
      local modified_line = string.gsub(verbosity_line, "%d+", tostring(new_verbosity_value), 1)
      file_content[verbosity_line_number] = modified_line

      -- Apri lo stesso file in modalità di scrittura per sovrascrivere
      local file = io.open(filepath, "w")
      for _, line in ipairs(file_content) do
          file:write(line, "\n")
      end

      file:close()
      return true
  else
    reaper.ShowMessageBox('Non sono riuscito ad aprire il file in write', 'setVerbosityDefaultsFile', 0)
      return false
  end
end


function magf.setAudioguideVerbosity(segmentation_script, defaults_script ,isVerbose) -- attiva o disattiva l' output su CL di Audioguide, se attivo non funziona quando chiamato da os.execute() 

  if isVerbose == false then
    magf.setVerbositySegmentationFile(segmentation_script, 0)
    magf.setVerbosityDefaultsFile(defaults_script, 0)
  else
    magf.setVerbositySegmentationFile(segmentation_script, 1)
    magf.setVerbosityDefaultsFile(defaults_script, 2)
  end

end




-- COSTRUZIONE CONCATENATION OPTION FILE AUDIOGUIDE

function magf.build_target_section(source_filename, start_offset, end_offset, tsf_threshold, tsf_offset_rise, tsf_min_seg_len, tsf_max_seg_len) -- prepara la stringa da inserire nella sezione tsf() dell' option file di Audioguide

  local target_section = '\n'
  
  target_section = target_section .. '\'' ..source_filename .. '\', \n'
  
  --sembra che start non funzioni correttamente, viene ignorato
  
  --target_section = target_section .. 'start=' .. tostring(mgf.truncateFloat(start_offset)) .. ', '
  
  --target_section = target_section .. 'end=' .. tostring(mgf.truncateFloat(end_offset)) .. ', '
  
  target_section = target_section .. 'thresh=' .. tostring(tsf_threshold) .. ', \n'
  
  target_section = target_section .. 'offsetRise=' .. tostring(tsf_offset_rise) .. ', \n'
  
  target_section = target_section .. 'minSegLen=' .. tostring(tsf_min_seg_len) .. ', \n'
  
  target_section = target_section .. 'maxSegLen=' .. tostring(tsf_max_seg_len) .. '\n'
  
  -- altri da aggiungere
  
  return target_section
  
end


function magf.build_corpus_section(corpus_items) -- Costruisce la stringa che comporrà la sezione CORPUS dell Option File di Audioguide
    
  local selected_items_path = {}
  local selected_items_start = {}
  local selected_items_end = {}
  
  local corpus_section = '\n'
  
  for i = 1, #corpus_items do
  
    local active_take = reaper.GetActiveTake(corpus_items[i])
    
    selected_items_path[i] = reaper.GetMediaSourceFileName(reaper.GetMediaItemTake_Source(active_take))
    
    selected_items_start[i] = tostring(mgf.truncateFloat(reaper.GetMediaItemTakeInfo_Value(active_take, 'D_STARTOFFS')))
  
    selected_items_end[i] = tostring(mgf.truncateFloat(reaper.GetMediaItemTakeInfo_Value(active_take, 'D_STARTOFFS') + reaper.GetMediaItemInfo_Value( corpus_items[i], 'D_LENGTH')))
  
    corpus_section = corpus_section .. 'csf(\'' .. selected_items_path[i] .. '\', start='.. selected_items_start[i] .. ', end=' .. selected_items_end[i] .. ')'
    
    if i < #corpus_items then
      corpus_section = corpus_section .. ',\n'
    else
      corpus_section = corpus_section .. '\n'
    end
    
  end
  
  return corpus_section
  
end


function magf.build_corpus_global_attributes_section(cga_limit_dur, cga_onset_len, cga_offset_len, cga_allow_repetition, cga_restrict_repetition, cga_restrict_overlaps, cga_clip_duration_to_target) -- Costruisce la stringa che comporrà la sezione CORPUS GLOBAL ATTRIBUTES dell Option File di Audioguide

  local corpus_global_attributes_section = '\n'

  if cga_limit_dur > 0 then
    corpus_global_attributes_section = corpus_global_attributes_section .. '\'limitDur\': ' .. tostring(cga_limit_dur) .. ', \n'
  else
    corpus_global_attributes_section = corpus_global_attributes_section .. '\'limitDur\': ' .. 'None' .. ', \n'
  end

  if cga_allow_repetition then
    corpus_global_attributes_section = corpus_global_attributes_section .. '\'allowRepetition\': ' .. 'True' .. ', \n'
  else
    corpus_global_attributes_section = corpus_global_attributes_section .. '\'allowRepetition\': ' .. 'False' .. ', \n'
  end

  if cga_clip_duration_to_target then
    corpus_global_attributes_section = corpus_global_attributes_section .. '\'clipDurationToTarget\': ' .. 'True' .. ', \n'
  else
    corpus_global_attributes_section = corpus_global_attributes_section .. '\'clipDurationToTarget\': ' .. 'False' .. ', \n'
  end

  corpus_global_attributes_section = corpus_global_attributes_section .. '\'offsetLen\': \'' .. tostring(cga_offset_len) .. '%%\', \n'

  corpus_global_attributes_section = corpus_global_attributes_section .. '\'onsetLen\': \'' .. tostring(cga_onset_len) .. '%%\', \n'

  corpus_global_attributes_section = corpus_global_attributes_section .. '\'restrictOverlaps\': ' .. tostring(cga_restrict_overlaps) .. ', \n'

  corpus_global_attributes_section = corpus_global_attributes_section .. '\'restrictRepetition\': ' .. tostring(cga_restrict_repetition) .. '\n'


  return corpus_global_attributes_section

end


function magf.buid_search_sequence_string(search_mode_list, search_mode_list_percentage, descriptors_matrix) -- costruisce la stringa che comporrà la sezione SEARCH dell option file

  local outstring = ''

  for i = 1, #search_mode_list do

    outstring = outstring .. '\nspass(\'' .. search_mode_list[i] .. '\', '

    for j = 1, #descriptors_matrix[i] do
      
      outstring = outstring .. 'd(\'' .. descriptors_matrix[i][j] .. '\''

      if descriptors_matrix[i][j] == 'effDur-seg' then

        outstring = outstring .. ', norm=1'

      end

      if j == #descriptors_matrix[i] then
        
        if search_mode_list[i] == 'closest_percent' or search_mode_list[i] == 'farthest_percent' then

          outstring = outstring .. '), percent=' .. tostring(search_mode_list_percentage[i]) .. ')'

          if i < #search_mode_list then
            outstring = outstring ..','
          end

        else

          if i == #search_mode_list then
            outstring = outstring ..'))'
          else
            outstring = outstring ..')),'
          end
        end
      else
        outstring = outstring .. '), '
      end
    end
  end

  outstring = outstring .. '\n'

  return outstring
end


function magf.convertSpassListToString(spass_items) -- converte la lista degli spass fornita dall interfaccia grafica in una stringa compatibile con l' option file

  --SPASS_STRING_LIST = 'closest\0closest_percent\0farthest\0farthest_percent\0'

  local search_string_list = {}

  for i = 1, #spass_items do

    if spass_items[i] == 0 then
      search_string_list[i] = 'closest'
    end

    if spass_items[i] == 1 then
      search_string_list[i] = 'closest_percent'
    end

    if spass_items[i] == 2 then
      search_string_list[i] = 'farthest'
    end

    if spass_items[i] == 3 then
      search_string_list[i] = 'farthest_percent'
    end
    
  end

  return search_string_list

end


function magf.convertDescriptorsMatrixToString(descriptors_matrix) -- converte la matrice dei descriptors fornita dall interfaccia grafica in una stringa compatibile con l' option file

  --DESCRIPTORS_STRING_LIST = 'effDur-seg\0power\0power-delta\0centroid\0centroid-delta\0mfccs\0mfccs-delta\0kurtosis\0kurtosis-delta'

  local descriptors_string_matrix = {}

  for i = 1, #descriptors_matrix do

    descriptors_string_matrix[i] = {}

    for j = 1, #descriptors_matrix[i] do

      if descriptors_matrix[i][j] == 0 then
        descriptors_string_matrix[i][j] = 'effDur-seg'
      end

      if descriptors_matrix[i][j] == 1 then
        descriptors_string_matrix[i][j] = 'power'
      end

      if descriptors_matrix[i][j] == 2 then
        descriptors_string_matrix[i][j] = 'power-delta'
      end

      if descriptors_matrix[i][j] == 3 then
        descriptors_string_matrix[i][j] = 'centroid'
      end

      if descriptors_matrix[i][j] == 4 then
        descriptors_string_matrix[i][j] = 'centroid-delta'
      end

      if descriptors_matrix[i][j] == 5 then
        descriptors_string_matrix[i][j] = 'mfccs'
      end

      if descriptors_matrix[i][j] == 6 then
        descriptors_string_matrix[i][j] = 'mfccs-delta'
      end

      if descriptors_matrix[i][j] == 7 then
        descriptors_string_matrix[i][j] = 'kurtosis'
      end

      if descriptors_matrix[i][j] == 8 then
        descriptors_string_matrix[i][j] = 'kurtosis-delta'
      end

    end

  end

  return descriptors_string_matrix

end

function magf.build_superimpose_section(si_min_segment,
                                        si_min_segment_enabled,
                                        si_max_segment,
                                        si_max_segment_enabled,
                                        si_min_frame,
                                        si_min_frame_enabled,
                                        si_max_frame,
                                        si_max_frame_enabled,
                                        si_min_overlap,
                                        si_min_overlap_enabled,
                                        si_max_overlap,
                                        si_max_overlap_enabled
                                      )
  --local superimpose_string = 'SUPERIMPOSE = si('
  local superimpose_string = ''
  local needToBuildString = false

  if si_min_segment_enabled then
    superimpose_string = superimpose_string .. 'minSegment=' .. tostring(si_min_segment) .. ', '
    needToBuildString = true
  end

  if si_max_segment_enabled then
    superimpose_string = superimpose_string .. 'maxSegment=' .. tostring(si_max_segment) .. ', '
    needToBuildString = true
  end

  if si_min_frame_enabled then
    superimpose_string = superimpose_string .. 'minFrame=' .. tostring(si_min_frame) .. ', '
    needToBuildString = true
  end

  if si_max_frame_enabled then
    superimpose_string = superimpose_string .. 'maxFrame=' .. tostring(si_max_frame) .. ', '
    needToBuildString = true
  end

  if si_min_overlap_enabled then
    superimpose_string = superimpose_string .. 'minOverlap=' .. tostring(si_min_overlap) .. ', '
    needToBuildString = true
  end

  if si_max_overlap_enabled then
    superimpose_string = superimpose_string .. 'maxOverlap=' .. tostring(si_max_overlap) .. ', '
    needToBuildString = true
  end

  if needToBuildString then
    superimpose_string = string.sub(superimpose_string, 1, -3)
  end

  --superimpose_string = superimpose_string .. ')'

  return superimpose_string

end

function magf.write_ag_option_file(option_file, target_path, corpus_path, corpus_global_attributes, outputevent_align_peaks, search_sequence, si_sequence, rpp_path) -- aggiorna l' option file di Audioguide

  -- Carica il contenuto del file in una variabile
  local file = io.open(option_file, "r")
  local content = file:read("*a")
  file:close()
  
  -- Applica le funzioni di sostituzione
  content = magf.replaceTarget(content, target_path)
  content = magf.replaceCorpusGlobalAttributes(content, corpus_global_attributes)
  content = magf.replaceCorpus(content, corpus_path)
  content = magf.replaceOutputEventAlignPeaks(content, outputevent_align_peaks)
  content = magf.replaceOutputRpp(content, rpp_path)
  content = magf.replaceSearch(content, search_sequence)
  content = magf.replaceSuperimpose(content, si_sequence)

  -- Scrivi il nuovo contenuto sul file
  file = io.open(option_file, "w")
  file:write(content)
  file:close()
  
end




-- PREPARAZIONE

function magf.clearArtifacts(corpus_audiofiles) -- rimuove dalla directory specificata tutti i file txt e RPP
  
    for i = 1, #corpus_audiofiles do

      --local file_to_remove = reaper.GetMediaSourceFileName(reaper.GetMediaItemTake_Source(reaper.GetActiveTake(corpus_items[i]))) .. '.txt'

      local command = 'rm ' .. mgf.insertBackslashBeforeSpaces(corpus_audiofiles[i] .. '.txt')

      os.execute(command)
    end
end




-- SEGMENTAZIONE

function magf.segmentation(selected_items, seg_threshold, seg_offset_rise, seg_multirise, debug_mode) -- Avvia la segmentazione tramite CL 

  NUMBER_OF_SEGMENTS = 0

  local AFs_path = {}

  for i = 1, #selected_items do
    source = reaper.GetMediaItemTake_Source(reaper.GetActiveTake(selected_items[i]))
    
    AFs_path[i] = reaper.GetMediaSourceFileName(source)

    local arguments_string = ' '

    arguments_string = arguments_string .. '-t ' .. tostring(seg_threshold) .. ' '

    arguments_string = arguments_string .. '-r ' .. tostring(seg_offset_rise) .. ' '

    if seg_multirise == true then arguments_string = arguments_string .. ' -m ' end
  
    command = python .. ' ' .. agSegmentationFile .. arguments_string ..'"' .. AFs_path[i] .. '"'

    if debug_mode then
      reaper.ShowMessageBox(command, 'Segmentation Command', 0)
    else
      return_string = os.execute(command .. " &")
      if (i == #selected_items) then
        return_string = os.execute(command .. " && echo 'done' > /tmp/segmentation_signal_file &")
      end
    end

    --NUMBER_OF_SEGMENTS = NUMBER_OF_SEGMENTS + mgf.countTextFileLines(AF_path .. '.txt')

  end

  return AFs_path
  --reaper.ShowMessageBox('Segmenti Rilevati', tostring(NUMBER_OF_SEGMENTS), 0)
end

-- && 

-- CONCATENAZIONE

function magf.concatenation( target_item , corpus_items, -- Avvia la concatenazione tramite CL, ha tantissimi parametri
  target_filename, 
  tsf_threshold, 
  tsf_offset_rise, 
  tsf_min_seg_len, 
  tsf_max_seg_len, 
  outputevent_align_peaks, 
  cga_limit_dur,
  cga_onset_len,
  cga_offset_len,
  cga_allow_repetition,
  cga_restrict_repetition,
  cga_restrict_overlaps,
  cga_clip_duration_to_target,
  search_mode_list,
  search_mode_list_percentage,
  descriptors_matrix,
  si_min_segment,
  si_min_segment_enabled,
  si_max_segment,
  si_max_segment_enabled,
  si_min_frame,
  si_min_frame_enabled,
  si_max_frame,
  si_max_frame_enabled,
  si_min_overlap,
  si_min_overlap_enabled,
  si_max_overlap,
  si_max_overlap_enabled,
  debug_mode
 ) 


local source = reaper.GetMediaItemTake_Source(reaper.GetActiveTake(target_item))

local start_time = reaper.GetMediaItemTakeInfo_Value(reaper.GetActiveTake(target_item),'D_STARTOFFS')

local end_time = start_time + reaper.GetMediaItemInfo_Value(target_item, 'D_LENGTH')

local source_filename = reaper.GetMediaSourceFileName(source)

local rpp_path = reaper.GetProjectPath() .. '/'..mgf.removeExtension(mgf.removePath(target_filename))..'.RPP'

rpp_path = mgf.uniqueFilename(rpp_path)

local corpus_global_attributes_section = magf.build_corpus_global_attributes_section(cga_limit_dur, cga_onset_len, cga_offset_len, cga_allow_repetition, cga_restrict_repetition, cga_restrict_overlaps, cga_clip_duration_to_target)

local target_section = magf.build_target_section(source_filename, start_time, end_time, tsf_threshold, tsf_offset_rise, tsf_min_seg_len, tsf_max_seg_len)

local corpus_section = magf.build_corpus_section(corpus_items)

local si_section = magf.build_superimpose_section(si_min_segment,
                                                  si_min_segment_enabled,
                                                  si_max_segment,
                                                  si_max_segment_enabled,
                                                  si_min_frame,
                                                  si_min_frame_enabled,
                                                  si_max_frame,
                                                  si_max_frame_enabled,
                                                  si_min_overlap,
                                                  si_min_overlap_enabled,
                                                  si_max_overlap,
                                                  si_max_overlap_enabled
                                                  )

local outputevent_align_peaks_string = ''

if outputevent_align_peaks then
outputevent_align_peaks_string = 'True'
else
outputevent_align_peaks_string = 'False'
end

local search_sequence = magf.buid_search_sequence_string( magf.convertSpassListToString(search_mode_list),
                                 search_mode_list_percentage,
                                 magf.convertDescriptorsMatrixToString(descriptors_matrix)
                               )

magf.write_ag_option_file(option_file,
target_section,
corpus_section,
corpus_global_attributes_section,
outputevent_align_peaks_string,
search_sequence,
si_section,
rpp_path)

command = python .. ' ' .. concatenate_path .. ' ' .. option_file


if debug_mode then
  reaper.ShowMessageBox(command, 'Concatenation Command', 0)
else
  os.execute(command .. " && echo 'done' > /tmp/concatenation_signal_file &")
end

return rpp_path

end


-- RENDER IMPORT E POST-PROCESS AUDIOGUIDE RPP

function magf.setRPPRenderTo32bf(fileName)

  local stringToInsert = '<RENDER_CFG\nZXZhdyAAAA==\n>'
  -- Legge il contenuto del file originale
  local lines = {}
  for line in io.lines(fileName) do 
      table.insert(lines, line)
  end

  -- Apre lo stesso file in scrittura
  local file = io.open(fileName, "w")
  
  -- Controlla se il file è vuoto
  if #lines == 0 then
      file:write(stringToInsert .. "\n")
  else
      -- Scrive la prima riga
      file:write(lines[1] .. "\n")

      -- Inserisce la nuova stringa
      file:write(stringToInsert .. "\n")

      -- Scrive le restanti righe
      for i = 2, #lines do
          file:write(lines[i] .. "\n")
      end
  end

  -- Chiude il file
  file:close()
end


function magf.cl_render_rpp(project_path, file_name, reaper_cli_path) -- renderizza tramite reaper CLI l' RPP di output generato da Audioguide 

  local file_name_without_path = mgf.removeExtension(mgf.removePath(file_name))
  local subproject_path = project_path .. '/'..file_name_without_path..'.RPP'

  -- parte da aggiungere all rpp per accertarsi che sia 32bf
--[[   <RENDER_CFG
  ZXZhdyAAAA==
> ]]

  magf.setRPPRenderTo32bf(subproject_path)

                  --reaper [options] [projectfile.rpp | mediafile.wav | scriptfile.lua [...]]
  local command = reaper_cli_path .. '  -renderproject "' .. subproject_path .. '"' 

  os.execute(command)

  mgf.cl_move(mgf.insertBackslashBeforeSpaces(project_path) .. '/Render/'..mgf.insertBackslashBeforeSpaces(file_name_without_path)..'.wav', mgf.insertBackslashBeforeSpaces(project_path .. '/'..file_name_without_path..'.RPP-PROX'))
  
  mgf.cl_removeDirectory(mgf.insertBackslashBeforeSpaces(project_path) .. '/Render')

  return mgf.removeExtension(file_name) .. '.RPP-PROX'
end


function magf.import_rpp(target_item, target_filename, target_position, reaper_cli_path) -- Importa l' RPP generato dalla concatenazione nel progetto
  
  local rpp_proxy_path = magf.cl_render_rpp(reaper.GetProjectPath(), target_filename, reaper_cli_path)
  
  reaper.InsertMedia(rpp_proxy_path, 1)

  reaper.Main_OnCommand(40285,0)  -- go to next track
  
  rpp_item = reaper.GetSelectedMediaItem(0,reaper.CountSelectedMediaItems(0)-1) 
  
  activeTake = reaper.GetActiveTake(rpp_item)
  
  --reaper.SetMediaItemTakeInfo_Value(activeTake, 'I_CHANMODE', 2) -- mono mix the RPP Proxy
  
  magf.trim_result(rpp_item, target_item) -- in sostituzione dei parametri start e end del tsf
  
  reaper.SetMediaItemPosition(rpp_item, target_position, true) -- move the RPP Proxy under the Target File
  
  reaper.Main_OnCommand(40289,0)  -- unselect all items
  
  reaper.SetMediaItemSelected(rpp_item,true) -- select the new item
  
  reaper.SetEditCurPos(target_position, false, false)

  magf.matchMaxPeak(rpp_item, target_item)
  
end



function magf.trim_result(mediaItem, reference_item) -- taglia in testa e coda il subproject in timeline in modo da farlo combaciare con il target

  local start_time = reaper.GetMediaItemTakeInfo_Value(reaper.GetActiveTake(reference_item),'D_STARTOFFS')
  
  reaper.SetMediaItemTakeInfo_Value(reaper.GetActiveTake(mediaItem), 'D_STARTOFFS', start_time)

  --local lenght = reaper.GetMediaItemInfo_Value(reference_item, 'D_LENGTH')
  
  --local rpp_lenght = reaper.GetMediaSourceLength(reaper.GetMediaItemTake_Source(reaper.GetActiveTake(mediaItem)))

  --reaper.SetMediaItemInfo_Value(mediaItem, 'D_LENGTH', lenght)
  
end

function magf.normalizeMediaItem(rpp_item)

  for i = 1, reaper.CountSelectedMediaItems() do
    reaper.SetMediaItemSelected(reaper.GetSelectedMediaItem(0,i - 1), false)
  end

  reaper.SetMediaItemSelected(rpp_item, true)

  reaper.Main_OnCommand(40108, 0)

end

function magf.matchMaxPeak(mediaItem, reference_item)

  local reference_item_peak = reaper.NF_GetMediaItemMaxPeak(reference_item)

  local mediaItem_peak = reaper.NF_GetMediaItemMaxPeak(mediaItem)
  
  reaper.SetMediaItemTakeInfo_Value(reaper.GetActiveTake(mediaItem), 'D_VOL', mgf.dbToFloat(reference_item_peak - mediaItem_peak))

end

return magf











