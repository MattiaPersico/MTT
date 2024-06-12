-- aggiungere controllo post-commit e in caso di fallimento fare report
-- capire se c'é modo di sapere se la revision attuale del progetto che sta sul server e quella che sta sul client sono la stessa
-- se c'é un modo aggiungere al refresh l'informazione di discrepanza in caso di revision non sincronizzate

local major_version = 1
local minor_version = 8

local name = 'Plastic Integration ' .. tostring(major_version) .. '.' .. tostring(minor_version)

local plastic_cl = "/Applications/PlasticSCM.app/Contents/Applications/cm.app/Contents/MacOS/cm"

-- Funzione EEL per i Vincoli delle Dimensioni della Finestra
local sizeConstraintsCallback = [=[
1 + 1
]=]

local AUDIO_FOLDER_INSIDE_REPOSITORY = '/Audio'

local EEL_DUMMY_FUNCTION = reaper.ImGui_CreateFunctionFromEEL(sizeConstraintsCallback)

local MAIN_WINDOW_WIDTH = 462
local MAIN_WINDOW_HEIGHT = 145

REAPER_CLI_PATH = reaper.GetExePath() .. '/REAPER.app/Contents/MacOS/REAPER'

local comment = string.sub(reaper.GetProjectName(0,''), 1, -5) .. ' Update'
local status_string = 'Offline'
local commit_enabled = false
local checkout_enabled = false
local getlatest_enabled = false
local last_frame_project_path = ''

dofile(reaper.GetResourcePath() .. '/Scripts/ReaTeam Extensions/API/imgui.lua')('0.8')
local ctx = reaper.ImGui_CreateContext(name)
local comic_sans = reaper.ImGui_CreateFont('/System/Library/Fonts/Supplemental/Comic Sans MS.ttf', 18)
local comic_sans_small = reaper.ImGui_CreateFont('/System/Library/Fonts/Supplemental/Comic Sans MS.ttf', 16)
local new_line_font = reaper.ImGui_CreateFont('/System/Library/Fonts/Supplemental/Comic Sans MS.ttf', 2)

reaper.ImGui_Attach(ctx, comic_sans_small)
reaper.ImGui_Attach(ctx, comic_sans)
reaper.ImGui_Attach(ctx, new_line_font)

function drawDot(x, y, raggio, color, n_segs)
    -- Assicurati che la finestra ImGui sia già stata creata con ImGui.Begin
    local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    --n_segs = 30
    -- draw_list,  center_x,  center_y,  radius,  col_rgba,   num_segmentsIn)
    -- Disegna un cerchio pieno alle coordinate (x, y) con un certo raggio
    reaper.ImGui_DrawList_AddCircleFilled(draw_list, x, y, raggio, color, n_segs)
end

function refreshStatus(proj_dir, proj_path)

    if proj_path ~= '' then
        if plastic_checkWorkspace(proj_path) then
            getlatest_enabled = true
    
            if plastic_checkStatus(proj_path) then
    
                if plastic_checkOut(proj_dir) then
                    status_string = 'Project Available'
                    plastic_undoCheckOut(proj_dir)
                    checkout_enabled = true
                else
                    status_string = "Project Locked in another workspace"
                    checkout_enabled = false
                end
    
                commit_enabled = false
    
            else
                status_string = 'Checked-Out'
                commit_enabled = true
            end
        else
            status_string = 'Not in a valid workspace'
            checkout_enabled = false
            commit_enabled = false
            getlatest_enabled = false
        end
    else
        checkout_enabled = false
        commit_enabled = false
        getlatest_enabled = false
    end

end

function guiNewLine()
    reaper.ImGui_PushFont(ctx, new_line_font)
    reaper.ImGui_NewLine(ctx)
    reaper.ImGui_PopFont(ctx)
end

