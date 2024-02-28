-- Appunti:

-- aggiungere supporto a fx dentro container

-- Script Name and Version

local major_version = 0
local minor_version = 15

local name = 'Metasurface ' .. tostring(major_version) .. '.' .. tostring(minor_version)

local PLAY_STOP_COMMAND = '_4d1cade28fdc481a931786c4bb44c78d'
local PLAY_STOP_LOOP_COMMAND = '_b254db4208aa487c98dc725e435e531c'
local SAVE_PROJECT_COMMAND = '40026'

local PREF_WINDOW_WIDTH = 300
local PREF_WINDOW_HEIGHT = 380

local MAX_MAIN_WINDOW_WIDTH = 600
local MAX_MAIN_WINDOW_HEIGHT = 600

local MAIN_WINDOW_WIDTH = 500
local MAIN_WINDOW_HEIGHT = 500

local WIDTH_OFFSET = 16
local HEIGHT_OFFSET = 74

local ACTION_WINDOW_WIDTH = MAIN_WINDOW_WIDTH - WIDTH_OFFSET
local ACTION_WINDOW_HEIGHT = MAIN_WINDOW_HEIGHT - HEIGHT_OFFSET

local IGNORE_PARAMS_PRE_SAVE_STRING = 'midi'
local IGNORE_PARAMS_POST_SAVE_STRING = ''
local IGNORE_FXs_STRING = ''
local IGNORE_TRACKS_STRING = ''

local LINK_TO_CONTROLLER = false
local CONTROL_TRACK = nil
local CONTROL_FX_INDEX = nil

-- Funzione EEL per i Vincoli delle Dimensioni della Finestra
local sizeConstraintsCallback = [=[
a = 0
]=]

local CONTROLLER = [=[
desc:mtt_metasurface_controller

// Sliders
slider1: 0.5 <0,1,0.0001>mtt_mc_x_pos
slider2: 0.5 <0,1,0.0001>mtt_mc_y_pos
// ... gli altri slider ...
    
@init
    cursor_x = slider1 * gfx_w;
    cursor_y = slider2 * gfx_h;

]=]

dofile(reaper.GetResourcePath() .. '/Scripts/ReaTeam Extensions/API/imgui.lua')('0.8')
local ctx = reaper.ImGui_CreateContext(name)
local comic_sans = reaper.ImGui_CreateFont('/System/Library/Fonts/Supplemental/Comic Sans MS.ttf', 18)
local comic_sans_bigger = reaper.ImGui_CreateFont('/System/Library/Fonts/Supplemental/Comic Sans MS.ttf', 21)
local comic_sans_smaller = reaper.ImGui_CreateFont('/System/Library/Fonts/Supplemental/Comic Sans MS.ttf', 17)
local new_line_font = reaper.ImGui_CreateFont('/System/Library/Fonts/Supplemental/Comic Sans MS.ttf', 2)

reaper.ImGui_Attach(ctx, comic_sans)
reaper.ImGui_Attach(ctx, comic_sans_bigger)
reaper.ImGui_Attach(ctx, comic_sans_smaller)
reaper.ImGui_Attach(ctx, new_line_font)

local grouped_parameters = {}
local points_list = {}
local snapshot_list = {}
local balls = {}

local ball_default_color = reaper.ImGui_ColorConvertDouble4ToU32(0.5,0.5,0.5, 1)
local ball_clicked_color = reaper.ImGui_ColorConvertDouble4ToU32(0.3,0.3,0.3, 1)

local selected_ball_default_color = reaper.ImGui_ColorConvertDouble4ToU32(0.0,0.5,0.0, 1)
local selected_ball_clicked_color = reaper.ImGui_ColorConvertDouble4ToU32(0.0,0.3,0.0, 1)

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
local isInterpolating = false
local DRAGGING_BALL = nil
local quit = false
local PLAY_STATE = false


