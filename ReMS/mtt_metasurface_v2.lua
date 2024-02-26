-- Appunti:

-- aggiungere menu dei settings
-- inserire filtri esclusione parametri personalizzabili 
-- inserire filtri esclusione tracce personalizzabili
-- inserire filtri esclusione effetti personalizzabili
-- salvare i filtri nel save file oppure in un foglio di salvataggio globale
-- 
-- Script Name and Version

local major_version = 0
local minor_version = 9

local name = 'Metasurface ' .. tostring(major_version) .. '.' .. tostring(minor_version)

local PLAY_STOP_COMMAND = '_4d1cade28fdc481a931786c4bb44c78d'
local PLAY_STOP_LOOP_COMMAND = '_b254db4208aa487c98dc725e435e531c'
local SAVE_PROJECT_COMMAND = '40026'

local PREF_WINDOW_WIDTH = 200
local PREF_WINDOW_HEIGHT = 400

local MAX_MAIN_WINDOW_WIDTH = 600
local MAX_MAIN_WINDOW_HEIGHT = 600

local MAIN_WINDOW_WIDTH = 500
local MAIN_WINDOW_HEIGHT = 500

local WIDTH_OFFSET = 16
local HEIGHT_OFFSET = 74

local ACTION_WINDOW_WIDTH = MAIN_WINDOW_WIDTH - WIDTH_OFFSET
local ACTION_WINDOW_HEIGHT = MAIN_WINDOW_HEIGHT - HEIGHT_OFFSET

local IGNORE_STRING = 'midi'
-- Funzione EEL per i Vincoli delle Dimensioni della Finestra
local sizeConstraintsCallback = [=[
a = 0
]=]

dofile(reaper.GetResourcePath() .. '/Scripts/ReaTeam Extensions/API/imgui.lua')('0.8')
local ctx = reaper.ImGui_CreateContext(name)
local comic_sans = reaper.ImGui_CreateFont('/System/Library/Fonts/Supplemental/Comic Sans MS.ttf', 18)
local comic_sans_bigger = reaper.ImGui_CreateFont('/System/Library/Fonts/Supplemental/Comic Sans MS.ttf', 21)
local comic_sans_smaller = reaper.ImGui_CreateFont('/System/Library/Fonts/Supplemental/Comic Sans MS.ttf', 17)

reaper.ImGui_Attach(ctx, comic_sans)
reaper.ImGui_Attach(ctx, comic_sans_bigger)
reaper.ImGui_Attach(ctx, comic_sans_smaller)

local grouped_parameters = {}
local points_list = {}
local snapshot_list = {}

--local is_new_value,filename,sectionID,cmdID,mode,resolution,val,contextstr = reaper.get_action_context()

local fx_snapshot = {
    guid = 0,
    param_list = {},
    param_index_list = {}
}

function fx_snapshot:new(guid)
    local instance = setmetatable({}, {__index = self})
    instance.param_list = {}
    instance.guid = guid or 0
    instance.param_index_list = {}
    return instance
end

local track_snapshot = {
    guid = 0,
    fx_list = {}
}

function track_snapshot:new(guid)
    local instance = setmetatable({}, {__index = self})
    instance.fx_list = {}
    instance.guid = guid or 0
    return instance
end

local proj_snapshot = {
    x = 0,
    y = 0,
    name,
    track_list = {},
    assigned = false
}

function proj_snapshot:new(x, y, name)
    local instance = setmetatable({}, {__index = self})
    instance.x = x or 0
    instance.y = y or 0
    instance.name = name
    instance.track_list = {}
    instance.assigned = false
    return instance
end

local parameter = {
    track = nil,
    fx_index = nil,
    param_list_index = nil,
    param_value = nil,
    snap_index = nil
}

function parameter:new(track, fx_index, param_list_index, param_value, snap_index)
    local instance = setmetatable({}, {__index = self})
    instance.track = track or nil
    instance.fx_index = fx_index or nil
    instance.param_list_index = param_list_index or nil
    instance.param_value = param_value or nil
    instance.snap_index = snap_index or nil
    return instance
end


LAST_TOUCHED_BUTTON_INDEX = nil

DRAG_X = 0
DRAG_Y = 0

-- Variabili per lo smoothing
local smoothing = 5
local smoothing_max_value = 20
local smoothing_fader_value = 0.3
local targetX, targetY = 0, 0 -- Coordinate target
local lastUpdateTime = reaper.time_precise()
local needToInitSmoothing = true
local CURRENT_DRAG_X = 0
local CURRENT_DRAG_Y = 0

local is_name_edited = false
local preferencesWindowState = false

local PROJECT_NAME = reaper.GetProjectName(0)
local PROJECT_PATH = reaper.GetProjectPath(0)

local need_to_save = false
local isDragging = false
local quit = false

