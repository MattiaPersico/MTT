-- mtt_Shelf.lua - Action Favorites Manager (Safe Styling)

package.path = reaper.ImGui_GetBuiltinPath() .. "/?.lua"
local ImGui = require "imgui" "0.10"
local ctx = reaper.ImGui_CreateContext("mtt_Shelf", reaper.ImGui_ConfigFlags_DockingEnable())
local FAVORITES_FILENAME = ".mtt_shelf.txt"
local favorites = {}

-- Variabili per la gestione della selezione azione (solo per aggiunta)
local is_adding_action = false
local proj_name = reaper.GetProjectName(0)
local os = reaper.GetOS()
local superKeyString = ""
local hasToBeRemoved = {}

-- Flag richiesta apertura popup FX (aperto a livello window, non dentro i child)
local open_fx_popup = false

-- Filtro dei formati nel popup FX: lo stato sopravvive alla apertura/chiusura dello script.
-- Un formato controlla anche la versione instrument omonima (VST filtra VSTi, ecc.)
local format_filters = {VST = true, VST3 = true, AU = true, JS = true, CLAP = true}

-- Prefissi di formato riconosciuti: servono a strappare il nome pulito
-- dall'estetica del bottone (strip_fx_prefix).
local FORMAT_PREFIXES = {VST = true, VST3 = true, AU = true, JS = true, CLAP = true}

function LoadAllFX()
    local raw_fx = {}
    local idx = 0
    while true do
        local ok, name, ident = reaper.EnumInstalledFX(idx)
        if not ok then
            break
        end
        table.insert(raw_fx, {name = name, ident = ident})
        idx = idx + 1
    end

    -- Priorità: più basso è il numero, più alta è la priorità. CLAP entra in cima,
    -- così un plugin presente in più formati mantiene la versione CLAP.
    local priority_map = {
        ["CLAP"] = 0,
        ["VST3"] = 1,
        ["AU"] = 2,
        ["VST"] = 3,
        ["JS"] = 4
    }

    local best_fx = {}
    local seen_names = {}

    for _, fx in ipairs(raw_fx) do
        local name = fx.name
        local ident = fx.ident

        -- Extract format from identifier (e.g., "VST3:...", "AU:...", etc.)
        local format = ""
        if string.find(ident, "^CLAP:") then
            format = "CLAP"
        elseif string.find(ident, "^VST3:") then
            format = "VST3"
        elseif string.find(ident, "^AU:") then
            format = "AU"
        elseif string.find(ident, "^VST:") then
            format = "VST"
        elseif string.find(ident, "^JS:") then
            format = "JS"
        else
            format = "OTHER"
        end

        local prio = priority_map[format] or 5

        local clean_name = name
        clean_name = string.gsub(clean_name, "^CLAP: ", "")
        clean_name = string.gsub(clean_name, "^VST3: ", "")
        clean_name = string.gsub(clean_name, "^AU: ", "")
        clean_name = string.gsub(clean_name, "^VST: ", "")
        clean_name = string.gsub(clean_name, "^JS: ", "")

        if seen_names[clean_name] == nil then
            seen_names[clean_name] = {name = name, ident = ident, prio = prio}
        else
            if prio < seen_names[clean_name].prio then
                seen_names[clean_name] = {name = name, ident = ident, prio = prio}
            end
        end
    end

    local fx_list = {}
    for _, data in pairs(seen_names) do
        table.insert(fx_list, {name = data.name, ident = data.ident})
    end

    table.sort(
        fx_list,
        function(a, b)
            return a.name < b.name
        end
    )

    return fx_list
end

local fx_list = LoadAllFX()
local fx_filter = ""

if os:find("Win") then
    superKeyString = "Ctrl"
elseif os:find("OSX") or os:find("macOS") then
    superKeyString = "Cmd"
end

-- ==========================================
-- Utility: Random String
-- ==========================================

function generate_random_string(length)
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local len = #chars
    local result = ""
    for i = 1, length do
        local idx = math.random(1, len)
        result = result .. chars:sub(idx, idx)
    end
    return result
