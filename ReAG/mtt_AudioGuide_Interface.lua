--[[ 
  APPUNTI
  - ratio limit per gli spass obj
  - f0 come descriptor
  - finestra di gestione avanzata del corpus
  - preset tramite option-files
  - un giorno ripristinare la debug mode capendo perchè non funziona piu
]]

-- Script Name and Version
local major_version = 0
local minor_version = 19

local name = 'AudioGuide Interface ' .. tostring(major_version) .. '.' .. tostring(minor_version)
-- Reaper ImGui Stuff

local MAIN_WINDOW_WIDTH = 650
local MAIN_WINDOW_HEIGHT = 342--930
local MAIN_WINDOW_MAX_HEIGHT = 800

local MINI_MAIN_WINDOW_WIDTH = 520
local MINI_MAIN_WINDOW_HEIGHT = 70
local MINIMIZED = false

local CURRENT_WINDOW_WIDTH = MAIN_WINDOW_WIDTH
local CURRENT_WINDOW_HEIGHT = MAIN_WINDOW_HEIGHT

local PREF_WINDOW_WIDTH = 200
local PREF_WINDOW_HEIGHT = 220

local SPASS_WINDOW_HEIGHT = 140

dofile(reaper.GetResourcePath() .. '/Scripts/ReaTeam Extensions/API/imgui.lua')('0.8')
local ctx = reaper.ImGui_CreateContext(name)
local comic_sans = reaper.ImGui_CreateFont('/System/Library/Fonts/Supplemental/Comic Sans MS.ttf', 18)
local comic_sans_bigger = reaper.ImGui_CreateFont('/System/Library/Fonts/Supplemental/Comic Sans MS.ttf', 21)
local comic_sans_smaller = reaper.ImGui_CreateFont('/System/Library/Fonts/Supplemental/Comic Sans MS.ttf', 2)

reaper.ImGui_Attach(ctx, comic_sans)
reaper.ImGui_Attach(ctx, comic_sans_bigger)
reaper.ImGui_Attach(ctx, comic_sans_smaller)


mtt_audioguide_paths = ''
if reaper.file_exists(reaper.GetResourcePath()..'/Scripts/MTT/ReAG/mtt_audioguide_paths.lua') then
  retval, mtt_audioguide_paths = require(reaper.GetResourcePath()..'/Scripts/MTT/ReAG/mtt_audioguide_paths')
else
  retval, mtt_audioguide_paths = require(reaper.GetResourcePath()..'/Scripts/MTT_Scripts/ReAG/mtt_audioguide_paths')
end
mtt_audioguide_paths = string.sub(string.sub(mtt_audioguide_paths, 4), 1, -5)


local mgf = {}
if reaper.file_exists(reaper.GetResourcePath().."/Scripts/MTT/ReAG/mtt_global_functions.lua") then
  mgf = require(reaper.GetResourcePath().."/Scripts/MTT/ReAG/mtt_global_functions")
else
  mgf = require(reaper.GetResourcePath().."/Scripts/MTT_Scripts/ReAG/mtt_global_functions")
end


local magf = {}
if reaper.file_exists(reaper.GetResourcePath().."/Scripts/MTT/ReAG/mtt_audioguide_functions.lua") then
  magf = require(reaper.GetResourcePath().."/Scripts/MTT/ReAG/mtt_audioguide_functions")
else
  magf = require(reaper.GetResourcePath().."/Scripts/MTT_Scripts/ReAG/mtt_audioguide_functions")
end


local magtooltips = {}
if reaper.file_exists(reaper.GetResourcePath().."/Scripts/MTT/ReAG/mtt_audioguide_tooltips.lua") then
  magtooltips = require(reaper.GetResourcePath().."/Scripts/MTT/ReAG/mtt_audioguide_tooltips")
else
  magtooltips = require(reaper.GetResourcePath().."/Scripts/MTT_Scripts/ReAG/mtt_audioguide_tooltips")
end

REAPER_CLI_PATH = reaper.GetExePath() .. '/REAPER.app/Contents/MacOS/REAPER'
CONCATENATION_IN_PROGRESS = false
SEGMENTATION_IN_PROGRESS = false

-- Segmentation Arguments
local seg_threshold = -45
local seg_offset_rise = 1.1
local seg_multirise = true


-- tsf Patameters
local tsf_threshold = -27
local tsf_offset_rise = 1.1
local tsf_min_seg_len = 0.050
local tsf_max_seg_len = 3.0


-- Corpus Global Attributes
local cga_limit_dur = 0
local cga_onset_len = 2
local cga_offset_len = 2
local cga_allow_repetition = true
local cga_restrict_repetition = 0.5
local cga_restrict_overlaps = 3
local cga_clip_duration_to_target = false

-- Opzioni Generali Concatenazione
local outputevent_align_peaks = false

-- Spass Options
local number_of_spass_objects = 2

-- Super Imposition Options
local si_min_segment = 1
local si_min_segment_enabled = false
local si_max_segment = 3
local si_max_segment_enabled = false
local si_min_frame = 1
local si_min_frame_enabled = false
local si_max_frame = 1
local si_max_frame_enabled = false
local si_min_overlap = 1
local si_min_overlap_enabled = false
local si_max_overlap = 3
local si_max_overlap_enabled = false

-- Items che compongono il CORPUS

local CORPUS_ITEMS = {}
local CORPUS_AFs = {}
local is_corpus_ready = false
local number_of_segments = 0


-- Init Spass Array and Descriptor Matrix
search_mode_list = search_mode_list or {}
search_mode_list_percentage = search_mode_list_percentage or {}
--
descriptors_matrix = descriptors_matrix or {}


for i = 0, number_of_spass_objects do
  descriptors_matrix[i] = descriptors_matrix[i] or {}     
end

-- 'effDur-seg\0power\0power-delta\0centroid\0centroid-delta\0mfccs\0mfccs-delta\0kurtosis\0kurtosis-delta\0'

search_mode_list[1] = 1
search_mode_list_percentage[1] = 30
descriptors_matrix[1][1] = 0
descriptors_matrix[1][2] = 1

search_mode_list[2] = 0
descriptors_matrix[2][1] = 5


-- Preferences Checks
local is_AudioGuide_folder_set = false
local is_python3_set = false

local preferencesWindowState = false

local debug_mode = false

