local major_version = 0
local minor_version = 1
local name = 'clone_envelope ' .. tostring(major_version) .. '.' .. tostring(minor_version)

local MIN_MAIN_WINDOW_WIDTH = 120
local MIN_MAIN_WINDOW_HEIGHT = 100

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


local sizeConstraintsCallback = [=[
a = 0
]=]

local stolenPeaksNormMult = {}

--[[
    local number = reaper.CalculateNormalization(PCM_source, 2, 0, 0, 0)

    Calculate normalize adjustment for source media.
    normalizeTo: 0=LUFS-I, 1=RMS-I, 2=peak, 3=true peak, 4=LUFS-M max, 5=LUFS-S max.
    normalizeTarget: dBFS or LUFS value.
    normalizeStart,
    normalizeEnd: time bounds within source media for normalization calculation.
    If normalizationStart=0 and normalizationEnd=0, the full duration of the media will be used for the calculation.
]]


function getTakeStartEndTime(take)
    if not take then return end

    local item = reaper.GetMediaItemTake_Item(take)
    local takeStart = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
    local takeRate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
    local takeLength = reaper.GetMediaItemInfo_Value(item, "D_LENGTH") * takeRate

    -- Calcola lo start time e l'end time della take rispetto al PCM_source
    local startTime = (takeStart / takeRate)
    local endTime = startTime + (takeLength / takeRate)

    return startTime, endTime
end

function createTrackVolumeEnvelopePoint(track, position, volumeValue)
    -- Assicurati che la traccia e i valori siano validi
    if not track or not position or not volumeValue then return end
    
    -- Ottieni l'envelope del volume per la traccia selezionata
    local envelope = reaper.GetTrackEnvelopeByName(track, "Volume")
    if not envelope then return end
    
    -- Converte il valore del volume da 0-1 a scala Reaper (dB)
    local valueDB = reaper.ScaleToEnvelopeMode(1, volumeValue) -- 1 è il modo per l'env di volume
    
    -- Inserisce il punto envelope
    reaper.InsertEnvelopePoint(envelope, position, valueDB, 0, 0, 0, true)
    
    -- Ricalcola e aggiorna l'envelope
    reaper.Envelope_SortPoints(envelope)
end

function createTakeVolumeEnvelopePoint(take, position, volumeValue)
    -- Assicurati che la traccia e i valori siano validi
    if not take or not position or not volumeValue then return end
    
    -- Ottieni l'envelope del volume per la traccia selezionata
    local envelope = reaper.GetTakeEnvelopeByName(take, "Volume")
    if not envelope then return end
    
    -- Converte il valore del volume da 0-1 a scala Reaper (dB)
    local valueDB = reaper.ScaleToEnvelopeMode(1, volumeValue) -- 1 è il modo per l'env di volume
    
    -- Inserisce il punto envelope
    reaper.InsertEnvelopePoint(envelope, position, valueDB, 0, 0, 0, true)
    
    -- Ricalcola e aggiorna l'envelope
    reaper.Envelope_SortPoints(envelope)
end

function stealEnvelope()

    

    stolenPeaksNormMult = {}

    local item = reaper.GetSelectedMediaItem(0, 0)
    local take = reaper.GetActiveTake(item)
    local PCM_source = reaper.GetMediaItemTake_Source(take)
    
    local track = reaper.GetSelectedTrack(0,0)
    
    local windowSize = 0.01
    local takeLenght = reaper.GetMediaItemInfo_Value(item, "D_LENGTH") * reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
    local startTime, endTime = getTakeStartEndTime(take)
    
    local nWindows = takeLenght/windowSize
    
    local itemStart = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    --setTakeVolumeEnvelopeVisible(item)
    --createVolumeEnvelopePoint(track, itemStart, 1)
    --createVolumeEnvelopePoint(track, itemStart + takeLenght, 1)
    --table.insert(stolenPeaksNormMult, 1)

    local position = itemStart
    
    for i = 0, nWindows do
        local newStepStartTime = startTime + windowSize * i
        local newStepEndtTime = newStepStartTime + windowSize
        position = itemStart + newStepStartTime + windowSize * 0.5
        local number = reaper.CalculateNormalization(PCM_source, 2, 0, newStepStartTime, newStepEndtTime)
    
        if position > itemStart + endTime then
            --table.insert(stolenPeaksNormMult, 1)
            break 
        end
        
        table.insert(stolenPeaksNormMult, number)

        position = itemStart + newStepStartTime + windowSize * 0.5
        --createVolumeEnvelopePoint(track, position, 16/number)
    end

    
    --createVolumeEnvelopePoint(track, itemStart + takeLenght, 1)