function serialize(obj)
    local luaType = type(obj)
    if luaType == "number" or luaType == "boolean" then
        return tostring(obj)
    elseif luaType == "string" then
        return string.format("%q", obj)
    elseif luaType == "table" then
        local isList = true
        local elements = {}
        for k, v in pairs(obj) do
            if type(k) ~= "number" then isList = false end -- Semplice verifica per distinguere le liste dalle mappe
            local serializedValue = serialize(v)
            if isList then
                table.insert(elements, serializedValue)
            else
                local key = type(k) == "string" and string.format("%q", k) or tostring(k)
                table.insert(elements, "[" .. key .. "] = " .. serializedValue)
            end
        end
        if isList then
            return "{" .. table.concat(elements, ", ") .. "}"
        else
            return "{ " .. table.concat(elements, ", ") .. " }"
        end
    else
        return "\"[unsupported type]\""
    end
end

function saveToFile(filePath, data)
    local file, err = io.open(filePath, "w") -- Apre il file in modalità scrittura
    if not file then
        error("Non è stato possibile aprire il file: " .. err)
    end
    file:write(data) -- Scrive i dati serializzati nel file
    file:close() -- Chiude il file
end

function writeSnapshotsToFile(filename)
    local data = serialize(snapshot_list)
    saveToFile(filename, data)
end

function readSnapshotsFromFile(filename)
    local file, err = io.open(filename, "r") -- Apre il file in modalità lettura
    if not file then
        return
    end
    local dataString = file:read("*a") -- Legge tutto il contenuto del file come stringa
    file:close() -- Chiude il file

    local projects = load("return " .. dataString) -- Deserializza la stringa in dati Lua
    if projects then
        return projects() -- Esegue la funzione deserializzata per ottenere i dati
    else
        error("Errore durante la deserializzazione dei dati")
    end
end

function GetNormalizedMousePosition()
    local mouseX, mouseY = GetMouseCursorPositionInWindow() -- Usa la tua funzione esistente
    local normalizedX = mouseX / ACTION_WINDOW_WIDTH
    local normalizedY = mouseY / ACTION_WINDOW_HEIGHT
    return normalizedX, normalizedY
end

