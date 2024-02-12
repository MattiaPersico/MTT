-- Script Name and Version

local major_version = 0
local minor_version = 1

local name = 'Metasurface ' .. tostring(major_version) .. '.' .. tostring(minor_version)

local MAIN_WINDOW_WIDTH = 400
local MAIN_WINDOW_HEIGHT = 400

local WIDTH_OFFSET = 16
local HEIGHT_OFFSET = 74

local ACTION_WINDOW_WIDTH = MAIN_WINDOW_WIDTH - WIDTH_OFFSET
local ACTION_WINDOW_HEIGHT = MAIN_WINDOW_HEIGHT - HEIGHT_OFFSET

dofile(reaper.GetResourcePath() .. '/Scripts/ReaTeam Extensions/API/imgui.lua')('0.8')
local ctx = reaper.ImGui_CreateContext(name)
local comic_sans = reaper.ImGui_CreateFont('/System/Library/Fonts/Supplemental/Comic Sans MS.ttf', 18)
local comic_sans_bigger = reaper.ImGui_CreateFont('/System/Library/Fonts/Supplemental/Comic Sans MS.ttf', 21)
local comic_sans_smaller = reaper.ImGui_CreateFont('/System/Library/Fonts/Supplemental/Comic Sans MS.ttf', 2)

reaper.ImGui_Attach(ctx, comic_sans)
reaper.ImGui_Attach(ctx, comic_sans_bigger)
reaper.ImGui_Attach(ctx, comic_sans_smaller)


local snapshot_list = {}

local snapshot = {
    x = 0,
    y = 0,
    name = '',
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
    instance.name = name or ''
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
    reaper.ImGui_SetNextWindowSize(ctx, MAIN_WINDOW_WIDTH, MAIN_WINDOW_HEIGHT)
    local mw_visible, mw_open = reaper.ImGui_Begin(ctx, name, true, reaper.ImGui_WindowFlags_NoResize()  
                                                                    | reaper.ImGui_WindowFlags_NoCollapse()
                                                                    | reaper.ImGui_WindowFlags_NoScrollbar()
                                                                    | reaper.ImGui_WindowFlags_NoScrollWithMouse()  
                                                                    )
  
    
  
    main_window_x, main_window_y = reaper.ImGui_GetWindowPos(ctx)
    main_window_w, main_window_h = reaper.ImGui_GetWindowSize(ctx)
    
    
  
  
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
        snapshot_list[#snapshot_list + 1] = snapshot:new(normalizedX, normalizedY, 'B')
        LAST_TOUCHED_BUTTON_INDEX = #snapshot_list

        saveSelected()
    end
end

function drawSnapshots()

    local num_selected_tracks = reaper.CountSelectedTracks(0)
    
    for s = #snapshot_list, 1, -1 do
        -- Converti le coordinate normalizzate in coordinate assolute basate sulle dimensioni attuali della finestra
        local absoluteX = snapshot_list[s].x * ACTION_WINDOW_WIDTH - 7
        local absoluteY = snapshot_list[s].y * ACTION_WINDOW_HEIGHT - 9

        reaper.ImGui_SetCursorPos(ctx, absoluteX, absoluteY)

        local name = 'B'
        if s == LAST_TOUCHED_BUTTON_INDEX or #snapshot_list == 1 then
            --LAST_TOUCHED_BUTTON_INDEX = s
            name = 'S'
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), reaper.ImGui_ColorConvertDouble4ToU32(0.0, 0.5, 0.0, 2))
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), reaper.ImGui_ColorConvertDouble4ToU32(0.0, 0.6, 0.0, 2))
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), reaper.ImGui_ColorConvertDouble4ToU32(0.0, 0.5, 0.0, 2))
        else
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), reaper.ImGui_ColorConvertDouble4ToU32(0.3, 0.3, 0.3, 2))
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), reaper.ImGui_ColorConvertDouble4ToU32(0.4, 0.4, 0.4, 2))
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), reaper.ImGui_ColorConvertDouble4ToU32(0.3, 0.3, 0.3, 2))
        end

        if reaper.ImGui_Button(ctx,  '##' .. tostring(s), 12, 12) then
            LAST_TOUCHED_BUTTON_INDEX = s

            if not reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftShift()) then
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
                table.remove(snapshot_list, s)
            end
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
        -- Calcola i valori interpolati per ogni parametro di ogni snapshot
        -- basandosi sulla posizione attuale del mouse
        for i, snap in ipairs(snapshot_list) do
            for j = 0, #snap.param_value_list do
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
                    --reaper.ShowMessageBox(fx_name, current_fx_name, 0)
                    if current_fx_name == fx_name then
                        reaper.TrackFX_SetParam(track, fx_index, param_index, interpolated_value)
                       -- local retval, trackname = reaper.GetTrackName(track)
                        --reaper.ShowConsoleMsg('Track: ' .. trackname .. '\n')
                    end
                end
            end
        end
    end
end

function saveSelected()
    local num_selected_tracks = reaper.CountSelectedTracks(0)

        if LAST_TOUCHED_BUTTON_INDEX and num_selected_tracks > 0 then

            local s = LAST_TOUCHED_BUTTON_INDEX

            local temp_x = snapshot_list[s].x
            local temp_y = snapshot_list[s].y

            snapshot_list[s] = snapshot:new(temp_x, temp_y, 'S')

            for t = 0, num_selected_tracks - 1 do
                local selected_track = reaper.GetSelectedTrack(0, t)
                local retval, selected_track_name = reaper.GetTrackName(selected_track)
                local num_track_fx = reaper.TrackFX_GetCount(selected_track)

                local retval, trackname = reaper.GetTrackName(selected_track)
                --reaper.ShowConsoleMsg('Track: ' .. trackname .. '\n')

                for f = 0, num_track_fx - 1 do
                    local num_fx_param = reaper.TrackFX_GetNumParams(selected_track, f)

                    --reaper.ShowConsoleMsg('Num Track FX: ' .. tostring(num_track_fx) .. '\n')
                    --reaper.ShowConsoleMsg('Num Param: ' .. tostring(num_fx_param) .. '\n')

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
        end
end

function mainWindow()
    
    if reaper.ImGui_Button(ctx, 'Save Selected', 130, 30) then

        saveSelected()
    end

    reaper.ImGui_SameLine(ctx)

    if reaper.ImGui_Button(ctx, 'Clear Snapshots', 130, 30) then
        for k in pairs (snapshot_list) do
            snapshot_list [k] = nil
        end

        LAST_TOUCHED_BUTTON_INDEX = nil
    end
    
    reaper.ImGui_SameLine(ctx)

    reaper.ImGui_Text(ctx, 'X:' .. tostring(DRAG_X) .. '  Y:'.. tostring(DRAG_Y))

    
    reaper.ImGui_BeginChild(ctx, 'MovementWindow', ACTION_WINDOW_WIDTH, ACTION_WINDOW_HEIGHT, true,   reaper.ImGui_WindowFlags_NoMove()
                                                                                                    | reaper.ImGui_WindowFlags_NoScrollbar()
                                                                                                    | reaper.ImGui_WindowFlags_NoScrollWithMouse())
    
    onRightClick()

    drawSnapshots()

    onDragLeftMouse()

    reaper.ImGui_EndChild(ctx)
end

reaper.defer(loop)
