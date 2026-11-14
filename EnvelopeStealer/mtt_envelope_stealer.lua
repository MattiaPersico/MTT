-- Envelope Stealer
-- Author: Mattia Persico (MTT)

-- This script is is based on "mpl_Peak follower tools.lua" and uses parts of its code

--[[ APPUNTI

- aggiungi hint di quanto sta sforando oltre il bordo accanto a 24db
- aggiungere istruzioni
- trovare un modo sano di integrare gli automation items
- fare redesign per fare in modo che analizzi selezione e non item

 APPUNTI ]]
local major_version = 0
local minor_version = 20

local name = "Envelope Stealer " .. tostring(major_version) .. "." .. tostring(minor_version)

if not reaper.APIExists("ImGui_GetVersion") or not reaper.APIExists("BR_GetMouseCursorContext") then
    reaper.MB("Envelope Stealer needs the ReaImGui and SWS extensions.", "Missing dependency", 0)
    return
end

dofile(reaper.GetResourcePath() .. "/Scripts/ReaTeam Extensions/API/imgui.lua")("0.10")
local ctx = reaper.ImGui_CreateContext(name)

-- Funzione EEL per i Vincoli delle Dimensioni della Finestra
local sizeConstraintsCallback = [=[
1 + 1
]=]

local EEL_DUMMY_FUNCTION = reaper.ImGui_CreateFunctionFromEEL(sizeConstraintsCallback)

local MAIN_WINDOW_WIDTH = 550
local MAIN_WINDOW_HEIGHT = 900

local PLOT_WINDOW_HEIGHT = 230

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

-- User Parameters
local definition = 0.5 -- user fader value to control the window_sec parameter
local window_sec = 1 - remapCurve(definition * 1, 0.05) --0.04 -- analysis window in seconds 0.001 - 0.4
local window_overlap = 2 -- overlap factor, 2 = 50% overlap, 1-16
local auto_update = true
local impose_envelope_on_items = false
local scaling_factor = 1 -- envelope scaling factor
local envelope_offset = 0 -- envelope offset
local envelope_top_limit = 90
local envelope_bottom_limit = -150
local attack_ms = 0.01 -- how fast it reacts to increases (ms)
local release_ms = 0.01 -- how fast it reacts to decreases (ms)
local compression = 0
local gain = 0
local update_only_on_slider_release = false

-- Private Parameters
local REF_ANALYSIS_DONE, REF_ENV, REF_AI_IDX  -- global vars to store state between stealing and applying
local REF_AUDIO_DATA  -- global var to store audio data between stealing and applying
local REF_ITEM = -1 -- global var to store reference item
local RMS_MEAN = -150
local RMS_MAX = -150
local VOL_ENV_RANGE = 24
local PITCH_ENV_RANGE = 12

local TARGET_ANALYSIS_DONE, TARGET_ENV, TARGET_AI_IDX  -- global vars to store state between stealing and applying
local TARGET_AUDIO_DATA  -- global var to store audio data between stealing and applying

-- Raw analysis caches (see ReadWindowLevels): the reference item and the last imposed target
local REF_LEVELS = {}
local TARGET_LEVELS = {}

-- drop memories
local last_envelope = nil
local last_take = nil
local was_last_drop_on_item = nil
local last_cursor_position = nil
local target_time = nil
local target_name = ""
local lock_target = false

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

-- Envelope values (dB) for the analysed levels `t`: scaled, limited, then offset.
-- A reference curve is scaled around its mean level; an imposed correction is already
-- relative, so it is scaled around 0 dB.
function Process_InsertData_PF(t, isImpose)
    local vals = {}

    for i = 1, #t do
        local val
        if isImpose then
            val = t[i] * scaling_factor
        else
            val = (t[i] - RMS_MEAN) * scaling_factor + RMS_MEAN
        end
        vals[i] = math.min(math.max(val, envelope_bottom_limit), envelope_top_limit) + envelope_offset
    end

    return vals
end

function remapToNewRange(value, old_min, old_max, new_min, new_max, k)
    -- Gestisce casi edge
    if old_min == old_max then
        return new_min -- evita divisione per zero
    end

    -- Clamp del valore di input al range originale
    value = math.max(old_min, math.min(old_max, value))

    -- Normalizza il valore nel range 0-1
    local normalized = (value - old_min) / (old_max - old_min)

    normalized = remapCurve(normalized, k)

    -- Rimappa linearmente nel nuovo range
    return new_min + normalized * (new_max - new_min)
end

function map_db_to_pixels(db_value, window_height, top)
    -- Assicuriamoci che il valore sia nel range dynamic: envelope_bottom_limit .. ENV_RANGE
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

--[[     local ts_start, ts_end = reaper.GetSet_LoopTimeRange(0, 0, 0, 0, 0)

    if ts_start ~= ts_end then
        boundary_start = ts_start
        boundary_end = ts_end
    end ]]

    return true, boundary_start, boundary_end, i_pos
end

-- Mean absolute level (linear, before gain) of every analysis window across the item's time
-- range, read from the item's track. Reading the audio is the expensive part of the analysis,
-- so the result is kept in `cache` and reused while the item, the window, the sample rate and
-- the project state are unchanged: gain, attack/release and compression are applied afterwards
-- (ShapeLevels) and never need the audio again.
-- env_to_clear: a take volume envelope to empty first, so that it is not part of the levels.
-- Returns nil for an item without an audio take.
local function ReadWindowLevels(item, cache, env_to_clear)
    if not (item and window_sec) then
        return
    end
    local take = reaper.GetActiveTake(item)
    if not take or reaper.TakeIsMIDI(take) then
        return
    end

    local SR_spls = tonumber(reaper.format_timestr_pos(1 - reaper.GetProjectTimeOffset(0, false), "", 4)) -- get sample rate obey project start offset
    -- taken before the envelope is cleared: loop() carries the cache over the script's own edits
    local state = reaper.GetProjectStateChangeCount(0)

    if env_to_clear then
        reaper.DeleteEnvelopePointRange(env_to_clear, -math.huge, math.huge)
        reaper.Envelope_SortPoints(env_to_clear)
    end

    if cache.item == item and cache.window_sec == window_sec and cache.srate == SR_spls and cache.state == state then
        return cache.levels
    end

    local accessor = reaper.CreateTrackAudioAccessor(reaper.GetMediaItem_Track(item))
    local bufsz = math.ceil(window_sec * SR_spls)
    -- allocate a single buffer and reuse it across iterations to avoid repeated allocations
    local samplebuffer = reaper.new_array(bufsz)
    local _, boundary_start, boundary_end = Process_GetBoundary(item)
    local step = window_sec / window_overlap
    local levels = {}
    local id = 0

    for pos = boundary_start, boundary_end, step do
        local sum = 0
        -- 1 = audio; 0 (no audio) and -1 (error) leave nothing to add up
        if reaper.GetAudioAccessorSamples(accessor, SR_spls, 1, pos, bufsz, samplebuffer) == 1 then
            -- one copy into a Lua table: indexing the reaper.array is an API call per sample
            local samples = samplebuffer.table()
            for i = 1, bufsz do
                local val = samples[i]
                if val < 0 then
                    sum = sum - val
                else
                    sum = sum + val
                end
            end
            samplebuffer.clear() -- clear for next reuse
        end
        id = id + 1
        levels[id] = sum / bufsz
    end
    reaper.DestroyAudioAccessor(accessor)

    cache.item, cache.window_sec, cache.srate, cache.state, cache.levels = item, window_sec, SR_spls, state, levels
    return levels
