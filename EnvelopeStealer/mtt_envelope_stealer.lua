-- Envelope Stealer
-- Author: Mattia Persico (MTT)

-- This script is is based on "mpl_Peak follower tools.lua" and uses parts of its code

--[[ APPUNTI

- aggiungi hint di quanto sta sforando oltre il bordo accanto a 24db
- rinomina window with tipo definition o simili
- aggiungere istruzioni

 APPUNTI ]]
local major_version = 0
local minor_version = 6

local name = "Envelope Stealer " .. tostring(major_version) .. "." .. tostring(minor_version)

dofile(reaper.GetResourcePath() .. "/Scripts/ReaTeam Extensions/API/imgui.lua")("0.10")
local ctx = reaper.ImGui_CreateContext(name)

-- Funzione EEL per i Vincoli delle Dimensioni della Finestra
local sizeConstraintsCallback = [=[
1 + 1
]=]

local EEL_DUMMY_FUNCTION = reaper.ImGui_CreateFunctionFromEEL(sizeConstraintsCallback)

local MAIN_WINDOW_WIDTH = 600
local MAIN_WINDOW_HEIGHT = 640

local PLOT_WINDOW_HEIGHT = 160

local comic_sans_size = 13
local comic_sans_small_size = 10
local new_line_font_size = 1

local comic_sans
local comic_sans_small
local new_line_font

local OS = reaper.GetOS()

if OS == "OSX32" or OS == "OSX64" or OS == "macOS-arm64" then
    comic_sans = reaper.ImGui_CreateFont("Comic Sans MS", 18)
    comic_sans_small = reaper.ImGui_CreateFont("Comic Sans MS", 17)
    new_line_font = reaper.ImGui_CreateFont("Comic Sans MS", 2)
else
    comic_sans = reaper.ImGui_CreateFont("C:/Windows/Fonts/comic.ttf", 18)
    comic_sans_small = reaper.ImGui_CreateFont("C:/Windows/Fonts/comic.ttf", 17)
    new_line_font = reaper.ImGui_CreateFont("C:/Windows/Fonts/comic.ttf", 2)
end

reaper.ImGui_Attach(ctx, comic_sans_small)
reaper.ImGui_Attach(ctx, comic_sans)
reaper.ImGui_Attach(ctx, new_line_font)

function SetButtonState(set)
    local _, _, sec, cmd = reaper.get_action_context()
    reaper.SetToggleCommandState(sec, cmd, set or 0)
    reaper.RefreshToolbar2(sec, cmd)
end

-- User Parameters
local window_sec = 0.04 -- analysis window in seconds 0.001 - 0.4
local window_overlap = 2 -- overlap factor, 2 = 50% overlap, 1-16
local auto_update = false
local auto_update_apply = true
local auto_update_impose = false
local scaling_factor = 1 -- envelope scaling factor
local envelope_offset = 0 -- envelope offset
local envelope_top_limit = 90
local envelope_bottom_limit = -150
local attack_ms = 0.01 -- how fast it reacts to increases (ms)
local release_ms = 0.01 -- how fast it reacts to decreases (ms)
local continuous_update = true

-- Private Parameters
local REF_ANALYSIS_DONE, REF_ENV, REF_AI_IDX  -- global vars to store state between stealing and applying
local REF_AUDIO_DATA  -- global var to store audio data between stealing and applying
local REF_ITEM = -1 -- global var to store reference item
local RMS_MEAN = -150
local RMS_MAX = -150
local ENV_RANGE = 24

local TARGET_ANALYSIS_DONE, TARGET_ENV, TARGET_AI_IDX  -- global vars to store state between stealing and applying
local TARGET_AUDIO_DATA  -- global var to store audio data between stealing and applying
local TARGET_ITEM = -1 -- global var to store reference item

local envelope_top_limit_to_plot = envelope_top_limit
local envelope_bottom_limit_to_plot = envelope_bottom_limit
local scaling_factor_to_plot = scaling_factor

local smoothing_enabled = true

local envelope_line_color = reaper.ImGui_ColorConvertDouble4ToU32(1, 0.5, 0, 1)

local drag_operation_started = false

function WDL_DB2VAL(x)
    return math.exp((x) * 0.11512925464970228420089957273422)
end

function WDL_VAL2DB(x) --https://github.com/majek/wdl/blob/master/WDL/db2val.h
    if not x or x < 0.0000000298023223876953125 then
        return -150.0
    end
    local v = math.log(x) * 8.6858896380650365530225783783321
    if v < -150.0 then
        return -150.0
    end
    return v
end

-- Generate a RFC4122 v4 GUID string like {XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX}
function generate_guid()
    -- seed randomness with time + clock for more entropy
    math.randomseed(os.time() + math.floor((os.clock() * 1000000) % 2147483647))
    local b = {}
    for i = 1, 16 do
        b[i] = math.random(0, 255)
    end
    -- set version (4) in byte 7 (1-based index 7)
    b[7] = (b[7] % 16) + 0x40
    -- set variant (10xxxxxx) in byte 9 (1-based index 9)
    b[9] = (b[9] % 64) + 0x80

    return string.format("{%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X}", table.unpack(b))
end

-- Replace the first EGUID {...} occurrence in a chunk with a newly generated GUID
function replace_eguid(chunk)
    if not chunk or type(chunk) ~= "string" then
        return chunk
    end
    local replaced, n =
        chunk:gsub(
        "EGUID%s*%b{}",
        function(s)
            return "EGUID " .. generate_guid()
        end,
        1
    )
    return replaced
end