function loop()

    guiStylePush()

    reaper.ImGui_SetNextWindowSizeConstraints(ctx, MAIN_WINDOW_WIDTH, MAIN_WINDOW_HEIGHT, MAIN_WINDOW_WIDTH, MAIN_WINDOW_HEIGHT, EEL_DUMMY_FUNCTION)

    local flags =  
          reaper.ImGui_WindowFlags_NoCollapse()
        | reaper.ImGui_WindowFlags_NoScrollbar()
        | reaper.ImGui_WindowFlags_NoScrollWithMouse()
        | reaper.ImGui_WindowFlags_NoDocking()  

    local proj_name = reaper.GetProjectName(0)

    if proj_name == '' then
        proj_name = 'Unsaved'
    else
        if proj_name ~= string.gsub(proj_name, '.RPP', "") then
            comment = string.sub(reaper.GetProjectName(0,''), 1, -5) .. ' Update' 
        end
        
        proj_name = string.gsub(proj_name, '.RPP', "")

    end

    local mw_visible, mw_open = reaper.ImGui_Begin(ctx, name .. '  -  ' .. proj_name, true, flags)

    if mw_visible then
          
      mainWindow()

      reaper.ImGui_End(ctx)
  
    end

    guiStylePop()

    if mw_open then
        reaper.defer(loop)
    end

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
  
    reaper.ImGui_PushFont(ctx, comic_sans)
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

function removeLastPathComponent(path)
    if type(path) == "string" and path ~= "" then
        -- Trova l'ultima occorrenza del separatore di percorso ("/" in Unix)
        local last_separator = path:find("/[^/]*$")

        -- Se l'ultima occorrenza del separatore di percorso è trovata, rimuovi l'ultima parte del percorso
        if last_separator then
            return path:sub(1, last_separator - 1)
        else
            return path
        end
    else
        -- Se path non è una stringa o è vuoto, restituisci nil o un valore predefinito
        return nil
    end
end

function drawCircularArrowButton(x, y, radius, color, thickness)
end