end

-- Turns the raw window levels into the analysed curve: gain, attack/release smoothing, dB,
-- compression. Returns the curve (dB per window), its mean and its maximum.
local function ShapeLevels(levels)
    local data = {}
    local count = #levels

    if count == 0 then
        return data, -150, -150
    end

    -- per-step coefficient for step length = window_sec/window_overlap
    local step = window_sec / window_overlap

    -- convert attack/release from ms to smoothing coefficients
    local function coef_from_time_ms(t_ms)
        if t_ms <= 0 then
            return 0
        end
        -- time constant in seconds
        local tau = t_ms / 1000
        -- classic exponential smoothing coef alpha = 1 - exp(-step / tau)
        return 1 - math.exp(-step / math.max(tau, 1e-12))
    end

    local attack_alpha = coef_from_time_ms(attack_ms)
    local release_alpha = coef_from_time_ms(release_ms)
    local gain_linear = WDL_DB2VAL(gain)

    local rms_sum = 0
    local max_rms = -150
    -- previous smoothed linear value (start very small)
    local prev_smoothed_linear = 1e-9

    for id = 1, count do
        local raw_rms_linear = levels[id] * gain_linear

        -- smoothing operates on linear values (not dB)
        local smoothed_linear
        if not smoothing_enabled then
            smoothed_linear = raw_rms_linear
        elseif raw_rms_linear > prev_smoothed_linear then
            -- attack (responding to increases)
            smoothed_linear = prev_smoothed_linear + attack_alpha * (raw_rms_linear - prev_smoothed_linear)
        else
            -- release (responding to decreases)
            smoothed_linear = prev_smoothed_linear + release_alpha * (raw_rms_linear - prev_smoothed_linear)
        end

        prev_smoothed_linear = smoothed_linear

        data[id] = WDL_VAL2DB(smoothed_linear)

        -- accumulate raw (unclamped) dB into rms_sum so limits don't change the normalization baseline
        rms_sum = rms_sum + data[id]
        max_rms = math.max(max_rms, data[id])
    end

    local rms_mean = rms_sum / count

    --- Compressione
    if compression > 0 then
        -- Applica uno scale factor uniforme a tutti i valori, verso 0 dB
        -- Questo mantiene l'ordine e non permette inversioni
        local scale_factor = 1 - compression
        local new_rms_sum = 0

        for i = 1, count do
            data[i] = data[i] * scale_factor
            new_rms_sum = new_rms_sum + data[i]
        end

        rms_mean = new_rms_sum / count
    end
    --- Fine Compressione

    return data, rms_mean, max_rms
end

-- Analyses an item: the dB curve, its mean and its maximum, or nil without an audio take.
function Process_GetAudioData(item, cache, env_to_clear)
    local levels = ReadWindowLevels(item, cache, env_to_clear)
    if not levels then
        return
    end
    return ShapeLevels(levels)
end

-- Writes the analysed levels `t` to `env` as points, one per analysis step from t_offset on,
-- replacing what was there over the item's length. map_value turns the dB value into the
-- envelope's own unit.
local function InsertEnvelopeData(item, env, AI_idx, t, isImpose, t_offset, map_value)
    local i_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")

    -- clear
    reaper.DeleteEnvelopePointRangeEx(env, AI_idx, t_offset, t_offset + i_len)

    -- get output points
    local vals = Process_InsertData_PF(t, isImpose)
    local sz = #vals
    local step = window_sec / window_overlap

    -- add points
    for i = 1, sz do
        local val = vals[i]
        -- a point between two neighbours of the same value changes nothing: skip it
        if not (i > 1 and i < sz and vals[i - 1] == val and vals[i + 1] == val) then
            reaper.InsertEnvelopePointEx(
                env,
                AI_idx,
                (i - 1) * step + t_offset,
                map_value(val),
                0, -- pointshape
                0,
                false,
                true
            )
        end
    end

    -- one final sort after all inserts
    reaper.Envelope_SortPointsEx(env, AI_idx)
end

function Process_InsertPitchData(item, env, AI_idx, t, isImpose, t_offset, pitch_range)
    InsertEnvelopeData(
        item,
        env,
        AI_idx,
        t,
        isImpose,
        t_offset,
        function(db)
            return remapToNewRange(db, -150, 24, -pitch_range, pitch_range, 4.8)
        end
    )
end

function Process_InsertPanData(item, env, AI_idx, t, isImpose, t_offset)
    InsertEnvelopeData(
        item,
        env,
        AI_idx,
        t,
        isImpose,
        t_offset,
        function(db)
            return remapToNewRange(db, -150, 24, -1, 1, 4.8)
        end
    )
end

-- Any other envelope: the curve remapped to 0..1
function Process_InsertNormData(item, env, AI_idx, t, isImpose, t_offset)
    InsertEnvelopeData(
        item,
        env,
        AI_idx,
        t,
        isImpose,
        t_offset,
        function(db)
            return remapToNewRange(db, -150, 24, 0, 1, 4.8)
        end
    )
end

function Process_InsertVolumeData(item, env, AI_idx, t, isImpose, t_offset)
    local scaling_mode = reaper.GetEnvelopeScalingMode(env)

    InsertEnvelopeData(
        item,
        env,
        AI_idx,
        t,
        isImpose,
        t_offset,
        function(db)
            return reaper.ScaleToEnvelopeMode(scaling_mode, WDL_DB2VAL(db))
        end
    )
end

-- Shows and activates an envelope (or hides and deactivates it). The chunk is written back
-- only when one of the two flags actually changes.
function EnvelopeVis(envelope, bool)
    if not reaper.ValidatePtr2(0, envelope, "TrackEnvelope*") then
        return
    end

    local retval, str = reaper.GetEnvelopeStateChunk(envelope, "", false)
    if not retval then
        return
    end

    local flag = bool and "1" or "0"
    local new_str = str:gsub("VIS %d", "VIS " .. flag):gsub("ACT %d", "ACT " .. flag)

    if new_str ~= str then
        reaper.SetEnvelopeStateChunk(envelope, new_str, true)
    end
end

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