function Process_InsertData_PF(t, boundary_start, offs, isImpose)
    local output = {}
    -- avoid shadowing the global `window_sec`; calculate the analysis step
    local step = window_sec / window_overlap

    --[[     local max_dB = -math.huge
    for i = 1, #t do
        max_dB = math.max(t[i], max_dB)
    end ]]
    if isImpose == false then
        for i = 1, #t do
            local tpos = (i - 1) * step + boundary_start - offs
            local val =
                math.min(
                math.max((((t[i] + RMS_MEAN) * scaling_factor) - RMS_MEAN), envelope_bottom_limit),
                envelope_top_limit
            ) + envelope_offset
            output[#output + 1] = {tpos = tpos, val = val}
        end
    else
        for i = 1, #t do
            local tpos = (i - 1) * step + boundary_start - offs
            local val =
                math.min(math.max((t[i] * scaling_factor), envelope_bottom_limit), envelope_top_limit) + envelope_offset
            -- Usiamo il valore dB direttamente, senza normalizzazione
            output[#output + 1] = {tpos = tpos, val = val}
        end
    end

    return output
end

function remapCurve(x, k)
    -- clamp per sicurezza
    if x < 0 then
        x = 0
    end
    if x > 1 then
        x = 1
    end
    return x ^ k
end

function remapCurveInv(x, k)
    if x < 0 then
        x = 0
    end
    if x > 1 then
        x = 1
    end
    return 1 - (1 - x) ^ k
end

function map_db_to_pixels(db_value, window_height)
    -- Assicuriamoci che il valore sia nel range dynamic: envelope_bottom_limit .. ENV_RANGE
    local top = ENV_RANGE or 0
    local bottom = -150
    db_value = math.max(bottom, math.min(top, db_value))

    -- Calcoliamo la percentuale nel range totale (bottom .. top)
    local range = top - bottom
    if range == 0 then
        return window_height * 0.5 -- fallback to center if no range
    end
    local percent = (db_value - bottom) / range

    percent = remapCurve(percent, 2.7)

    return window_height * (1 - percent)
end

function Process_GetBoundary(item)
    local i_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local i_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local boundary_start = i_pos
    local boundary_end = i_pos + i_len
    return true, boundary_start, boundary_end, i_pos
end

function Process_GetAudioData(item, clear_envelope)
    -- init
    if not (item and window_sec) then
        return
    end
    local take = reaper.GetActiveTake(item)
    if reaper.TakeIsMIDI(take) then
        return
    end

    -- clear existing take env pts
    local env = reaper.GetTakeEnvelopeByName(take, "Volume")
    if env and clear_envelope then
        reaper.DeleteEnvelopePointRange(env, 0, math.huge)
        reaper.Envelope_SortPoints(env)
    end

    local track = reaper.GetMediaItem_Track(item)
    local accessor = reaper.CreateTrackAudioAccessor(track)
    local id = 0
    local SR_spls = tonumber(reaper.format_timestr_pos(1 - reaper.GetProjectTimeOffset(0, false), "", 4)) -- get sample rate obey project start offset
    local bufsz = math.ceil(window_sec * SR_spls)
    local data = {}
    -- allocate a single buffer and reuse it across iterations to avoid repeated allocations
    local samplebuffer = reaper.new_array(bufsz)

    local ret, boundary_start, boundary_end = Process_GetBoundary(item)
    if not ret then
        return
    end

    -- peak follower in RMS mode with optional attack/release smoothing
    local rms_sum = 0
    local max_rms = -150
    local count = 0

    -- previous smoothed linear value (start very small)
    local prev_smoothed_linear = 1e-9

    -- convert attack/release from ms to per-sample smoothing coefficients
    local function coef_from_time_ms(t_ms)
        if t_ms <= 0 then
            return 0
        end
        -- time constant in seconds
        local tau = t_ms / 1000
        -- per-step coefficient for step length = window_sec/window_overlap
        local step = window_sec / window_overlap
        -- classic exponential smoothing coef alpha = 1 - exp(-step / tau)
        return 1 - math.exp(-step / math.max(tau, 1e-12))
    end

    local attack_alpha = coef_from_time_ms(attack_ms)
    local release_alpha = coef_from_time_ms(release_ms)

    local step = window_sec / window_overlap
    for pos = boundary_start, boundary_end, step do
        reaper.GetAudioAccessorSamples(accessor, SR_spls, 1, pos, bufsz, samplebuffer)
        local sum = 0
        for i = 1, bufsz do
            local val = math.abs(samplebuffer[i])
            sum = sum + val
        end
        samplebuffer.clear() -- clear for next reuse
        id = id + 1

        -- raw RMS (linear)
        local raw_rms_linear = sum / bufsz

        -- smoothing operates on linear values (not dB)
        local smoothed_linear
        if not smoothing_enabled then
            smoothed_linear = raw_rms_linear
        else
            if raw_rms_linear > prev_smoothed_linear then
                -- attack (responding to increases)
                local a = attack_alpha
                smoothed_linear = prev_smoothed_linear + a * (raw_rms_linear - prev_smoothed_linear)
            else
                -- release (responding to decreases)
                local r = release_alpha
                smoothed_linear = prev_smoothed_linear + r * (raw_rms_linear - prev_smoothed_linear)
            end
        end

        prev_smoothed_linear = smoothed_linear

        local db_raw = WDL_VAL2DB(smoothed_linear)
        -- clamp to limits for storage/apply but keep raw for mean calculation

        local db_clamped = math.min(math.max(db_raw, envelope_bottom_limit), envelope_top_limit)
        data[id] = db_clamped

        -- accumulate raw (unclamped) dB into rms_sum so limits don't change the normalization baseline
        rms_sum = rms_sum + db_raw
        count = count + 1
        max_rms = math.max(max_rms, db_raw)
    end
    reaper.DestroyAudioAccessor(accessor)
    -- free our shared buffer
    samplebuffer = nil

    if count == 0 then
        return data, -150
    end

    return data, (rms_sum / count), max_rms
end

function Process_InsertData_reduceSameVal(output)
    local sz = #output
    -- reduce pts with same values

    local last_val = 0
    local trigval
    for i = 1, sz - 1 do
        local val = output[i].val
        local valnext = output[i + 1].val
        if last_val == val and valnext == val then
            output[i].ignore = true
        end
        last_val = val
    end
end

function Process_InsertVolumeData(item, env, AI_idx, t, isImpose, t_offset)
    local scaling_mode = reaper.GetEnvelopeScalingMode(env)

    -- get boundary
    local ret, boundary_start, boundary_end, i_pos = Process_GetBoundary(item)
    if not ret then
        return
    end

    -- init vars
    local offs = i_pos

    -- clear
    reaper.DeleteEnvelopePointRangeEx(env, AI_idx, boundary_start - offs + t_offset, boundary_end - offs + t_offset)

    -- do window shift
    local wind_offs = 0
    --window_ms

    -- get output points
    local output = Process_InsertData_PF(t, boundary_start, offs, isImpose)

    -- add points
    if output then
        Process_InsertData_reduceSameVal(output)
        local valout
        --local valout_max = reaper.ScaleToEnvelopeMode(scaling_mode, 1)
        local sz = #output
        for i = 1, sz do
            if output[i] and (not output[i].ignore or output[i].ignore == false) then
                valout = output[i].val

                local valout = reaper.ScaleToEnvelopeMode(scaling_mode, WDL_DB2VAL(valout))
                reaper.InsertEnvelopePointEx(
                    env,
                    AI_idx,
                    output[i].tpos + t_offset,
                    valout,
                    0, -- pointshape
                    0,
                    false,
                    true
                )
            end
        end

        -- one final sort after all inserts
        reaper.Envelope_SortPointsEx(env, AI_idx)
    --[[if (EXT.CONF_dest == 0 or EXT.CONF_dest == 2) then -- if AI set scale offset for AI
          GetSetAutomationItemInfo( env, AI_idx, 'D_BASELINE', EXT.CONF_out_AI_D_BASELINE, true )
          GetSetAutomationItemInfo( env, AI_idx, 'D_AMPLITUDE', EXT.CONF_out_AI_D_AMPLITUDE, true )
        end]]
    end

    -- boundary
    --[[     if EXT.CONF_zeroboundary == 1 then
        local ptidx = GetEnvelopePointByTimeEx(env, AI_idx, #t * EXT.CONF_window + boundary_start - offs)
        if ptidx then
            local retval, time, value, shape, tension, selected = reaper.GetEnvelopePointEx(env, AI_idx, ptidx)
            reaper.SetEnvelopePointEx(
                env,
                AI_idx,
                ptidx,
                time,
                ScaleToEnvelopeMode(scaling_mode, 1),
                shape,
                tension,
                selected,
                true
            )
        end
    end ]]
    -- sort 2nd pass
    reaper.Envelope_SortPointsEx(env, AI_idx)
end

function Process_RemapAndInsertData(item, env, AI_idx, t, isImpose, t_offset)
    local scaling_mode = reaper.GetEnvelopeScalingMode(env)

    -- get boundary
    local ret, boundary_start, boundary_end, i_pos = Process_GetBoundary(item)
    if not ret then
        return
    end

    -- init vars
    local offs = i_pos

    -- clear
    reaper.DeleteEnvelopePointRangeEx(env, AI_idx, boundary_start - offs + t_offset, boundary_end - offs + t_offset)

    -- do window shift
    local wind_offs = 0
    --window_ms

    -- get output points
    local output = Process_InsertData_PF(t, boundary_start, offs, isImpose)

    -- add points
    if output then
        Process_InsertData_reduceSameVal(output)
        local valout
        --local valout_max = reaper.ScaleToEnvelopeMode(scaling_mode, 1)
        local sz = #output
        for i = 1, sz do
            if output[i] and (not output[i].ignore or output[i].ignore == false) then
                
                valout = remapCurve((output[i].val + 150) / (174), 4.8)

                reaper.InsertEnvelopePointEx(
                    env,
                    AI_idx,
                    output[i].tpos + t_offset,
                    valout,
                    0, -- pointshape
                    0,
                    false,
                    true
                )
            end
        end

        -- one final sort after all inserts
        reaper.Envelope_SortPointsEx(env, AI_idx)
    --[[if (EXT.CONF_dest == 0 or EXT.CONF_dest == 2) then -- if AI set scale offset for AI
          GetSetAutomationItemInfo( env, AI_idx, 'D_BASELINE', EXT.CONF_out_AI_D_BASELINE, true )
          GetSetAutomationItemInfo( env, AI_idx, 'D_AMPLITUDE', EXT.CONF_out_AI_D_AMPLITUDE, true )
        end]]
    end

    -- boundary
    --[[     if EXT.CONF_zeroboundary == 1 then
        local ptidx = GetEnvelopePointByTimeEx(env, AI_idx, #t * EXT.CONF_window + boundary_start - offs)
        if ptidx then
            local retval, time, value, shape, tension, selected = reaper.GetEnvelopePointEx(env, AI_idx, ptidx)
            reaper.SetEnvelopePointEx(
                env,
                AI_idx,
                ptidx,
                time,
                ScaleToEnvelopeMode(scaling_mode, 1),
                shape,
                tension,
                selected,
                true
            )
        end
    end ]]
    -- sort 2nd pass
    reaper.Envelope_SortPointsEx(env, AI_idx)
end

function VF_Action(s, sectionID, ME)
    if sectionID == 32060 and ME then
        reaper.MIDIEditor_OnCommand(ME, reaper.NamedCommandLookup(s))
    else
        reaper.Main_OnCommand(reaper.NamedCommandLookup(s), sectionID or 0)
    end
end

function Process_GenerateTakeVolume(item)
    -- get boundary
    --[[     local ret, boundary_start, boundary_end, i_pos = Process_GetBoundary(item)
    if not ret then
        return
    end ]]
    -- destination
    local env
    local AI_idx = -1

    --local select = 3

    --[[ if select == 1 then -- track vol AI
        local track = reaper.GetMediaItem_Track(item)
        env = reaper.GetTrackEnvelopeByName(track, "Volume")
        if not reaper.ValidatePtr2(-1, env, "TrackEnvelope*") then
            reaper.SetOnlyTrackSelected(track)
            reaper.Main_OnCommand(40406, 0) -- show vol envelope
            env = reaper.GetTrackEnvelopeByName(track, "Volume")
        end
        --AI_idx = Process_GetEditAIbyEdges(env, boundary_start, boundary_end)
        if not AI_idx then
            AI_idx = reaper.InsertAutomationItem(env, -1, boundary_start, boundary_end - boundary_start)
        end
    end

    -- destination
    if select == 2 then -- prefx track vol AI
        local track = reaper.GetMediaItem_Track(item)
        env = reaper.GetTrackEnvelopeByName(track, "Volume (Pre-FX)")
        if not reaper.ValidatePtr2(-1, env, "TrackEnvelope*") then
            reaper.SetOnlyTrackSelected(track)
            reaper.Main_OnCommand(40408, 0) -- show Pre-FX vol envelope
            env = reaper.GetTrackEnvelopeByName(track, "Volume (Pre-FX)")
        end
        --AI_idx = Process_GetEditAIbyEdges(env, boundary_start, boundary_end)
        if not AI_idx then
            AI_idx = reaper.InsertAutomationItem(env, -1, boundary_start, boundary_end - boundary_start)
        end
    end ]]
    -- take env
    --if select == 3 then
    local take = reaper.GetActiveTake(item)
    if not take then
        return
    end

    for envidx = 1, reaper.CountTakeEnvelopes(take) do
        local tkenv = reaper.GetTakeEnvelope(take, envidx - 1)
        local retval, envname = reaper.GetEnvelopeName(tkenv)
        if envname == "Volume" then
            env = tkenv
            break
        end
    end

    if not reaper.ValidatePtr2(0, env, "TakeEnvelope*") then
        VF_Action(40693) -- Take: Toggle take volume envelope
        for envidx = 1, reaper.CountTakeEnvelopes(take) do
            local tkenv = reaper.GetTakeEnvelope(take, envidx - 1)
            local retval, envname = reaper.GetEnvelopeName(tkenv)
            if envname == "Volume" then
                env = tkenv
                break
            end
        end
    end
    --end

    -- apply points
    if not env then
        return
    end
    --local cntpts = CountEnvelopePointsEx( env, AI_idx )
    --DeleteEnvelopePointEx( env, AI_idx,  cntpts )
    --Envelope_SortPointsEx( env, AI_idx )

    return true, env, AI_idx
end

function EnvelopeVis(envelope, bool)
    local retval, str = reaper.GetEnvelopeStateChunk(envelope, "VIS", false)

    if retval then
        if bool then
            str = string.gsub(str, "VIS %d", "VIS 1")
        else
            str = string.gsub(str, "VIS %d", "VIS 0")
        end
    end
    reaper.SetEnvelopeStateChunk(envelope, str, true)

    local retval, str = reaper.GetEnvelopeStateChunk(envelope, "ACT", false)

    if retval then
        if bool then
            str = string.gsub(str, "ACT %d", "ACT 1")
        else
            str = string.gsub(str, "ACT %d", "ACT 0")
        end
    end
    reaper.SetEnvelopeStateChunk(envelope, str, true)
end

-- Return true if the envelope is visible/active in the arrange (based on VIS/ACT chunk flags)
function IsEnvelopeVisible(envelope)
    if not reaper.ValidatePtr2(0, envelope, "TrackEnvelope*") then
        return false
    end

    -- Try VIS chunk first
    local retval, vis_chunk = reaper.GetEnvelopeStateChunk(envelope, "VIS", false)
    if retval and vis_chunk then
        -- VIS line typically is like: "VIS 1" or "VIS 0"
        local v = vis_chunk:match("VIS%s+(%d+)")
        if v then
            return tonumber(v) == 1
        end
    end

    -- Fallback: check ACT (active) flag
    local retval2, act_chunk = reaper.GetEnvelopeStateChunk(envelope, "ACT", false)
    if retval2 and act_chunk then
        local a = act_chunk:match("ACT%s+(%d+)")
        if a then
            return tonumber(a) == 1
        end
    end

    -- If nothing found, assume visible
    return true
end

function AnalyseReferenceEnvelope()
    REF_AUDIO_DATA, RMS_MEAN, RMS_MAX = Process_GetAudioData(REF_ITEM, false)
    RMS_MEAN = math.abs(RMS_MEAN)
    REF_ANALYSIS_DONE = true
end

function makeCorrectiveEnvelope(TARGET_AUDIO_DATA, REF_AUDIO_DATA)
    local CorrectiveEnvelope = {}
    if not TARGET_AUDIO_DATA or not REF_AUDIO_DATA then
        return CorrectiveEnvelope
    end

    for i = 1, math.min(#TARGET_AUDIO_DATA, #REF_AUDIO_DATA) do
        -- Limita i valori di input al range valido
        local target_db = math.max(-150, math.min(24, TARGET_AUDIO_DATA[i] or -150))
        local ref_db = math.max(-150, math.min(24, REF_AUDIO_DATA[i] or -150))

        -- Converti da dB a valori lineari
        local target_linear = WDL_DB2VAL(target_db)
        local ref_linear = WDL_DB2VAL(ref_db)

        -- Calcola il fattore moltiplicativo necessario
        local correction_factor = ref_linear / math.max(target_linear, 1e-10)

        -- Converti il fattore di correzione in dB e limita il range
        local correction_db = WDL_VAL2DB(correction_factor)
        correction_db = math.max(-150, math.min(90, correction_db))

        CorrectiveEnvelope[i] = correction_db
    end

    return CorrectiveEnvelope
end

function Process_GenerateTrackEnvelope(envelope)
    --[[     local env = envelope
    local AI_idx = -1

    local track = reaper.GetMediaItem_Track(item)
    env = reaper.GetTrackEnvelopeByName(track, "Volume")
    if not reaper.ValidatePtr2(-1, env, "TrackEnvelope*") then
        reaper.SetOnlyTrackSelected(track)
        reaper.Main_OnCommand(40406, 0) -- show vol envelope
        env = reaper.GetTrackEnvelopeByName(track, "Volume")
    end ]]
    -- if not AI_idx then

    AI_idx = reaper.InsertAutomationItem(envelope, -1, 0, reaper.GetMediaItemInfo_Value(REF_ITEM, "D_LENGHT"))
    --end

    if not envelope then
        return
    end

    return true, envelope, AI_idx
end

function InsertTrackEnvelope(envelope, remap)

    local ret = nil
    ret, TARGET_ENV, TARGET_AI_IDX = Process_GenerateTrackEnvelope(envelope)
    if ret then

        local position = reaper.BR_PositionAtMouseCursor(false)

        local start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)

        if start_time ~= end_time then
            position = start_time
        end

        if remap == true then
            Process_RemapAndInsertData(REF_ITEM, TARGET_ENV, TARGET_AI_IDX, REF_AUDIO_DATA, false, position)
        else
            Process_InsertVolumeData(REF_ITEM, TARGET_ENV, TARGET_AI_IDX, REF_AUDIO_DATA, false, position)
        end
        
        EnvelopeVis(TARGET_ENV, true)
        reaper.UpdateTimeline()
    end
end

function ApplyTakeVolumeEnvelope(item)
    if item == REF_ITEM then
        return
    end

    local ret = nil
    ret, TARGET_ENV, TARGET_AI_IDX = Process_GenerateTakeVolume(item)
    if ret then
        Process_InsertVolumeData(item, TARGET_ENV, TARGET_AI_IDX, REF_AUDIO_DATA, false, 0)
        EnvelopeVis(TARGET_ENV, true)
        reaper.UpdateItemInProject(item)
    end
end

function ImposeTakeVolumeEnvelope(item)
    if item == REF_ITEM or reaper.CountSelectedMediaItems(0) == 0 then
        return
    end

    TARGET_ITEM = item

    --reaper.Main_OnCommand(40254, 0) -- Normalize

    TARGET_AUDIO_DATA = Process_GetAudioData(TARGET_ITEM, true)
    TARGET_ANALYSIS_DONE, TARGET_ENV, TARGET_AI_IDX = Process_GenerateTakeVolume(TARGET_ITEM)

    local CorrectiveEnvelope = makeCorrectiveEnvelope(TARGET_AUDIO_DATA, REF_AUDIO_DATA)

    if TARGET_ANALYSIS_DONE then
        Process_InsertVolumeData(TARGET_ITEM, TARGET_ENV, TARGET_AI_IDX, CorrectiveEnvelope, true, 0)
        EnvelopeVis(TARGET_ENV, true)
        reaper.UpdateItemInProject(TARGET_ITEM)
    end
end

function onExit()
    SetButtonState(0)
end

function plotWindow()
    reaper.ImGui_PushFont(ctx, comic_sans_small, comic_sans_small_size)
    --reaper.ImGui_SetCursorPosX(ctx, 0 + 1)
    --reaper.ImGui_SetCursorPosY(ctx, -2)
    reaper.ImGui_TextColored(ctx, reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 0.8), tostring(ENV_RANGE) .. "dB")
    -- .. " (" .. tostring(math.floor(ENV_RANGE + envelope_offset)) .. "dB)")

    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 0)

    reaper.ImGui_BeginChild(
        ctx,
        "PlotWindow",
        reaper.ImGui_GetWindowWidth(ctx) - 15,
        PLOT_WINDOW_HEIGHT,
        reaper.ImGui_ChildFlags_FrameStyle() | reaper.ImGui_ChildFlags_AutoResizeX() |
            reaper.ImGui_ChildFlags_AutoResizeY() |
            --reaper.ImGui_ChildFlags_AlwaysUseWindowPadding() |
            --reaper.ImGui_ChildFlags_Borders() |
            reaper.ImGui_ChildFlags_AlwaysAutoResize(),
        reaper.ImGui_WindowFlags_NoScrollbar()
    )

    dragOutEnvelope()
    --local window_height = reaper.ImGui_GetWindowHeight(ctx)
    local offset_x = -4.5
    local offset_y = -2.5

    if REF_AUDIO_DATA ~= nil then
        for i = 2, #REF_AUDIO_DATA do
            local x, y = reaper.ImGui_GetCursorScreenPos(ctx)

            local point_x = x + ((i / #REF_AUDIO_DATA) * reaper.ImGui_GetWindowWidth(ctx) + offset_x)
            local prev_point_x = x + (((i - 1) / #REF_AUDIO_DATA) * reaper.ImGui_GetWindowWidth(ctx) + offset_x)

            local point_y_raw =
                math.min(
                math.max(
                    ((REF_AUDIO_DATA[i] + RMS_MEAN) * scaling_factor_to_plot) - RMS_MEAN,
                    envelope_bottom_limit_to_plot
                ),
                envelope_top_limit_to_plot
            )
            local prev_point_y_raw =
                math.min(
                math.max(
                    ((REF_AUDIO_DATA[i - 1] + RMS_MEAN) * scaling_factor_to_plot) - RMS_MEAN,
                    envelope_bottom_limit_to_plot
                ),
                envelope_top_limit_to_plot
            )

            local point_y = map_db_to_pixels --[[ envelope_offset +  ]](point_y_raw, PLOT_WINDOW_HEIGHT)
            local prev_point_y = map_db_to_pixels --[[ envelope_offset +  ]](prev_point_y_raw, PLOT_WINDOW_HEIGHT)

            if i == 2 then
                reaper.ImGui_DrawList_AddLine(
                    reaper.ImGui_GetForegroundDrawList(ctx),
                    prev_point_x,
                    y + prev_point_y + offset_y,
                    x + offset_x,
                    y + prev_point_y + offset_y,
                    envelope_line_color,
                    1
                )

            --[[                 reaper.ImGui_DrawList_AddCircleFilled(
                    reaper.ImGui_GetForegroundDrawList(ctx),
                    prev_point_x,
                    prev_point_y,
                    1,
                    envelope_point_color
                )

                reaper.ImGui_DrawList_AddCircleFilled(
                    reaper.ImGui_GetForegroundDrawList(ctx),
                    x + offset_x,
                    prev_point_y,
                    1,
                    envelope_point_color
                ) ]]
            end

            reaper.ImGui_DrawList_AddLine(
                reaper.ImGui_GetForegroundDrawList(ctx),
                point_x,
                y + point_y + offset_y,
                prev_point_x,
                y + prev_point_y + offset_y,
                envelope_line_color,
                1
            )

            --[[             reaper.ImGui_DrawList_AddCircleFilled(
                reaper.ImGui_GetForegroundDrawList(ctx),
                point_x,
                point_y,
                1,
                envelope_point_color
            ) ]]
        end
    else
        --[[    SPINNER       
        local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
        -- use same offsets as plotting (offset_x/offset_y) so spinner is centered in plot area
        local center_x = x + ((reaper.ImGui_GetWindowWidth(ctx) - 15) * 0.5) + offset_x
        local center_y = y + (PLOT_WINDOW_HEIGHT * 0.5) + offset_y
        drawSpinner(center_x, center_y, 100, 0.3) ]]
    end

    reaper.ImGui_PopStyleVar(ctx)
    reaper.ImGui_EndChild(ctx)

    --reaper.ImGui_SetCursorPosX(ctx, 0 + 1)
    --reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetWindowHeight(ctx) * 0.92)
    reaper.ImGui_TextColored(ctx, reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 0.8), "-150dB")

    reaper.ImGui_PopFont(ctx)
end

function updateAfterSliderValueChange(retval)
    -- Normalize behavior: if nothing changed and the item wasn't deactivated, do nothing
    if not retval and not reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then
        return
    end

    -- require a valid reference item
    if REF_ITEM == -1 then
        return
    end

    -- If continuous update is enabled, react to any value change (retval true)
    if continuous_update then
        envelope_bottom_limit_to_plot = envelope_bottom_limit
        envelope_top_limit_to_plot = envelope_top_limit
        scaling_factor_to_plot = scaling_factor

        AnalyseReferenceEnvelope()

        if auto_update and reaper.CountSelectedMediaItems(0) ~= 0 then
            if auto_update_apply then
                ApplyTakeVolumeEnvelope(reaper.GetSelectedMediaItem(0, 0))
            else
                ImposeTakeVolumeEnvelope(reaper.GetSelectedMediaItem(0, 0))
            end
        end
        return
    end

    -- If continuous update is disabled, only react when the item was deactivated after edit
    if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then
        envelope_bottom_limit_to_plot = envelope_bottom_limit
        envelope_top_limit_to_plot = envelope_top_limit
        scaling_factor_to_plot = scaling_factor

        AnalyseReferenceEnvelope()
        if auto_update and reaper.CountSelectedMediaItems(0) ~= 0 then
            if auto_update_apply then
                ApplyTakeVolumeEnvelope(reaper.GetSelectedMediaItem(0, 0))
            else
                ImposeTakeVolumeEnvelope(reaper.GetSelectedMediaItem(0, 0))
            end
        end
    end
end

function mainWindow()
    -- CHECK ITEMS
    if not reaper.ValidatePtr2(0, REF_ITEM, "MediaItem*") then
        REF_ITEM = -1
        REF_ANALYSIS_DONE = false
        REF_ENV = nil
        REF_AI_IDX = nil
        REF_AUDIO_DATA = nil
    end

    if not reaper.ValidatePtr2(0, TARGET_ITEM, "MediaItem*") then
        TARGET_ITEM = -1
        TARGET_ANALYSIS_DONE = false
        TARGET_ENV = nil
        TARGET_AI_IDX = nil
        TARGET_AUDIO_DATA = nil
    end

    -- SET REF_ITEM BUTTON

    if reaper.CountSelectedMediaItems(0) == 0 then
        reaper.ImGui_BeginDisabled(ctx)
    end

    if reaper.ImGui_Button(ctx, "Set Reference Item") then
        REF_ITEM = -1
        REF_ANALYSIS_DONE = false
        REF_ENV = nil
        REF_AI_IDX = nil
        REF_AUDIO_DATA = nil

        TARGET_ITEM = -1
        TARGET_ANALYSIS_DONE = false
        TARGET_ENV = nil
        TARGET_AI_IDX = nil
        TARGET_AUDIO_DATA = nil

        REF_ITEM = reaper.GetSelectedMediaItem(0, 0)

        AnalyseReferenceEnvelope()
    end

    if reaper.CountSelectedMediaItems(0) == 0 then
        reaper.ImGui_EndDisabled(ctx)
    end

    --- HELPER SPINNER

    if REF_ITEM == -1 then
        reaper.ImGui_SameLine(ctx)
        local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
        drawSpinner(x + 13, y + 11.5, 13, 1)
        reaper.ImGui_NewLine(ctx)
    end

    -- REF ITEM NAME TEXT
    if REF_ITEM ~= -1 then
        reaper.ImGui_SameLine(ctx)
        local retval, stringNeedBig =
            reaper.GetSetMediaItemTakeInfo_String(reaper.GetActiveTake(REF_ITEM), "P_NAME", "", false)
        reaper.ImGui_Text(ctx, stringNeedBig)
    end

    reaper.ImGui_NewLine(ctx)

    -- ANALYSIS PARAMETERS

    if not REF_ANALYSIS_DONE then
        reaper.ImGui_BeginDisabled(ctx)
    end

    local retval, v = reaper.ImGui_SliderDouble(ctx, "Window Width (ms)", window_sec, 0.001, 0.2)

    if retval and REF_ITEM ~= -1 then
        window_sec = v
    end

    updateAfterSliderValueChange(retval)

    --[[     local retval, v = reaper.ImGui_SliderInt(ctx, "Window Overlap", window_overlap, 1, 16)

    if retval and REF_ITEM ~= -1 then
        window_overlap = v
        AnalyseReferenceEnvelope()

        if auto_update and reaper.CountSelectedMediaItems(0) ~= 0 then
            if auto_update_apply then
                ApplyEnvelope()
            else
                ImposeEnvelope()
            end
        end
    end ]]
    local retval, v = reaper.ImGui_SliderDouble(ctx, "Scaling Factor", scaling_factor, 0, 2)

    if retval and REF_ITEM ~= -1 then
        scaling_factor = v
    end

    updateAfterSliderValueChange(retval)

    reaper.ImGui_NewLine(ctx)

    --[[     -- Smoothing controls
    local retval_s, vs = reaper.ImGui_Checkbox(ctx, "Enable Smoothing", smoothing_enabled)
    if retval_s and REF_ITEM ~= -1 then
        smoothing_enabled = vs
        AnalyseReferenceEnvelope()

        if auto_update and reaper.CountSelectedMediaItems(0) ~= 0 then
            if auto_update_apply then
                ApplyEnvelope()
            else
                ImposeEnvelope()
            end
        end
    end ]]
    local retval, a_ms = reaper.ImGui_SliderDouble(ctx, "Attack (ms)", attack_ms, 0.01, 100)
    if retval and REF_ITEM ~= -1 then
        attack_ms = a_ms
    end

    updateAfterSliderValueChange(retval)

    local retval, r_ms = reaper.ImGui_SliderDouble(ctx, "Release (ms)", release_ms, 0.01, 100)
    if retval and REF_ITEM ~= -1 then
        release_ms = r_ms
    end

    updateAfterSliderValueChange(retval)

    reaper.ImGui_NewLine(ctx)

    local retval, v1, v2 =
        reaper.ImGui_SliderDouble2(ctx, "Limits (dB)", envelope_bottom_limit, envelope_top_limit, -150, 90)

    if retval and REF_ITEM ~= -1 then
        envelope_bottom_limit = v1
        envelope_top_limit = v2
    end

    updateAfterSliderValueChange(retval)

    if not REF_ANALYSIS_DONE then
        reaper.ImGui_EndDisabled(ctx)
    end

    -- ENVELOPE PLOT WINDOW

    reaper.ImGui_NewLine(ctx)

    plotWindow()

    reaper.ImGui_NewLine(ctx)

    if not REF_ANALYSIS_DONE then
        reaper.ImGui_BeginDisabled(ctx)
    end

    local retval, v = reaper.ImGui_SliderDouble(ctx, "Offset (dB)", envelope_offset, -150, 90)

    if retval and REF_ITEM ~= -1 then
        envelope_offset = v
    end

    updateAfterSliderValueChange(retval)

    if not REF_ANALYSIS_DONE then
        reaper.ImGui_EndDisabled(ctx)
    end

    -- TARGET ITEM NAME TEXT

    reaper.ImGui_NewLine(ctx)

    local target_name = "no valid target item selected"

    if reaper.CountSelectedMediaItems(0) ~= 0 and reaper.GetSelectedMediaItem(0, 0) ~= REF_ITEM and REF_ANALYSIS_DONE then
        local retval, str =
            reaper.GetSetMediaItemTakeInfo_String(
            reaper.GetActiveTake(reaper.GetSelectedMediaItem(0, 0)),
            "P_NAME",
            "",
            false
        )
        target_name = str
    end

    if REF_ITEM ~= -1 then
        reaper.ImGui_TextColored(ctx, reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 1), "Target Item: " .. target_name)
    else
        reaper.ImGui_TextColored(
            ctx,
            reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 0.3),
            "Target Item: " .. target_name
        )
    end

    --- HELPER SPINNER
    if (reaper.CountSelectedMediaItems(0) == 0 or reaper.GetSelectedMediaItem(0, 0) == REF_ITEM) and REF_ITEM ~= -1 then
        reaper.ImGui_SameLine(ctx)
        local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
        drawSpinner(x + 7, y + 10.5, 13, 1)
        reaper.ImGui_NewLine(ctx)
    end

    reaper.ImGui_NewLine(ctx)

    -- APPLY ENVELOPE BUTTON

    if not auto_update then
        if reaper.CountSelectedMediaItems(0) <= 0 or reaper.GetSelectedMediaItem(0, 0) == REF_ITEM or REF_ITEM == -1 then
            reaper.ImGui_BeginDisabled(ctx)
        end

        if reaper.ImGui_Button(ctx, "Apply") then
            ApplyTakeVolumeEnvelope(reaper.GetSelectedMediaItem(0, 0))
            auto_update_apply = true
            auto_update_impose = false
        end

        if reaper.CountSelectedMediaItems(0) <= 0 or reaper.GetSelectedMediaItem(0, 0) == REF_ITEM or REF_ITEM == -1 then
            reaper.ImGui_EndDisabled(ctx)
        end

        -- IMPOSE ENVELOPE BUTTON

        reaper.ImGui_SameLine(ctx)

        if reaper.CountSelectedMediaItems(0) <= 0 or reaper.GetSelectedMediaItem(0, 0) == REF_ITEM or REF_ITEM == -1 then
            reaper.ImGui_BeginDisabled(ctx)
        end

        if reaper.ImGui_Button(ctx, "Impose") then
            ImposeTakeVolumeEnvelope(reaper.GetSelectedMediaItem(0, 0))
            auto_update_apply = false
            auto_update_impose = true
        end

        if reaper.CountSelectedMediaItems(0) <= 0 or reaper.GetSelectedMediaItem(0, 0) == REF_ITEM or REF_ITEM == -1 then
            reaper.ImGui_EndDisabled(ctx)
        end
    else -- if auto apply
        -- Apply Button
        if reaper.CountSelectedMediaItems(0) <= 0 or reaper.GetSelectedMediaItem(0, 0) == REF_ITEM or REF_ITEM == -1 then
            reaper.ImGui_BeginDisabled(ctx)
        end

        if auto_update_apply then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), envelope_line_color)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), envelope_line_color)
            if reaper.ImGui_Button(ctx, "Apply") then
                auto_update_apply = true
                auto_update_impose = false
                ApplyTakeVolumeEnvelope(reaper.GetSelectedMediaItem(0, 0))
            end
            reaper.ImGui_PopStyleColor(ctx)
            reaper.ImGui_PopStyleColor(ctx)
        else
            if reaper.ImGui_Button(ctx, "Apply") then
                auto_update_apply = true
                auto_update_impose = false
                ApplyTakeVolumeEnvelope(reaper.GetSelectedMediaItem(0, 0))
            end
        end

        reaper.ImGui_SameLine(ctx)

        -- Impose Button
        if auto_update_impose then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), envelope_line_color)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), envelope_line_color)
            if reaper.ImGui_Button(ctx, "Impose") then
                auto_update_apply = false
                auto_update_impose = true
                ImposeTakeVolumeEnvelope(reaper.GetSelectedMediaItem(0, 0))
            end
            reaper.ImGui_PopStyleColor(ctx)
            reaper.ImGui_PopStyleColor(ctx)
        else
            if reaper.ImGui_Button(ctx, "Impose") then
                auto_update_apply = false
                auto_update_impose = true
                ImposeTakeVolumeEnvelope(reaper.GetSelectedMediaItem(0, 0))
            end
        end

        if reaper.CountSelectedMediaItems(0) <= 0 or reaper.GetSelectedMediaItem(0, 0) == REF_ITEM or REF_ITEM == -1 then
            reaper.ImGui_EndDisabled(ctx)
        end
    end

    -- SPINNER

    if reaper.CountSelectedMediaItems(0) > 0 and reaper.GetSelectedMediaItem(0, 0) ~= REF_ITEM and REF_ITEM ~= -1 then
        reaper.ImGui_SameLine(ctx)
        local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
        drawSpinner(x + 12, y + 11.5, 13, 1)
    end

    -- AUTO-UPDATE ENVELOPE CHECKBOX

    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetWindowWidth(ctx) - 30)
    --reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetWindowHeight(ctx) - 30)

    local retval, v = reaper.ImGui_Checkbox(ctx, "##Auto-Update", auto_update)

    if retval then
        auto_update = v

        if reaper.CountSelectedMediaItems(0) ~= 0 then
            if auto_update and REF_ANALYSIS_DONE then
                if auto_update_apply then
                    ApplyTakeVolumeEnvelope(reaper.GetSelectedMediaItem(0, 0))
                else
                    ImposeTakeVolumeEnvelope(reaper.GetSelectedMediaItem(0, 0))
                end
            end
        end
    end

    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetWindowWidth(ctx) - 118)
    --reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetWindowHeight(ctx) - 30)
    reaper.ImGui_Text(ctx, "Auto-Update")

    -- CONTINUOUS ENVELOPE CHECKBOX

    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetWindowWidth(ctx) - 170)
    --reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetWindowHeight(ctx) - 30)

    local retval, v = reaper.ImGui_Checkbox(ctx, "##Continuous-Update", continuous_update)

    if retval then
        continuous_update = v

    --[[ if reaper.CountSelectedMediaItems(0) ~= 0 then
            if continuous_update and REF_ANALYSIS_DONE then
                if auto_update_apply then
                    ApplyEnvelope()
                else
                    ImposeEnvelope()
                end
            end
        end ]]
    end

    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetWindowWidth(ctx) - 295)
    --reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetWindowHeight(ctx) - 30)
    reaper.ImGui_Text(ctx, "Continuous-Update")
