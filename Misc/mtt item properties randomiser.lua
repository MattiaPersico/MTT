
local major_version = 0
local minor_version = 2

local name = 'Item Properties Randomiser ' .. tostring(major_version) .. '.' .. tostring(minor_version)

if not reaper.APIExists('ImGui_GetBuiltinPath') then
    reaper.MB('ReaImGui 0.10 is required (ReaPack: ReaTeam Extensions).', name, 0)
    return
end

local imgui_ok, imgui_error = pcall(function()
    dofile(reaper.ImGui_GetBuiltinPath() .. '/imgui.lua')('0.10')
end)
if not imgui_ok then
    reaper.MB('Could not load ReaImGui 0.10:\n' .. tostring(imgui_error), name, 0)
    return
end
local ctx = reaper.ImGui_CreateContext(name)

-- Funzione EEL per i Vincoli delle Dimensioni della Finestra
local sizeConstraintsCallback = [=[
1 + 1
]=]

local EEL_DUMMY_FUNCTION = reaper.ImGui_CreateFunctionFromEEL(sizeConstraintsCallback)


local MAIN_WINDOW_WIDTH = 462
local MAIN_WINDOW_HEIGHT = 145

local comic_sans_size = 13
local comic_sans_small_size = 11
local new_line_font_size = 1

local comic_sans
local comic_sans_small
local new_line_font

local OS = reaper.GetOS()

if OS == "OSX32" or OS == "OSX64" or OS == "macOS-arm64" then
    comic_sans = reaper.ImGui_CreateFont('Comic Sans MS', 18)
    comic_sans_small = reaper.ImGui_CreateFont('Comic Sans MS', 17)
    new_line_font = reaper.ImGui_CreateFont('Comic Sans MS', 2)
else
    comic_sans = reaper.ImGui_CreateFont('C:/Windows/Fonts/comic.ttf', 18)
    comic_sans_small = reaper.ImGui_CreateFont('C:/Windows/Fonts/comic.ttf', 17)
    new_line_font = reaper.ImGui_CreateFont('C:/Windows/Fonts/comic.ttf', 2)
end

reaper.ImGui_Attach(ctx, comic_sans_small)
reaper.ImGui_Attach(ctx, comic_sans)
reaper.ImGui_Attach(ctx, new_line_font)

--- paramters
local rate = 0
--local rate_offset = 0

local volume = 0
--local volume_offset = 1

local pan = 0
--local pan_offset = 0

function SetButtonState(set)
  local _, _, sec, cmd = reaper.get_action_context()
  reaper.SetToggleCommandState(sec, cmd, set or 0)
  reaper.RefreshToolbar2(sec, cmd)
end

function guiStylePush()
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
    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ResizeGrip(), reaper.ImGui_ColorConvertDouble4ToU32(0.1, 0.1, 0.1, 2))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ResizeGripActive(), reaper.ImGui_ColorConvertDouble4ToU32(0.3, 0.3, 0.3, 2))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ResizeGripHovered(), reaper.ImGui_ColorConvertDouble4ToU32(0.18, 0.18, 0.18, 2))

    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBg(), reaper.ImGui_ColorConvertDouble4ToU32(0.14, 0.14, 0.14, 2)) 
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBgActive(), reaper.ImGui_ColorConvertDouble4ToU32(0.18, 0.18, 0.18, 2))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBgCollapsed(), reaper.ImGui_ColorConvertDouble4ToU32(0.18, 0.18, 0.18, 2))
  
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), reaper.ImGui_ColorConvertDouble4ToU32(0.2, 0.2, 0.2, 2))
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
  
    reaper.ImGui_PushFont(ctx, comic_sans, comic_sans_size)
end

function guiStylePop()
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

function randomiseRate()
    local retval, v = reaper.ImGui_SliderDouble(ctx, "Rate", rate, 0, 2)

    if retval then

        rate = v

        local selected_items = {}
        reaper.Main_OnCommand(40652, 0) -- reset playrate to 1.0

        local last = reaper.CountSelectedMediaItems(0) - 1
        for i = 0, last do
            selected_items[i] = reaper.GetSelectedMediaItem(0, i)
        end

        for i = 0, last do
            reaper.SetMediaItemSelected(selected_items[i], false)
        end

        -- Keep native steps and selection order: the actions also resize the item.
        local run_command = reaper.Main_OnCommand
        for i = 0, last do
            local how_many_cycles = (math.random() * 100) * rate
            local command = math.random(0, 1) == 0 and 40520 or 40519 -- decrease/increase rate by 10 cents
            local item = selected_items[i]

            reaper.SetMediaItemSelected(item, true)
            for j = 1, how_many_cycles do
                run_command(command, 0)
            end
            reaper.SetMediaItemSelected(item, false)
        end

        for i = 0, last do
            reaper.SetMediaItemSelected(selected_items[i], true)
        end

        reaper.UpdateArrange()
        --reaper.ShowConsoleMsg("\n")
    end
end

function randomiseVolume()

    local retval, v = reaper.ImGui_SliderDouble(ctx, "Volume", volume, 0, 1)

    if retval then

        volume = v

        for i = 0, reaper.CountSelectedMediaItems(0) - 1, 1 do

            local take = reaper.GetActiveTake(reaper.GetSelectedMediaItem(0, i))
            local new_volume = math.max((((math.random() * 3) - 2) * volume) + 1, 0.001)

            if take then reaper.SetMediaItemTakeInfo_Value(take, "D_VOL", new_volume) end

        end

        reaper.UpdateArrange()
    end
end

function randomisePan()
    local retval, v = reaper.ImGui_SliderDouble(ctx, "Pan", pan, 0, 1)

    if retval then

        pan = v

        for i = 0, reaper.CountSelectedMediaItems(0) - 1, 1 do

            local take = reaper.GetActiveTake(reaper.GetSelectedMediaItem(0, i))
            local new_pan = (math.random() * 2 - 1) * pan

            if take then reaper.SetMediaItemTakeInfo_Value(take, "D_PAN", new_pan) end

        end

        reaper.UpdateArrange()
    end
end

function mainWindow()

    local no_selection = reaper.CountSelectedMediaItems(0) == 0
    if no_selection then reaper.ImGui_BeginDisabled(ctx) end

    randomiseVolume()
    randomiseRate()
    randomisePan()

    if no_selection then reaper.ImGui_EndDisabled(ctx) end

end

function onExit()
    SetButtonState(0)
end

function loop()

    guiStylePush()

    reaper.ImGui_SetNextWindowSizeConstraints(ctx, MAIN_WINDOW_WIDTH, MAIN_WINDOW_HEIGHT, MAIN_WINDOW_WIDTH, MAIN_WINDOW_HEIGHT, EEL_DUMMY_FUNCTION)

    local flags =  
          reaper.ImGui_WindowFlags_NoCollapse()
        | reaper.ImGui_WindowFlags_NoScrollbar()
        | reaper.ImGui_WindowFlags_NoScrollWithMouse()
        | reaper.ImGui_WindowFlags_NoDocking()

    local mw_visible, mw_open = reaper.ImGui_Begin(ctx, name, true, flags)

    if mw_visible then
          
      mainWindow()

      reaper.ImGui_End(ctx)
  
    end

    guiStylePop()

    if mw_open then
        reaper.defer(loop)
    end

end


SetButtonState(1)
reaper.atexit(onExit)
reaper.defer(loop)