-- Forgets the reference item and its analysis
local function ClearReference()
    REF_ITEM = -1
    REF_ANALYSIS_DONE = false
    REF_ENV = nil
    REF_AI_IDX = nil
    REF_AUDIO_DATA = nil
end

-- True while `env` is still an envelope of `take`
local function TakeHasEnvelope(take, env)
    for i = 0, reaper.CountTakeEnvelopes(take) - 1 do
        if reaper.GetTakeEnvelope(take, i) == env then
            return true
        end
    end
    -- not found by handle: let REAPER have the last word
    return reaper.ValidatePtr2(0, env, "TrackEnvelope*")
end

-- Analyses REF_ITEM. An item without an audio take cannot be a reference: it is dropped.
-- Returns true when the reference curve is available.
function AnalyseReferenceEnvelope()
    local data, rms_mean, rms_max = Process_GetAudioData(REF_ITEM, REF_LEVELS)
    if not data then
        ClearReference()
        return false
    end

    -- RMS_MEAN keeps its sign: it is the level the Scale parameter pivots on
    REF_AUDIO_DATA, RMS_MEAN, RMS_MAX = data, rms_mean, rms_max
    REF_ANALYSIS_DONE = true
    return true
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

function InsertTrackEnvelope(envelope, remap, cur_pos)
    if not envelope then
        return
    end

    TARGET_ENV = envelope

    local position = cur_pos
    local handles = 0.05
    reaper.DeleteEnvelopePointRange(envelope, position, position + reaper.GetMediaItemInfo_Value(REF_ITEM, "D_LENGTH"))

    InsertEnvBoundaries(envelope, position, reaper.GetMediaItemInfo_Value(REF_ITEM, "D_LENGTH"), handles)

    if remap == true then
        Process_InsertNormData(REF_ITEM, TARGET_ENV, -1, REF_AUDIO_DATA, false, position)
    else
        Process_InsertVolumeData(REF_ITEM, TARGET_ENV, -1, REF_AUDIO_DATA, false, position)
    end

    EnvelopeVis(TARGET_ENV, true)
    reaper.UpdateTimeline()
end

function ApplyTakeEnvelope(take, takeEnv, isImpose)
    local item = reaper.GetMediaItemTake_Item(take)

    if item == REF_ITEM then
        return
    end

    local ret = nil


    TARGET_ENV = takeEnv
    TARGET_AI_IDX = -1

    local ret, envName = reaper.GetEnvelopeName(takeEnv)
    --reaper.ShowConsoleMsg(envName)

    if ret then
        if envName == "Volume" then
            if isImpose == true then
                ImposeTakeVolumeEnvelope(item, TARGET_ENV)
            else
                Process_InsertVolumeData(item, TARGET_ENV, TARGET_AI_IDX, REF_AUDIO_DATA, false, 0)
            end
        elseif envName == "Pitch" then
            Process_InsertPitchData(item, TARGET_ENV, TARGET_AI_IDX, REF_AUDIO_DATA, false, 0, PITCH_ENV_RANGE)
        elseif envName == "Pan" then
            Process_InsertPanData(item, TARGET_ENV, TARGET_AI_IDX, REF_AUDIO_DATA, false, 0)
        else
            Process_InsertNormData(item, TARGET_ENV, TARGET_AI_IDX, REF_AUDIO_DATA, false, 0)
        end
        --EnvelopeVis(TARGET_ENV, true)
        reaper.UpdateItemInProject(item)
    end
end

-- Writes on `env`, the take volume envelope of `item`, the correction that makes the item's
-- level follow the reference curve.
function ImposeTakeVolumeEnvelope(item, env)
    -- the item is analysed without its volume envelope, which is rewritten below
    TARGET_AUDIO_DATA = Process_GetAudioData(item, TARGET_LEVELS, env)
    TARGET_ANALYSIS_DONE = TARGET_AUDIO_DATA ~= nil

    if TARGET_ANALYSIS_DONE then
        local CorrectiveEnvelope = makeCorrectiveEnvelope(TARGET_AUDIO_DATA, REF_AUDIO_DATA)

        Process_InsertVolumeData(item, env, -1, CorrectiveEnvelope, true, 0)
        EnvelopeVis(env, true)
        reaper.UpdateItemInProject(item)
    end
end

function onExit()
    SetButtonState(0)
end

-- Curve caches: one per place the reference curve is drawn
local PLOT_CURVE = {}
local DRAG_CURVE = {}

-- The reference curve as points (xs, ys) inside a width x height box, ready to draw. Rebuilt only
-- when the analysis, a plot parameter or the box changes: a frame otherwise just draws lines.
local function GetPlotCurve(cache, width, height)
    local data = REF_AUDIO_DATA

    if
        cache.data == data and cache.mean == RMS_MEAN and cache.scale == scaling_factor_to_plot and
            cache.bottom == envelope_bottom_limit_to_plot and
            cache.top == envelope_top_limit_to_plot and
            cache.range == VOL_ENV_RANGE and
            cache.width == width and
            cache.height == height
     then
        return cache.xs, cache.ys
    end

    local n = #data
    local xs, ys = {}, {}

    local function y_at(i)
        local db =
            math.min(
            math.max((data[i] - RMS_MEAN) * scaling_factor_to_plot + RMS_MEAN, envelope_bottom_limit_to_plot),
            envelope_top_limit_to_plot
        )
        return map_db_to_pixels(db, height, VOL_ENV_RANGE)
    end

    if n <= 4 * math.max(1, math.floor(width)) then
        for i = 1, n do
            xs[i] = (i / n) * width
            ys[i] = y_at(i)
        end
    else
        -- more points than the box can show: the first, highest, lowest and last point of every
        -- pixel column draw the same picture with a fraction of the lines
        local count = 0
        local column, first_i, first_y, last_i, last_y, min_i, min_y, max_i, max_y

        local function emit(i, y)
            count = count + 1
            xs[count] = (i / n) * width
            ys[count] = y
        end

        local function flush()
            emit(first_i, first_y)
            local a_i, a_y, b_i, b_y = min_i, min_y, max_i, max_y
            if b_i < a_i then
                a_i, a_y, b_i, b_y = b_i, b_y, a_i, a_y
            end
            if a_i ~= first_i and a_i ~= last_i then
                emit(a_i, a_y)
            end
            if b_i ~= a_i and b_i ~= first_i and b_i ~= last_i then
                emit(b_i, b_y)
            end
            if last_i ~= first_i then
                emit(last_i, last_y)
            end
        end

        for i = 1, n do
            local y = y_at(i)
            local c = math.floor((i / n) * width)
            if c ~= column then
                if column then
                    flush()
                end
                column, first_i, first_y, min_i, min_y, max_i, max_y = c, i, y, i, y, i, y
            else
                if y < min_y then
                    min_i, min_y = i, y
                end
                if y > max_y then
                    max_i, max_y = i, y
                end
            end
            last_i, last_y = i, y
        end
        flush()
    end

    cache.data, cache.mean, cache.scale = data, RMS_MEAN, scaling_factor_to_plot
    cache.bottom, cache.top = envelope_bottom_limit_to_plot, envelope_top_limit_to_plot
    cache.range, cache.width, cache.height = VOL_ENV_RANGE, width, height
    cache.xs, cache.ys = xs, ys
    return xs, ys