end

function guiStylePush()
    reaper.ImGui_PushStyleColor(
        ctx,
        reaper.ImGui_Col_WindowBg(),
        reaper.ImGui_ColorConvertDouble4ToU32(0.1, 0.1, 0.1, 1)
    )

    reaper.ImGui_PushStyleColor(
        ctx,
        reaper.ImGui_Col_Border(),
        reaper.ImGui_ColorConvertDouble4ToU32(0.45, 0.45, 0.45, 2)
    )
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_BorderShadow(), reaper.ImGui_ColorConvertDouble4ToU32(0, 0, 0, 2))

    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), reaper.ImGui_ColorConvertDouble4ToU32(0.1, 0.1, 0.1, 2))
    reaper.ImGui_PushStyleColor(
        ctx,
        reaper.ImGui_Col_HeaderActive(),
        reaper.ImGui_ColorConvertDouble4ToU32(0.1, 0.1, 0.1, 2)
    )
    reaper.ImGui_PushStyleColor(
        ctx,
        reaper.ImGui_Col_HeaderHovered(),
        reaper.ImGui_ColorConvertDouble4ToU32(0.18, 0.18, 0.18, 2)
    )

    reaper.ImGui_PushStyleColor(
        ctx,
        reaper.ImGui_Col_MenuBarBg(),
        reaper.ImGui_ColorConvertDouble4ToU32(0.1, 0.1, 0.1, 2)
    )

    reaper.ImGui_PushStyleColor(
        ctx,
        reaper.ImGui_Col_Button(),
        reaper.ImGui_ColorConvertDouble4ToU32(0.18, 0.18, 0.18, 2)
    )
    reaper.ImGui_PushStyleColor(
        ctx,
        reaper.ImGui_Col_ButtonHovered(),
        reaper.ImGui_ColorConvertDouble4ToU32(0.3, 0.3, 0.3, 2)
    )
    reaper.ImGui_PushStyleColor(
        ctx,
        reaper.ImGui_Col_ButtonActive(),
        reaper.ImGui_ColorConvertDouble4ToU32(0.18, 0.18, 0.18, 2)
    )

    reaper.ImGui_PushStyleColor(
        ctx,
        reaper.ImGui_Col_ResizeGrip(),
        reaper.ImGui_ColorConvertDouble4ToU32(0.1, 0.1, 0.1, 2)
    )
    reaper.ImGui_PushStyleColor(
        ctx,
        reaper.ImGui_Col_ResizeGripActive(),
        reaper.ImGui_ColorConvertDouble4ToU32(0.3, 0.3, 0.3, 2)
    )
    reaper.ImGui_PushStyleColor(
        ctx,
        reaper.ImGui_Col_ResizeGripHovered(),
        reaper.ImGui_ColorConvertDouble4ToU32(0.18, 0.18, 0.18, 2)
    )

    reaper.ImGui_PushStyleColor(
        ctx,
        reaper.ImGui_Col_TitleBg(),
        reaper.ImGui_ColorConvertDouble4ToU32(0.14, 0.14, 0.14, 2)
    )
    reaper.ImGui_PushStyleColor(
        ctx,
        reaper.ImGui_Col_TitleBgActive(),
        reaper.ImGui_ColorConvertDouble4ToU32(0.18, 0.18, 0.18, 2)
    )
    reaper.ImGui_PushStyleColor(
        ctx,
        reaper.ImGui_Col_TitleBgCollapsed(),
        reaper.ImGui_ColorConvertDouble4ToU32(0.18, 0.18, 0.18, 2)
    )

    reaper.ImGui_PushStyleColor(
        ctx,
        reaper.ImGui_Col_FrameBg(),
        reaper.ImGui_ColorConvertDouble4ToU32(0.2, 0.2, 0.2, 2)
    )
    reaper.ImGui_PushStyleColor(
        ctx,
        reaper.ImGui_Col_FrameBgActive(),
        reaper.ImGui_ColorConvertDouble4ToU32(0.4, 0.4, 0.4, 2)
    )
    reaper.ImGui_PushStyleColor(
        ctx,
        reaper.ImGui_Col_FrameBgHovered(),
        reaper.ImGui_ColorConvertDouble4ToU32(0.25, 0.25, 0.25, 2)
    )

    reaper.ImGui_PushStyleColor(
        ctx,
        reaper.ImGui_Col_SliderGrab(),
        reaper.ImGui_ColorConvertDouble4ToU32(0.5, 0.5, 0.5, 2)
    )
    reaper.ImGui_PushStyleColor(
        ctx,
        reaper.ImGui_Col_SliderGrabActive(),
        reaper.ImGui_ColorConvertDouble4ToU32(0.13, 0.13, 0.13, 2)
    )

    reaper.ImGui_PushStyleColor(
        ctx,
        reaper.ImGui_Col_CheckMark(),
        reaper.ImGui_ColorConvertDouble4ToU32(0.8, 0.8, 0.8, 2)
    )

    reaper.ImGui_PushStyleColor(
        ctx,
        reaper.ImGui_Col_Separator(),
        reaper.ImGui_ColorConvertDouble4ToU32(0.35, 0.35, 0.35, 2)
    )

    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ScrollbarSize(), 10)
    reaper.ImGui_PushStyleColor(
        ctx,
        reaper.ImGui_Col_ScrollbarBg(),
        reaper.ImGui_ColorConvertDouble4ToU32(0.09, 0.09, 0.09, 1)
    )
    reaper.ImGui_PushStyleColor(
        ctx,
        reaper.ImGui_Col_ScrollbarGrab(),
        reaper.ImGui_ColorConvertDouble4ToU32(0.3, 0.3, 0.3, 1)
    )
    reaper.ImGui_PushStyleColor(
        ctx,
        reaper.ImGui_Col_ScrollbarGrabActive(),
        reaper.ImGui_ColorConvertDouble4ToU32(0.2, 0.2, 0.2, 1)
    )
    reaper.ImGui_PushStyleColor(
        ctx,
        reaper.ImGui_Col_ScrollbarGrabHovered(),
        reaper.ImGui_ColorConvertDouble4ToU32(0.5, 0.5, 0.5, 1)
    )

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