---------------------------------------------------------------------------------------------------------------------------------------
function Spinner(radius, thickness, color)
  local center = {reaper.ImGui_GetCursorScreenPos(ctx)}
  center[1] = center[1] + radius
  center[2] = center[2] + radius
  local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
  local num_segments = 3
  local start = os.clock() * 8 % num_segments
  for i = 0, num_segments do
      local a = (i + start) / num_segments * math.pi * 2
      local b = (i + 1 + start) / num_segments * math.pi * 2
      local xa = center[1] + math.cos(a) * radius
      local ya = center[2] + math.sin(a) * radius
      local xb = center[1] + math.cos(b) * radius
      local yb = center[2] + math.sin(b) * radius
      local col = reaper.ImGui_ColorConvertDouble4ToU32(color[1], color[2], color[3], color[4])
      reaper.ImGui_DrawList_AddLine(draw_list, xa, ya, xb, yb, col, thickness)
  end
end


function drawSpinner(x,y)
  reaper.ImGui_SetCursorPosX(ctx, x) -- Posizione X della rotella
  reaper.ImGui_SetCursorPosY(ctx, y) -- Posizione Y della rotella
  Spinner(8, 2, {1.0, 1.0, 1.0, 1.0}) -- Chiamata a Spinner
end


function areAGandPythonSet()
  if not is_AudioGuide_folder_set then
    reaper.ShowMessageBox( 'Please choose a valid AudioGuide folder (Preferences)','Error', 0)
    return false
  end

  if not is_python3_set then
    reaper.ShowMessageBox('Please choose a valid Python3 distribution (Preferences)','Error',  0)
    return false
  end
 return true
end


function checkSegmentationSignalFile()

  local signalfile

  for i = 1 , #CORPUS_ITEMS do
    signalfile = io.open("/tmp/segmentation_signal_file_" .. tostring(i), "r")
    if not signalfile then
      reaper.defer(checkSegmentationSignalFile)
      return
    else
      signalfile:close()
    end
  end

  for i = 1 , #CORPUS_ITEMS do
    --os.remove("/tmp/segmentation_signal_file_" .. tostring(i))
  end

  for i = 1, #CORPUS_AFs do
    number_of_segments = number_of_segments + mgf.countTextFileLines(CORPUS_AFs[i] .. '.txt')
  end

  if number_of_segments > 0 then
    is_corpus_ready = true
  end

  SEGMENTATION_IN_PROGRESS = false

end


function validateSelectedMediaItems()

  local selected_item_number = reaper.CountSelectedMediaItems(0)

  for i = 1, selected_item_number do
    local media_item = reaper.GetSelectedMediaItem(0, i - 1)
    local media_item_take = reaper.GetActiveTake(media_item)

    if media_item_take then
      local file_extension = mgf.getFileExtension(reaper.GetMediaSourceFileName(reaper.GetMediaItemTake_Source(media_item_take)))
      if file_extension ~= '.wav' and file_extension ~= '.aiff' then
        return false
      end
    else
      return false
    end
  end

  return true
end


function validateSelectedMediaItem()

  local media_item = reaper.GetSelectedMediaItem(0, 0)
  local media_item_take = reaper.GetActiveTake(media_item)

  if media_item_take then
    local file_extension = mgf.getFileExtension(reaper.GetMediaSourceFileName(reaper.GetMediaItemTake_Source(media_item_take)))
    if file_extension ~= '.wav' and file_extension ~= '.aiff' then
      return false
    end
  else
    return false
  end

  return true
end


function onLoadCorpusPressed()

  if not areAGandPythonSet() then
    return
  end

  local selected_item_number = reaper.CountSelectedMediaItems(0)
  
  if selected_item_number > 0 then

    if not validateSelectedMediaItems() then
      reaper.ShowMessageBox('Source file type must be wav or aiff', 'Error', 0)
      return
    end

    is_corpus_ready = false

    if #CORPUS_ITEMS > 0 then
      magf.clearArtifacts(CORPUS_AFs)
    end

    CORPUS_ITEMS = {}
    
    for i=1, selected_item_number, 1 do
      CORPUS_ITEMS[i]=reaper.GetSelectedMediaItem(0, i - 1);
    end

    is_corpus_ready = false
    number_of_segments = 0
    CORPUS_AFs = magf.segmentation(CORPUS_ITEMS, seg_threshold, seg_offset_rise, seg_multirise, debug_mode)
    SEGMENTATION_IN_PROGRESS = true
    reaper.defer(checkSegmentationSignalFile)
  end

end


function checkConcatenationSignalFile()
  local signalfile

  signalfile = io.open("/tmp/concatenation_signal_file", "r")
  if signalfile then
      signalfile:close()
      os.remove("/tmp/concatenation_signal_file")
      
      magf.import_rpp(concatenation_selected_item, concatenation_rpp_path, concatenation_target_position, REAPER_CLI_PATH)
      CONCATENATION_IN_PROGRESS = false
      -- codice post comando di segmentazione

  else
      reaper.defer(checkConcatenationSignalFile)
  end
end


function onMatchTargetPressed()

  if not is_corpus_ready then
    reaper.ShowMessageBox('No CORPUS found.', 'Warning', 0)
    return
  end

  if not areAGandPythonSet() then
    return
  end

  local selected_item_number = reaper.CountSelectedMediaItems(0)

  if selected_item_number > 0 then

    if not validateSelectedMediaItem() then
      reaper.ShowMessageBox('Source file type must be wav or aiff', 'Error', 0)
      return
    end

     concatenation_selected_item = reaper.GetSelectedMediaItem(0,0)

     concatenation_target_filename = reaper.GetMediaSourceFileName(reaper.GetMediaItemTake_Source(reaper.GetActiveTake(concatenation_selected_item)))
  
     concatenation_target_position = reaper.GetMediaItemInfo_Value(concatenation_selected_item, 'D_POSITION')
    
     concatenation_rpp_path = magf.concatenation(  concatenation_selected_item, CORPUS_ITEMS,
                                          concatenation_target_filename, 
                                          tsf_threshold, 
                                          tsf_offset_rise, 
                                          tsf_min_seg_len, 
                                          tsf_max_seg_len, 
                                          outputevent_align_peaks,
                                          cga_limit_dur,
                                          cga_onset_len,
                                          cga_offset_len,
                                          cga_allow_repetition,
                                          cga_restrict_repetition,
                                          cga_restrict_overlaps,
                                          cga_clip_duration_to_target,
                                          search_mode_list,
                                          search_mode_list_percentage,
                                          descriptors_matrix,
                                          si_min_segment,
                                          si_min_segment_enabled,
                                          si_max_segment,
                                          si_max_segment_enabled,
                                          si_min_frame,
                                          si_min_frame_enabled,
                                          si_max_frame,
                                          si_max_frame_enabled,
                                          si_min_overlap,
                                          si_min_overlap_enabled,
                                          si_max_overlap,
                                          si_max_overlap_enabled,
                                          debug_mode
                                        )
      if not debug_mode then
        CONCATENATION_IN_PROGRESS = true
        reaper.defer(checkConcatenationSignalFile)
      end
  end