function serializeSnapshots(obj)
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
            local serializedValue = serializeSnapshots(v)
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
    file:write("IGNORE_PARAMS_PRE_SAVE_STRING = " .. string.format("%q", IGNORE_PARAMS_PRE_SAVE_STRING) .. "\n")
    file:write("IGNORE_PARAMS_POST_SAVE_STRING = " .. string.format("%q", IGNORE_PARAMS_POST_SAVE_STRING) .. "\n")
    file:write("IGNORE_FXs_STRING = " .. string.format("%q", IGNORE_FXs_STRING) .. "\n")
    file:write("IGNORE_TRACKS_STRING = " .. string.format("%q", IGNORE_TRACKS_STRING) .. "\n")
    file:write("LINK_TO_CONTROLLER = " .. string.format("%q", LINK_TO_CONTROLLER) .. "\n")
    file:write(data) -- Scrive i dati serializzati nel file
    file:close() -- Chiude il file
end

function writeSnapshotsToFile(filename)
    local data = serializeSnapshots(snapshot_list)
    saveToFile(filename, data)
end

function loadFromFile(filename)
    local file, err = io.open(filename, "r")
    if not file then
        return nil, 'midi', '', '', '', false
    end
    local ignoreParamsPreSave = file:read("*l") -- Legge la prima linea che contiene IGNORE_PARAMS_PRE_SAVE_STRING
    local ignoreParamsPostSave = file:read("*l") -- Legge la prima linea che contiene IGNORE_PARAMS_PRE_SAVE_STRING
    local ignoreFxs = file:read("*l") -- Legge la prima linea che contiene IGNORE_PARAMS_PRE_SAVE_STRING
    local ignoreTracks = file:read("*l") -- Legge la prima linea che contiene IGNORE_PARAMS_PRE_SAVE_STRING
    local linkToController = file:read("*l")
    local dataString = file:read("*a") -- Legge il resto del file per i dati serializzati
    file:close()

    local ignoreParamsPreSaveString = ignoreParamsPreSave:match("^IGNORE_PARAMS_PRE_SAVE_STRING = (.+)$")
    if ignoreParamsPreSaveString then
        ignoreParamsPreSaveString = load("return " .. ignoreParamsPreSaveString)()
    end

    local ignoreParamsPostSaveString = ignoreParamsPostSave:match("^IGNORE_PARAMS_POST_SAVE_STRING = (.+)$")
    if ignoreParamsPostSaveString then
        ignoreParamsPostSaveString = load("return " .. ignoreParamsPostSaveString)()
    end

    local ignoreFXsString = ignoreFxs:match("^IGNORE_FXs_STRING = (.+)$")
    if ignoreFXsString then
        ignoreFXsString = load("return " .. ignoreFXsString)()
    end

    local ignoreTracksString = ignoreTracks:match("^IGNORE_TRACKS_STRING = (.+)$")
    if ignoreTracksString then
        ignoreTracksString = load("return " .. ignoreTracksString)()
    end

    local linkToControllerBool = linkToController:match("^LINK_TO_CONTROLLER = (.+)$")
    if linkToControllerBool then
        linkToControllerBool = load("return " .. linkToControllerBool)()
    end

    local dataFunction = load("return " .. dataString)
    if not dataFunction then
        error("Errore durante la deserializzazione dei dati")
    end
    local data = dataFunction()

    if not ignoreParamsPreSaveString then ignoreParamsPreSaveString = 'midi' end
    if not ignoreParamsPostSaveString then ignoreParamsPostSaveString = '' end
    if not ignoreFXsString then ignoreFXsString = '' end
    if not ignoreTracksString then ignoreTracksString = '' end
    if not linkToControllerBool then linkToControllerBool = false end

    return data, ignoreParamsPreSaveString, ignoreParamsPostSaveString, ignoreFXsString, ignoreTracksString, linkToControllerBool
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
    
    gui_loop()
    
    if not isInterpolating then
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

        --local ball_x, ball_y = windowToScreenCoordinates((normalizedX * ACTION_WINDOW_WIDTH - 1), (normalizedY * ACTION_WINDOW_HEIGHT - 3))

        table.insert(balls, { pos_x = normalizedX, pos_y = normalizedY, radius = 7, color = ball_default_color, dragging = false })

        saveSelected()
    end
end

function isMouseOverBall(ball_x, ball_y, radius)
    local mouse_x, mouse_y = reaper.ImGui_GetMousePos(ctx)
    return ((mouse_x - ball_x) ^ 2 + (mouse_y - ball_y) ^ 2) <= radius ^ 2