end

-- Draws a curve from GetPlotCurve with its box origin at (x, y)
local function DrawPlotCurve(drawlist, xs, ys, x, y, color)
    local n = #xs
    if n < 2 then
        return
    end

    local prev_x, prev_y = x + xs[1], y + ys[1]
    -- lead-in from the left edge to the first point
    reaper.ImGui_DrawList_AddLine(drawlist, prev_x, prev_y, x, prev_y, color, 1)

    for i = 2, n do
        local point_x, point_y = x + xs[i], y + ys[i]
        reaper.ImGui_DrawList_AddLine(drawlist, point_x, point_y, prev_x, prev_y, color, 1)
        prev_x, prev_y = point_x, point_y
    end
end

function TransparentWindowForDraggingOutTheEnvelope()
    local mouse_x, mouse_y = reaper.ImGui_GetMousePos(ctx)

    -- Overlay senza bordi
    reaper.ImGui_SetNextWindowPos(ctx, mouse_x + 10, mouse_y - 17)

    local win_h = 60
    local win_w = 120

    reaper.ImGui_SetNextWindowSize(ctx, win_w, win_h)
    reaper.ImGui_SetNextWindowBgAlpha(ctx, 0) -- semi-trasparente
    local window_flags =
        reaper.ImGui_WindowFlags_NoDecoration() | reaper.ImGui_WindowFlags_NoBackground() |
        reaper.ImGui_WindowFlags_AlwaysAutoResize() |
        reaper.ImGui_WindowFlags_NoSavedSettings() |
        reaper.ImGui_WindowFlags_NoMove()

    local visible, open = reaper.ImGui_Begin(ctx, "Overlay", true, window_flags)
    if not visible then
        return
    end

    local offset_x = 0
    local offset_y = -10
    local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
    local xs, ys = GetPlotCurve(DRAG_CURVE, reaper.ImGui_GetWindowWidth(ctx), win_h)

    DrawPlotCurve(reaper.ImGui_GetForegroundDrawList(ctx), xs, ys, x + offset_x, y + offset_y, envelope_line_color)

    reaper.ImGui_End(ctx)
end

function plotWindow()
    reaper.ImGui_PushFont(ctx, comic_sans_small, comic_sans_small_size)
    reaper.ImGui_TextColored(ctx, reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 0.8), tostring(VOL_ENV_RANGE) .. "dB")
    -- .. " (" .. tostring(math.floor(ENV_RANGE + envelope_offset)) .. "dB)")

    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 0)

    local drawlist = reaper.ImGui_GetWindowDrawList(ctx)
    local rect_x, rect_y = reaper.ImGui_GetCursorScreenPos(ctx)
    local rect_width = reaper.ImGui_GetWindowWidth(ctx)

    --reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ChildRounding(), 0)

    if
        reaper.ImGui_BeginChild(
            ctx,
            "PlotWindow",
            reaper.ImGui_GetWindowWidth(ctx) - 15,
            PLOT_WINDOW_HEIGHT,
            reaper.ImGui_ChildFlags_FrameStyle() | reaper.ImGui_ChildFlags_AutoResizeX() |
                reaper.ImGui_ChildFlags_AutoResizeY() |
                reaper.ImGui_ChildFlags_AlwaysAutoResize(),
            reaper.ImGui_WindowFlags_NoScrollbar()
        )
     then
        local guide_text_x, guide_text_y = reaper.ImGui_GetCursorScreenPos(ctx)

        DragOutEnvelope()
        -- original simple color logic: orange when not dragging, random when dragging
        --local window_height = reaper.ImGui_GetWindowHeight(ctx)
        local offset_x = -4.5
        local offset_y = -2.5

        if REF_AUDIO_DATA ~= nil then
            local color = envelope_line_color

            if drag_operation_started then
                color = reaper.ImGui_ColorConvertDouble4ToU32(0.1, 0.1, 0.1, 1)
                TransparentWindowForDraggingOutTheEnvelope()
            end

            local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
            local plot_width = reaper.ImGui_GetWindowWidth(ctx)
            local xs, ys = GetPlotCurve(PLOT_CURVE, plot_width, PLOT_WINDOW_HEIGHT)

            DrawPlotCurve(drawlist, xs, ys, x + offset_x, y + offset_y, color)

            local top_limit_y = map_db_to_pixels(envelope_top_limit_to_plot, PLOT_WINDOW_HEIGHT, VOL_ENV_RANGE)
            local bottom_limit_y = map_db_to_pixels(envelope_bottom_limit_to_plot, PLOT_WINDOW_HEIGHT, VOL_ENV_RANGE)
            local limit_color = reaper.ImGui_ColorConvertDouble4ToU32(0.4, 0.4, 0.4, 1)

            reaper.ImGui_DrawList_AddLine(
                drawlist,
                x + offset_x,
                y + top_limit_y + offset_y - 1,
                x + plot_width + offset_x,
                y + top_limit_y + offset_y - 1,
                limit_color,
                1
            )

            reaper.ImGui_DrawList_AddLine(
                drawlist,
                x + offset_x,
                y + bottom_limit_y + offset_y + 1,
                x + plot_width + offset_x,
                y + bottom_limit_y + offset_y + 1,
                limit_color,
                1
            )
        end

        reaper.ImGui_DrawList_AddRect(
            reaper.ImGui_GetForegroundDrawList(ctx),
            rect_x - 1,
            rect_y - 1,
            rect_x + rect_width - 15 + 1,
            rect_y + PLOT_WINDOW_HEIGHT + 1,
            reaper.ImGui_ColorConvertDouble4ToU32(0.3, 0.3, 0.3, 1),
            0,
            reaper.ImGui_DrawFlags_None(),
            1
        )

        if reaper.ImGui_IsWindowHovered(ctx) and drag_operation_started == false and REF_ITEM ~= -1 then
            reaper.ImGui_DrawList_AddRectFilled(
                drawlist,
                rect_x - 1,
                rect_y - 1,
                rect_x + rect_width - 15 + 1,
                rect_y + PLOT_WINDOW_HEIGHT + 1,
                reaper.ImGui_ColorConvertDouble4ToU32(0.3, 0.3, 0.3, 0.5),
                0,
                reaper.ImGui_DrawFlags_None()
            )

            reaper.ImGui_DrawList_AddRect(
                reaper.ImGui_GetForegroundDrawList(ctx),
                rect_x - 1,
                rect_y - 1,
                rect_x + rect_width - 15 + 1,
                rect_y + PLOT_WINDOW_HEIGHT + 1,
                reaper.ImGui_ColorConvertDouble4ToU32(0.8, 0.8, 0.8, 1),
                0,
                reaper.ImGui_DrawFlags_None(),
                1
            )

            reaper.ImGui_PushFont(ctx, comic_sans, comic_sans_size)

            reaper.ImGui_SetCursorScreenPos(
                ctx,
                guide_text_x + reaper.ImGui_GetWindowWidth(ctx) * 0.5 - 150,
                guide_text_y + PLOT_WINDOW_HEIGHT * 0.5 - 10
            )

            reaper.ImGui_TextColored(
                ctx,
                reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 1),
                "Drag and drop on Envelopes or Items"
            )

            reaper.ImGui_PopFont(ctx)
        end

        reaper.ImGui_EndChild(ctx)
    end

    reaper.ImGui_PopStyleVar(ctx)

    reaper.ImGui_TextColored(ctx, reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 0.8), "-150dB")

    reaper.ImGui_PopFont(ctx)