function gui_loop()

    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), reaper.ImGui_ColorConvertDouble4ToU32(0.1, 0.1, 0.1, 1))
  
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), reaper.ImGui_ColorConvertDouble4ToU32(0.45, 0.45, 0.45, 2)) 
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_BorderShadow(), reaper.ImGui_ColorConvertDouble4ToU32(0, 0, 0, 2))
  
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), reaper.ImGui_ColorConvertDouble4ToU32(0.1, 0.1, 0.1, 2)) 
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), reaper.ImGui_ColorConvertDouble4ToU32(0.1, 0.1, 0.1, 2))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), reaper.ImGui_ColorConvertDouble4ToU32(0.18, 0.18, 0.18, 2)) 
  
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_MenuBarBg(), reaper.ImGui_ColorConvertDouble4ToU32(0.1, 0.1, 0.1, 2)) 
  
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), reaper.ImGui_ColorConvertDouble4ToU32(0.18, 0.18, 0.18, 2))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), reaper.ImGui_ColorConvertDouble4ToU32(0.3, 0.3, 0.3, 2))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), reaper.ImGui_ColorConvertDouble4ToU32(0.18, 0.18, 0.18, 2))
    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ResizeGrip(), reaper.ImGui_ColorConvertDouble4ToU32(0.18, 0.18, 0.18, 2))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ResizeGripActive(), reaper.ImGui_ColorConvertDouble4ToU32(0.3, 0.3, 0.3, 2))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ResizeGripHovered(), reaper.ImGui_ColorConvertDouble4ToU32(0.18, 0.18, 0.18, 2))

    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBg(), reaper.ImGui_ColorConvertDouble4ToU32(0.14, 0.14, 0.14, 2)) 
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBgActive(), reaper.ImGui_ColorConvertDouble4ToU32(0.18, 0.18, 0.18, 2))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBgCollapsed(), reaper.ImGui_ColorConvertDouble4ToU32(0.18, 0.18, 0.18, 2))
  
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), reaper.ImGui_ColorConvertDouble4ToU32(0.18, 0.18, 0.18, 2))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgActive(), reaper.ImGui_ColorConvertDouble4ToU32(0.4, 0.4, 0.4, 2))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(), reaper.ImGui_ColorConvertDouble4ToU32(0.25, 0.25, 0.25, 2))
  
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_SliderGrab(), reaper.ImGui_ColorConvertDouble4ToU32(0.5, 0.5, 0.5, 2))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_SliderGrabActive(), reaper.ImGui_ColorConvertDouble4ToU32(0.13, 0.13, 0.13, 2))
    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_CheckMark(), reaper.ImGui_ColorConvertDouble4ToU32(0.8, 0.8, 0.8, 2))
  
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Separator(), reaper.ImGui_ColorConvertDouble4ToU32(0.35, 0.35, 0.35, 2))
  
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ScrollbarSize(), 10)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarBg(), reaper.ImGui_ColorConvertDouble4ToU32(0.09, 0.09, 0.09, 1))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrab(), reaper.ImGui_ColorConvertDouble4ToU32(0.3, 0.3, 0.3, 1))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrabActive(), reaper.ImGui_ColorConvertDouble4ToU32(0.2, 0.2, 0.2, 1))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrabHovered(), reaper.ImGui_ColorConvertDouble4ToU32(0.5, 0.5, 0.5, 1))
    
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 7)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ScrollbarRounding(), 7)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_GrabRounding(), 7)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ChildRounding(), 7)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 5) 
  
    reaper.ImGui_PushFont(ctx, comic_sans)

    reaper.ImGui_SetNextWindowSizeConstraints(ctx, MAX_MAIN_WINDOW_WIDTH, MAX_MAIN_WINDOW_HEIGHT, 900, 900, reaper.ImGui_CreateFunctionFromEEL(sizeConstraintsCallback))

    local mw_visible, mw_open = reaper.ImGui_Begin(ctx, name, true, --reaper.ImGui_WindowFlags_NoResize() |  
                                                                     reaper.ImGui_WindowFlags_NoCollapse()
                                                                    | reaper.ImGui_WindowFlags_NoScrollbar()
                                                                    | reaper.ImGui_WindowFlags_NoScrollWithMouse()  
                                                                    )
    

    MAIN_WINDOW_WIDTH, MAIN_WINDOW_HEIGHT = reaper.ImGui_GetWindowSize(ctx)
    ACTION_WINDOW_WIDTH = MAIN_WINDOW_WIDTH - WIDTH_OFFSET
    ACTION_WINDOW_HEIGHT = MAIN_WINDOW_HEIGHT - HEIGHT_OFFSET
    
    main_window_x, main_window_y = reaper.ImGui_GetWindowPos(ctx)
    main_window_w, main_window_h = reaper.ImGui_GetWindowSize(ctx)
  
  
    if mw_visible then
      mainWindow()

      reaper.ImGui_End(ctx)


      pref_window_x = main_window_x + main_window_w
      pref_window_y = main_window_y
  
      if preferencesWindowState then
  
        reaper.ImGui_SetNextWindowPos(ctx, pref_window_x, pref_window_y)
        reaper.ImGui_SetNextWindowSize(ctx, PREF_WINDOW_WIDTH, PREF_WINDOW_HEIGHT)--, reaper.ImGui_Cond_FirstUseEver())
  
        local pw_visible, pw_open = reaper.ImGui_Begin(ctx, 'Preferences',false, reaper.ImGui_WindowFlags_NoResize() | reaper.ImGui_WindowFlags_NoCollapse())
  
        if pw_visible then
          preferencesWindow()
          reaper.ImGui_End(ctx)
          
        end
      end

      reaper.ImGui_PopFont(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleVar(ctx)
      reaper.ImGui_PopStyleVar(ctx)
      reaper.ImGui_PopStyleVar(ctx)  
      reaper.ImGui_PopStyleVar(ctx)
      reaper.ImGui_PopStyleVar(ctx)
      reaper.ImGui_PopStyleVar(ctx)
  
    end

    if mw_open and PROJECT_NAME ~= '' and quit == false then
        reaper.defer(loop)
    end

end

function loop()
    
    --reaper.ShowConsoleMsg(contextstr .. '\n')

    gui_loop()
    
    if not isDragging then
        if reaper.GetProjectName(0) ~= PROJECT_NAME then
            onExit()
            initMS()
        end

        if reaper.IsProjectDirty(0) == 1 then need_to_save = true end

        if reaper.IsProjectDirty(0) == 0 and need_to_save == true then
            writeSnapshotsToFile(PROJECT_PATH .. '/ms_save')
            need_to_save = false
        end
    end

end

function GetMouseClickPositionInWindow(ctx, button)
    -- Ottieni la posizione del click del mouse
    local mouseClickedX, mouseClickedY = reaper.ImGui_GetMouseClickedPos(ctx, button)

    -- Ottieni la posizione dell'angolo in alto a sinistra della finestra ImGui
    local windowPosX, windowPosY = reaper.ImGui_GetWindowPos(ctx)

    -- Calcola la posizione del click del mouse relativa alla finestra ImGui
    local relativeClickPosX = mouseClickedX - windowPosX
    local relativeClickPosY = mouseClickedY - windowPosY

    -- (Opzionale) Controlla se il click è all'interno della finestra
    local windowWidth, windowHeight = reaper.ImGui_GetWindowSize(ctx)
    if relativeClickPosX >= 0 and relativeClickPosX <= windowWidth and
       relativeClickPosY >= 0 and relativeClickPosY <= windowHeight then
        -- Il click è all'interno della finestra
        return relativeClickPosX, relativeClickPosY
    else
        -- Il click è fuori dalla finestra, puoi gestire questo caso come preferisci
        return nil, nil
    end
end

function GetMouseCursorPositionInWindow()
    local mouseClickedX, mouseClickedY = reaper.ImGui_GetMousePos(ctx)

    -- Ottieni la posizione dell'angolo in alto a sinistra della finestra ImGui
    local windowPosX, windowPosY = reaper.ImGui_GetWindowPos(ctx)

    -- Calcola la posizione del click del mouse relativa alla finestra ImGui
    local relativeClickPosX = mouseClickedX - windowPosX
    local relativeClickPosY = mouseClickedY - windowPosY

    -- (Opzionale) Controlla se il click è all'interno della finestra
    local windowWidth, windowHeight = reaper.ImGui_GetWindowSize(ctx)
    if relativeClickPosX >= 0 and relativeClickPosX <= windowWidth and
       relativeClickPosY >= 0 and relativeClickPosY <= windowHeight then
        -- Il click è all'interno della finestra
        return relativeClickPosX, relativeClickPosY
    else
        -- Il click è fuori dalla finestra, puoi gestire questo caso come preferisci
        return DRAG_X, DRAG_Y
    end
end

function onRightClick()
    if reaper.ImGui_IsMouseClicked(ctx, 1, false) and reaper.CountTracks(0) > 0 then
        -- Ottieni la posizione del click del mouse come coordinate assolute
        local absX, absY = GetMouseClickPositionInWindow(ctx, 1)

        if not absX or not absY then return end

        -- Converti le coordinate assolute in coordinate normalizzate
        local normalizedX = absX / ACTION_WINDOW_WIDTH
        local normalizedY = absY / ACTION_WINDOW_HEIGHT

        -- Crea un nuovo snapshot utilizzando le coordinate normalizzate
        snapshot_list[#snapshot_list + 1] = proj_snapshot:new(normalizedX, normalizedY)
        LAST_TOUCHED_BUTTON_INDEX = #snapshot_list

        saveSelected()
    end
end

function drawSnapshots()

    local num_selected_tracks = reaper.CountTracks(0)
    
    for s = #snapshot_list, 1, -1 do
        -- Converti le coordinate normalizzate in coordinate assolute basate sulle dimensioni attuali della finestra
        local absoluteX = snapshot_list[s].x * ACTION_WINDOW_WIDTH - 7
        local absoluteY = snapshot_list[s].y * ACTION_WINDOW_HEIGHT - 9

        reaper.ImGui_SetCursorPos(ctx, absoluteX, absoluteY)

        --local name = 'B'
        if s == LAST_TOUCHED_BUTTON_INDEX or #snapshot_list == 1 then
            --LAST_TOUCHED_BUTTON_INDEX = s
            --name = 'S'
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), reaper.ImGui_ColorConvertDouble4ToU32(0.0, 0.5, 0.0, 2))
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), reaper.ImGui_ColorConvertDouble4ToU32(0.0, 0.6, 0.0, 2))
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), reaper.ImGui_ColorConvertDouble4ToU32(0.0, 0.5, 0.0, 2))
        else
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), reaper.ImGui_ColorConvertDouble4ToU32(0.3, 0.3, 0.3, 2))
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), reaper.ImGui_ColorConvertDouble4ToU32(0.4, 0.4, 0.4, 2))
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), reaper.ImGui_ColorConvertDouble4ToU32(0.3, 0.3, 0.3, 2))
        end

        if reaper.ImGui_Button(ctx,  '##' .. tostring(s), 12, 12) then
            
            if not reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftShift()) then

                LAST_TOUCHED_BUTTON_INDEX = s

                for t = 1, #snapshot_list[s].track_list do
                    local track = getTrackByGUID(0, snapshot_list[s].track_list[t].guid)

                    for f = 1, #snapshot_list[s].track_list[t].fx_list do
                        --reaper.MB(snapshot_list[s].track_list[t].fx_list[f].guid, '', 0)
                        local retval, fx_index = getFxIndexByGUID(track, snapshot_list[s].track_list[t].fx_list[f].guid)

                        if retval then
                            for p = 1, #snapshot_list[s].track_list[t].fx_list[f].param_list do

                                local param_value = snapshot_list[s].track_list[t].fx_list[f].param_list[p]

                                if track then
                                    reaper.TrackFX_SetParam(track, fx_index, (p-1), param_value)
                                end
                            end
                        end
                    end
                end
            else
                if LAST_TOUCHED_BUTTON_INDEX == #snapshot_list then LAST_TOUCHED_BUTTON_INDEX = #snapshot_list - 1 end
                table.remove(snapshot_list, s)
                updateSnapshotIndexList()
            end
        end
        
        if snapshot_list[s] then
            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_SetNextItemWidth(ctx, 60)
            if reaper.ImGui_GetCursorPosX(ctx) > ((MAIN_WINDOW_WIDTH / 3) * 2) then
                local str_len = string.len(snapshot_list[s].name)
                local  w,  h = reaper.ImGui_CalcTextSize(ctx, snapshot_list[s].name, 60, 20)
                reaper.ImGui_SetCursorPos(ctx, reaper.ImGui_GetCursorPosX(ctx)- 25 - w, reaper.ImGui_GetCursorPosY(ctx) - 7)
            else
                reaper.ImGui_SetCursorPos(ctx, reaper.ImGui_GetCursorPosX(ctx)- 3, reaper.ImGui_GetCursorPosY(ctx) - 7)
            end

            reaper.ImGui_Text(ctx, snapshot_list[s].name)
        end

        reaper.ImGui_PopStyleColor(ctx)
        reaper.ImGui_PopStyleColor(ctx)
        reaper.ImGui_PopStyleColor(ctx)
    end