end

function imposeEnvelope()

    if stolenPeaksNormMult then
        local item = reaper.GetSelectedMediaItem(0, 0)
        local take = reaper.GetActiveTake(item)
        local PCM_source = reaper.GetMediaItemTake_Source(take)
        
        local track = reaper.GetSelectedTrack(0,0)
        
        local windowSize = 0.01
        local takeLenght = reaper.GetMediaItemInfo_Value(item, "D_LENGTH") * reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
        local startTime, endTime = getTakeStartEndTime(take)
        
        local nWindows = takeLenght/windowSize
        
        --local itemStart = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local itemStart = 0
        --createVolumeEnvelopePoint(track, itemStart, 1)
        --createVolumeEnvelopePoint(track, itemStart + takeLenght, 1)
        
        local position = itemStart

        setTakeVolumeEnvelopeVisible(item)

        createTakeVolumeEnvelopePoint(take, position, 1)
        position = itemStart + windowSize * 0.5



        for i = 1, #stolenPeaksNormMult do
            local newStepStartTime = startTime + windowSize * i
            local newStepEndtTime = newStepStartTime + windowSize
            
            local number = stolenPeaksNormMult[i]
        
            if position > itemStart + endTime then
                --createVolumeEnvelopePoint(track, position, 1)
                break 
            end
            
            createTakeVolumeEnvelopePoint(take, position, 16/number)

            position = itemStart + newStepStartTime + windowSize * 0.5
        end
        
        createTakeVolumeEnvelopePoint(take, position, 1)
    end
end

function setTakeVolumeEnvelopeVisible(item)
    
    if not item then return end

    local take = reaper.GetActiveTake(item)
    if not take or reaper.TakeIsMIDI(take) then return end

    -- Ottiene lo state chunk dell'item
    local _, itemChunk = reaper.GetItemStateChunk(item, "", false)
    local envChunkExists = itemChunk:find("<VOLENV") ~= nil

    if not envChunkExists then
        -- Aggiunge un inviluppo di volume se non presente
        local envChunk = "<VOLENV\nEGUID {FDCF5A46-AFD6-1244-BD64-F5A8DA0BF054}\nACT 1 -1\nVIS 1 1 1\nLANEHEIGHT 0 0\nARM 0\nDEFSHAPE 0 -1 -1\nVOLTYPE 1\nPT 0 1 0\n>\n"
        itemChunk = itemChunk:gsub("<EXT", envChunk .. "<EXT")
    else
        -- Rende visibile l'inviluppo se già presente ma non visibile
        itemChunk = itemChunk:gsub("<VOLENV.-\n>", function(match)
            if match:find("VIS 0") then
                return match:gsub("VIS 0", "VIS 1")
            else
                return match
            end
        end)
    end

    reaper.SetItemStateChunk(item, itemChunk, false)
    reaper.UpdateArrange()
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

    reaper.ImGui_SetNextWindowSizeConstraints(ctx, MIN_MAIN_WINDOW_WIDTH, MIN_MAIN_WINDOW_HEIGHT, MIN_MAIN_WINDOW_WIDTH, MIN_MAIN_WINDOW_HEIGHT, reaper.ImGui_CreateFunctionFromEEL(sizeConstraintsCallback))

    local flags =  
          reaper.ImGui_WindowFlags_NoCollapse()
        | reaper.ImGui_WindowFlags_NoScrollbar()
        | reaper.ImGui_WindowFlags_NoScrollWithMouse()
        | reaper.ImGui_WindowFlags_NoDocking()  


    local mw_visible, mw_open = reaper.ImGui_Begin(ctx, name, true, flags)

    MAIN_WINDOW_WIDTH, MAIN_WINDOW_HEIGHT = reaper.ImGui_GetWindowSize(ctx)
  
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
        reaper.defer(gui_loop)
    end

end

function mainWindow()
    if reaper.ImGui_Button(ctx, 'steal', 100) then
        stealEnvelope()
    end

    if reaper.ImGui_Button(ctx, 'impose', 100) then
        reaper.Undo_BeginBlock()
        imposeEnvelope()
        reaper.Undo_EndBlock(0,0)
    end
end

reaper.defer(gui_loop)






--reaper.ShowConsoleMsg(tostring(number) .. '\n')