end

-- ==========================================
-- Data Management
-- ==========================================

local MAIN_SECTION = 0

function get_action_name(action_id)
    local name = reaper.kbd_getTextFromCmd(action_id, -1)

    if name == "" or name == nil then
        return "<Azione sconosciuta o non trovata>"
    end

    return name
end

function load_favorites()
    local path = reaper.GetProjectPath()
    if not path or path == "" then
        return {}
    end

    local filepath = string.format("%s/%s", path, FAVORITES_FILENAME)
    local file, err = io.open(filepath, "r")
    if not file then
        return {}
    end

    local content = file:read("*a")
    file:close()

    favorites = {}
    for line in content:gmatch("[^\n]+") do
        -- Skip empty lines
        if line == "" then
            goto continue
        end

        -- Try new format first: A|id||name  OR  F||ident|name
        local fav_type, part2, part3, name_val = line:match("^([AF])|([^|]*)|([^|]*)|(.+)$")

        if fav_type then
            if fav_type == "A" then
                local id_val = tonumber(part2)
                if id_val and id_val > 0 then
                    table.insert(favorites, {type = "action", id = id_val, name = name_val})
                end
            elseif fav_type == "F" then
                -- part2 should be empty for FX, ident is in part3
                local fx_ident = part3
                if fx_ident and fx_ident ~= "" then
                    table.insert(favorites, {type = "fx", ident = fx_ident, name = name_val})
                end
            end
            goto continue
        end

        -- Fallback to old format: id|name (where id starts with a digit)
        local old_id_str, old_name = line:match("^(%d+)|(.+)$")
        if old_id_str and old_name then
            table.insert(favorites, {type = "action", id = tonumber(old_id_str), name = old_name})
        end

        ::continue::
    end
end

function save_favorites()
    local path = reaper.GetProjectPath()
    if not path or path == "" then
        return
    end

    local filepath = string.format("%s/%s", path, FAVORITES_FILENAME)
    local file, err = io.open(filepath, "w")
    if not file then
        return
    end

    for _, fav in ipairs(favorites) do
        if fav.type == "action" and fav.id and fav.id > 0 and fav.name then
            -- Format: A|id||name
            file:write(string.format("A|%d||%s\n", fav.id, fav.name))
        elseif fav.type == "fx" and fav.ident and fav.name then
            -- Format: F||ident|name
            file:write(string.format("F||%s|%s\n", fav.ident, fav.name))
        end
    end
    file:close()
end
-- Il filtro formati è una preferenza della libreria di plugin, non del progetto:
-- viene salvato nella config directory di REAPER, non nel progetto come i favorites.
local FORMAT_FILTERS_FILENAME = ".mtt_shelf_format_filters.txt"

function load_format_filters()
    local filepath = reaper.GetResourcePath() .. FORMAT_FILTERS_FILENAME
    local file, err = io.open(filepath, "r")
    if not file then
        return
    end

    local content = file:read("*a")
    file:close()

    for line in content:gmatch("[^\n]+") do
        local format, value = line:match("^(%S+)|([01])$")
        if format and format_filters[format] ~= nil then
            format_filters[format] = (value == "1")
        end
    end
end

function save_format_filters()
    local filepath = reaper.GetResourcePath() .. FORMAT_FILTERS_FILENAME
    local file, err = io.open(filepath, "w")
    if not file then
        return
    end

    for _, format in ipairs({"VST", "VST3", "AU", "JS", "CLAP"}) do
        file:write(string.format("%s|%d\n", format, format_filters[format] and 1 or 0))
    end
    file:close()
end

-- Il formato è il prefisso all'inizio del nome ("AU: kHs Gate"); un prefisso
-- sconosciuto non filtra mai, e le versioni instrument (VSTi, VST3i, AUi, CLAPi)
-- seguono il filtro della versione omonima.
function fx_visible(fx)
    local format = fx.name:match("^(%w+): ")
    if format == nil then
        return true
    end
    if format:sub(-1) == "i" then
        format = format:sub(1, -2)
    end
    return format_filters[format] ~= false