end

function inverseDistanceWeighting(points, x, y, power)
    local numerator = 0
    local denominator = 0
    power = power or 2 -- Imposta il valore di default del power se non specificato

    for _, point in ipairs(points) do
        local dx = x - point.x
        local dy = y - point.y
        local distance = math.sqrt(dx^2 + dy^2)
        if distance > 0 then -- Evita la divisione per zero
            local weight = 1 / (distance ^ power)
            numerator = numerator + (point.value * weight)
            denominator = denominator + weight
        else
            return point.value -- Ritorna immediatamente il valore se il punto è esattamente uguale
        end
    end

    if denominator == 0 then return 0 end -- Evita la divisione per zero
    return numerator / denominator
end

function initSmoothing(x, y)
    CURRENT_DRAG_X, CURRENT_DRAG_Y = x, y -- Imposta le coordinate iniziali
    targetX, targetY = x, y -- Sincronizza il target con la posizione iniziale
    lastUpdateTime = reaper.time_precise()
    needToInitSmoothing = false
end

function updateSmoothingTarget(x, y)
    targetX, targetY = x, y -- Aggiorna il target con le nuove coordinate
end

function updateSmoothingPosition()
    local currentTime = reaper.time_precise()
    local deltaTime = currentTime - lastUpdateTime
    local smooth_multiplier

    if smoothing > 0 then smooth_multiplier = smoothing else smooth_multiplier = 0.3 end

    
    local smoothingFactor = deltaTime * smooth_multiplier -- Regola questo valore per modificare la "velocità" di smoothing

    CURRENT_DRAG_X = CURRENT_DRAG_X + (targetX - CURRENT_DRAG_X) * smoothingFactor
    CURRENT_DRAG_Y = CURRENT_DRAG_Y + (targetY - CURRENT_DRAG_Y) * smoothingFactor

    lastUpdateTime = currentTime