end

function clamp(val, min, max)
    return math.max(min, math.min(max, val))
end

function drawSnapshots()

    local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    local window_x, window_y = reaper.ImGui_GetWindowPos(ctx)
    local window_width, window_height = reaper.ImGui_GetWindowSize(ctx)
    local mouse_x, mouse_y = reaper.ImGui_GetMousePos(ctx)

    local mouse_x_rel = (mouse_x - window_x) / window_width
    local mouse_y_rel = (mouse_y - window_y) / window_height

    for s, ball in ipairs(balls) do
        
        local ball_screen_pos_x = window_x + ball.pos_x * window_width
        local ball_screen_pos_y = window_y + ball.pos_y * window_height

        if s == LAST_TOUCHED_BUTTON_INDEX then
            ball.color = selected_ball_default_color
        else
            ball.color = ball_default_color
        end

        reaper.ImGui_DrawList_AddCircleFilled(draw_list, ball_screen_pos_x, ball_screen_pos_y, ball.radius, ball.color)
        
        if snapshot_list[s] then
            reaper.ImGui_SetNextItemWidth(ctx, 60)
            if ball.pos_x * window_width > ((MAIN_WINDOW_WIDTH / 3) * 2) then
                local str_len = string.len(snapshot_list[s].name)
                local  w,  h = reaper.ImGui_CalcTextSize(ctx, snapshot_list[s].name, 60, 20)
                reaper.ImGui_SetCursorPos(ctx, ball.pos_x * window_width - 12 - w, ball.pos_y * window_height - 10)
            else
                reaper.ImGui_SetCursorPos(ctx, ball.pos_x * window_width + 12, ball.pos_y * window_height - 10)
            end

            reaper.ImGui_Text(ctx, snapshot_list[s].name)
        end

        if isMouseOverBall(ball_screen_pos_x, ball_screen_pos_y, ball.radius) or DRAGGING_BALL then
            reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
        end

        -- DRAGGING
        if DRAGGING_BALL == ball or (isMouseOverBall(ball_screen_pos_x, ball_screen_pos_y, ball.radius) and not isInterpolating) then
            if reaper.ImGui_IsMouseDown(ctx, 0) and not DRAGGING_BALL then

                if s == LAST_TOUCHED_BUTTON_INDEX then
                    ball.color = selected_ball_clicked_color
                else
                    ball.color = ball_clicked_color
                end
                
                DRAGGING_BALL = ball
                
                ball.offset_x, ball.offset_y = mouse_x_rel - ball.pos_x, mouse_y_rel - ball.pos_y
            end

            if reaper.ImGui_IsMouseDragging(ctx, 0, 0.1) and DRAGGING_BALL == ball then
                
                ball.dragging = true
                ball.pos_x = clamp(mouse_x_rel - ball.offset_x, 0, 1)
                ball.pos_y = clamp(mouse_y_rel - ball.offset_y, 0, 1)
                snapshot_list[s].x = ball.pos_x
                snapshot_list[s].y = ball.pos_y

            end
        end

        -- MOUSE RELEASE
        if reaper.ImGui_IsMouseReleased(ctx, 0) and ball.dragging == false and not isInterpolating then
            if isMouseOverBall(ball_screen_pos_x, ball_screen_pos_y, ball.radius) then
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
            end
        end

        if reaper.ImGui_IsMouseReleased(ctx, 0) and not isInterpolating then

            ball.dragging = false
            DRAGGING_BALL = nil
            
            if s == LAST_TOUCHED_BUTTON_INDEX then
                ball.color = selected_ball_default_color
            else
                ball.color = ball_default_color
            end
        end

        -- SHIFT-CLICK
        if reaper.ImGui_IsMouseClicked(ctx, 0) and reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftShift()) and isMouseOverBall(ball_screen_pos_x, ball_screen_pos_y, ball.radius) and not isInterpolating then
            if LAST_TOUCHED_BUTTON_INDEX == #snapshot_list then LAST_TOUCHED_BUTTON_INDEX = #snapshot_list - 1 end
            table.remove(snapshot_list, s)
            table.remove(balls, s)
            updateSnapshotIndexList()
            break
        end

         -- RIGHT CLICK
         if reaper.ImGui_IsMouseClicked(ctx, 0) then
            if not reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftShift()) then

                
            end
        end
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