function mainWindow()

    local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
    local color = reaper.ImGui_ColorConvertDouble4ToU32(1,1,1,1)

    if commit_enabled then 
        color = reaper.ImGui_ColorConvertDouble4ToU32(1,1,0,1)
    else
        if checkout_enabled then
            color = reaper.ImGui_ColorConvertDouble4ToU32(0,1,0,1) 
        else
            color = reaper.ImGui_ColorConvertDouble4ToU32(1,0,0,1)
        end
    end

    if not getlatest_enabled then
        color = reaper.ImGui_ColorConvertDouble4ToU32(1,0,0,1)
    end

    drawDot(x + 6, y + 11, 6, color, 0)

    local retval, proj_path = reaper.EnumProjects(-1, "")
    local proj_dir = removeLastPathComponent(proj_path)

    reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + 20)

    reaper.ImGui_PushFont(ctx, comic_sans_small)

    if reaper.ImGui_Button(ctx, 'Refresh') then
        refreshStatus(proj_dir, proj_path)
    end

    reaper.ImGui_PopFont(ctx)

    
    if last_frame_project_path ~= proj_path then
        refreshStatus(proj_dir, proj_path)
    end

    last_frame_project_path = proj_path

    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetCursorPosY(ctx) - 2)
    reaper.ImGui_Text(ctx, "Status: " .. status_string)

    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetWindowWidth(ctx) - 132)

    reaper.ImGui_BeginDisabled(ctx, not getlatest_enabled)

    if reaper.ImGui_Button(ctx, "Update Repository") then
        if reaper.ShowMessageBox("This operation will recursively restore the state of all the Projects inside the selected root to the Server version.\n\nYou will lose all your progress.", 'WARNING', 1) == 1 then

            local retval, folder = reaper.JS_Dialog_BrowseForFolder("Choose the folder to update recursively", plastic_getWorkspaceRoot(proj_dir) .. AUDIO_FOLDER_INSIDE_REPOSITORY)

            if retval == 1 then

                reaper.Main_OnCommand(40026, 0)

                reaper.Main_OnCommand(40860, 0)
    
                plastic_undoChanges(folder)
            
                plastic_update(folder)
    
                reaper.ExecProcess(REAPER_CLI_PATH .. ' \"' .. proj_path .. '\"', 0)
    
                refreshStatus(proj_dir, proj_path)
            end

        end
    end

    reaper.ImGui_EndDisabled(ctx)

    guiNewLine()
    guiNewLine()

    reaper.ImGui_BeginDisabled(ctx, not getlatest_enabled)

    if reaper.ImGui_Button(ctx, "Get Server Version") then

        if reaper.ShowMessageBox("This operation will restore the state of the Project to the Server version.\n\nYou will lose all your progress.", 'WARNING', 1) == 1 then

            if plastic_checkWorkspace(proj_path) then
                checkout_enabled = true
                
                if plastic_checkStatus(proj_path) then

                    reaper.Main_OnCommand(40026, 0)

                    reaper.Main_OnCommand(40860, 0)
    
                    plastic_undoChanges(proj_dir)
    
                    --plastic_undoCheckOut(proj_dir)
    
                    plastic_update(proj_dir)
    
                    reaper.ExecProcess(REAPER_CLI_PATH .. ' \"' .. proj_path .. '\"', 0)
    
                    --reaper.Main_openProject(proj_path)
    
                    refreshStatus(proj_dir, proj_path)
    
                else

                    reaper.Main_OnCommand(40026, 0)

                    reaper.Main_OnCommand(40860, 0)
    
                    plastic_undoChanges(proj_dir)
    
                    --plastic_undoCheckOut(proj_dir)
    
                    plastic_update(proj_dir)
    
                    reaper.ExecProcess(REAPER_CLI_PATH .. ' \"' .. proj_path .. '\"', 0)
    
                    --reaper.Main_openProject(proj_path)
    
                    refreshStatus(proj_dir, proj_path)

                    if plastic_checkOut(proj_dir) then
                        status_string = 'Checked-Out'
                        commit_enabled = true
                    else
                        status_string = "Project Locked in another workspace"
                        checkout_enabled = false
                        commit_enabled = false
                    end

                    status_string = 'Checked-Out'
                    commit_enabled = true
                end
                --reaper.ShowConsoleMsg(proj_dir .. '\n')
            else
                status_string = 'Not in a valid workspace'
                checkout_enabled = false
                commit_enabled = false
            end
        end
    end

    reaper.ImGui_EndDisabled(ctx)

    reaper.ImGui_SameLine(ctx)

    reaper.ImGui_BeginDisabled(ctx, not checkout_enabled)
    --reaper.ShowConsoleMsg(tostring(not checkout_enabled) .. '\n')

    local buttonText = "Get Server Version and Check-Out"
    local warningText = "This operation will restore the state of the Project to the Server version.\n\nYou will lose all your progress."
    local isSuperDown = false
