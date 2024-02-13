-- Appunti:
-- Ottimizza meglio l'array degli indici,
-- ad ogni insert controlla se non è già salvato
-- quell index del parametro

-- Script Name and Version

local major_version = 0
local minor_version = 1

local name = 'Metasurface ' .. tostring(major_version) .. '.' .. tostring(minor_version)

local PLAY_STOP_COMMAND = '_4d1cade28fdc481a931786c4bb44c78d'
local PLAY_STOP_LOOP_COMMAND = '_b254db4208aa487c98dc725e435e531c'

local MAIN_WINDOW_WIDTH = 400
local MAIN_WINDOW_HEIGHT = 400

local WIDTH_OFFSET = 16
local HEIGHT_OFFSET = 74

local ACTION_WINDOW_WIDTH = MAIN_WINDOW_WIDTH - WIDTH_OFFSET
local ACTION_WINDOW_HEIGHT = MAIN_WINDOW_HEIGHT - HEIGHT_OFFSET

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

    reaper.ImGui_SetNextWindowSizeConstraints(ctx, 400, 400, 900, 900, reaper.ImGui_CreateFunctionFromEEL(sizeConstraintsCallback))

    local mw_visible, mw_open = reaper.ImGui_Begin(ctx, name, true, --reaper.ImGui_WindowFlags_NoResize() |  
                                                                     reaper.ImGui_WindowFlags_NoCollapse()
                                                                    | reaper.ImGui_WindowFlags_NoScrollbar()
                                                                    | reaper.ImGui_WindowFlags_NoScrollWithMouse()  
                                                                    )
  
    
    

    MAIN_WINDOW_WIDTH, MAIN_WINDOW_HEIGHT = reaper.ImGui_GetWindowSize(ctx)
    ACTION_WINDOW_WIDTH = MAIN_WINDOW_WIDTH - WIDTH_OFFSET
    ACTION_WINDOW_HEIGHT = MAIN_WINDOW_HEIGHT - HEIGHT_OFFSET
    
    
  
  
    if mw_visible then
      mainWindow()

      reaper.ImGui_End(ctx)

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
    if mw_open then
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

function onDragLeftMouse()
    local isDragging = reaper.ImGui_IsMouseDragging(ctx, 0)

    if isDragging then
        -- Ottieni la posizione normalizzata del mouse
        local normalizedX, normalizedY = GetNormalizedMousePosition()

        -- Converti le coordinate normalizzate in posizione reale se necessario
        -- Esempio: applicazione diretta senza conversione, poiché la logica IDW utilizza valori normalizzati
        DRAG_X = normalizedX * ACTION_WINDOW_WIDTH
        DRAG_Y = normalizedY * ACTION_WINDOW_HEIGHT

        reaper.ImGui_SetCursorPos(ctx, DRAG_X - 12, DRAG_Y - 12)
        reaper.ImGui_Bullet(ctx)

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
                local interpolated_value = inverseDistanceWeighting(points, DRAG_X, DRAG_Y, 2) -- power = 2 come esempio

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
                                    table.insert(snapshot_index_list, c)
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

            updateSnapshotIndexList()

        end
end

function mainWindow()
    
    if reaper.ImGui_Button(ctx, 'Save Snapshot', 110, 30) then
        saveSelected()
    end

    reaper.ImGui_SameLine(ctx)

    if reaper.ImGui_Button(ctx, 'Clear Snapshots', 110, 30) then
        for k in pairs (snapshot_list) do
            snapshot_list [k] = nil
            snapshot_index_list [k] = nil
        end

        LAST_TOUCHED_BUTTON_INDEX = nil
    end
    
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, 60)
    reaper.ImGui_Text(ctx, 'Name:')

    if LAST_TOUCHED_BUTTON_INDEX and snapshot_list[LAST_TOUCHED_BUTTON_INDEX] then
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_SetNextItemWidth(ctx, MAIN_WINDOW_WIDTH - 20 - 60 - 110 - 110)
        rv, snapshot_list[LAST_TOUCHED_BUTTON_INDEX].name = reaper.ImGui_InputText(ctx, '##ti'.. tostring(LAST_TOUCHED_BUTTON_INDEX), snapshot_list[LAST_TOUCHED_BUTTON_INDEX].name)
        is_name_edited = reaper.ImGui_IsItemFocused(ctx)
    end
    
    reaper.ImGui_BeginChild(ctx, 'MovementWindow', ACTION_WINDOW_WIDTH, ACTION_WINDOW_HEIGHT, true,   reaper.ImGui_WindowFlags_NoMove()
                                                                                                    | reaper.ImGui_WindowFlags_NoScrollbar()
                                                                                                    | reaper.ImGui_WindowFlags_NoScrollWithMouse())
    


    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), reaper.ImGui_ColorConvertDouble4ToU32(0.25, 0.25, 0.25, 2))
    reaper.ImGui_PushFont(ctx, comic_sans_smaller)
    reaper.ImGui_SetCursorPosY(ctx, ACTION_WINDOW_HEIGHT - 75)
    reaper.ImGui_SetCursorPosX(ctx, 10)
    reaper.ImGui_Text(ctx, "Right-Click: add snapshot of current FX values\nShift + Left-Click: remove clicked snapshot\nLeft-Click: select a snapshot and load its FX values\nLeft-Drag: interpolate")
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

    reaper.ImGui_EndChild(ctx)
end


reaper.defer(loop)