function EnsureTrackVolumeEnvelope(chunk)
    -- controlla se c'è già un envelope di volume
    if chunk:match("<VOLENV2") then
        return chunk -- già presente, ritorna com'è
    end

    -- utility: generate a RFC4122 v4 GUID in form {XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX}
    local function generate_guid()
        -- seed randomness with time + clock for more entropy
        math.randomseed(os.time() + math.floor((os.clock() * 1000000) % 2147483647))
        local b = {}
        for i = 1, 16 do
            b[i] = math.random(0, 255)
        end
        -- set version (4) in byte 7 (1-based index 7)
        b[7] = (b[7] % 16) + 0x40
        -- set variant (10xxxxxx) in byte 9 (1-based index 9)
        b[9] = (b[9] % 64) + 0x80

        return string.format("{%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X}", table.unpack(b))
    end

    -- envelope di volume "di default" (use freshly generated GUID to avoid collisions)
    local vol_env =
        string.format(
        [[
<VOLENV2
EGUID %s
ACT 1 -1
VIS 1 1 1
LANEHEIGHT 0 0
ARM 0
DEFSHAPE 0 -1 -1
VOLTYPE 1
PT 0 1 0
>
]],
        generate_guid()
    )

    -- inserisce l'envelope PRIMA del ">"
    local pos = chunk:find(">%s*$") -- trova l'ultimo ">"
    if not pos then
        return chunk -- non valido, ritorna com'è
    end

    local before = chunk:sub(1, pos - 1)
    local after = chunk:sub(pos)

    local new_chunk = before .. vol_env .. after
    return new_chunk