end

-- Called right after a parameter slider; retval is what the slider returned.
-- reanalyse: false for the parameters applied after the analysis (scale, limits, offset),
-- which only need the plot and the last drop target refreshed.
function updateAfterSliderValueChange(retval, reanalyse)
    -- continuous update reacts to every change of the value, the other mode only once the
    -- slider is let go
    if update_only_on_slider_release then
        if not reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then
            return
        end
    elseif not retval then
        return
    end

    -- require a valid reference item
    if REF_ITEM == -1 then
        return
    end

    envelope_bottom_limit_to_plot = envelope_bottom_limit
    envelope_top_limit_to_plot = envelope_top_limit
    scaling_factor_to_plot = scaling_factor

    if reanalyse and not AnalyseReferenceEnvelope() then
        return
    end

    if not auto_update or was_last_drop_on_item == nil then
        return
    end

    if was_last_drop_on_item == true then
        if reaper.ValidatePtr(last_take, "MediaItem_Take*") then
            ApplyTakeEnvelope(last_take, last_envelope, impose_envelope_on_items)
        end
    elseif reaper.ValidatePtr(last_envelope, "TrackEnvelope*") then
        local _, env_name = reaper.GetEnvelopeName(last_envelope)

        reaper.Undo_BeginBlock()
        InsertTrackEnvelope(last_envelope, env_name ~= "Volume", last_cursor_position)
        reaper.Undo_EndBlock("Envelope Dropped", 0)
    end
end

function TextLink(ctx, text, normalColor, hoverColor)
    local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
    -- colore normale
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), normalColor)
    reaper.ImGui_Text(ctx, text)
    reaper.ImGui_PopStyleColor(ctx)

    -- se hover, ridisegna con colore hover
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_SetCursorScreenPos(ctx, x, y)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), hoverColor)
        reaper.ImGui_Text(ctx, text)
        reaper.ImGui_PopStyleColor(ctx)

        -- cambia cursore
        reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
    end

    -- ritorna true se cliccato
    return reaper.ImGui_IsItemClicked(ctx)
end

function drawIconButton(name, image, width, height, tint_color, is_toggled)
    -- tint_color: U32 color for the image tint (optional)
    -- is_toggled: optional boolean, when true button appears active
    local buttonPressed = false

    local image_tint = tint_color

    if is_toggled then
        image_tint = envelope_line_color
    else
        image_tint = reaper.ImGui_ColorConvertDouble4ToU32(0.8, 0.8, 0.8, 1)
    end

    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 0))
    reaper.ImGui_PushStyleColor(
        ctx,
        reaper.ImGui_Col_ButtonHovered(),
        reaper.ImGui_ColorConvertDouble4ToU32(0, 0, 0, 0)
    )
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), reaper.ImGui_ColorConvertDouble4ToU32(0, 0, 0, 0))

    -- ImGui_ImageButton expects background color first, then tint color
    if
        reaper.ImGui_ImageButton(
            ctx,
            name,
            image,
            width,
            height,
            0,
            0,
            1,
            1,
            reaper.ImGui_ColorConvertDouble4ToU32(0, 0, 0, 0),
            image_tint
        )
     then
        buttonPressed = true
    end

    reaper.ImGui_PopStyleColor(ctx)
    reaper.ImGui_PopStyleColor(ctx)
    reaper.ImGui_PopStyleColor(ctx)

    return buttonPressed
end