end


function initReAG()

  signalfile = io.open("/tmp/concatenation_signal_file", "r")
  if signalfile then
      signalfile:close()
      os.remove("/tmp/concatenation_signal_file")
  end

  magf.deleteSegmentationSignalFiles("/private/tmp")

  preferencesWindowState = false

  if magf.validateAudioGuidePath(AG_path) then
     magf.setAudioguideVerbosity(agSegmentationFile, agDefaultsFile , false)
     magf.makeAgOptionFileIfNeeded(AG_path)
    --reaper.ShowMessageBox( 'ag','Success', 0)
     is_AudioGuide_folder_set = true
  end

  if magf.validatePython3Path(python) then
    --if magf.ensureNumpy(python) then
     is_python3_set = true
    --end
  end

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
  reaper.ImGui_SetNextWindowSize(ctx, CURRENT_WINDOW_WIDTH, CURRENT_WINDOW_HEIGHT)
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


function preferencesWindow()


  if reaper.ImGui_Button(ctx, 'Set Environment Path') then
    local retval, folder = reaper.JS_Dialog_BrowseForFolder('', "/Applications")
    if retval then
      if magf.setEnvironmentPath(folder, mtt_audioguide_paths) then

        if magf.setAudioGuidePath(folder .. '/' .. magf.findFolderName(folder, 'audioguide'), mtt_audioguide_paths) == true then
          reaper.ShowMessageBox('AudioGuide localized.','Success',  0)
          is_AudioGuide_folder_set = true
        else
          reaper.ShowMessageBox('Please choose a valid AudioGuide folder', 'Error', 0)
          is_AudioGuide_folder_set = false
          return
        end
        if magf.setPython3Path(folder .. '/' .. magf.findFolderName(folder, 'AG_P3Env_') .. '/bin/python3.12' , mtt_audioguide_paths) then
          reaper.ShowMessageBox('Python localized.','Success', 0)
          is_python3_set = true
        else
         reaper.ShowMessageBox('Please choose a valid Python3 environment', 'Error', 0)
         is_python3_set = false
         return
        end

        magf.refreshGlobalPaths(mtt_audioguide_paths)

      else
        reaper.ShowMessageBox('Please choose a valid Environment or Set AudioGuide and Python3 separately', 'Error', 0)
        return
      end
    end
  end

  if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
    reaper.ImGui_SetTooltip(ctx, magtooltips.PREF_SET_ENV_PATH)
    if reaper.ImGui_BeginTooltip(ctx) then
      reaper.ImGui_EndTooltip(ctx)
    end
  end

  reaper.ImGui_NewLine(ctx)

  if reaper.ImGui_Button(ctx, 'Download Environment') then
    os.execute("open " .. 'https://github.com/MattiaPersico/MTT/raw/main/Environment%20Installer/ReAG_Environment_Installer.pkg?download=')
  end

  if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
    reaper.ImGui_SetTooltip(ctx, magtooltips.PREF_DOWNLOAD_ENV)
    if reaper.ImGui_BeginTooltip(ctx) then
      reaper.ImGui_EndTooltip(ctx)
    end
  end

  reaper.ImGui_NewLine(ctx)
  
  if reaper.ImGui_Button(ctx, 'Override AudioGuide Path') then
    local retval, folder = reaper.JS_Dialog_BrowseForFolder('', os.getenv("HOME") .. "/Documents")
    
    if retval then
      if magf.setAudioGuidePath(folder, mtt_audioguide_paths) == true then
        reaper.ShowMessageBox('AudioGuide has been successfully localized.','Success',  0)
        is_AudioGuide_folder_set = true
      else
        reaper.ShowMessageBox('Please choose a valid AudioGuide folder', 'Error', 0)
        is_AudioGuide_folder_set = false 
      end
    end
  end
  
  if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
    reaper.ImGui_SetTooltip(ctx, magtooltips.PREF_OVERRIDE_AG_PATH)
    if reaper.ImGui_BeginTooltip(ctx) then
      reaper.ImGui_EndTooltip(ctx)
    end
  end

  if reaper.ImGui_Button(ctx, 'Override Python Path') then
    local retval, file = reaper.JS_Dialog_BrowseForOpenFiles('Select Python File', '/usr/local/bin', 'python3', '', false)
    if retval then
      if magf.setPython3Path(file, mtt_audioguide_paths) then
         reaper.ShowMessageBox( mgf.removePath(file),'Success', 0)
         is_python3_set = true
      else
        reaper.ShowMessageBox('Please choose a valid Python3 distribution', 'Error', 0)
        is_python3_set = false
      end
    end
  end

  if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
    reaper.ImGui_SetTooltip(ctx, magtooltips.PREF_OVERRIDE_PYTHON_PATH)
    if reaper.ImGui_BeginTooltip(ctx) then
      reaper.ImGui_EndTooltip(ctx)
    end
  end
end