end

function windowToScreenCoordinates(xRelativo, yRelativo)
    -- Ottieni la posizione della finestra ImGui
    local posXFinestra, posYFinestra = reaper.ImGui_GetWindowPos(ctx)

    -- Calcola le coordinate assolute aggiungendo le coordinate relative della finestra
    local xSchermo = posXFinestra + xRelativo
    local ySchermo = posYFinestra + yRelativo

    return xSchermo, ySchermo
end

function onDragLeftMouse()
    isDragging = reaper.ImGui_IsMouseDragging(ctx, 0)
    
    if isDragging then
        reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_None())
        -- Ottieni la posizione normalizzata del mouse
        local normalizedX, normalizedY = GetNormalizedMousePosition()

        -- Converti le coordinate normalizzate in posizione reale se necessario
        -- Esempio: applicazione diretta senza conversione, poiché la logica IDW utilizza valori normalizzati
        DRAG_X = normalizedX * ACTION_WINDOW_WIDTH
        DRAG_Y = normalizedY * ACTION_WINDOW_HEIGHT

        if smoothing_fader_value ~= 0 then
            if needToInitSmoothing == true then
                initSmoothing(DRAG_X, DRAG_Y)
                updateSnapshotIndexList()
                --reaper.ShowConsoleMsg('brodo' .. '\n')
            end

            updateSmoothingTarget(DRAG_X, DRAG_Y)
            updateSmoothingPosition()
        else
            CURRENT_DRAG_X = DRAG_X
            CURRENT_DRAG_Y = DRAG_Y
        end

        local circle_x, circle_y = windowToScreenCoordinates(CURRENT_DRAG_X, CURRENT_DRAG_Y)
        local dot_x, dot_y = windowToScreenCoordinates(DRAG_X, DRAG_Y)

        drawCircle(circle_x,circle_y, 4)
        drawDot(dot_x,dot_y, 2)

         for groupIndex, group in ipairs(grouped_parameters) do
            local pointsForGroup = points_list[groupIndex] -- Ottieni i punti corrispondenti per questo gruppo
        
            -- Calcola il valore interpolato per questo gruppo di punti
            local interpolatedValue = inverseDistanceWeighting(pointsForGroup, CURRENT_DRAG_X, CURRENT_DRAG_Y, 2) -- power = 2 come esempio
        
            -- Applica questo valore interpolato a tutti i parametri nel gruppo
            for _, parameter in ipairs(group) do
                reaper.TrackFX_SetParam(parameter.track, parameter.fx_index, parameter.param_list_index, interpolatedValue)
            end
        end
    else
        needToInitSmoothing = true
        reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Arrow())
    end
end