--[[     if reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftSuper()) then 
        buttonText = "Check-Out (no update)"
        warningText = "This operation will attempt to check out the Project without updating to the Server version.\n\nThe operation is safe but may fail."
        isSuperDown = true
    end ]]
    
    if reaper.ImGui_Button(ctx, buttonText) then
        if reaper.ShowMessageBox(warningText, 'WARNING', 1) == 1 then
            if plastic_checkWorkspace(proj_path) then

                checkout_enabled = true

                if plastic_checkStatus(proj_path) then

                    if not isSuperDown then

                        reaper.Main_OnCommand(40026, 0)

                        reaper.Main_OnCommand(40860, 0)

                        plastic_undoChanges(proj_dir)

                        plastic_undoCheckOut(proj_dir)

                        plastic_update(proj_dir)
                
                        reaper.ExecProcess(REAPER_CLI_PATH .. ' \"' .. proj_path .. '\"', 0)
                    end

                    --reaper.Main_openProject(proj_path)

                    if plastic_checkOut(proj_dir) then
                        status_string = 'Checked-Out'
                        commit_enabled = true
                    else
                        status_string = "Project Locked in another workspace"
                        checkout_enabled = false
                        commit_enabled = false
                    end
                else
                    status_string = 'Checked-Out'
                    commit_enabled = true
                end
                --reaper.ShowConsoleMsg(proj_dir .. '\n')
            else
                status_string = 'Not in a valid workspace'
                commit_enabled = false
                checkout_enabled = false
            end
        end
    end

    if commit_enabled == true then checkout_enabled = false end

    reaper.ImGui_EndDisabled(ctx)

    reaper.ImGui_SameLine(ctx)
    
    reaper.ImGui_BeginDisabled(ctx, not commit_enabled)

    if reaper.ImGui_Button(ctx, "Release Lock") then
        if reaper.ShowMessageBox("You are about to make this Project available without committing to the Server.\n\nAre you sure you want to proceed?", 'ALERT', 1) == 1 then
            plastic_undoCheckOut(proj_dir)
            refreshStatus(proj_dir, proj_path)
        end
    end

    reaper.ImGui_EndDisabled(ctx)

    guiNewLine()
    guiNewLine()

    reaper.ImGui_BeginDisabled(ctx, not commit_enabled)

    if reaper.ImGui_Button(ctx, "Commit") then

        if reaper.ShowMessageBox("You are about to commit the changes to the Project and release the lock on the files.\n\nAre you sure you want to continue?", 'ALERT', 1) == 1 then
            
            if plastic_checkWorkspace(proj_dir) then
                reaper.Main_OnCommand(40026, 0)
                plastic_Add(proj_dir)
                plastic_checkIn(proj_dir, comment)
                refreshStatus(proj_dir, proj_path)
            else
                status_string = 'Not in a valid workspace'
                commit_enabled = false
            end
        end
    
    end

    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, reaper.ImGui_GetWindowWidth(ctx) - 78)
    local retval, buf = reaper.ImGui_InputText(ctx, '##comment', comment)--, reaper.ImGui_InputTextFlags_EnterReturnsTrue())

    if retval then
        comment = buf
    end

    if comment == '' then
        comment = string.sub(reaper.GetProjectName(0,''), 1, -5) .. ' Update'
    end

    reaper.ImGui_EndDisabled(ctx)

end

function plastic_checkWorkspace(dir)

    local command = plastic_cl .. " getworkspacefrompath " .. dir 
    --reaper.ShowConsoleMsg(command)

    local handle = io.popen(command)
    local result = handle:read("*a")
    handle:close()

    if result ~= '' then
        --reaper.ShowConsoleMsg(result .. '\n')
        return true
    else
        --reaper.ShowConsoleMsg('Directory is not a Workspace\n')
        return false
    end
end

function plastic_checkStatus(proj_file)

    local command = plastic_cl .. " getstatus " .. proj_file 
    

    local handle = io.popen(command)
    local result = handle:read("*a")
    handle:close()

    --reaper.ShowConsoleMsg(result .. '\n')
    --reaper.ShowConsoleMsg("The item " .. proj_file .. " is under Unity VCS control and is checked in." .. '\n')
    local ecc = "The item " .. proj_file .. " is under Unity VCS control and is checked in.\n"

    if result == ecc then 
        return true -- not owned by user
    else
        return false -- already owned by user
    end
end

function plastic_update(dir)
    local command = 'cd ' .. dir .. ' && ' .. plastic_cl .. " partial update"
    os.execute(command)
end

function getFirstBlock(str)
    local firstBlock = str:match("^(.-)[%s\n]")
    return firstBlock or str
end

function getSecondBlock(str)
    local _, index = str:find("[%s\n]") -- Trova l'indice del primo spazio o newline
    if index then
        local secondBlock = str:sub(index + 1):match("^(.-)[%s\n]")
        return secondBlock or ""
    else
        return ""  -- Se non viene trovato uno spazio o un newline, restituisci una stringa vuota
    end
end

function getThirdBlock(str)
    local _, index = str:find("[%s\n]") -- Trova l'indice del primo spazio o newline
    if index then
        local secondBlock = str:sub(index + 1)
        local _, secondIndex = secondBlock:find("[%s\n]") -- Trova l'indice del secondo spazio o newline
        if secondIndex then
            local thirdBlock = secondBlock:sub(secondIndex + 1):match("^(.-)[%s\n]")
            return thirdBlock or ""
        end
    end
    return ""  -- Se non viene trovato il terzo blocco, restituisci una stringa vuota