function screenToWindowCoordinates(xSchermo, ySchermo)
    -- Ottieni la posizione della finestra ImGui
    local posXFinestra, posYFinestra = reaper.ImGui_GetWindowPos(ctx)

    -- Calcola le coordinate relative sottraendo la posizione della finestra dalle coordinate dello schermo
    local xRelativo = xSchermo - posXFinestra
    local yRelativo = ySchermo - posYFinestra

    return xRelativo, yRelativo
end

function onDragLeftMouse()
    
    if reaper.ImGui_IsMouseDragging(ctx, 0) and not DRAGGING_BALL and (LINK_TO_CONTROLLER == false or (LINK_TO_CONTROLLER == true and reaper.GetPlayState() == 0)) then
        isInterpolating = true
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

        CURRENT_DRAG_X = clamp(CURRENT_DRAG_X, 0, ACTION_WINDOW_WIDTH)
        CURRENT_DRAG_Y = clamp(CURRENT_DRAG_Y, 0, ACTION_WINDOW_HEIGHT)

        DRAG_X = clamp(DRAG_X, 0, ACTION_WINDOW_WIDTH)
        DRAG_Y = clamp(DRAG_Y, 0, ACTION_WINDOW_HEIGHT)

        local circle_x, circle_y = windowToScreenCoordinates(CURRENT_DRAG_X, CURRENT_DRAG_Y)
        local dot_x, dot_y = windowToScreenCoordinates(DRAG_X, DRAG_Y)

        drawCircle(circle_x,circle_y, 4, reaper.ImGui_ColorConvertDouble4ToU32(0, 1, 0, 1))
        drawDot(dot_x,dot_y, 2, reaper.ImGui_ColorConvertDouble4ToU32(0, 1, 0, 1))

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
        isInterpolating = false
        needToInitSmoothing = true
    end
end

