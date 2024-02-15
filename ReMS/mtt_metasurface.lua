-- Appunti:
-- aggiungere menu dei settings
-- inserire filtri esclusione parametri personalizzabili 
-- inserire filtri esclusione tracce personalizzabili
-- inserire filtri esclusione effetti personalizzabili
-- salvare i filtri nel save file oppure in un foglio di salvataggio globale
-- 
-- Script Name and Version

local major_version = 0
local minor_version = 5

local name = 'Metasurface ' .. tostring(major_version) .. '.' .. tostring(minor_version)

local PLAY_STOP_COMMAND = '_4d1cade28fdc481a931786c4bb44c78d'
local PLAY_STOP_LOOP_COMMAND = '_b254db4208aa487c98dc725e435e531c'

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

local focused_window = reaper.JS_Window_GetFocus()

dofile(reaper.GetResourcePath() .. '/Scripts/ReaTeam Extensions/API/imgui.lua')('0.8')
local ctx = reaper.ImGui_CreateContext(name)
local comic_sans = reaper.ImGui_CreateFont('/System/Library/Fonts/Supplemental/Comic Sans MS.ttf', 18)
local comic_sans_bigger = reaper.ImGui_CreateFont('/System/Library/Fonts/Supplemental/Comic Sans MS.ttf', 21)
local comic_sans_smaller = reaper.ImGui_CreateFont('/System/Library/Fonts/Supplemental/Comic Sans MS.ttf', 17)

reaper.ImGui_Attach(ctx, comic_sans)
reaper.ImGui_Attach(ctx, comic_sans_bigger)
reaper.ImGui_Attach(ctx, comic_sans_smaller)

local snapshot_name_list = {}

local snapshot_index_list = {}

local snapshot_list = {}

local snapshot = {
    x = 0,
    y = 0,
    name,
    param_value_list = {}, -- i valori dei singoli parametri
    param_index_list = {}, -- lista parallela param_value_list
    track_GUID_list = {},  -- lista parallela a param_value_list
    fx_index_list = {}, -- lista parallela a param_value_list
    fx_name = {}, -- lista parallela a param_value_list
    assigned = false
}

function snapshot:new(x, y, name)
    local instance = setmetatable({}, {__index = self})
    instance.x = x or 0
    instance.y = y or 0
    instance.name = name
    instance.param_value_list = {}
    instance.param_index_list = {}
    instance.track_GUID_list = {}
    instance.fx_index_list = {}
    instance.fx_name = {}
    instance.assigned = false
    return instance
end


local point = {
    x = 0,
    y = 0,
    value = 0
}

function point:new(x, y, value)
    local instance = setmetatable({}, {__index = self})
    instance.x = x or 0
    instance.y = y or 0
    instance.value = value or 0
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

-- Funzione per scrivere l'array su un file
function writeSnapshotsToFile(snapshots, filename)
    local file = io.open(filename, "w")
    if not file then
        error("Failed to open file for writing")
    end

    for _, snapshot in ipairs(snapshots) do
        file:write(snapshot.x, "\n")
        file:write(snapshot.y, "\n")
        file:write(snapshot.name or "", "\n")
        for i, value in ipairs(snapshot.param_value_list) do
            file:write(value, ",", snapshot.param_index_list[i], ",", snapshot.track_GUID_list[i], ",", snapshot.fx_index_list[i], ",", (snapshot.fx_name[i] or ""), "\n")
        end
        file:write("END_SNAPSHOT\n")
    end

    file:close()
end

function readSnapshotsFromFile(filename)
    local file = io.open(filename, "r")
    if not file then
        return nil -- oppure error("Failed to open file for reading")
    end

    local snapshots = {}
    local snapshot = nil
    local line = file:read("*line")

    while line do
        if line == "END_SNAPSHOT" then
            if snapshot then
                table.insert(snapshots, snapshot)
                snapshot = nil
            end
        else
            if not snapshot then
                snapshot = {x = tonumber(line), y = tonumber(file:read("*line")), name = file:read("*line"),param_value_list = {}, param_index_list = {}, track_GUID_list = {}, fx_index_list = {}, fx_name = {}, assigned = false}
                --snapshot.x = tonumber(line) -- Legge il valore di x
                --snapshot.y = tonumber(file:read("*line")) -- Legge il valore di y sulla prossima riga
                --snapshot.name = file:read("*line") -- Legge il nome sulla riga successiva
            else
                local value, pIndex, guid, fxIndex, fxName = line:match("^(.-)%,(.-)%,(.-)%,(.-)%,(.-)$")
                if value and pIndex and guid and fxIndex and fxName then
                    table.insert(snapshot.param_value_list, value)
                    table.insert(snapshot.param_index_list, tonumber(pIndex))
                    table.insert(snapshot.track_GUID_list, guid)
                    table.insert(snapshot.fx_index_list, tonumber(fxIndex))
                    table.insert(snapshot.fx_name, fxName)
                else
                    error("Errore nel formato dei dati del parametro.")
                end
            end
        end
        line = file:read("*line")
    end

    file:close()
    return snapshots