end

function GetFXEnvelopeRange(env)
  if not env then return nil,nil end

  -- prendi la traccia
  local track = reaper.Envelope_GetParentTrack(env)
  if not track then return nil,nil end

  -- nome dell’envelope (es: "ReaEQ: Band 1 Gain")
  local retval, env_name = reaper.GetEnvelopeName(env, "")
  if not retval then return nil,nil end

  -- loop sugli FX della traccia
  local fx_count = reaper.TrackFX_GetCount(track)
  for fx = 0, fx_count-1 do
    local param_count = reaper.TrackFX_GetNumParams(track, fx)
    for p = 0, param_count-1 do
      local _, pname = reaper.TrackFX_GetParamName(track, fx, p, "")
      -- match sul nome (grezzo: puoi raffinare se serve)
      if env_name:find(pname, 1, true) then
        local minval, maxval, midval, step = reaper.TrackFX_GetParamEx(track, fx, p)
        return minval, maxval
      end
    end
  end

  return nil,nil
end

function dragOutEnvelope()

    local l_mouse_down = reaper.ImGui_IsMouseDown(ctx, reaper.ImGui_MouseButton_Left())

    if l_mouse_down and drag_operation_started == true then
        reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
    end

    if l_mouse_down and drag_operation_started == false and reaper.ImGui_IsWindowHovered(ctx) and REF_ANALYSIS_DONE and REF_ITEM then
        drag_operation_started = true
        reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
    end

    if l_mouse_down == false and drag_operation_started == true then
        reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Arrow())
        drag_operation_started = false


        local track, context, position = reaper.BR_TrackAtMouseCursor()

        if reaper.ValidatePtr(track, "MediaTrack*") and context == 2 then
            
            local destination_envelope = reaper.GetTrackEnvelopeByName(track, "Volume")
            
            if not reaper.ValidatePtr(destination_envelope, "TrackEnvelope*") then
                local retval, str = reaper.GetTrackStateChunk(track, "", false)
                reaper.SetTrackStateChunk(track, EnsureTrackVolumeEnvelope(str), false)
                destination_envelope = reaper.GetTrackEnvelopeByName(track, "Volume")
            end
            InsertTrackEnvelope(destination_envelope, false)
            return
        end

        reaper.BR_GetMouseCursorContext()

        local track_env, is_take = reaper.BR_GetMouseCursorContext_Envelope()

        if track_env then
            local trk, info = reaper.GetThingFromPoint(reaper.GetMousePosition())
            local envidx = info:match('(%d+)')
            local track, i1, i2 = reaper.Envelope_GetParentTrack(track_env)
            local idx = math.floor(tonumber(envidx))
            if not idx then return end
            local env0 = reaper.GetTrackEnvelope( track, idx )
            local retval, env_name = reaper.GetEnvelopeName(track_env)

            if env_name == "Volume" then
                InsertTrackEnvelope(env0, false)
                return
            else
                InsertTrackEnvelope(env0, true)
                return
            end
        end

        local take, position = reaper.BR_TakeAtMouseCursor()

        if take then
            if REF_ITEM ~= -1 and REF_ANALYSIS_DONE == true then
                ApplyTakeVolumeEnvelope(reaper.GetMediaItemTake_Item(take))
                return
            end
        end
    end