function getControllerUpdate()

    if not DRAGGING_BALL then
        isInterpolating = true 
        --reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_None())
        -- Ottieni la posizione normalizzata del mouse
        local normalizedX, normalizedY = 0, 0

        if reaper.ImGui_IsMouseDragging(ctx, 0) then
            reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_None())
        -- Ottieni la posizione normalizzata del mouse
            normalizedX, normalizedY = GetNormalizedMousePosition()
            reaper.TrackFX_SetParam(CONTROL_TRACK, CONTROL_FX_INDEX, 0, normalizedX)
            reaper.TrackFX_SetParam(CONTROL_TRACK, CONTROL_FX_INDEX, 1, normalizedY)
        else
            normalizedX, min, max = reaper.TrackFX_GetParam(CONTROL_TRACK, CONTROL_FX_INDEX, 0)
            normalizedY, min, max = reaper.TrackFX_GetParam(CONTROL_TRACK, CONTROL_FX_INDEX, 1)
        end

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

        CURRENT_DRAG_X = clamp(CURRENT_DRAG_X, 0, ACTION_WINDOW_WIDTH)
        CURRENT_DRAG_Y = clamp(CURRENT_DRAG_Y, 0, ACTION_WINDOW_HEIGHT)

        DRAG_X = clamp(DRAG_X, 0, ACTION_WINDOW_WIDTH)
        DRAG_Y = clamp(DRAG_Y, 0, ACTION_WINDOW_HEIGHT)

        local circle_x, circle_y = windowToScreenCoordinates(CURRENT_DRAG_X, CURRENT_DRAG_Y)
        local dot_x, dot_y = windowToScreenCoordinates(DRAG_X, DRAG_Y)

        drawCircle(circle_x,circle_y, 4, reaper.ImGui_ColorConvertDouble4ToU32(1, 0, 0, 1))
        drawDot(dot_x,dot_y, 2, reaper.ImGui_ColorConvertDouble4ToU32(1, 0, 0, 1))

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
        isInterpolating = false
        needToInitSmoothing = true
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
                                        local retval, track_name = reaper.GetTrackName(track)
                                        local fx_index_retval, fx = getFxIndexByGUID(track, snapshot_list[s1].track_list[t].fx_list[f].guid)

                                        if fx_index_retval then

                                            local retval, fx_name = reaper.TrackFX_GetFXName(track, fx)
                                            local retval, param_name = reaper.TrackFX_GetParamName(track, fx, fx_parameter_indexes[p] - 1)

                                            if  not containsAnyFormOf(track_name, IGNORE_TRACKS_STRING) and
                                                not containsAnyFormOf(fx_name, IGNORE_FXs_STRING) and
                                                not containsAnyFormOf(param_name, IGNORE_PARAMS_POST_SAVE_STRING) then
 
                                                local parameter_index = fx_parameter_indexes[p]
                                                local new_parameter = parameter:new(track, fx, snapshot_list[s1].track_list[t].fx_list[f].param_index_list[parameter_index], snapshot_list[s1].track_list[t].fx_list[f].param_list[parameter_index], s1)
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

                for z = 0, reaper.TrackFX_GetNumParams(current_track, current_fx_index) - 1 do
                    local retval, p_name = reaper.TrackFX_GetParamName(current_track, current_fx_index, z)
                    if not containsAnyFormOf(p_name, IGNORE_PARAMS_PRE_SAVE_STRING .. ', mtt_mc_') then
                        --reaper.ShowConsoleMsg(p_name .. '  gesucane\n')
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
    -- Prepara s rimuovendo gli spazi superflui e convertendola in minuscolo
    local compactS = s:gsub("%s+", ""):lower()

    -- Divide ref_string in base alle virgole, gestendo spazi
    for segment in ref_string:gmatch("[^,]+") do
        -- Rimuove gli spazi all'inizio e alla fine di ogni segmento e controlla per corrispondenze esatte o generiche
        local word = segment:match("^%s*(.-)%s*$")
        local exactMatch = word:match('^"(.*)"$')
        
        if exactMatch then
            -- Se la parola chiave è tra virgolette, cerca corrispondenza esatta in s senza rimuovere gli spazi e convertendo in minuscolo
            if s:lower() == exactMatch:lower() then
                return true
            end
        else
            -- Altrimenti, cerca la parola chiave in qualsiasi punto della stringa compactS
            if string.find(compactS, word:lower()) then
                return true
            end
        end
    end

    return false
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
            balls = {}
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

    if reaper.ImGui_IsWindowHovered(ctx) and LINK_TO_CONTROLLER == false then
        onDragLeftMouse()
    end

    if LINK_TO_CONTROLLER == true then
        if reaper.GetPlayState() == 1 then
            if PLAY_STATE == false then
                CONTROL_TRACK, CONTROL_FX_INDEX = getControlTrack()
                needToInitSmoothing = true
                updateSnapshotIndexList()
                PLAY_STATE = true
                --reaper.ShowConsoleMsg('PLAY\n')
            end

            getControllerUpdate()

        end

        if reaper.GetPlayState() == 0 then
            if PLAY_STATE == true then
                PLAY_STATE = false
                isInterpolating = false
                --reaper.ShowConsoleMsg('STOP\n')
            end
        end
        
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

    -- IGNORE PARAMETERS (PRE-SAVE)
    reaper.ImGui_Text(ctx, 'Ignore Parameters (pre-save)')
    reaper.ImGui_PushFont(ctx, new_line_font)
    reaper.ImGui_NewLine(ctx)
    reaper.ImGui_PopFont(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, PREF_WINDOW_WIDTH - 20)

    local rv, rs = reaper.ImGui_InputText(ctx, '##IgnoreParamsPreSave', IGNORE_PARAMS_PRE_SAVE_STRING, reaper.ImGui_InputTextFlags_EnterReturnsTrue())

    if rv then IGNORE_PARAMS_PRE_SAVE_STRING = rs end

    if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then 
        is_name_edited = false
    end

    if reaper.ImGui_IsItemActivated(ctx) then
        is_name_edited = true
    end

    reaper.ImGui_PushFont(ctx, new_line_font)
    reaper.ImGui_NewLine(ctx)
    reaper.ImGui_NewLine(ctx)
    reaper.ImGui_NewLine(ctx)
    reaper.ImGui_PopFont(ctx)


    -- IGNORE PARAMETERS (POST-SAVE)
    reaper.ImGui_Text(ctx, 'Ignore Parameters (post-save)')
    reaper.ImGui_PushFont(ctx, new_line_font)
    reaper.ImGui_NewLine(ctx)
    reaper.ImGui_PopFont(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, PREF_WINDOW_WIDTH - 20)

    local rv, rs = reaper.ImGui_InputText(ctx, '##IgnoreParamsPostSave', IGNORE_PARAMS_POST_SAVE_STRING, reaper.ImGui_InputTextFlags_EnterReturnsTrue())

    if rv then IGNORE_PARAMS_POST_SAVE_STRING = rs end

    if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then 
        is_name_edited = false
    end

    if reaper.ImGui_IsItemActivated(ctx) then
        is_name_edited = true
    end

    reaper.ImGui_PushFont(ctx, new_line_font)
    reaper.ImGui_NewLine(ctx)
    reaper.ImGui_NewLine(ctx)
    reaper.ImGui_NewLine(ctx)
    reaper.ImGui_PopFont(ctx)


    -- IGNORE FX
    reaper.ImGui_Text(ctx, 'Ignore Fx')
    reaper.ImGui_PushFont(ctx, new_line_font)
    reaper.ImGui_NewLine(ctx)
    reaper.ImGui_PopFont(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, PREF_WINDOW_WIDTH - 20)
    
    local rv, rs = reaper.ImGui_InputText(ctx, '##IgnoreFXs', IGNORE_FXs_STRING, reaper.ImGui_InputTextFlags_EnterReturnsTrue())
    
    if rv then IGNORE_FXs_STRING = rs end
    
    if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then 
        is_name_edited = false
    end
    
    if reaper.ImGui_IsItemActivated(ctx) then
        is_name_edited = true
    end
    
    reaper.ImGui_PushFont(ctx, new_line_font)
    reaper.ImGui_NewLine(ctx)
    reaper.ImGui_NewLine(ctx)
    reaper.ImGui_NewLine(ctx)
    reaper.ImGui_PopFont(ctx)    



    -- IGNORE TRACKS
    reaper.ImGui_Text(ctx, 'Ignore Tracks')
    reaper.ImGui_PushFont(ctx, new_line_font)
    reaper.ImGui_NewLine(ctx)
    reaper.ImGui_PopFont(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, PREF_WINDOW_WIDTH - 20)
    
    local rv, rs = reaper.ImGui_InputText(ctx, '##IgnoreTracks', IGNORE_TRACKS_STRING, reaper.ImGui_InputTextFlags_EnterReturnsTrue())
    
    if rv then IGNORE_TRACKS_STRING = rs end
    
    if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then 
        is_name_edited = false
    end
    
    if reaper.ImGui_IsItemActivated(ctx) then
        is_name_edited = true
    end
    
    reaper.ImGui_PushFont(ctx, new_line_font)
    reaper.ImGui_NewLine(ctx)
    reaper.ImGui_NewLine(ctx)
    reaper.ImGui_NewLine(ctx)
    reaper.ImGui_PopFont(ctx)


    local retval, link = reaper.ImGui_Checkbox(ctx, 'Link to Metasurface Controller', LINK_TO_CONTROLLER)
    if retval then 
        LINK_TO_CONTROLLER = link

        if LINK_TO_CONTROLLER == true then
            CONTROL_TRACK, CONTROL_FX_INDEX = getControlTrack()
        end
    end