function mainWindow()
    -- CHECK ITEMS
    if not reaper.ValidatePtr2(0, REF_ITEM, "MediaItem*") then
        ClearReference()
    end

    if was_last_drop_on_item == true then
        -- the take can outlive the envelope that was dropped on
        if reaper.ValidatePtr(last_take, "MediaItem_Take*") == false or not TakeHasEnvelope(last_take, last_envelope) then
            last_take = nil
            was_last_drop_on_item = nil
            target_time = nil
            target_name = ""
            lock_target = false
            last_envelope = nil
        end
    elseif was_last_drop_on_item == false then
        if reaper.ValidatePtr(last_envelope, "TrackEnvelope*") == false then
            last_envelope = nil
            was_last_drop_on_item = nil
            last_cursor_position = nil
            target_time = nil
            target_name = ""
            lock_target = false
        end
    end

    -- SET REF_ITEM BUTTON

    reaper.ImGui_BeginDisabled(ctx, reaper.CountSelectedMediaItems(0) == 0)

    if reaper.ImGui_Button(ctx, "Set Reference Item") then
        ClearReference()

        TARGET_ANALYSIS_DONE = false
        TARGET_ENV = nil
        TARGET_AI_IDX = nil
        TARGET_AUDIO_DATA = nil

        REF_ITEM = reaper.GetSelectedMediaItem(0, 0)
        -- setting the reference always reads its audio again
        REF_LEVELS.item = nil

        AnalyseReferenceEnvelope()
    end

    reaper.ImGui_EndDisabled(ctx)

    -- REF ITEM NAME TEXT
    if REF_ITEM ~= -1 then
        local stringNeedBig = ""
        local ref_take = reaper.GetActiveTake(REF_ITEM)

        if ref_take then
            local _
            _, stringNeedBig = reaper.GetSetMediaItemTakeInfo_String(ref_take, "P_NAME", "", false)
        end

        if string.len(stringNeedBig) > 90 then
            stringNeedBig = string.sub(stringNeedBig, 0, 90) .. "..."
        end

        reaper.ImGui_SameLine(ctx)
        TextLink(
            ctx,
            stringNeedBig,
            reaper.ImGui_ColorConvertDouble4ToU32(0.85, 0.85, 0.85, 1),
            reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 1)
        )
        --reaper.ImGui_Text(ctx, stringNeedBig)
        if reaper.ImGui_IsItemClicked(ctx) then
            reaper.SetEditCurPos(reaper.GetMediaItemInfo_Value(REF_ITEM, "D_POSITION"), true, false)
            reaper.Main_OnCommand(40289, 0)
            reaper.SetMediaItemSelected(REF_ITEM, true)
        end
    end

    reaper.ImGui_NewLine(ctx)

    -- ANALYSIS PARAMETERS

    reaper.ImGui_BeginDisabled(ctx, not REF_ANALYSIS_DONE)


    local retval, v = reaper.ImGui_SliderDouble(ctx, "Definition", definition, 0.001, 1)

    if v <= 0 then v = definition end

    if retval and REF_ITEM ~= -1 then
        definition = v
        window_sec = math.max(1 - remapCurve(definition * 1, 0.05), 0.001)
    end

    updateAfterSliderValueChange(retval, true)

    reaper.ImGui_NewLine(ctx)

    local retval, v = reaper.ImGui_SliderDouble(ctx, "Gain (dB)", gain, -30, 60)
    if retval and REF_ITEM ~= -1 then
        gain = v
    end

    updateAfterSliderValueChange(retval, true)

    local retval, v = reaper.ImGui_SliderDouble(ctx, "Compress", compression, 0, 1)
    if retval and REF_ITEM ~= -1 then
        compression = v
    end

    updateAfterSliderValueChange(retval, true)

    local retval, a_ms = reaper.ImGui_SliderDouble(ctx, "Attack (ms)", attack_ms, 0.01, 100)
    if retval and REF_ITEM ~= -1 then
        attack_ms = a_ms
    end

    updateAfterSliderValueChange(retval, true)

    local retval, r_ms = reaper.ImGui_SliderDouble(ctx, "Release (ms)", release_ms, 0.01, 100)
    if retval and REF_ITEM ~= -1 then
        release_ms = r_ms
    end

    updateAfterSliderValueChange(retval, true)


    local retval, v = reaper.ImGui_SliderDouble(ctx, "Scale", scaling_factor, -10, 10)

    if retval and REF_ITEM ~= -1 then
        scaling_factor = v
    end

    updateAfterSliderValueChange(retval, false)

    reaper.ImGui_NewLine(ctx)
    local retval, v1, v2 =
        reaper.ImGui_SliderDouble2(ctx, "Limits (dB)", envelope_bottom_limit, envelope_top_limit, -150, 90)

    if retval and REF_ITEM ~= -1 then
        envelope_bottom_limit = v1
        envelope_top_limit = v2
    end

    updateAfterSliderValueChange(retval, false)

    reaper.ImGui_EndDisabled(ctx)

    -- CONTINUOUS ENVELOPE TOGGLE

    reaper.ImGui_BeginDisabled(ctx, REF_ITEM == -1)

    reaper.ImGui_NewLine(ctx)
    local retval, v =
        reaper.ImGui_Checkbox(ctx, "##Update analysis only on slider release", update_only_on_slider_release)

    if retval then
        update_only_on_slider_release = v
    end

    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_Text(ctx, "Update analysis only on slider release")

    reaper.ImGui_EndDisabled(ctx)

    -- IMPOSE ENVELOPE ON ITEMS TOGGLE

    reaper.ImGui_NewLine(ctx)

    reaper.ImGui_BeginDisabled(ctx, REF_ITEM == -1)

    local retval, v = reaper.ImGui_Checkbox(ctx, "##Impose envelope on target item volume", impose_envelope_on_items)

    if retval then
        impose_envelope_on_items = v

        if was_last_drop_on_item ~= nil and auto_update and was_last_drop_on_item == true then
            ApplyTakeEnvelope(last_take, last_envelope, impose_envelope_on_items)
        end
    end

    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_Text(ctx, "Impose envelope on target item volume")

    reaper.ImGui_EndDisabled(ctx)

    -- ENVELOPE PLOT WINDOW

    reaper.ImGui_NewLine(ctx)

    plotWindow()

    reaper.ImGui_NewLine(ctx)

    reaper.ImGui_BeginDisabled(ctx, not REF_ANALYSIS_DONE)

    local retval, v = reaper.ImGui_SliderDouble(ctx, "Post Analysis Offset (dB)", envelope_offset, -150, 90)

    if retval and REF_ITEM ~= -1 then
        envelope_offset = v
    end

    updateAfterSliderValueChange(retval, false)

    reaper.ImGui_EndDisabled(ctx)

    reaper.ImGui_BeginDisabled(ctx, was_last_drop_on_item == nil or REF_ITEM == -1)

    reaper.ImGui_NewLine(ctx)

    -- TARGET ITEM NAME TEXT

    TextLink(
        ctx,
        "Last Drop Target: " .. target_name,
        reaper.ImGui_ColorConvertDouble4ToU32(0.85, 0.85, 0.85, 1),
        reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 1)
    )

    if was_last_drop_on_item ~= nil then
        if reaper.ImGui_IsItemClicked(ctx) then
            if was_last_drop_on_item == true then
                reaper.SetEditCurPos(
                    reaper.GetMediaItemInfo_Value(reaper.GetMediaItemTake_Item(last_take), "D_POSITION"),
                    true,
                    false
                )
                reaper.Main_OnCommand(40289, 0)
                reaper.SetMediaItemSelected(reaper.GetMediaItemTake_Item(last_take), true)
            else
                reaper.SetEditCurPos(last_cursor_position, true, false)
                EnvelopeVis(last_envelope, true)
                reaper.UpdateTimeline()
            end
        end

        reaper.ImGui_PushFont(ctx, comic_sans_small, comic_sans_small_size)
        reaper.ImGui_TextColored(
            ctx,
            reaper.ImGui_ColorConvertDouble4ToU32(0.8, 0.8, 0.8, 1),
            string.sub(reaper.format_timestr_pos(target_time, "", -1), -11) .. "\n\n"
        )
        reaper.ImGui_PopFont(ctx)
    else
        reaper.ImGui_PushFont(ctx, comic_sans_small, comic_sans_small_size)
        reaper.ImGui_TextColored(ctx, reaper.ImGui_ColorConvertDouble4ToU32(0.8, 0.8, 0.8, 1), "\n\n")
        reaper.ImGui_PopFont(ctx)
    end

    reaper.ImGui_EndDisabled(ctx)

    -- LOCK TARGET TOGGLE

    reaper.ImGui_BeginDisabled(ctx, was_last_drop_on_item == nil)

    local retval, v = reaper.ImGui_Checkbox(ctx, "##Lock Last Drop Target", lock_target)

    if retval then
        lock_target = v
    end

    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_Text(ctx, "Lock Last Drop Target")

    reaper.ImGui_EndDisabled(ctx)

    -- AUTO UPDATE TOGGLE

    reaper.ImGui_BeginDisabled(ctx, was_last_drop_on_item == nil)

    local retval, v =
        reaper.ImGui_Checkbox(ctx, "##Automatically update Last Drop Target on paramters change", auto_update)

    if retval then
        auto_update = v
    end

    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_Text(ctx, "Automatically update Last Drop Target on paramters change")

    reaper.ImGui_EndDisabled(ctx)
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