function updateSnapshotIndexList()

    if #snapshot_list <= 1 then return end

    local parameters_to_be_updated = {}

    for s1 = 1, #snapshot_list do
        for s2 = 1, #snapshot_list do
            
            for t = 1, #snapshot_list[s1].track_list do
                local retval, track_list_index = checkIfSameTrackExists(snapshot_list[s1].track_list[t], snapshot_list[s2].track_list)
                
                if retval then
                    local track = getTrackByGUID(0, snapshot_list[s1].track_list[t].guid)

                    for f = 1, #snapshot_list[s1].track_list[t].fx_list do
                        local retval, fx_list_index = checkIfSameFxExists(snapshot_list[s1].track_list[t].fx_list[f], snapshot_list[s2].track_list[track_list_index].fx_list)
                        
                        if retval then
                            local retval, fx_parameter_indexes = checkIfParametersHaveDifferentValues(snapshot_list[s1].track_list[t].fx_list[f].param_list, snapshot_list[s2].track_list[track_list_index].fx_list[fx_list_index].param_list)
                            
                            if retval then
                                for p = 1, #fx_parameter_indexes do

                                    if track then
                                        local fx_index_retval, fx = getFxIndexByGUID(track, snapshot_list[s1].track_list[t].fx_list[f].guid)

                                        if fx_index_retval then
                                            local parameter_index = fx_parameter_indexes[p]

                                            local new_parameter = parameter:new(track, fx, snapshot_list[s1].track_list[t].fx_list[f].param_index_list[parameter_index], snapshot_list[s1].track_list[t].fx_list[f].param_list[parameter_index], s1)
                                            --reaper.ShowConsoleMsg(tostring(param_value) .. '\n')
                                            table.insert(parameters_to_be_updated, new_parameter)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end


    grouped_parameters = {} -- Questo conterrà le liste finali raggruppate

    for _, parameter in ipairs(parameters_to_be_updated) do
        local foundGroup = false

        for _, group in ipairs(grouped_parameters) do
            if  group[1].track == parameter.track and
                group[1].fx_index == parameter.fx_index and
                group[1].param_list_index == parameter.param_list_index then
                table.insert(group, parameter)
                foundGroup = true
                break
            end
        end

        if not foundGroup then
            table.insert(grouped_parameters, {parameter})
        end
    end

    points_list = {}

    for _, group in ipairs(grouped_parameters) do
        local pointsForGroup = {} -- Lista di punti per l'attuale gruppo di parametri
    
        for _, param in ipairs(group) do
            local snap = snapshot_list[param.snap_index] -- Ottieni lo snapshot basato sull'indice
    
            if snap then -- Controlla se lo snapshot esiste per evitare errori
                local point = {
                    x = snap.x * ACTION_WINDOW_WIDTH,
                    y = snap.y * ACTION_WINDOW_HEIGHT,
                    value = param.param_value
                }
                table.insert(pointsForGroup, point)
            end
        end
    
        -- Aggiungi i punti generati per questo gruppo alla lista principale dei punti
        table.insert(points_list, pointsForGroup)
    end

end