end

function plastic_undoChanges(dir)

    local command = plastic_cl .. " undo -R " .. dir 
    
    local handle = io.popen(command)
    local result = handle:read("*a")
    handle:close()

    if result ~= '' then
        --reaper.ShowConsoleMsg(result .. '\n')
        return true
    else
        --reaper.ShowConsoleMsg('Directory is not a Workspace\n')
        return false
    end
end

function plastic_getWorkspaceRoot(dir)
    local command = 'cd ' .. dir .. ' && ' .. plastic_cl .. " wk"

    local handle = io.popen(command)
    local result = handle:read("*a")
    handle:close()

    result = getSecondBlock(result)

    return result
end

function plastic_checkOut(dir)
    local command = plastic_cl .. " co -R " .. dir
    local timeout = 0  -- Consente al comando di eseguirsi indefinitamente
    local result = reaper.ExecProcess(command, timeout)

    if containsExclusiveCheckout(result) then
        --reaper.ShowMessageBox('Project Locked in another workspace', 'ERROR', 0)
        return false
    else
        return true
    end
end

function containsExclusiveCheckout(text)
    local pattern = "These items are exclusively checked out by:"
    return string.find(text, pattern) ~= nil
end

function plastic_undoCheckOut(dir)

    local command = plastic_cl .. " partial undocheckout " .. dir

    local handle = io.popen(command)
    local result = handle:read("*a")
    --local result = handle:read("*a")
    handle:close()

    if result ~= '' then
        --reaper.ShowConsoleMsg(result .. '\n')
        return true
    else
        --reaper.ShowConsoleMsg('Directory is not a Workspace\n')
        return false
    end
end

function plastic_Add(dir)

    local command = plastic_cl .. " add -R " .. dir

    local handle = io.popen(command)
    local result = handle:read("*a")
    handle:close()

    if result ~= '' then
        --reaper.ShowConsoleMsg(result .. '\n')
        return true
    else
        --reaper.ShowConsoleMsg('NOPE\n')
        return false
    end
end

function plastic_checkIn(dir, comment)

    local command = plastic_cl .. " partial checkin " .. dir .. ' -c="'.. string.gsub(comment, " ", "__") ..'" --applychanged'

    local timeout = 0  -- Consente al comando di eseguirsi indefinitamente
    local result = reaper.ExecProcess(command, timeout)
    --local result = os.execute(command)

    if errorCheck(result) == false then
        reaper.ShowMessageBox('', "SUCCESS", 0)
    else

        local file_to_delete = getMissingFilePath(result)

        if file_to_delete then
            local rm_command = plastic_cl ..  ' remove "' .. file_to_delete .. '"'
            os.execute(rm_command)
            plastic_checkIn(dir, comment)
        else
            reaper.ShowMessageBox(getSecondBlock(result), "ERROR", 0)
        end

    end
end

function getMissingFilePath(input)
    local lines = {}
    for line in input:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    if #lines >= 3 then
        local thirdLine = lines[3]
        local path = thirdLine:match("Error: The changed (.+) is not on disk")
        return path
    else
        return nil
    end
end

function errorCheck(input)
    local lines = {}
    for line in input:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    for i = 3, #lines do
        local firstWord = lines[i]:match("(%S+)")
        if firstWord == "Error:" then
            return true
        end
    end
    return false
end

function plastic_isFileLocked(proj)
    local command = string.format(plastic_cl .. ' status %s --locked --machinereadable --short', proj)
    local handle = io.popen(command)
    local result = handle:read("*a")
    handle:close()

    -- Se il risultato contiene "LO", il file è in lock
    --reaper.ShowConsoleMsg(result .. '\n')
    return result:find("LO") ~= nil
end

function onExit()
end

reaper.defer(loop)

reaper.atexit(onExit)