function EnsureItemVolumeEnv(chunk, take_index)
    take_index = take_index or 0

    -- prepara blocco VOLENV standard (già attivo e visibile, come quello di traccia)
    local volenv =
        [[
<VOLENV
EGUID ]] ..
        reaper.genGuid() .. "\n" .. [[
ACT 1 -1
VIS 1 1 1
LANEHEIGHT 0 0
ARM 0
DEFSHAPE 0 -1 -1
VOLTYPE 1
PT 0 1 0
>]]

    -- Nel chunk di un item le righe della PRIMA take (compresi i suoi
    -- envelope: il VOLENV è direttamente sotto <ITEM) seguono le righe
    -- dell'item, mentre ogni take successiva è un blocco <TAKE>.
    -- I blocchi sono indentati: i match tollerano gli spazi a inizio riga.
    local lines = {}
    for line in chunk:gmatch("[^\r\n]*") do
        lines[#lines + 1] = line
    end

    -- sezione con i campi della take richiesta + punto di inserimento
    local check_start = nil
    local check_end = nil
    local insert_at = nil

    if take_index == 0 then
        -- prima take: dall'inizio al primo blocco <TAKE
        -- (o fino alla chiusura di <ITEM se l'item ha una sola take)
        check_start = 1
        local first_take = nil
        for idx = 2, #lines do
            if lines[idx]:match("^%s*<TAKE%s*$") then
                first_take = idx
                break
            end
        end
        if first_take then
            check_end = first_take - 1
            insert_at = first_take -- prima del primo blocco <TAKE
        else
            insert_at = #lines
            while insert_at >= 1 and lines[insert_at] == "" do
                insert_at = insert_at - 1
            end
            check_end = insert_at - 1 -- riga prima della > che chiude <ITEM
        end
    else
        -- take_index = 1 è il primo blocco <TAKE, e così via
        local depth = 0
        local take_idx = 0
        local target_depth = nil
        for idx, line in ipairs(lines) do
            if line:match("^%s*<[A-Z]") then
                if line:match("^%s*<TAKE%s*$") and target_depth == nil then
                    take_idx = take_idx + 1
                    if take_idx == take_index then
                        check_start = idx
                        target_depth = depth + 1
                    end
                end
                depth = depth + 1
            elseif line:match("^%s*>%s*$") then
                depth = depth - 1
                if target_depth ~= nil and depth == target_depth - 1 then
                    check_end = idx
                    insert_at = idx -- prima della > che chiude il blocco <TAKE
                    break
                end
            end
        end
    end

    if not check_start or not check_end or check_end < check_start then
        return chunk -- take non trovata: chunk invariato
    end

    -- la take ha già un VOLENV? se è disattivo, lo attivo (ACT 1)
    local env_start = nil
    local env_depth = 0
    local env_end = nil
    for idx = check_start, check_end do
        if env_start == nil then
            if lines[idx]:match("^%s*<VOLENV%s*$") then
                env_start = idx
                env_depth = 1
            end
        else
            if lines[idx]:match("^%s*<[A-Z]") then
                env_depth = env_depth + 1
            elseif lines[idx]:match("^%s*>%s*$") then
                env_depth = env_depth - 1
                if env_depth == 0 then
                    env_end = idx
                    break
                end
            end
        end
    end

    if env_start and env_end then
        local changed = false
        for idx = env_start + 1, env_end - 1 do
            local new_line = lines[idx]:gsub("^(%s*)ACT %d", "%1ACT 1")
            if new_line ~= lines[idx] then
                lines[idx] = new_line
                changed = true
            end
        end
        if changed then
            return table.concat(lines, "\n")
        end
        return chunk -- già attivo
    end

    -- nessun VOLENV: lo inserisco nel punto di inserimento
    local volenv_lines = {}
    for line in volenv:gmatch("[^\r\n]*") do
        volenv_lines[#volenv_lines + 1] = line
    end
    for i = #volenv_lines, 1, -1 do
        table.insert(lines, insert_at, volenv_lines[i])
    end

    return table.concat(lines, "\n")
end

function InsertEnvBoundaries(env, time, length, handles)
    if not env then
        return
    end

    local _, val_before = reaper.Envelope_Evaluate(env, time - handles, 0, 0)
    local _, val_after = reaper.Envelope_Evaluate(env, time + length + handles, 0, 0)

    reaper.DeleteEnvelopePointRange(env, time - handles, time - handles)
    reaper.DeleteEnvelopePointRange(env, time + length + handles, time + length + handles)
    reaper.InsertEnvelopePoint(env, time - handles, val_before, 0, 0, false, true)
    reaper.InsertEnvelopePoint(env, time + length + handles, val_after, 0, 0, false, true)
    reaper.Envelope_SortPoints(env)
end

function SaveDropInformations(env, is_item, position)
    if is_item then
        local take, index, index2 = reaper.Envelope_GetParentTake(env)
        last_take = take
        local item = reaper.GetMediaItemTake_Item(take)
        --if last_take ~= nil then  reaper.ShowConsoleMsg('HELLO\n') end
        was_last_drop_on_item = true
        last_envelope = env
        local ret, item_name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)

        if string.len(item_name) > 70 then
            item_name = string.sub(item_name, 0, 70) .. "..."
        end

        local ret, track_name = reaper.GetTrackName(reaper.GetMediaItem_Track(item))
        local ret, env_name = reaper.GetEnvelopeName(env)
        target_name = track_name .. "/Item/" .. item_name .. "/" .. env_name
        target_time = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    else
        last_envelope = env
        was_last_drop_on_item = false
        last_cursor_position = position
        local ret, track_name = reaper.GetTrackName(reaper.Envelope_GetParentTrack(env))
        local ret, env_name = reaper.GetEnvelopeName(env)
        target_name = track_name .. "/Envelope/" .. env_name
        target_time = position
    end
end

function DragOutEnvelope()
    local l_mouse_down = reaper.ImGui_IsMouseDown(ctx, reaper.ImGui_MouseButton_Left())

    if l_mouse_down and drag_operation_started == true then
        reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
    end

    if
        l_mouse_down and drag_operation_started == false and reaper.ImGui_IsWindowHovered(ctx) and REF_ANALYSIS_DONE and
            REF_ITEM
     then
        drag_operation_started = true
        reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
    -- start drag
    end

    if l_mouse_down == false and drag_operation_started == true then
        reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Arrow())
        drag_operation_started = false
        -- end drag

        --local take, position = reaper.BR_TakeAtMouseCursor()

        reaper.BR_GetMouseCursorContext()
        local takeEnv, isTakeEnv = reaper.BR_GetMouseCursorContext_Envelope()

        if isTakeEnv == true then --- BLOCCO DROP SU ITEM
            if REF_ITEM ~= -1 and REF_ANALYSIS_DONE == true then
                local take, index, index2 = reaper.Envelope_GetParentTake(takeEnv)

                if REF_ITEM == reaper.GetMediaItemTake_Item(take) then
                    return
                end

                reaper.Undo_BeginBlock()
                ApplyTakeEnvelope(take, takeEnv, impose_envelope_on_items)

                if lock_target == false then
                    SaveDropInformations(takeEnv, true, reaper.GetCursorPosition())
                end

                reaper.Undo_EndBlock("Envelope Dropped", 0)
                return
            end
        end --- BLOCCO DROP SU ITEM

        local take, position = reaper.BR_TakeAtMouseCursor()

        if reaper.ValidatePtr(take, "MediaItem_Take*") then
            if REF_ITEM ~= -1 and REF_ANALYSIS_DONE == true then
                if REF_ITEM == reaper.GetMediaItemTake_Item(take) then
                    return
                end

                local item = reaper.GetMediaItemTake_Item(take)
                local env = reaper.GetTakeEnvelopeByName(take, "Volume")

                if not reaper.ValidatePtr2(0, env, "TrackEnvelope*") then
                    local ret, str = reaper.GetItemStateChunk(item, "", false)
                    if ret then
                        local take_index = 0
                        for i = 0, reaper.CountTakes(item) - 1 do
                            if reaper.GetMediaItemTake(item, i) == take then
                                take_index = i
                                break
                            end
                        end
                        reaper.SetItemStateChunk(item, EnsureItemVolumeEnv(str, take_index), false)
                        -- la take può essere ricreata dal chunk: la ricavano per indice
                        take = reaper.GetMediaItemTake(item, take_index)
                        env = reaper.GetTakeEnvelopeByName(take, "Volume")
                    end
                end

                if not reaper.ValidatePtr2(0, env, "TrackEnvelope*") then
                    return
                end

                EnvelopeVis(env, true)
                reaper.Undo_BeginBlock()

                ApplyTakeEnvelope(take, env, impose_envelope_on_items)

                if lock_target == false then
                    SaveDropInformations(env, true, reaper.GetCursorPosition())
                end

                reaper.Undo_EndBlock("Envelope Dropped", 0)
                return
            end
        end

        local track, context, position = reaper.BR_TrackAtMouseCursor()

        --- BLOCCO DROP SU TRACCIA
        if reaper.ValidatePtr(track, "MediaTrack*") and context == 2 then
            local destination_envelope = reaper.GetTrackEnvelopeByName(track, "Volume")

            if not reaper.ValidatePtr(destination_envelope, "TrackEnvelope*") then
                local retval, str = reaper.GetTrackStateChunk(track, "", false)
                if retval then
                    reaper.SetTrackStateChunk(track, EnsureTrackVolumeEnvelope(str), false)
                    destination_envelope = reaper.GetTrackEnvelopeByName(track, "Volume")
                end
            end
            if not reaper.ValidatePtr(destination_envelope, "TrackEnvelope*") then
                return
            end
            reaper.Undo_BeginBlock()
            InsertTrackEnvelope(destination_envelope, false, reaper.GetCursorPosition())
            reaper.Undo_EndBlock("Envelope Dropped", 0)
            if lock_target == false then
                SaveDropInformations(destination_envelope, false, reaper.GetCursorPosition())
            end
            return
        end
        --- BLOCCO DROP SU TRACCIA

        --- BLOCCO DROP SU ENVELOPE TRACK
        reaper.BR_GetMouseCursorContext()

        local track_env, is_take = reaper.BR_GetMouseCursorContext_Envelope()

        if track_env then
            local trk, info = reaper.GetThingFromPoint(reaper.GetMousePosition())
            local track, i1, i2 = reaper.Envelope_GetParentTrack(track_env)
            -- over an envelope lane info is "envelope <index>"
            local idx = tonumber((info or ""):match("(%d+)"))
            if not idx then
                return
            end
            local env0 = reaper.GetTrackEnvelope(track, math.floor(idx))
            if not env0 then
                return
            end
            local retval, env_name = reaper.GetEnvelopeName(track_env)

            --local r, s = reaper.GetEnvelopeStateChunk(env0, "", false)

            if env_name == "Volume" then
                reaper.Undo_BeginBlock()
                InsertTrackEnvelope(env0, false, reaper.GetCursorPosition())
                reaper.Undo_EndBlock("Envelope Dropped", 0)
                if lock_target == false then
                    SaveDropInformations(env0, false, reaper.GetCursorPosition())
                end
                return
            else
                reaper.Undo_BeginBlock()
                InsertTrackEnvelope(env0, true, reaper.GetCursorPosition())
                reaper.Undo_EndBlock("Envelope Dropped", 0)
                if lock_target == false then
                    SaveDropInformations(env0, false, reaper.GetCursorPosition())
                end
                return
            end
        end
    --- BLOCCO DROP SU ENVELOPE TRACK
    end
end

local last_ranges_poll = nil

-- The envelope ranges come from reaper.ini, which is read from disk: once a second is enough
local function UpdateEnvelopeRanges()
    local now = reaper.time_precise()
    if last_ranges_poll and now - last_ranges_poll < 1 then
        return
    end
    last_ranges_poll = now

    local ini_file = reaper.get_ini_file()
    local _, val = reaper.BR_Win32_GetPrivateProfileString("REAPER", "volenvrange", "", ini_file)

    if val == "5" then
        VOL_ENV_RANGE = 6
    elseif val == "6" then
        VOL_ENV_RANGE = 12
    elseif val == "7" then
        VOL_ENV_RANGE = 24
    else
        VOL_ENV_RANGE = 0
    end

    _, val = reaper.BR_Win32_GetPrivateProfileString("REAPER", "pitchenvrange", "", ini_file)
    -- kept as a number; a missing or unreadable entry leaves the previous range
    PITCH_ENV_RANGE = tonumber(val) or PITCH_ENV_RANGE
end

function loop()
    UpdateEnvelopeRanges()

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
        -- Whatever changes the project state while the window runs is this script writing
        -- envelopes, which leaves the analysed audio as it was: the raw analysis caches follow.
        local state_before = reaper.GetProjectStateChangeCount(0)

        mainWindow()

        local state_after = reaper.GetProjectStateChangeCount(0)
        if state_after ~= state_before then
            if REF_LEVELS.state == state_before then
                REF_LEVELS.state = state_after
            end
            if TARGET_LEVELS.state == state_before then
                TARGET_LEVELS.state = state_after
            end
        end

        reaper.ImGui_End(ctx)
    end

    guiStylePop()

    if mw_open then
        reaper.defer(loop)
    end
end

SetButtonState(1)
reaper.defer(loop)
reaper.atexit(onExit)