end

function getControlTrack()

    for t = 0, reaper.CountTracks(0) - 1 do
        local current_track = reaper.GetTrack(0, t)
        local retval, track_name = reaper.GetTrackName(current_track)
        if retval then
            if track_name == 'mtt_metasurface_controller' then
                local n_fx = reaper.TrackFX_GetCount(current_track)
                for f = 0, n_fx do
                    
                    local retval, fx_name = reaper.TrackFX_GetFXName(current_track, f)
                    
                    if fx_name == 'JS: mtt_metasurface_controller [MTT/mtt_metasurface_controller]' then
                        --reaper.ShowConsoleMsg('qui\n')
                        --reaper.ShowConsoleMsg(fx_name .. '\n')
                        return current_track, f
                    end
                end
            end
        end
    end

    reaper.InsertTrackAtIndex(reaper.CountTracks(0), 0)
    local new_track = reaper.GetTrack(0, reaper.CountTracks(0) - 1)

    local trackName = "mtt_metasurface_controller"
    reaper.GetSetMediaTrackInfo_String(new_track, "P_NAME", trackName, true)

    reaper.TrackFX_AddByName(new_track, 'JS: mtt_metasurface_controller', false, 1)

    return new_track, 0

end

function drawCircle(x, y, raggio, color)
    -- Assicurati che la finestra ImGui sia già stata creata con ImGui.Begin
    local draw_list = reaper.ImGui_GetForegroundDrawList(ctx)
    local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    
    -- Disegna un cerchio pieno alle coordinate (x, y) con un certo raggio
    reaper.ImGui_DrawList_AddCircle(draw_list, x, y, raggio, color, 0, 1)