end

-- Stratta il prefisso di formato dall'estetica ("VST3: Foo" -> "Foo"), inclusa la
-- versione instrument ("VSTi: " -> "Foo"), e il suffisso "(manufacturer)" alla fine
-- ("ReaComp (REAPER)" -> "ReaComp"): i bottone degli fx mostrano il nome del plugin,
-- non il produttore, che nel drag-and-drop e nel tooltip è già visibile via `ident`.
-- Il prefisso di formato viene stratto solo se riconosciuto (le versioni "i" seguono
-- la base); se non è riconosciuto il nome resta con il prefix. Il suffisso tra
-- parentesi viene stratto sempre, quando presente ("Synth1" -> "Synth1").
function strip_fx_prefix(name)
    local prefix = name:match("^(%w+): ")
    if prefix then
        local base = prefix
        if base:sub(-1) == "i" then
            base = base:sub(1, -2)
        end
        if FORMAT_PREFIXES[base] then
            name = name:sub(#prefix + 3)
        end
    end
    return (name:gsub("%s*%b()", ""))
end

-- Strappa il prefisso di sezione (e, se presente, il suffisso ".lua") dal nome di un'azione
-- ("Script: Toggle play" -> "Toggle play", "aescript: mtt_Shelf.lua" -> "mtt_Shelf"):
-- REAPER prepende sempre un prefisso "<sezione>: ", quindi strappare il testo prima della
-- prima ": " restituisce il nome pulito; se non c'è prefisso, si stratta solo il suffisso
-- ".lua" finale; un nome che non ha nulla di tutto questo torna così com'è.
function strip_action_prefix(name)
    local prefix = name:match("^(%S+): ")
    if prefix then
        name = name:sub(#prefix + 3)
    end
    return (name:gsub("%.lua$", ""))
end

function add_favorite_action()
    if is_adding_action then
        return
    end
    is_adding_action = true
    reaper.PromptForAction(1, 0, -1)
end

function remove_favorite(index)
    if index >= 1 and index <= #favorites then
        table.remove(favorites, index)
        save_favorites()
    end
end

-- Identificatore unico del favorite: id per un'azione, ident per un FX. Prima di
-- aggiungerne uno nuovo si controlla che non esista già un favorite dello stesso tipo
-- con lo stesso identificatore; se è già presente l'inserimento viene scarto senza alcun
-- aviso, così un duplicato non si accumula nella lista.
function has_favorite(fav_list, fav_type, key)
    for _, fav in ipairs(fav_list or {}) do
        if fav.type == fav_type then
            if fav_type == "action" then
                if fav.id == key then
                    return true
                end
            elseif fav.ident == key then
                return true
            end
        end
    end
    return false
end

-- ==========================================
-- Style Management (Strict Push/Pop Order)
-- ==========================================

function apply_style()
    local col = reaper.ImGui_ColorConvertDouble4ToU32

    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), col(0.1, 0.1, 0.1, 1))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), col(0.45, 0.45, 0.45, 2))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_BorderShadow(), col(0, 0, 0, 2))

    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), col(0.1, 0.1, 0.1, 2))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), col(0.1, 0.1, 0.1, 2))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), col(0.18, 0.18, 0.18, 2))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_MenuBarBg(), col(0.1, 0.1, 0.1, 2))

    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), col(0.18, 0.18, 0.18, 2))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), col(0.3, 0.3, 0.3, 2))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), col(0.18, 0.18, 0.18, 2))

    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ResizeGrip(), col(0.1, 0.1, 0.1, 2))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ResizeGripActive(), col(0.3, 0.3, 0.3, 2))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ResizeGripHovered(), col(0.18, 0.18, 0.18, 2))

    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBg(), col(0.14, 0.14, 0.14, 2))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBgActive(), col(0.18, 0.18, 0.18, 2))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBgCollapsed(), col(0.18, 0.18, 0.18, 2))

    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), col(0.2, 0.2, 0.2, 2))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgActive(), col(0.4, 0.4, 0.4, 2))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(), col(0.25, 0.25, 0.25, 2))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_SliderGrab(), col(0.5, 0.5, 0.5, 2))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_SliderGrabActive(), col(0.13, 0.13, 0.13, 2))

    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_CheckMark(), col(0.8, 0.8, 0.8, 2))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Separator(), col(0.35, 0.35, 0.35, 2))

    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ScrollbarSize(), 10)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarBg(), col(0.09, 0.09, 0.09, 1))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrab(), col(0.3, 0.3, 0.3, 1))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrabActive(), col(0.2, 0.2, 0.2, 1))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrabHovered(), col(0.5, 0.5, 0.5, 1))

    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 7)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ScrollbarRounding(), 7)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_GrabRounding(), 7)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ChildRounding(), 7)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 5)
