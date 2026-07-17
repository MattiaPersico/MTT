-- ============================================================================
-- CONFIGURAZIONE
-- ============================================================================
-- Inserisci il percorso assoluto della tua cartella whisper.cpp
local WHISPER_DIR = "/Users/mattiapersico/whisper.cpp"

-- Lingua del parlato ("auto" per il riconoscimento automatico, oppure "it", "en", ecc.)
local LANGUAGE = "auto"

function deleteFile(filePath)
    local handle, err = io.open(filePath, "r") -- Prova ad aprire il file in lettura

    if not handle then
        print("Errore durante l'apertura del file: " .. err)
        return false
    end

    handle:close() -- Chiudi la gestione del file

    local status, err = os.remove(filePath) -- Prova a eliminare il file

    if not status then
        print("Errore durante l'eliminazione del file: " .. err)
        return false
    end

    return true
end

function whisper(item)
    -- 2. Ottieni il take attivo e controlla che non sia MIDI
    local take = reaper.GetActiveTake(item)

    if not take or reaper.TakeIsMIDI(take) then
        reaper.ShowMessageBox("L'item selezionato non è valido o è MIDI. Seleziona un file audio.", "Errore", 0)
        return
    end

    -- 3. FASE DI ESTRAZIONE AUDIO (GLUE TEMPORANEO)
    -- Blocchiamo l'interfaccia di REAPER per non far vedere i passaggi a schermo
    reaper.PreventUIRefresh(1)
    reaper.Undo_BeginBlock()

    -- Salviamo lo stato attuale di cursor e tracce
    local orig_cursor_pos = reaper.GetCursorPosition()
    local orig_track = reaper.GetMediaItem_Track(item)

    -- Copia la porzione dell'item
    reaper.Main_OnCommand(41383, 0) -- Edit: Copy items

    -- Crea una traccia temporanea in fondo al progetto
    reaper.InsertTrackAtIndex(reaper.GetNumTracks(), false)
    local temp_track = reaper.GetTrack(0, reaper.GetNumTracks() - 1)
    reaper.SetOnlyTrackSelected(temp_track)

    -- Sposta il cursore a inizio progetto e incolla l'item
    reaper.SetEditCurPos(0, false, false)
    reaper.Main_OnCommand(40058, 0) -- Item: Paste items/tracks

    -- Fa il "Glue" dell'item, creando un file audio tagliato su misura
    reaper.Main_OnCommand(41588, 0) -- Item: Glue items

    -- Recupera il percorso del nuovo file audio tagliato
    local pasted_item = reaper.GetSelectedMediaItem(0, 0)
    local pasted_take = reaper.GetActiveTake(pasted_item)
    local pasted_source = reaper.GetMediaItemTake_Source(pasted_take)
    local temp_audio_path = reaper.GetMediaSourceFileName(pasted_source, "")

    -- Distrugge la traccia temporanea e ripristina la visuale originale
    reaper.DeleteTrack(temp_track)
    reaper.SetEditCurPos(orig_cursor_pos, false, false)
    reaper.SetOnlyTrackSelected(orig_track)
    reaper.SetMediaItemSelected(item, true)

    reaper.Undo_EndBlock("Estrazione temporanea per Whisper", -1)
    reaper.PreventUIRefresh(-1)

    if temp_audio_path == "" then
        reaper.ShowMessageBox("Errore nella generazione del file audio temporaneo.", "Errore", 0)
        return
    end

    -- 4. Costruisci il comando Whisper (ora passiamo il file perfetto, niente offset necessari!)
    local cmd =
        string.format(
        'cd "%s" && ./build/bin/whisper-cli -f "%s" -nt -np -l %s 2>&1',
        WHISPER_DIR,
        temp_audio_path,
        LANGUAGE
    )

    -- Avviso in console
    --reaper.PrintToConsole("Whisper sta elaborando l'audio ritagliato... Attendi.\n")

    -- 5. Esegui il comando e cattura l'outputn
    local handle = io.popen(cmd)
    if not handle then
        reaper.ShowMessageBox("Errore critico nell'apertura del terminale di sistema.", "Errore", 0)
        return
    end

    local result = handle:read("*a")
    handle:close()

    os.remove(temp_audio_path) -- Prova a eliminare il file

    -- 6. FILTRO DEI LOG
    local cleaned_lines = {}
    for line in result:gmatch("[^\r\n]+") do
        if not line:match("^read_audio_data:") and not line:match("^main:") and not line:match("^whisper_") then
            table.insert(cleaned_lines, line)
        end
    end
    result = table.concat(cleaned_lines, "\n")
    result = result:gsub("^%s*(.-)%s*$", "%1")

    -- 7. Mostra il risultato a schermo
    if result == "" then
        return ""
    else
        return result
    end
end

function doTheMagic() --rinominami
    local selectedItem = reaper.GetSelectedMediaItem(0, 0)

    if selectedItem == nil then
        reaper.ShowMessageBox("Selezionare il Media Item da analizzare", "", 0)
        return
    end

    local selStart, selEnd = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)

    local track = reaper.GetMediaItem_Track(selectedItem)

    -- Trova la traccia parent più alta
    local parentTrack = track
    
    while true do
        local nextParentTrack = reaper.GetParentTrack(parentTrack)
        if not nextParentTrack then
            break
        end
        parentTrack = nextParentTrack
    end

    if parentTrack == track or parentTrack == nil then
        reaper.ShowMessageBox("Il Media Item deve essere contenuto in una child track", "", 0)
        return
    end

    local nItems = reaper.CountTrackMediaItems(parentTrack)

    for i = 0, nItems - 1 do
        local targetItem = reaper.GetTrackMediaItem(parentTrack, i)

        local itemStartPosition = reaper.GetMediaItemInfo_Value(targetItem, "D_POSITION")

        local itemLenght = reaper.GetMediaItemInfo_Value(targetItem, "D_LENGTH")

        local take = reaper.GetActiveTake(targetItem)

        local itemEndPosition = itemStartPosition + itemLenght

        if not ((selEnd < itemStartPosition) or (selStart > itemEndPosition)) then
            local takeStartOffset = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")

            local firstMarkerPosition = takeStartOffset + selStart - itemStartPosition
            local endMarkerPosition = firstMarkerPosition + selEnd - selStart

            if firstMarkerPosition < 0 then
                firstMarkerPosition = 0 + takeStartOffset
            end

            if itemEndPosition < selEnd then
                endMarkerPosition = itemLenght
            end

            local text = whisper(selectedItem)

            if text == "[BLANK_AUDIO]" then text = " " --reaper.ShowConsoleMsg(text)
            end

            reaper.SetTakeMarker(take, -1, text, firstMarkerPosition)

            reaper.SetTakeMarker(take, -1, "B", endMarkerPosition)
        end
    end
end

function main()
    reaper.Undo_BeginBlock()

    doTheMagic()

    reaper.Undo_EndBlock("mtt_Whisper", 0)
end

-- ============================================================================
-- FUNZIONE PRINCIPALE
-- ============================================================================

-- Esegui lo script
main()
