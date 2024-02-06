-- Script Name and Version

local major_version = 0
local minor_version = 1

local name = 'Metasurface ' .. tostring(major_version) .. '.' .. tostring(minor_version)

local MAIN_WINDOW_WIDTH = 400
local MAIN_WINDOW_HEIGHT = 400

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
    param_list = {},
    param_index_list = {},
    track_GUID_list = {},
    fx_index_list = {},
    fx_name = {}
}

function snapshot:new(x, y, name)
    local instance = setmetatable({}, snapshot)
    instance.x = x or 0
    instance.y = y or 0
    instance.name = name
    instance.param_value_list = {}
    instance.param_index_list = {}
    instance.track_GUID_list = {}
    instance.fx_index_list = {}
    instance.fx_name = {}
    return instance
end

LAST_TOUCHED_BUTTON_INDEX = 0

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

function onCmdLeftClick()
    if reaper.ImGui_IsMouseClicked(ctx, 1, false) then --and reaper.ImGui_IsKeyDown(ctx, 0x11) then
        local  x,  y = GetMouseClickPositionInWindow(ctx, 1)
        snapshot_list[#snapshot_list + 1] = snapshot:new(x, y, 'B')
    end
end

function drawSnapshots()

    local num_selected_tracks = reaper.CountSelectedTracks(0)
    
    for s = #snapshot_list, 1, -1 do
    
        reaper.ImGui_SetCursorPos(ctx, snapshot_list[s].x, snapshot_list[s].y)

        local name = 'B'
        if s == LAST_TOUCHED_BUTTON_INDEX then name = 'S' end

        if reaper.ImGui_Button(ctx, name .. '##' .. tostring(s), 25, 25) then

            LAST_TOUCHED_BUTTON_INDEX = s

            if not reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftShift()) then

                        for i = 1, #snapshot_list[s].param_value_list do
                            local track = reaper.BR_GetMediaTrackByGUID(0, snapshot_list[s].track_GUID_list[i])

                            local param_index = snapshot_list[s].param_index_list[i]
                            local fx_index = snapshot_list[s].fx_index_list[i]
                            local param_value = snapshot_list[s].param_value_list[i]

                            --reaper.ShowMessageBox(tostring(track), '', 0)

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
    end
end


function mainWindow()

    if reaper.ImGui_Button(ctx, 'Save Last Touched', 130, 30) then

        local num_selected_tracks = reaper.CountSelectedTracks(0)

        local s = LAST_TOUCHED_BUTTON_INDEX

        for t = 0, num_selected_tracks - 1 do
            local selected_track = reaper.GetSelectedTrack(0, t)
            local retval, selected_track_name = reaper.GetTrackName(selected_track)
            local num_track_fx = reaper.TrackFX_GetCount(selected_track)

            for f = 0, num_track_fx - 1 do
                local num_fx_param = reaper.TrackFX_GetNumParams(selected_track, t)

                for p = 0, num_fx_param - 1 do

                    local val, min, max = reaper.TrackFX_GetParam(selected_track, f, p)

                    table.insert(snapshot_list[s].param_value_list, val)
                    table.insert(snapshot_list[s].param_index_list, p)
                    table.insert(snapshot_list[s].track_GUID_list, reaper.BR_GetMediaTrackGUID(selected_track))
                    table.insert(snapshot_list[s].fx_index_list, f)
                    local retval, fx_name = reaper.TrackFX_GetFXName(selected_track, f)
                    table.insert(snapshot_list[s].fx_name, fx_name)
                end
            end
        end
    end

--[[     if reaper.ImGui_Button(ctx, 'Save', 20, 20) then
        
    end ]]

    reaper.ImGui_BeginChild(ctx, 'MovementWindow', MAIN_WINDOW_WIDTH, MAIN_WINDOW_HEIGHT, false, reaper.ImGui_WindowFlags_NoMove())
    
    onCmdLeftClick()

    drawSnapshots()

    reaper.ImGui_EndChild(ctx)
end

reaper.defer(loop)