end

function pop_style()
    for _ = 1, 6 do
        reaper.ImGui_PopStyleVar(ctx)
    end
    for _ = 1, 27 do
        reaper.ImGui_PopStyleColor(ctx)
    end
end

function update_action_selection_state()
    if not is_adding_action then
        return false
    end

    local result = reaper.PromptForAction(0, 0, -1)

    if result > 0 then
        local pending_action_id = result

        local action_name = reaper.kbd_getTextFromCmd(pending_action_id, -1)
        if not action_name or action_name == "" then
            action_name = "Action #" .. pending_action_id
        end

        if not has_favorite(favorites, "action", pending_action_id) then
            table.insert(favorites, {type = "action", id = pending_action_id, name = action_name})
        end

        reaper.PromptForAction(-1, 0, 0)
        is_adding_action = false
        save_favorites()
        return false
    elseif result == -1 then
        is_adding_action = false
        reaper.PromptForAction(-1, 0, -1)
        return false
    end

    return true
end

-- ==========================================
-- UI: Render singolo bottone favorite
-- ==========================================

function render_favorite_button(i)
    local fav = favorites[i]

    if not fav then
        return
    end

    local display_name = fav.name
    if fav.type == "fx" then
        display_name = strip_fx_prefix(fav.name)
    elseif fav.type == "action" then
        display_name = strip_action_prefix(fav.name)
    end

    local btn_id = string.format("%s##fav_btn_%d", display_name, i)

    -- Colora il bottone in base al tipo
    local col_convert = reaper.ImGui_ColorConvertDouble4ToU32

    if fav.type == "action" then
        -- Colore per Action (Bluastro/Grigio)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), col_convert(0.15, 0.2, 0.3, 1))
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), col_convert(0.25, 0.3, 0.4, 1))
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), col_convert(0.1, 0.15, 0.2, 1))
    elseif fav.type == "fx" then
        -- Colore per FX (Verde scuro)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), col_convert(0.1, 0.2, 0.15, 1))
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), col_convert(0.15, 0.3, 0.2, 1))
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), col_convert(0.05, 0.15, 0.1, 1))
    end

    local clicked =
        reaper.ImGui_Button(
        ctx,
        btn_id,
        reaper.ImGui_CalcTextSize(ctx, display_name) + 10,
        reaper.ImGui_GetWindowHeight(ctx)
    )

    -- Pop dei colori spinti sopra (3 volte: Button, Hovered, Active)
    reaper.ImGui_PopStyleColor(ctx, 3)

    if reaper.ImGui_IsItemHovered(ctx) then
        local tooltip_info = ""
        if fav.type == "action" then
            tooltip_info = string.format("Type: Action\nID: %d\nLeft Click: Run Action\nAlt+Click: Remove", fav.id)
        elseif fav.type == "fx" then
            tooltip_info =
                string.format(
                "Type: FX\nIdent: %s\nDrag: Add to track under cursor\nAlt+Click: Remove",
                fav.ident or ""
            )
        end

        reaper.ImGui_SetTooltip(ctx, tooltip_info)
    end

    -- Drag and Drop per gli FX
    if fav.type == "fx" then
        if reaper.ImGui_BeginDragDropSource(ctx) then
            isDraggingFx = true
            draggedFx = fav
            reaper.ImGui_Text(ctx, "Drag: " .. display_name)
            reaper.ImGui_EndDragDropSource(ctx)
        end
    end

    if clicked then
        local is_alt = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftAlt())

        if is_alt then
            table.insert(hasToBeRemoved, i)
        else
            if fav.type == "action" and fav.id and fav.id > 0 then
                reaper.Main_OnCommand(fav.id, -1)
            elseif fav.type == "fx" and fav.ident then
            -- Nessuna azione al click: l'FX si aggiunge solo tramite drag-and-drop
            end
        end
    end