function spassWindow()

  for i = 1, #search_mode_list do

    search_mode_list[i] = search_mode_list[i] or 0
    search_mode_list_percentage[i] = search_mode_list_percentage[i] or 50

    reaper.ImGui_SetNextItemWidth(ctx, 150)
    local retvalSearchMode, selectedSearchMode = reaper.ImGui_Combo(ctx, '##combo' .. tostring(i), search_mode_list[i], SPASS_STRING_LIST, 10)
    
    if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
      reaper.ImGui_SetTooltip(ctx, magtooltips.SPASS_MODE)
      if reaper.ImGui_BeginTooltip(ctx) then
        reaper.ImGui_EndTooltip(ctx)
      end
    end

    if selectedSearchMode == 1 or selectedSearchMode == 3 then 
      reaper.ImGui_SameLine(ctx);
      reaper.ImGui_SetNextItemWidth(ctx, 40)
      local retvalDrag, search_mode_list_percentage_value = reaper.ImGui_DragInt(ctx, '##DragInt' .. tostring(i), search_mode_list_percentage[i], 0.3, 1, 100, "%d%%")
      
      if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
        reaper.ImGui_SetTooltip(ctx, magtooltips.SPASS_PERCENTAGE)
        if reaper.ImGui_BeginTooltip(ctx) then
          reaper.ImGui_EndTooltip(ctx)
        end
      end

      if retvalDrag then
        search_mode_list_percentage[i] = search_mode_list_percentage_value
      end
    end
  
    if retvalSearchMode then
        search_mode_list[i] = selectedSearchMode
    end
      
    if #descriptors_matrix > 0 and descriptors_matrix[i] then
      for c = 1, #descriptors_matrix[i] do
        reaper.ImGui_SameLine(ctx);
        reaper.ImGui_SetNextItemWidth(ctx, 123)
        local retvalDesMatrix, selectedDescriptor = reaper.ImGui_Combo(ctx, '##comboD' .. tostring(i) .. tostring(c), descriptors_matrix[i][c], DESCRIPTORS_STRING_LIST, 10)
        
        if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
          reaper.ImGui_SetTooltip(ctx, magtooltips.DESCRIPTOR)
          if reaper.ImGui_BeginTooltip(ctx) then
            reaper.ImGui_EndTooltip(ctx)
          end
        end

        if retvalDesMatrix then
           descriptors_matrix[i][c] = selectedDescriptor
        end
      end
    end

    reaper.ImGui_SameLine(ctx);
    if reaper.ImGui_Button(ctx, '+##AddDescriptor'..tostring(i)..tostring(c)) then
      if not descriptors_matrix[i] then
        descriptors_matrix[i] = {0}
      else
        table.insert(descriptors_matrix[i], 0)
      end
    end

    if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
      reaper.ImGui_SetTooltip(ctx, magtooltips.ADD_DESCRIPTOR)
      if reaper.ImGui_BeginTooltip(ctx) then
        reaper.ImGui_EndTooltip(ctx)
      end
    end
    
    reaper.ImGui_SameLine(ctx);
    if reaper.ImGui_Button(ctx, '-##RemoveDescriptor'..tostring(i)..tostring(c)) then
      if descriptors_matrix[i] and #descriptors_matrix[i] > 1 then
        table.remove(descriptors_matrix[i], #descriptors_matrix[i])
      end
    end

    if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
      reaper.ImGui_SetTooltip(ctx, magtooltips.REMOVE_DESCRIPTOR)
      if reaper.ImGui_BeginTooltip(ctx) then
        reaper.ImGui_EndTooltip(ctx)
      end
    end

  end

  if reaper.ImGui_Button(ctx, '+##AddSpassObj' ..tostring(i)) then
    number_of_spass_objects = number_of_spass_objects + 1
    table.insert(search_mode_list, 0)
    descriptors_matrix[#descriptors_matrix + 1] = descriptors_matrix[#descriptors_matrix + 1] or {}
    descriptors_matrix[#descriptors_matrix][1] = descriptors_matrix[#descriptors_matrix][1] or 0
  end

  if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
    reaper.ImGui_SetTooltip(ctx, magtooltips.ADD_SPASS)
    if reaper.ImGui_BeginTooltip(ctx) then
      reaper.ImGui_EndTooltip(ctx)
    end
  end

  reaper.ImGui_SameLine(ctx);
  if reaper.ImGui_Button(ctx, '-##RemoveSpassObj' ..tostring(i)) and #search_mode_list > 1 then
    table.remove(search_mode_list, #search_mode_list)
  end

  if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
    reaper.ImGui_SetTooltip(ctx, magtooltips.REMOVE_SPASS)
    if reaper.ImGui_BeginTooltip(ctx) then
      reaper.ImGui_EndTooltip(ctx)
    end
  end

end


function GUI_MatchTargetButton()
  if not is_corpus_ready or CONCATENATION_IN_PROGRESS or SEGMENTATION_IN_PROGRESS then
    reaper.ImGui_BeginDisabled(ctx, true)
  else
    reaper.ImGui_BeginDisabled(ctx, false)
  end

  if reaper.ImGui_Button(ctx, 'Match Target') then
    onMatchTargetPressed()
  end

  reaper.ImGui_EndDisabled(ctx)

  if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
    reaper.ImGui_SetTooltip(ctx, magtooltips.MATCH_TARGET_BUTTON)
    if reaper.ImGui_BeginTooltip(ctx) then
      reaper.ImGui_EndTooltip(ctx)
    end
  end

end


function GUI_BuildCorpusButton()

  if CONCATENATION_IN_PROGRESS or SEGMENTATION_IN_PROGRESS then
    reaper.ImGui_BeginDisabled(ctx, true)
  else
    reaper.ImGui_BeginDisabled(ctx, false)
  end

  if reaper.ImGui_Button(ctx, 'Build Corpus') then
    onLoadCorpusPressed()
  end

  reaper.ImGui_EndDisabled(ctx)

  if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
    reaper.ImGui_SetTooltip(ctx, magtooltips.BUILD_CORPUS_BUTTON)
    if reaper.ImGui_BeginTooltip(ctx) then
      reaper.ImGui_EndTooltip(ctx)
    end
  end

end


function GUI_MinimizeButton()
  local spazioSinistra = reaper.ImGui_GetWindowWidth(ctx) - 89 - 72;
  reaper.ImGui_SetCursorPosX(ctx, spazioSinistra);

  local minimized_button_name = 'Minimize'

  if MINIMIZED then minimized_button_name = 'Maximize' else minimized_button_name = 'Minimize' end

  if reaper.ImGui_Button(ctx, minimized_button_name) then
    if MINIMIZED then
      CURRENT_WINDOW_HEIGHT = MAIN_WINDOW_HEIGHT
      MINIMIZED = false
    else
      CURRENT_WINDOW_HEIGHT = MINI_MAIN_WINDOW_HEIGHT
      MINIMIZED = true
    end
  end

  if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
    reaper.ImGui_SetTooltip(ctx, magtooltips.MINMAXIMIZE)
    if reaper.ImGui_BeginTooltip(ctx) then
      reaper.ImGui_EndTooltip(ctx)
    end
  end

end


function GUI_PreferencesButton()
  local spazioSinistra = reaper.ImGui_GetWindowWidth(ctx) - 89;
  reaper.ImGui_SetCursorPosX(ctx, spazioSinistra);

  if reaper.ImGui_Button(ctx, 'Preferences') then
    preferencesWindowState = not preferencesWindowState
  end

  if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
    reaper.ImGui_SetTooltip(ctx, magtooltips.PREFERENCES)
    if reaper.ImGui_BeginTooltip(ctx) then
      reaper.ImGui_EndTooltip(ctx)
    end
  end
end


function GUI_TargetSoundFilesParameters()
  reaper.ImGui_PopFont(ctx)
  reaper.ImGui_PushFont(ctx, comic_sans_smaller)
  reaper.ImGui_NewLine(ctx)
  reaper.ImGui_PopFont(ctx)
  reaper.ImGui_PushFont(ctx, comic_sans)


retval, tsf_threshold = reaper.ImGui_SliderInt(ctx,'tsf_threshold',tsf_threshold,-80,-3)

if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
  reaper.ImGui_SetTooltip(ctx, magtooltips.TSF_THRESHOLD)
  if reaper.ImGui_BeginTooltip(ctx) then
    reaper.ImGui_EndTooltip(ctx)
  end
end

retval, tsf_offset_rise = reaper.ImGui_SliderDouble(ctx,'tsf_offset_rise',tsf_offset_rise,1.0,2.0)

if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
  reaper.ImGui_SetTooltip(ctx, magtooltips.TSF_OFFSET_RISE)
  if reaper.ImGui_BeginTooltip(ctx) then
    reaper.ImGui_EndTooltip(ctx)
  end
end

retval, tsf_min_seg_len = reaper.ImGui_SliderDouble(ctx,'tsf_min_seg_len',tsf_min_seg_len,0.05,5)
if tsf_max_seg_len <= tsf_min_seg_len then tsf_max_seg_len = tsf_min_seg_len + 0.05 end

if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
  reaper.ImGui_SetTooltip(ctx, magtooltips.TSF_MIN_SEG_LEN)
  if reaper.ImGui_BeginTooltip(ctx) then
    reaper.ImGui_EndTooltip(ctx)
  end
end

retval, tsf_max_seg_len = reaper.ImGui_SliderDouble(ctx,'tsf_max_seg_len',tsf_max_seg_len,0.1,5.05)
if tsf_min_seg_len >= tsf_max_seg_len then tsf_min_seg_len = tsf_max_seg_len - 0.05 end

if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
  reaper.ImGui_SetTooltip(ctx, magtooltips.TSF_MAX_SEG_LEN)
  if reaper.ImGui_BeginTooltip(ctx) then
    reaper.ImGui_EndTooltip(ctx)
  end
end

return 120
end


function GUI_SegmentationArguments()
  reaper.ImGui_PopFont(ctx)
  reaper.ImGui_PushFont(ctx, comic_sans_smaller)
  reaper.ImGui_NewLine(ctx)
  reaper.ImGui_PopFont(ctx)
  reaper.ImGui_PushFont(ctx, comic_sans)

  retval, seg_threshold = reaper.ImGui_SliderInt(ctx,'seg_threshold',seg_threshold,-80,-3)

  if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
    reaper.ImGui_SetTooltip(ctx, magtooltips.SEG_THRESHOLD)
    if reaper.ImGui_BeginTooltip(ctx) then
      reaper.ImGui_EndTooltip(ctx)
    end
  end

  retval, seg_offset_rise = reaper.ImGui_SliderDouble(ctx,'seg_offset_rise',seg_offset_rise,1.0,2.0)

  if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
    reaper.ImGui_SetTooltip(ctx, magtooltips.SEG_OFFSET_RISE)
    if reaper.ImGui_BeginTooltip(ctx) then
      reaper.ImGui_EndTooltip(ctx)
    end
  end

  retval, seg_multirise = reaper.ImGui_Checkbox(ctx,'seg_multirise', seg_multirise)

  if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
    reaper.ImGui_SetTooltip(ctx, magtooltips.SEG_MULTI_RISE)
    if reaper.ImGui_BeginTooltip(ctx) then
      reaper.ImGui_EndTooltip(ctx)
    end
  end

  return 90
end


function GUI_CorpusParameters()
  reaper.ImGui_PopFont(ctx)
  reaper.ImGui_PushFont(ctx, comic_sans_smaller)
  reaper.ImGui_NewLine(ctx)
  reaper.ImGui_PopFont(ctx)
  reaper.ImGui_PushFont(ctx, comic_sans)


retval, cga_restrict_overlaps = reaper.ImGui_SliderInt(ctx,'cga_restrict_overlaps',cga_restrict_overlaps, 1, 100)

if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
  reaper.ImGui_SetTooltip(ctx, magtooltips.CGA_RESTRICT_OVERLAPS)
  if reaper.ImGui_BeginTooltip(ctx) then
    reaper.ImGui_EndTooltip(ctx)
  end
end

retval, cga_onset_len = reaper.ImGui_SliderInt(ctx,'cga_onset_len',cga_onset_len, 1, 100)

if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
  reaper.ImGui_SetTooltip(ctx, magtooltips.CGA_ONSET_LEN)
  if reaper.ImGui_BeginTooltip(ctx) then
    reaper.ImGui_EndTooltip(ctx)
  end
end

retval, cga_offset_len = reaper.ImGui_SliderInt(ctx,'cga_offset_len',cga_offset_len, 1, 100)

if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
  reaper.ImGui_SetTooltip(ctx, magtooltips.CGA_OFFSET_LEN)
  if reaper.ImGui_BeginTooltip(ctx) then
    reaper.ImGui_EndTooltip(ctx)
  end
end

retval, cga_limit_dur = reaper.ImGui_SliderDouble(ctx,'cga_limit_dur',cga_limit_dur,0.0,5.0)

if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
  reaper.ImGui_SetTooltip(ctx, magtooltips.CGA_LIMIT_DUR)
  if reaper.ImGui_BeginTooltip(ctx) then
    reaper.ImGui_EndTooltip(ctx)
  end
end


reaper.ImGui_PopFont(ctx)
reaper.ImGui_PushFont(ctx, comic_sans_smaller)
reaper.ImGui_NewLine(ctx)
reaper.ImGui_NewLine(ctx)
reaper.ImGui_PopFont(ctx)
reaper.ImGui_PushFont(ctx, comic_sans)

retval, cga_allow_repetition = reaper.ImGui_Checkbox(ctx,'cga_allow_repetition', cga_allow_repetition)

if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
  reaper.ImGui_SetTooltip(ctx, magtooltips.CGA_ALLOW_REPETITION)
  if reaper.ImGui_BeginTooltip(ctx) then
    reaper.ImGui_EndTooltip(ctx)
  end
end

if cga_allow_repetition == false then
  reaper.ImGui_BeginDisabled(ctx, true)
  retval, cga_restrict_repetition = reaper.ImGui_SliderDouble(ctx,'cga_restrict_repetition',cga_restrict_repetition, 0.0, 5.0)
  reaper.ImGui_EndDisabled(ctx)

else
  retval, cga_restrict_repetition = reaper.ImGui_SliderDouble(ctx,'cga_restrict_repetition',cga_restrict_repetition, 0.0, 5.0)
end

if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
  reaper.ImGui_SetTooltip(ctx, magtooltips.CGA_RESTRICT_REPETITION)
  if reaper.ImGui_BeginTooltip(ctx) then
    reaper.ImGui_EndTooltip(ctx)
  end
end

reaper.ImGui_PopFont(ctx)
reaper.ImGui_PushFont(ctx, comic_sans_smaller)
reaper.ImGui_NewLine(ctx)
reaper.ImGui_NewLine(ctx)
reaper.ImGui_PopFont(ctx)
reaper.ImGui_PushFont(ctx, comic_sans)

retval, cga_clip_duration_to_target = reaper.ImGui_Checkbox(ctx,'cga_clip_duration_to_target', cga_clip_duration_to_target)

if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
  reaper.ImGui_SetTooltip(ctx, magtooltips.CGA_CLIP_DUR_TO_TARGET)
  if reaper.ImGui_BeginTooltip(ctx) then
    reaper.ImGui_EndTooltip(ctx)
  end
end

retval, outputevent_align_peaks = reaper.ImGui_Checkbox(ctx,'align_peaks', outputevent_align_peaks)

if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
  reaper.ImGui_SetTooltip(ctx, magtooltips.ALIGN_PEAKS)
  if reaper.ImGui_BeginTooltip(ctx) then
    reaper.ImGui_EndTooltip(ctx)
  end
end

return 253

end


function GUI_SuperimposeParameters()
  reaper.ImGui_PopFont(ctx)
      reaper.ImGui_PushFont(ctx, comic_sans_smaller)
      reaper.ImGui_NewLine(ctx)
      reaper.ImGui_PopFont(ctx)
      reaper.ImGui_PushFont(ctx, comic_sans)
  
      si_min_segment_enabled_retval, si_min_segment_enabled = reaper.ImGui_Checkbox(ctx,'##si_min_segment_enabled', si_min_segment_enabled)

      if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
        reaper.ImGui_SetTooltip(ctx, magtooltips.SI_ENABLE_MIN_SEG)
        if reaper.ImGui_BeginTooltip(ctx) then
          reaper.ImGui_EndTooltip(ctx)
        end
      end

      reaper.ImGui_SameLine(ctx);
      reaper.ImGui_BeginDisabled(ctx, not si_min_segment_enabled)
      retval, si_min_segment = reaper.ImGui_SliderInt(ctx,'si_min_segment',si_min_segment, 0, 100)
      reaper.ImGui_EndDisabled(ctx)

      if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
        reaper.ImGui_SetTooltip(ctx, magtooltips.SI_MIN_SEG)
        if reaper.ImGui_BeginTooltip(ctx) then
          reaper.ImGui_EndTooltip(ctx)
        end
      end


      if si_min_segment_enabled_retval and si_min_segment_enabled then 
        if si_max_segment < si_min_segment then si_min_segment = si_max_segment end
      end

      if retval and si_min_segment_enabled and si_max_segment_enabled then
        if si_min_segment > si_max_segment then si_max_segment = si_min_segment end
      end

      si_max_segment_enabled_retval, si_max_segment_enabled = reaper.ImGui_Checkbox(ctx,'##si_max_segment_enabled', si_max_segment_enabled)

      if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
        reaper.ImGui_SetTooltip(ctx, magtooltips.SI_ENABLE_MAX_SEG)
        if reaper.ImGui_BeginTooltip(ctx) then
          reaper.ImGui_EndTooltip(ctx)
        end
      end

      reaper.ImGui_SameLine(ctx);
      reaper.ImGui_BeginDisabled(ctx, not si_max_segment_enabled)
      retval, si_max_segment = reaper.ImGui_SliderInt(ctx,'si_max_segment',si_max_segment, 1, 100)
      reaper.ImGui_EndDisabled(ctx)

      if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
        reaper.ImGui_SetTooltip(ctx, magtooltips.SI_MAX_SEG)
        if reaper.ImGui_BeginTooltip(ctx) then
          reaper.ImGui_EndTooltip(ctx)
        end
      end

      if si_max_segment_enabled_retval and si_max_segment_enabled then 
        if si_min_segment > si_max_segment then si_max_segment = si_min_segment end
      end

      if retval and si_min_segment_enabled and si_max_segment_enabled then
        if si_max_segment < si_min_segment then si_min_segment = si_max_segment end
      end

      if si_min_segment_enabled and si_max_segment_enabled then
          if si_max_segment > 100 then si_max_segment = 100 end
          if si_min_segment < 0 then si_min_segment = 0 end
      end
      

      si_min_frame_enabled_retval, si_min_frame_enabled = reaper.ImGui_Checkbox(ctx,'##si_min_frame_enabled', si_min_frame_enabled)

      if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
        reaper.ImGui_SetTooltip(ctx, magtooltips.SI_ENABLE_MIN_FRAME)
        if reaper.ImGui_BeginTooltip(ctx) then
          reaper.ImGui_EndTooltip(ctx)
        end
      end

      reaper.ImGui_SameLine(ctx);
      reaper.ImGui_BeginDisabled(ctx, not si_min_frame_enabled)
      retval, si_min_frame = reaper.ImGui_SliderInt(ctx,'si_min_frame',si_min_frame, 0, 100)
      reaper.ImGui_EndDisabled(ctx)

      if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
        reaper.ImGui_SetTooltip(ctx, magtooltips.SI_MIN_FRAME)
        if reaper.ImGui_BeginTooltip(ctx) then
          reaper.ImGui_EndTooltip(ctx)
        end
      end

      if si_min_frame_enabled_retval and si_min_frame_enabled then 
        if si_max_frame < si_min_frame then si_min_frame = si_max_frame end
      end

      if retval and si_min_frame_enabled and si_max_frame_enabled then
        if si_min_frame > si_max_frame then si_max_frame = si_min_frame end
      end

      si_max_frame_enabled_retval, si_max_frame_enabled = reaper.ImGui_Checkbox(ctx,'##si_max_frame_enabled', si_max_frame_enabled)

      if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
        reaper.ImGui_SetTooltip(ctx, magtooltips.SI_ENABLE_MAX_FRAME)
        if reaper.ImGui_BeginTooltip(ctx) then
          reaper.ImGui_EndTooltip(ctx)
        end
      end

      reaper.ImGui_SameLine(ctx);
      reaper.ImGui_BeginDisabled(ctx, not si_max_frame_enabled)
      retval, si_max_frame = reaper.ImGui_SliderInt(ctx,'si_max_frame',si_max_frame, 1, 100)
      reaper.ImGui_EndDisabled(ctx)

      if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
        reaper.ImGui_SetTooltip(ctx, magtooltips.SI_MAX_FRAME)
        if reaper.ImGui_BeginTooltip(ctx) then
          reaper.ImGui_EndTooltip(ctx)
        end
      end

      if si_max_frame_enabled_retval and si_max_frame_enabled then 
        if si_min_frame > si_max_frame then si_max_frame = si_min_frame end
      end

      if retval and si_min_frame_enabled and si_max_frame_enabled then
        if si_max_frame < si_min_frame then si_min_frame = si_max_frame end
      end

      if si_min_frame_enabled and si_max_frame_enabled then
          if si_max_frame > 100 then si_max_frame = 100 end
          if si_min_frame < 0 then si_min_frame = 0 end
      end

      si_min_overlap_enabled_retval, si_min_overlap_enabled = reaper.ImGui_Checkbox(ctx,'##si_min_overlap_enabled', si_min_overlap_enabled)

      if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
        reaper.ImGui_SetTooltip(ctx, magtooltips.SI_ENABLE_MIN_OVERLAP)
        if reaper.ImGui_BeginTooltip(ctx) then
          reaper.ImGui_EndTooltip(ctx)
        end
      end

      reaper.ImGui_SameLine(ctx);
      reaper.ImGui_BeginDisabled(ctx, not si_min_overlap_enabled)
      retval, si_min_overlap = reaper.ImGui_SliderInt(ctx,'si_min_overlap',si_min_overlap, 0, 100)
      reaper.ImGui_EndDisabled(ctx)

      if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
        reaper.ImGui_SetTooltip(ctx, magtooltips.SI_MIN_OVERLAP)
        if reaper.ImGui_BeginTooltip(ctx) then
          reaper.ImGui_EndTooltip(ctx)
        end
      end

      if si_min_overlap_enabled_retval and si_min_overlap_enabled then 
        if si_max_overlap < si_min_overlap then si_min_overlap = si_max_overlap end
      end

      if retval and si_min_overlap_enabled and si_max_overlap_enabled then
        if si_min_overlap > si_max_overlap then si_max_overlap = si_min_overlap end
      end

      si_max_overlap_enabled_retval, si_max_overlap_enabled = reaper.ImGui_Checkbox(ctx,'##si_max_overlap_enabled', si_max_overlap_enabled)

      if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
        reaper.ImGui_SetTooltip(ctx, magtooltips.SI_ENABLE_MAX_OVERLAP)
        if reaper.ImGui_BeginTooltip(ctx) then
          reaper.ImGui_EndTooltip(ctx)
        end
      end

      reaper.ImGui_SameLine(ctx);
      reaper.ImGui_BeginDisabled(ctx, not si_max_overlap_enabled)
      retval, si_max_overlap = reaper.ImGui_SliderInt(ctx,'si_max_overlap',si_max_overlap, 0, 100)
      reaper.ImGui_EndDisabled(ctx)

      if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
        reaper.ImGui_SetTooltip(ctx, magtooltips.SI_MAX_OVERLAP)
        if reaper.ImGui_BeginTooltip(ctx) then
          reaper.ImGui_EndTooltip(ctx)
        end
      end

      if si_max_overlap_enabled_retval and si_max_overlap_enabled then 
        if si_min_overlap > si_max_overlap then si_max_overlap = si_min_overlap end
      end

      if retval and si_min_overlap_enabled and si_max_overlap_enabled then
        if si_max_overlap < si_min_overlap then si_min_overlap = si_max_overlap end
      end

      if si_min_overlap_enabled and si_max_overlap_enabled then
          if si_max_overlap > 100 then si_max_overlap = 100 end
          if si_min_overlap < 0 then si_min_overlap = 0 end
      end

      return 178
end


function GUI_SearchPasses()
  reaper.ImGui_PopFont(ctx)
  reaper.ImGui_PushFont(ctx, comic_sans_smaller)
  reaper.ImGui_NewLine(ctx)
  reaper.ImGui_PopFont(ctx)
  reaper.ImGui_PushFont(ctx, comic_sans)
  reaper.ImGui_SetCursorPosX(ctx, 3);
  if reaper.ImGui_BeginChild(ctx, 'Spass Window', MAIN_WINDOW_WIDTH - 30, SPASS_WINDOW_HEIGHT, true, reaper.ImGui_WindowFlags_HorizontalScrollbar()) then

    spassWindow()
    reaper.ImGui_EndChild(ctx)
  end

  return 149

end


function GUI_ParameterSeparatorMacro()
  reaper.ImGui_PopFont(ctx)
  reaper.ImGui_PushFont(ctx, comic_sans_smaller)
  reaper.ImGui_NewLine(ctx)
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_NewLine(ctx)
  reaper.ImGui_NewLine(ctx)
  reaper.ImGui_PopFont(ctx)
  reaper.ImGui_PushFont(ctx, comic_sans_bigger)
  reaper.ImGui_SetCursorPosX(ctx, 0);
end


function mainWindow()

  local window_height_increment = 0

  reaper.ImGui_PushFont(ctx, comic_sans)

  reaper.ImGui_SetCursorPosX(ctx, 8)

  GUI_MatchTargetButton()

  reaper.ImGui_SameLine(ctx)

  GUI_BuildCorpusButton()

  reaper.ImGui_SameLine(ctx);
  reaper.ImGui_Text(ctx, 'Corpus Segments: ' .. tostring(number_of_segments))

  reaper.ImGui_SameLine(ctx);
  if CONCATENATION_IN_PROGRESS or SEGMENTATION_IN_PROGRESS then
    drawSpinner(reaper.ImGui_GetCursorPosX(ctx) + 10 , reaper.ImGui_GetCursorPosY(ctx) + 4)
  end

  reaper.ImGui_SameLine(ctx);
  
  GUI_MinimizeButton()

  reaper.ImGui_SameLine(ctx);

  GUI_PreferencesButton()
  
  if MINIMIZED == false then

    reaper.ImGui_PushFont(ctx, comic_sans_smaller)
    reaper.ImGui_NewLine(ctx)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Separator(), reaper.ImGui_ColorConvertDouble4ToU32(0.7, 0.7, 0.7, 2))
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_PopStyleColor(ctx)
    reaper.ImGui_PopFont(ctx)

    if reaper.ImGui_BeginChild(ctx, '##ParametersInvisibleWindow', CURRENT_WINDOW_WIDTH - 12, CURRENT_WINDOW_HEIGHT - 90, false) then

      reaper.ImGui_PushFont(ctx, comic_sans_smaller)
      reaper.ImGui_NewLine(ctx)
      reaper.ImGui_NewLine(ctx)
      reaper.ImGui_NewLine(ctx)
      reaper.ImGui_PopFont(ctx)
      reaper.ImGui_PushFont(ctx, comic_sans_bigger)
      reaper.ImGui_SameLine(ctx);
      reaper.ImGui_SetCursorPosX(ctx, 0);
      
      if reaper.ImGui_CollapsingHeader(ctx, 'Target Sound File Parameters', false) then

        if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
          reaper.ImGui_SetTooltip(ctx, magtooltips.TARGET_SF_PARAMS_HEADER)
          if reaper.ImGui_BeginTooltip(ctx) then
            reaper.ImGui_EndTooltip(ctx)
          end
        end

          window_height_increment = window_height_increment + GUI_TargetSoundFilesParameters()
      else
        if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
          reaper.ImGui_SetTooltip(ctx, magtooltips.TARGET_SF_PARAMS_HEADER)
          if reaper.ImGui_BeginTooltip(ctx) then
            reaper.ImGui_EndTooltip(ctx)
          end
        end
      end

      GUI_ParameterSeparatorMacro()
    
      if reaper.ImGui_CollapsingHeader(ctx, 'Segmentation Arguments') then

        if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
          reaper.ImGui_SetTooltip(ctx, magtooltips.SEG_ARG_HEADER)
          if reaper.ImGui_BeginTooltip(ctx) then
            reaper.ImGui_EndTooltip(ctx)
          end
        end

         window_height_increment = window_height_increment + GUI_SegmentationArguments()
      else
        if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
          reaper.ImGui_SetTooltip(ctx, magtooltips.SEG_ARG_HEADER)
          if reaper.ImGui_BeginTooltip(ctx) then
            reaper.ImGui_EndTooltip(ctx)
          end
        end
      end

      GUI_ParameterSeparatorMacro()

      if reaper.ImGui_CollapsingHeader(ctx, 'Corpus Parameters') then

        if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
          reaper.ImGui_SetTooltip(ctx, magtooltips.CORPUS_PARAMS_HEADER)
          if reaper.ImGui_BeginTooltip(ctx) then
            reaper.ImGui_EndTooltip(ctx)
          end
        end

        window_height_increment = window_height_increment + GUI_CorpusParameters()
      else
        if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
          reaper.ImGui_SetTooltip(ctx, magtooltips.CORPUS_PARAMS_HEADER)
          if reaper.ImGui_BeginTooltip(ctx) then
            reaper.ImGui_EndTooltip(ctx)
          end
        end
      end

      GUI_ParameterSeparatorMacro()

      if reaper.ImGui_CollapsingHeader(ctx, 'Superimpose Parameters') then

        if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
          reaper.ImGui_SetTooltip(ctx, magtooltips.SUPERIMPOSE_PARAMS_HEADER)
          if reaper.ImGui_BeginTooltip(ctx) then
            reaper.ImGui_EndTooltip(ctx)
          end
        end

        window_height_increment = window_height_increment + GUI_SuperimposeParameters()
      else
        if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
          reaper.ImGui_SetTooltip(ctx, magtooltips.SUPERIMPOSE_PARAMS_HEADER)
          if reaper.ImGui_BeginTooltip(ctx) then
            reaper.ImGui_EndTooltip(ctx)
          end
        end
      end

      GUI_ParameterSeparatorMacro()

    if reaper.ImGui_CollapsingHeader(ctx, 'Search Passes') then

      if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
        reaper.ImGui_SetTooltip(ctx, magtooltips.SEARCH_PASS_HEADER)
        if reaper.ImGui_BeginTooltip(ctx) then
          reaper.ImGui_EndTooltip(ctx)
        end
      end

      window_height_increment = window_height_increment + GUI_SearchPasses()
    else
      if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled() |  reaper.ImGui_HoveredFlags_DelayNormal() | reaper.ImGui_HoveredFlags_NoSharedDelay())then
        reaper.ImGui_SetTooltip(ctx, magtooltips.SEARCH_PASS_HEADER)
        if reaper.ImGui_BeginTooltip(ctx) then
          reaper.ImGui_EndTooltip(ctx)
        end
      end
    end
      
      if MAIN_WINDOW_HEIGHT + window_height_increment > MAIN_WINDOW_MAX_HEIGHT then
        CURRENT_WINDOW_HEIGHT = MAIN_WINDOW_MAX_HEIGHT
      else
        CURRENT_WINDOW_HEIGHT = MAIN_WINDOW_HEIGHT + window_height_increment
      end
      reaper.ImGui_PopFont(ctx)
      reaper.ImGui_EndChild(ctx)
    end
  end
    reaper.ImGui_PopFont(ctx)
end


function onExit()
  if #CORPUS_ITEMS > 0 then
    magf.clearArtifacts(CORPUS_AFs)
  end
end


initReAG()
reaper.defer(loop)
reaper.atexit(onExit)