end

function GetNormalizedMousePosition()
    local mouseX, mouseY = GetMouseCursorPositionInWindow() -- Usa la tua funzione esistente
    local normalizedX = mouseX / ACTION_WINDOW_WIDTH
    local normalizedY = mouseY / ACTION_WINDOW_HEIGHT
    return normalizedX, normalizedY
end

function loop()
  
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

    if reaper.GetProjectName(0) ~= PROJECT_NAME then
        onExit()
        initMS()
    end

    if mw_open and PROJECT_NAME ~= '' then
        reaper.defer(loop)
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
    if reaper.ImGui_IsMouseClicked(ctx, 1, false) then
        -- Ottieni la posizione del click del mouse come coordinate assolute
        local absX, absY = GetMouseClickPositionInWindow(ctx, 1)

        if not absX or not absY then return end

        -- Converti le coordinate assolute in coordinate normalizzate
        local normalizedX = absX / ACTION_WINDOW_WIDTH
        local normalizedY = absY / ACTION_WINDOW_HEIGHT

        -- Crea un nuovo snapshot utilizzando le coordinate normalizzate
        snapshot_list[#snapshot_list + 1] = snapshot:new(normalizedX, normalizedY)
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

                for i = 1, #snapshot_list[s].param_value_list do
                    local track = reaper.BR_GetMediaTrackByGUID(0, snapshot_list[s].track_GUID_list[i])
                    local param_index = snapshot_list[s].param_index_list[i]
                    local fx_index = snapshot_list[s].fx_index_list[i]
                    local param_value = snapshot_list[s].param_value_list[i]

                    if track then
                        local retval, fx_name = reaper.TrackFX_GetFXName(track, fx_index)
                        if fx_name == snapshot_list[s].fx_name[i] then
                            reaper.TrackFX_SetParam(track, fx_index, param_index, param_value)
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
    local isDragging = reaper.ImGui_IsMouseDragging(ctx, 0)
    
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
        --reaper.ImGui_SetCursorPos(ctx, DRAG_X - 12, DRAG_Y - 12)
        --reaper.ImGui_Bullet(ctx)

        -- Calcola i valori interpolati solo per gli indici dei parametri diversi
        for i, snap in ipairs(snapshot_list) do
            for _, j in ipairs(snapshot_index_list) do
                local points = {}

                -- Costruisce i punti solo per il parametro corrente attraverso tutti i snapshot
                for _, other_snap in ipairs(snapshot_list) do
                    if other_snap.param_value_list[j] then -- Assicura che il parametro esista
                        table.insert(points, {
                            x = other_snap.x * ACTION_WINDOW_WIDTH,
                            y = other_snap.y * ACTION_WINDOW_HEIGHT,
                            value = other_snap.param_value_list[j]
                        })
                    end
                end

                -- Applica l'IDW per calcolare il valore interpolato basato sulla posizione del mouse
                local interpolated_value = inverseDistanceWeighting(points, CURRENT_DRAG_X, CURRENT_DRAG_Y, 2) -- power = 2 come esempio

                -- Applica il valore interpolato direttamente all'effetto sulla traccia corrispondente
                local track = reaper.BR_GetMediaTrackByGUID(0, snap.track_GUID_list[j])
                local fx_index = snap.fx_index_list[j]
                local param_index = snap.param_index_list[j]
                local fx_name = snap.fx_name[j]

                if track and fx_index and param_index then
                    local retval, current_fx_name = reaper.TrackFX_GetFXName(track, fx_index)
                    if current_fx_name == fx_name then
                        reaper.TrackFX_SetParam(track, fx_index, param_index, interpolated_value)
                    end
                end
            end
        end
    else
        needToInitSmoothing = true
        reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Arrow())
    end
end