end

function loop()
    local ret, val = reaper.BR_Win32_GetPrivateProfileString("REAPER", "volenvrange", "", reaper.get_ini_file())

    if val == "4" then
        ENV_RANGE = 0
    elseif val == "5" then
        ENV_RANGE = 6
    elseif val == "6" then
        ENV_RANGE = 12
    elseif val == "7" then
        ENV_RANGE = 24
    end

    guiStylePush()

    reaper.ImGui_SetNextWindowSizeConstraints(
        ctx,
        MAIN_WINDOW_WIDTH,
        MAIN_WINDOW_HEIGHT,
        MAIN_WINDOW_WIDTH + 300,
        MAIN_WINDOW_HEIGHT,
        EEL_DUMMY_FUNCTION
    )

    local flags =
        reaper.ImGui_WindowFlags_NoCollapse() | reaper.ImGui_WindowFlags_NoScrollbar() |
        reaper.ImGui_WindowFlags_NoScrollWithMouse() |
        reaper.ImGui_WindowFlags_NoResize() |
        reaper.ImGui_WindowFlags_NoDocking()

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

function drawSpinner(x, y, size, alpha)
    -- treat x,y as the center of the spinner (caller already computes center)
    local rotation = (os.clock() * 6) % (2 * math.pi)
    local r = size / 2
    local thickness = 1

    if size > 50 then
        thickness = 2
    end
    -- draw ellipse centered at (x,y). use more segments for smoothness and slightly thicker stroke
    reaper.ImGui_DrawList_AddEllipse(
        reaper.ImGui_GetWindowDrawList(ctx),
        x,
        y,
        r,
        r,
        reaper.ImGui_ColorConvertDouble4ToU32(1, 0.5, 0, alpha),
        rotation,
        3,
        thickness
    )
end

SetButtonState(1)
reaper.defer(loop)
reaper.atexit(onExit)