end

function drawDot(x, y, raggio, color)
    -- Assicurati che la finestra ImGui sia già stata creata con ImGui.Begin
    draw_list = reaper.ImGui_GetForegroundDrawList(ctx)
    local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    
    -- Disegna un cerchio pieno alle coordinate (x, y) con un certo raggio
    reaper.ImGui_DrawList_AddCircleFilled(draw_list, x, y, raggio, color, 0)
end

function onExit()
    
    --if reaper.GetProjectName(0, "") ~= '' then
        if PROJECT_NAME ~= '' then
            writeSnapshotsToFile(PROJECT_PATH .. '/ms_save')
        end
    --end
end

function initBalls()

    balls = {}

    for i = 1, #snapshot_list do
        --reaper.ShowConsoleMsg('lamaladonna\n')
        --local ball_x, ball_y = windowToScreenCoordinates((snapshot_list[i].x * ACTION_WINDOW_WIDTH - 1), (snapshot_list[i].y * ACTION_WINDOW_HEIGHT - 3))
        table.insert(balls, { pos_x = snapshot_list[i].x, pos_y = snapshot_list[i].y, radius = 7, color = ball_default_color, dragging = false })
        
        --reaper.ShowConsoleMsg('ball_x: ' .. tostring(ACTION_WINDOW_WIDTH) .. '\n' .. 'ball_y: ' .. tostring(ACTION_WINDOW_HEIGHT) .. '\n')
    end

    return true

end

function ensureController(nomeFile, contenuto)
    local path = string.match(nomeFile, "(.+)/[^/]*$")
    if path then
        -- Usa virgolette per gestire i percorsi con spazi su macOS
        os.execute("mkdir -p \"" .. path .. "\"")
        --reaper.ShowConsoleMsg("\"" .. path .. "\"")
    end

    local file = io.open(nomeFile, "r")

    if file then
        file:close()
    else
        file = io.open(nomeFile, "w")
        if file then
            file:write(contenuto)
            file:close()
        else
            print("Errore nella creazione del file")
        end
    end
end

function initMS()

    PROJECT_NAME = reaper.GetProjectName(0, "")
    PROJECT_PATH = reaper.GetProjectPath(0)

    if PROJECT_NAME == '' then reaper.ShowMessageBox('You must save the project to use Metasurface.', 'Metasurface Error', 0) return false end

    
    ensureController(reaper.GetResourcePath() .. '/Effects/MTT/mtt_metasurface_controller', CONTROLLER)

    snapshot_list = {}

    if PROJECT_NAME ~= '' then
        --data, ignoreParamsPreSaveString, ignoreParamsPostSaveString, ignoreFXsString, ignoreTracksString
        snapshot_list, IGNORE_PARAMS_PRE_SAVE_STRING, IGNORE_PARAMS_POST_SAVE_STRING, IGNORE_FXs_STRING, IGNORE_TRACKS_STRING, LINK_TO_CONTROLLER = loadFromFile(reaper.GetProjectPath(0) .. '/ms_save')
    end
    
    if snapshot_list == nil then snapshot_list = {} end

    initBalls()
    updateSnapshotIndexList()

    if LINK_TO_CONTROLLER == true then
        CONTROL_TRACK, CONTROL_FX_INDEX = getControlTrack()
    end

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