function saveSelected()
    
    if LAST_TOUCHED_BUTTON_INDEX and reaper.CountTracks(0) > 0 then

        local s = LAST_TOUCHED_BUTTON_INDEX

        local temp_x = snapshot_list[s].x
        local temp_y = snapshot_list[s].y

        local snap_name = snapshot_list[s].name or ('Snap ' .. tostring(s))

        snapshot_list[s] = proj_snapshot:new(temp_x, temp_y, snap_name)

        for i = 0, reaper.CountTracks(0) - 1 do
            local current_track = reaper.GetTrack(0,i)
            local new_track_snapshot = track_snapshot:new(reaper.GetTrackGUID(current_track))
            table.insert(snapshot_list[s].track_list, new_track_snapshot)
            --snapshot_list[s].track_list[#snapshot_list[s].track_list + 1] = new_track_snapshot

            for j = 0, reaper.TrackFX_GetCount(current_track) - 1 do
                local current_fx_index_retval, current_fx_index = getFxIndexByGUID(current_track, reaper.TrackFX_GetFXGUID(current_track, j))
                local new_fx_snapshot = fx_snapshot:new(reaper.TrackFX_GetFXGUID(current_track, j))
                table.insert(snapshot_list[s].track_list[i+1].fx_list, new_fx_snapshot)

                for z = 0, reaper.TrackFX_GetNumParams(current_track, current_fx_index) do
                    local retval, p_name = reaper.TrackFX_GetParamName(current_track, current_fx_index, z)
                    if not containsAnyFormOf(p_name, IGNORE_STRING) then
                        local retval, minval, maxval
                        retval, minval, maxval = reaper.TrackFX_GetParam(current_track, current_fx_index, z)
                        table.insert(snapshot_list[s].track_list[i+1].fx_list[j+1].param_list, retval)
                        table.insert(snapshot_list[s].track_list[i+1].fx_list[j+1].param_index_list, z)
                    end
                    --local retnameval, name = reaper.TrackFX_GetParamName(current_track, current_fx_index, z)
                    --reaper.MB(tostring(retval), name, 0)
                end

            end

        end

        snapshot_list[s].assigned = true

        updateSnapshotIndexList()
    end

    reaper.MarkProjectDirty(0)

    PROJECT_PATH = reaper.GetProjectPath(0)
end

function checkIfParametersHaveDifferentValues(param_list_1, param_list_2)

    local param_list_indexes = {}
    local retval = false

    for i = 1, #param_list_1 do
        if param_list_1[i] ~= param_list_2[i] then
            table.insert(param_list_indexes, i)
            retval = true
        end
    end

    if retval then
        return true, param_list_indexes
    else
        return false, nil
    end

end

function checkIfSameTrackExists(track, track_list)

    for i = 1, #track_list do
        if track.guid == track_list[i].guid then
            return true, i
        end
    end

    return false, nil
end

function checkIfSameFxExists(fx, fx_list)

    for i = 1, #fx_list do
        if fx.guid == fx_list[i].guid then
            return true, i
        end
    end

    return false, nil
end

function containsAnyFormOf(s, ref_string)
    -- Rimuovi gli spazi per gestire concatenazioni come "NoteMidiCC" e converti in minuscolo
    local compactS = s:gsub("%s+", ""):lower()
    local compactRef = ref_string:lower() -- Assicura che anche la stringa di riferimento sia in minuscolo
    
    -- Cerca la stringa di riferimento in qualsiasi punto della stringa
    return string.find(compactS, compactRef) ~= nil
end

function mainWindow()
    
    if reaper.ImGui_Button(ctx, 'Save Selected', 100, 30) then
        saveSelected()
    end

    reaper.ImGui_SameLine(ctx)

    if reaper.ImGui_Button(ctx, 'Clear', 45, 30) then
        for k in pairs (snapshot_list) do
            snapshot_list = {}
            grouped_parameters = {}
            points_list = {}
        end

        LAST_TOUCHED_BUTTON_INDEX = nil
    end

    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + 20)
    reaper.ImGui_Text(ctx, 'Smoothing')
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, 40)
    local retval = false
    retval, smoothing_fader_value = reaper.ImGui_DragDouble(ctx, '##SmoothingValue', smoothing_fader_value, 0.01, 0, 1, '%.2f', reaper.ImGui_SliderFlags_AlwaysClamp())
    smoothing = (1 - smoothing_fader_value) * smoothing_max_value
   

    
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, 60)
    reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + 20)
    reaper.ImGui_Text(ctx, 'Name:')

    local textEditWidth = MAIN_WINDOW_WIDTH - 20 - 60 - 110 - 110 - 85 - 100

    if LAST_TOUCHED_BUTTON_INDEX and snapshot_list[LAST_TOUCHED_BUTTON_INDEX] then
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_SetNextItemWidth(ctx, textEditWidth)
        local rv
        rv, snapshot_list[LAST_TOUCHED_BUTTON_INDEX].name = reaper.ImGui_InputText(ctx, '##ti'.. tostring(LAST_TOUCHED_BUTTON_INDEX), snapshot_list[LAST_TOUCHED_BUTTON_INDEX].name, reaper.ImGui_InputTextFlags_EnterReturnsTrue())

        if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then 
            is_name_edited = false
        end

        if reaper.ImGui_IsItemActivated(ctx) then
            is_name_edited = true
        end
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + 10)
    else
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + textEditWidth + 18)
    end
    

    if reaper.ImGui_Button(ctx, 'Preferences', 82, 30) then
        preferencesWindowState = not preferencesWindowState
    end

    reaper.ImGui_BeginChild(ctx, 'MovementWindow', ACTION_WINDOW_WIDTH, ACTION_WINDOW_HEIGHT, true,   reaper.ImGui_WindowFlags_NoMove()
                                                                                                    | reaper.ImGui_WindowFlags_NoScrollbar()
                                                                                                    | reaper.ImGui_WindowFlags_NoScrollWithMouse())
    


    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), reaper.ImGui_ColorConvertDouble4ToU32(0.25, 0.25, 0.25, 2))
    reaper.ImGui_PushFont(ctx, comic_sans_smaller)
    reaper.ImGui_SetCursorPosY(ctx, ACTION_WINDOW_HEIGHT - 90)
    reaper.ImGui_SetCursorPosX(ctx, 9)
    reaper.ImGui_Text(ctx, "Right-Click: add snapshot of current FX values\nShift + Left-Click: remove clicked snapshot\nLeft-Click: select a snapshot and load its FX values\nMouse-Wheel: adjust Smoothing\nLeft-Drag: interpolate")
    reaper.ImGui_SetCursorPosX(ctx, 8)
    reaper.ImGui_SetCursorPosY(ctx, 4)
    reaper.ImGui_Text(ctx,string.sub(reaper.GetProjectName(0, ""), 1, -5))
    reaper.ImGui_PopFont(ctx)
    reaper.ImGui_PopStyleColor(ctx)

    onRightClick()

    drawSnapshots()

    if reaper.ImGui_IsWindowHovered(ctx) then
        onDragLeftMouse()
    end

    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Space()) and is_name_edited == false then

        if reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftShift()) then
            reaper.Main_OnCommand(reaper.NamedCommandLookup(PLAY_STOP_LOOP_COMMAND), 0)
        else
            reaper.Main_OnCommand(reaper.NamedCommandLookup(PLAY_STOP_COMMAND), 0)
        end
    end
    
    if reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftSuper()) and reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_S()) then
        reaper.Main_OnCommand(reaper.NamedCommandLookup(SAVE_PROJECT_COMMAND), 0)
    end

    if reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftSuper()) and reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_W()) then
        quit = true
    end

    if reaper.ImGui_GetMouseWheel(ctx) > 0 and smoothing_fader_value < 1 then
        smoothing_fader_value = smoothing_fader_value + 0.02
    elseif reaper.ImGui_GetMouseWheel(ctx) < 0 and smoothing_fader_value >= 0 then
        smoothing_fader_value = smoothing_fader_value - 0.02
        if smoothing_fader_value < 0.01 then smoothing_fader_value = 0 end
    end

    reaper.ImGui_EndChild(ctx)
