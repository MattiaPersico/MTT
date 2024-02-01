local mgf = {}

function mgf.uniqueFilename(fullpath)
  local path, name, ext = fullpath:match("(.-)([^\\/]-%.?([^%.\\/]*))$")
  local base, number = name:match("(.+)_0(%d+)")
  if not base then
    base = name
    number = 0
  else
    number = tonumber(number)
  end

  while true do
    local file = io.open(fullpath, "r")
    if file then
      io.close(file)
      number = number + 1
      fullpath = path .. base .. "_0" .. number .. (ext ~= "" and "." .. ext or "")
    else
      break
    end
  end

  return fullpath
end


function mgf.countTextFileLines(fileName)
  local file = io.open(fileName, "r")  -- Opens the file in read mode
  if not file then
    return 0
  end

  local count = 0
  for _ in file:lines() do
    count = count + 1
  end

  file:close()  -- Closes the file
  return count
end


function mgf.removeLastPathComponent(inputPath)
  -- Cerca tutto il testo che precede l'ultimo slash
  local outputPath = inputPath:match("(.+)/")
  return outputPath
end


function mgf.insertBackslashBeforeSpaces(inputString)
  -- Sostituisci ogni spazio con un backslash seguito da uno spazio
  local outputString = inputString:gsub("(%s)", "\\%1")
  return outputString
end


function mgf.truncateFloat(num)
  return math.floor(num * 10^2) / 10^2
end

function mgf.clearArtifacts(directory)
    
  -- Assicurati che il percorso della directory termini con uno slash
  if directory:sub(-1) ~= "/" then
      directory = directory .. "/"
  end
  
  -- Costruisci il comando per trovare ed eliminare tutti i file .txt
  local command = 'rm ' .. directory .. '*.txt'
  
  -- Esegui il comando
  local result = os.execute(command)
  
  -- Costruisci il comando per trovare ed eliminare tutti i file .txt
  local command = 'rm ' .. directory .. '*.RPP'
  
  -- Esegui il comando
  local result = os.execute(command)
  
  
  -- Costruisci il comando per trovare ed eliminare tutti i file .txt
  local command = 'rm ' .. directory .. '*.RPP-PROX'
  
  -- Esegui il comando
  local result = os.execute(command)
  --reaper.ShowMessageBox(command,command,0)
end

function mgf.removePath(path)
  return path:match("([^/\\]+)$")
end

function mgf.removeExtension(filename)
  return filename:match("(.+)%..+")
end

function mgf.cl_move(current_path, target_path)
  command = 'mv ' .. current_path .. ' ' .. target_path
  os.execute(command)
end

function mgf.cl_removeDirectory(directory)
  command = 'rmdir ' .. directory
  os.execute(command)
end

function mgf.file_exists(file_path)
  local file = io.open(file_path, "r")
  if file then
      io.close(file)
      return true
  else
      return false
  end
end

function mgf.directory_exists(directory_path)
  local handle = io.popen("[ -d '" .. directory_path .. "' ] && echo 'yes'")
  local result = handle:read("*a")
  handle:close()
  return result:match("yes")
end

function mgf.makeFile(file_name, content)
  --local file_path = file_name .. ".py"
  local file = io.open(file_name, "w") -- Apri il file in modalità scrittura, sovrascrivendo se esiste già

  if not file then
      --print("Impossibile creare il file.")
      return false
  end

  -- Scrivi il contenuto nel file
  file:write(content)
  file:close()
  --print("File '" .. file_name .. "' creato con successo.")
end


return mgf