end

-- ==========================================
-- Main Loop
-- ==========================================

function SetButtonState(set)
    local _, _, sec, cmd = reaper.get_action_context()
    reaper.SetToggleCommandState(sec, cmd, set or 0)
    reaper.RefreshToolbar2(sec, cmd)
end

function onExit()
    SetButtonState(0)
end

function draw_action_fx_buttons()
    if reaper.ImGui_Button(ctx, "+Action", 60, reaper.ImGui_GetWindowHeight(ctx)) then
        add_favorite_action()
    end

    reaper.ImGui_SameLine(ctx)

    -- Non chiamare OpenPopup qui: siamo dentro un child window.
    -- Setta il flag; l'apertura avviene a livello window (vedi main_loop).
    if reaper.ImGui_Button(ctx, "+Fx", 60, reaper.ImGui_GetWindowHeight(ctx)) then
        open_fx_popup = true
        fx_filter = ""
    end
end

function main_loop()
    if reaper.GetProjectName(0) ~= proj_name then
        proj_name = reaper.GetProjectName(0)
        favorites = {}
        load_favorites()
    end

    if #favorites == 0 then
        load_favorites()
    end

    is_adding_action = update_action_selection_state()

    apply_style()

    local window_flags = reaper.ImGui_WindowFlags_NoCollapse() | reaper.ImGui_WindowFlags_NoResize()

    local visible, is_open = reaper.ImGui_Begin(ctx, "Shelf", true, window_flags)

    if visible then
        hasToBeRemoved = {}

        local total_items = #favorites + 1

        if reaper.ImGui_IsWindowDocked(ctx) then
            local win_w, win_h = reaper.ImGui_GetWindowSize(ctx)

            -- Top child: odd indices (1, 3, ...)
            reaper.ImGui_BeginChild(ctx, "##top_row", 0, win_h * 0.4)
            for i = 1, #favorites do
                if i % 2 ~= 0 then
                    reaper.ImGui_SameLine(ctx)
                    render_favorite_button(i)
                end
            end
            if total_items % 2 ~= 0 then
                reaper.ImGui_SameLine(ctx)
                draw_action_fx_buttons()
            end
            reaper.ImGui_EndChild(ctx)

            -- Bottom child: even indices (2, 4, ...)
            reaper.ImGui_BeginChild(ctx, "##bottom_row", 0, win_h * 0.4)
            for i = 1, #favorites do
                if i % 2 == 0 then
                    reaper.ImGui_SameLine(ctx)
                    render_favorite_button(i)
                end
            end
            if total_items % 2 == 0 then
                reaper.ImGui_SameLine(ctx)
                draw_action_fx_buttons()
            end
            reaper.ImGui_EndChild(ctx)
        else
            for i = 1, #favorites do
                render_favorite_button(i)
            end
            draw_action_fx_buttons()
        end

        -- Rimozione DOPO il loop, in ordine inverso per non sballare gli indici
        for j = #hasToBeRemoved, 1, -1 do
            remove_favorite(hasToBeRemoved[j])
        end

        -- Gestione del drop FX sulla finestra
        if ImGui.IsMouseReleased(ctx, 0) and isDraggingFx == true then
            
            isDraggingFx = false

            local payload = draggedFx.ident

            if payload then
                -- Ottieni la traccia sotto il cursore del mouse
                reaper.BR_GetMouseCursorContext()
                local track = reaper.BR_GetMouseCursorContext_Track()
                local take = reaper.BR_GetMouseCursorContext_Take()

                if take then
                    reaper.TakeFX_AddByName(take, payload, -1)
                elseif track then
                    reaper.TrackFX_AddByName(track, payload, false, -1)
                else
                    --reaper.ShowConsoleMsg("No track found under cursor.\n")
                end
            end
        end

        -- Apertura popup a livello window (ID stack coerente con BeginPopup)
        if open_fx_popup then
            reaper.ImGui_OpenPopup(ctx, "##FxContextPopup")
            open_fx_popup = false
        end

        -- Limita la width del popup alla larghezza del nome FX piú lungo tra quelli
        -- filtrati, cosí non si allarga con il contenuto scorrevole della child. La
        -- altezza resta in adattamento automatico (0 sull'asse y).
        local max_name_w = 0
        for _, Fx in ipairs(fx_list) do
            if fx_visible(Fx) and (fx_filter == "" or Fx.name:lower():find(fx_filter:lower(), 1, true)) then
                local w = reaper.ImGui_CalcTextSize(ctx, Fx.name)
                if w > max_name_w then max_name_w = w end
            end
        end
        reaper.ImGui_SetNextWindowSize(ctx, max_name_w + 40, 0, reaper.ImGui_Cond_Appearing())

        if reaper.ImGui_BeginPopup(ctx, "##FxContextPopup") then
            -- Focus automatico sul campo filtro quando il popup si apre
            if reaper.ImGui_IsWindowAppearing(ctx) then
                reaper.ImGui_SetKeyboardFocusHere(ctx, 0)
            end
            -- Larghezza fissa: con quella di default (~65% della finestra) i
            -- checkbox sulla stessa riga non ci starebbero
            reaper.ImGui_SetNextItemWidth(ctx, 100)
            local _, filter_buf = reaper.ImGui_InputTextWithHint(ctx, "##fx_filter", "Filtra FX...", fx_filter)
            fx_filter = filter_buf

            -- Checkbox dei formati sulla stessa riga della barra di ricerca:
            -- uno non spuntato esclude i plugin di quel formato (e della versione
            -- instrument omonima) dalla lista
            for _, format in ipairs({"VST", "VST3", "AU", "JS", "CLAP"}) do
                reaper.ImGui_SameLine(ctx)
                local pressed, v = reaper.ImGui_Checkbox(ctx, format, format_filters[format])
                if pressed then
                    format_filters[format] = v
                    save_format_filters()
                end
            end

            -- Lista in una child window con altezza fissa: scorre internamente
            -- invece di far gonfiare il popup con tutti gli FX
            if reaper.ImGui_BeginChild(ctx, "##fx_list", 0, 300) then
                local found = false
                for _, Fx in ipairs(fx_list) do
                    if fx_visible(Fx) and (fx_filter == "" or Fx.name:lower():find(fx_filter:lower(), 1, true)) then
                        found = true
                        if reaper.ImGui_Selectable(ctx, Fx.name) then
                            if not has_favorite(favorites, "fx", Fx.ident) then
                                table.insert(favorites, {type = "fx", ident = Fx.ident, name = Fx.name})
                                save_favorites()
                            end
                            -- Chiude il popup dopo la selezione: il pulsante è stato
                            -- salvato come favorite, la selezione non serve più.
                            reaper.ImGui_CloseCurrentPopup(ctx)
                        end
                    end
                end
                if not found then
                    reaper.ImGui_Text(ctx, "Nessun FX trovato")
                end
                reaper.ImGui_EndChild(ctx)
            end

            if reaper.ImGui_MenuItem(ctx, "Annulla") then
                reaper.ImGui_CloseCurrentPopup(ctx)
            end

            reaper.ImGui_EndPopup(ctx)
        end

        reaper.ImGui_End(ctx)
    end

    pop_style()

    if is_open then
        reaper.defer(main_loop)
    end
end

-- Start
load_format_filters()
SetButtonState(1)
main_loop()
reaper.atexit(onExit)