function updateSnapshotIndexList()

    if #snapshot_list <= 1 then return end

    snapshot_index_list = {}

    for i = 1, #snapshot_list do
        for j = 1, #snapshot_list do
            if #snapshot_list[i].param_value_list == #snapshot_list[j].param_value_list then
                for c = 1, #snapshot_list[i].param_value_list do
                    if snapshot_list[i].track_GUID_list[c] == snapshot_list[j].track_GUID_list[c] then
                        if snapshot_list[i].fx_index_list[c] == snapshot_list[j].fx_index_list[c] then
                            if snapshot_list[i].fx_name[c] == snapshot_list[j].fx_name[c] then
                                if snapshot_list[i].param_value_list[c] ~= snapshot_list[j].param_value_list[c] then

                                    local needToAdd = true

                                    for sil = 1, #snapshot_index_list do
                                        if snapshot_index_list[sil] == c then needToAdd = false end
                                    end

                                    if needToAdd then table.insert(snapshot_index_list, c) end

                                end
                            end
                        end
                    end
                end
            end
        end
    end

end

function saveSelected()
    local num_selected_tracks = reaper.CountTracks(0)

        if LAST_TOUCHED_BUTTON_INDEX and num_selected_tracks > 0 then

            local s = LAST_TOUCHED_BUTTON_INDEX

            local temp_x = snapshot_list[s].x
            local temp_y = snapshot_list[s].y

            local snap_name = snapshot_list[s].name or ('Snap ' .. tostring(s))

            snapshot_list[s] = snapshot:new(temp_x, temp_y, snap_name)

            for t = 0, num_selected_tracks - 1 do
                local selected_track = reaper.GetTrack(0, t)
                local num_track_fx = reaper.TrackFX_GetCount(selected_track)

                for f = 0, num_track_fx - 1 do
                    local num_fx_param = reaper.TrackFX_GetNumParams(selected_track, f)

                    for p = 0, num_fx_param - 1 do

                        local retval, param_name = reaper.TrackFX_GetParamName(selected_track, f, p)

                        if containsAnyFormOf(param_name, IGNORE_STRING) == false then

                            local val, min, max = reaper.TrackFX_GetParam(selected_track, f, p)

                            table.insert(snapshot_list[s].param_value_list, val)
                            table.insert(snapshot_list[s].param_index_list, p)
                            table.insert(snapshot_list[s].track_GUID_list, reaper.BR_GetMediaTrackGUID(selected_track))
                            table.insert(snapshot_list[s].fx_index_list, f)
                            local retval, fx_name = reaper.TrackFX_GetFXName(selected_track, f)
                            table.insert(snapshot_list[s].fx_name, fx_name)
                            snapshot_list[s].assigned = true
                        end
                    end
                end
            end

            updateSnapshotIndexList()
        end
        PROJECT_PATH = reaper.GetProjectPath(0)
end

function containsAnyFormOf(s, ref_string)
    -- Rimuovi gli spazi per gestire concatenazioni come "NoteMidiCC"
    local compactS = s:gsub("%s+", ""):lower()
    -- Cerca "midi" in qualsiasi punto della stringa
    return string.find(compactS, ref_string) ~= nil
end

function mainWindow()
    
    if reaper.ImGui_Button(ctx, 'Save Selected', 100, 30) then
        saveSelected()
    end

    reaper.ImGui_SameLine(ctx)

    if reaper.ImGui_Button(ctx, 'Clear', 45, 30) then
        for k in pairs (snapshot_list) do
            snapshot_list [k] = nil
            snapshot_index_list [k] = nil
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

    --if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter()) then  is_name_edited = false reaper.ShowConsoleMsg('enter') end

    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Space()) and is_name_edited == false then

        if reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftShift()) then
            reaper.Main_OnCommand(reaper.NamedCommandLookup(PLAY_STOP_LOOP_COMMAND), 0)
        else
            reaper.Main_OnCommand(reaper.NamedCommandLookup(PLAY_STOP_COMMAND), 0)
        end
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
    
    if reaper.GetProjectName(0, "") ~= '' then
        if PROJECT_NAME ~= '' then
            writeSnapshotsToFile(snapshot_list, PROJECT_PATH .. '/ms_save')
        end
    end
end

function initMS()

    PROJECT_NAME = reaper.GetProjectName(0, "")
    PROJECT_PATH = reaper.GetProjectPath(0)

    if PROJECT_NAME == '' then reaper.ShowMessageBox('You must save the project to use Metasurface.', 'Metasurface Error', 0) return false end

    snapshot_list = {}

    if PROJECT_NAME ~= '' then
        --name = 'Metasurface ' .. tostring(major_version) .. '.' .. tostring(minor_version)
        snapshot_list = readSnapshotsFromFile(reaper.GetProjectPath(0) .. '/ms_save')
    else
        --name = 'Metasurface ' .. tostring(major_version) .. '.' .. tostring(minor_version)
    end
    
    if snapshot_list == nil then snapshot_list = {} end
    
    updateSnapshotIndexList()

    return true
end


if initMS() then
    reaper.defer(loop)
end

reaper.atexit(onExit)