end

function preferencesWindow()
    local rv, rs = reaper.ImGui_InputText(ctx, 'Ignore', IGNORE_STRING, reaper.ImGui_InputTextFlags_EnterReturnsTrue())

    if rv then IGNORE_STRING = rs end

    if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then 
        is_name_edited = false
    end

    if reaper.ImGui_IsItemActivated(ctx) then
        is_name_edited = true
    end


end

function drawCircle(x, y, raggio)
    -- Assicurati che la finestra ImGui sia già stata creata con ImGui.Begin
    local draw_list = reaper.ImGui_GetForegroundDrawList(ctx)
    
    -- Definisce il colore verde nel formato RGBA (R, G, B, A)
    local coloreVerde = reaper.ImGui_ColorConvertDouble4ToU32(0, 1, 0, 1) -- Verde puro con opacità completa
    
    -- Disegna un cerchio pieno alle coordinate (x, y) con un certo raggio
    reaper.ImGui_DrawList_AddCircle(draw_list, x, y, raggio, coloreVerde, 0, 1)
end

function drawDot(x, y, raggio)
    -- Assicurati che la finestra ImGui sia già stata creata con ImGui.Begin
    local draw_list = reaper.ImGui_GetForegroundDrawList(ctx)
    
    -- Definisce il colore verde nel formato RGBA (R, G, B, A)
    local coloreVerde = reaper.ImGui_ColorConvertDouble4ToU32(0, 1, 0, 1) -- Verde puro con opacità completa
    
    -- Disegna un cerchio pieno alle coordinate (x, y) con un certo raggio
    reaper.ImGui_DrawList_AddCircleFilled(draw_list, x, y, raggio, coloreVerde, 0)
end

function onExit()
    
    --if reaper.GetProjectName(0, "") ~= '' then
        if PROJECT_NAME ~= '' then
            writeSnapshotsToFile(PROJECT_PATH .. '/ms_save')
        end
    --end
end

function initMS()

    PROJECT_NAME = reaper.GetProjectName(0, "")
    PROJECT_PATH = reaper.GetProjectPath(0)

    if PROJECT_NAME == '' then reaper.ShowMessageBox('You must save the project to use Metasurface.', 'Metasurface Error', 0) return false end

    snapshot_list = {}

    if PROJECT_NAME ~= '' then
        --name = 'Metasurface ' .. tostring(major_version) .. '.' .. tostring(minor_version)
        snapshot_list = readSnapshotsFromFile(reaper.GetProjectPath(0) .. '/ms_save')
    end
    
    if snapshot_list == nil then snapshot_list = {} end
    
    updateSnapshotIndexList()

    return true
end

function getFxIndexByGUID(track, guid)
    
    local num_track_fx

    if track then
        num_track_fx = reaper.TrackFX_GetCount(track)
        for i = 0, num_track_fx - 1 do
            if guid == reaper.TrackFX_GetFXGUID(track, i) then
                return true, i
            end
        end
    else
        --return 0
        --reaper.MB('bob', 'bob', 0)
        return false, 0
    end
end

function getTrackByGUID(proj, guid)
    for i = 0, reaper.GetNumTracks() - 1 do
        if guid == reaper.GetTrackGUID(reaper.GetTrack(proj,i)) then
            return reaper.GetTrack(proj,i)
        end
    end
end

function printProjectSnapshotOnFile()

    local string_to_print = ''

    local file, err = io.open('/Users/mattiapersico/Desktop/debug.txt', "w")
    if not file then
        print("Impossibile aprire il file: " .. err)
        return false
    end
    file:write(string_to_print)
    file:close()

end

function printSnapIndexListOnFile()

    local string_to_print = ''

    local file, err = io.open('/Users/mattiapersico/Desktop/debugSnapList.txt', "w")
    if not file then
        print("Impossibile aprire il file: " .. err)
        return false
    end
    file:write(string_to_print)
    file:close()

end



if initMS() then
    reaper.defer(loop)
end

reaper.atexit(onExit)

