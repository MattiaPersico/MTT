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

-- Preset: istantanee nominate dello scaffale (la lista favorites), conservate in un
-- unico file nella resource path di REAPER, condiviso tra tutti i progetti: permettono
-- di caricare un setup premade in un progetto con scaffale vuoto.
local PRESETS_FILENAME = ".mtt_shelf_presets.txt"
local presets = {}            -- nome -> lista di favorite
local preset_names = {}       -- nomi ordinati, per l'elenco in UI
local preset_name_input = ""  -- campo "salva come"
local open_preset_popup = false

-- Dimensioni del layout a scaffale: altezza fissa dei bottoni favorite (la
-- larghezza la definisce il testo), distanza orizzontale tra due bottoni della
-- stessa riga e effetto "rilievo" all'hover: font a 1.1x e 4px di altezza in più.
-- Ogni favorite occupa uno slot: dimensioni del bottone + un extra costante
-- (il massimo extra hover tra i nomi). Il bottone non hoverato è disegnato
-- centrato dentro lo slot con un inserimento uguale per tutti, così la crescita
-- all'hover è centrale, i bottoni alla destra non si spostano e spazi e bordi
-- delle righe restano costanti.
local FAV_BTN_H = 28        -- altezza fissa del bottone (px)
local FAV_BTN_PAD_X = 15    -- padding orizzontale attorno al nome
local UPPER_BTN_SP_X = 0    -- distanza tra pulsanti superiori (+Action, +Fx, +Preset)
local UPPER_SECTION_PAD_X = 10  -- margine sinistro della sezione pulsanti superiori
local FAV_BTN_SP_X = -4      -- distanza orizzontale tra due favorite button della stessa riga
local FAV_SECTION_PAD_X = 0    -- margine sinistro della child window che contiene i favorite button
local FAV_HOVER_FONT = 1.1  -- font 1.1x all'hover (effetto "rilievo")
local FAV_HOVER_H = 4       -- extra di altezza dello slot per l'hover
local FAV_HOVER_PALETTE_PERIOD = 0.8 -- secondi per un giro completo della palette dell'anello hover
local FAV_HOVER_BORDER_BASE = 1   -- spessore bordo non hover (FrameBorderSize)
local FAV_HOVER_BORDER_EXTRA = 1  -- extra hover: 1 + 1 = 2px (spessore dell'anelo cromatico)
local FAV_PRESSED_SHRINK_X = 4  -- riduzione di larghezza del bottone alla pressione
local FAV_PRESSED_SHRINK_Y = 2  -- riduzione di altezza del bottone alla pressione
local FAV_DRAG_SRC_GRAY = 0.3  -- "negativo" in drag: luminosità di bordo + scritta del button d'origine
local hovered_favorite_idx = -1  -- indice del button hoverato (frame precedente, per bordo grosso)
local current_hovered_idx = -1   -- indice del button attualmente hoverato (frame corrente)
local pressed_favorite_idx = -1  -- indice del button premuto (frame precedente, per il feedback di pressione)
local current_pressed_idx = -1   -- indice del button attualmente premuto (frame corrente)
local isDraggingFx = false       -- un favorite FX è trattenuto (drag in corso)
local draggedFx = nil            -- favorite in corso di drag
local drag_grab_x = 0            -- punto di presa: offset del mouse dal bordo del button (screen space)
local drag_grab_y = 0
local drag_grab_captured = false -- presa catturata al frame della press (vale per il gesto corrente)
local fav_hover_extra = 0        -- extra di larghezza hover (font 1.1x): massimo tra le favorite, set in render_favorites_flow

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

-- Preset: un file globale in resource path, condiviso tra tutti i progetti.
-- Formato: una riga "P|<nome>" apre un blocco, seguito dalle favorite in formato
-- identico a quello del file dei favorites (A|id||nome / F||ident|nome).
function preset_path()
    return reaper.GetResourcePath() .. "/" .. PRESETS_FILENAME
end

function load_presets()
    presets = {}
    preset_names = {}

    local file = io.open(preset_path(), "r")
    if not file then
        return
    end

    local content = file:read("*a")
    file:close()

    local current = nil
    for line in content:gmatch("[^\n\r]+") do
        if line == "" then
            goto continue
        end

        -- Apertura di un blocco preset
        local name = line:match("^P|(.+)$")
        if name then
            current = name
            presets[current] = {}
            table.insert(preset_names, current)
            goto continue
        end

        -- Favorite del preset corrente (stesso formato del file dei favorites)
        if current then
            local fav_type, part2, part3, name_val = line:match("^([AF])|([^|]*)|([^|]*)|(.+)$")
            if fav_type == "A" then
                local id_val = tonumber(part2)
                if id_val and id_val > 0 then
                    table.insert(presets[current], {type = "action", id = id_val, name = name_val})
                end
            elseif fav_type == "F" then
                local fx_ident = part3
                if fx_ident and fx_ident ~= "" then
                    table.insert(presets[current], {type = "fx", ident = fx_ident, name = name_val})
                end
            end
        end

        ::continue::
    end
end

function save_presets_file()
    local file = io.open(preset_path(), "w")
    if not file then
        return
    end

    for _, name in ipairs(preset_names) do
        file:write(string.format("P|%s\n", name))
        for _, fav in ipairs(presets[name]) do
            if fav.type == "action" and fav.id and fav.id > 0 and fav.name then
                file:write(string.format("A|%d||%s\n", fav.id, fav.name))
            elseif fav.type == "fx" and fav.ident and fav.name then
                file:write(string.format("F||%s|%s\n", fav.ident, fav.name))
            end
        end
    end
    file:close()
end

function has_preset(name)
    return presets[name] ~= nil
end

-- Salva lo scaffale corrente come istantanea sotto un nome (copia profonda:
-- le modifiche successive ai favorite non alterano il preset già salvato).
function save_current_as_preset(name)
    if name == "" then
        return
    end

    local copy = {}
    for _, fav in ipairs(favorites) do
        table.insert(copy, {type = fav.type, id = fav.id, ident = fav.ident, name = fav.name})
    end

    local is_new = not has_preset(name)
    presets[name] = copy
    if is_new then
        table.insert(preset_names, name)
    end
    save_presets_file()
end

-- Carica un preset nello scaffale corrente (sostituendo i favorite) e lo
-- consolida nel file del progetto: il progetto da ora mantiene quel setup.
function load_preset(name)
    local p = presets[name]
    if not p then
        return
    end

    favorites = {}
    for _, fav in ipairs(p) do
        table.insert(favorites, {type = fav.type, id = fav.id, ident = fav.ident, name = fav.name})
    end
    save_favorites()
end

function delete_preset(name)
    presets[name] = nil
    for i = #preset_names, 1, -1 do
        if preset_names[i] == name then
            table.remove(preset_names, i)
        end
    end
    save_presets_file()
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

-- Ricerca testuale che ignora la punteggiatura: "Pro Q" trova "Pro-Q 3".
-- Entrambi i lati vengono ridotti a sole lettere/cifre e poi confrontati a sottostringa;
-- un filtro vuoto (o fatto solo di punteggiatura) mostra tutto.
function fx_matches(fx, filter)
    local f = (filter:lower():gsub("[^%a%d]", ""))
    if f == "" then
        return true
    end
    local n = (fx.name:lower():gsub("[^%a%d]", ""))
    return n:find(f, 1, true) ~= nil
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
            --reaper.ShowConsoleMsg("[MTT_Shelf] Nuovo Action Favorite: type='action', id=" .. pending_action_id .. ", name='" .. action_name .. "'\n")
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

-- Nome visualizzato dal bottone: prefisso di formato (FX) o di sezione
-- (action) già strappati
function favorite_display_name(fav)
    if fav.type == "fx" then
        return strip_fx_prefix(fav.name)
    elseif fav.type == "action" then
        return strip_action_prefix(fav.name)
    end
    return fav.name
end

-- Bordo hover: anello attorno a un rettangolo arrotondato.
-- Col_Border è un singolo colore e non può variare attorno al perimetro,
-- quindi l'anelo è disegnato sulla draw list: il perimetro è spezzato in
-- segmenti e il colore di ciascuno viene interpolato in `ring_palette`
-- (5 tinte in ordine ciclico) sfasato della posizione lungo il perimetro —
-- la palette fa un giro completo attorno al bottone mentre `t` la fa
-- avanzare nel tempo.
-- Palette dell'anello: #ff7a00 #ffb36b #0b4f6c #1b85b8 #f6f2ea,
-- già convertite in float 0..1.
local ring_palette = {
    {1.000, 0.478, 0.000}, -- #ff7a00
    {1.000, 0.702, 0.420}, -- #ffb36b
    {0.043, 0.310, 0.424}, -- #0b4f6c
    {0.106, 0.522, 0.722}, -- #1b85b8
    {0.965, 0.949, 0.918}, -- #f6f2ea
}

local function draw_palette_ring(ctx, x0, y0, x1, y1, rounding, thickness, t)
    local r = math.min(rounding, (x1 - x0) / 2, (y1 - y0) / 2)

    -- Perimetro ordinato: 4 lati dritti (segmenti da ~6px) + 4 angoli
    -- (quarti di cerchio, 4 segmenti ciascuno: con r piccolo la corda
    -- approssima l'arco senza essere visibile).
    local seg_px = 6
    local pts = {}
    local function add_edge(ax, ay, bx, by)
        local n = math.max(2, math.floor(math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2) / seg_px))
        for k = 1, n do
            local s = k / n
            pts[#pts + 1] = {ax + (bx - ax) * s, ay + (by - ay) * s}
        end
    end
    local function add_corner(cx, cy, a0, a1)
        for k = 1, 4 do
            local a = a0 + (a1 - a0) * k / 4
            pts[#pts + 1] = {cx + r * math.cos(a), cy + r * math.sin(a)}
        end
    end

    add_edge(x0 + r, y0, x1 - r, y0)                 -- alto, sx → dx
    add_corner(x1 - r, y0 + r, -math.pi / 2, 0)     -- angolo alto-destra
    add_edge(x1, y0 + r, x1, y1 - r)                -- destro, su → giù
    add_corner(x1 - r, y1 - r, 0, math.pi / 2)      -- angolo basso-destra
    add_edge(x1 - r, y1, x0 + r, y1)                -- basso, dx → sx
    add_corner(x0 + r, y1 - r, math.pi / 2, math.pi) -- angolo basso-sinistra
    add_edge(x0, y1 - r, x0, y0 + r)                -- sinistro, giù → su
    add_corner(x0 + r, y0 + r, math.pi, math.pi * 1.5) -- angolo alto-sinistra (chiude)

    -- Lunghezza cumulativa di ogni punto: la fase spaziale della ruota.
    local cum = {}
    cum[1] = 0
    for i = 2, #pts do
        cum[i] = cum[i - 1] + math.sqrt((pts[i][1] - pts[i - 1][1]) ^ 2 + (pts[i][2] - pts[i - 1][2]) ^ 2)
    end
    local total = cum[#pts] + math.sqrt((pts[1][1] - pts[#pts][1]) ^ 2 + (pts[1][2] - pts[#pts][2]) ^ 2)

    local col_convert = reaper.ImGui_ColorConvertDouble4ToU32
    local dl = reaper.ImGui_GetWindowDrawList(ctx)
    for i = 1, #pts do
        local j = i % #pts + 1
        local ph = (t + 2 * math.pi * cum[i] / total) % (2 * math.pi)
        local s = ph / (2 * math.pi) * #ring_palette
        local k = math.floor(s)
        local f = s - k
        local c0 = ring_palette[k + 1]
        local c1 = ring_palette[(k + 1) % #ring_palette + 1]
        local cr = c0[1] + (c1[1] - c0[1]) * f
        local cg = c0[2] + (c1[2] - c0[2]) * f
        local cb = c0[3] + (c1[3] - c0[3]) * f
        reaper.ImGui_DrawList_AddLine(
            dl,
            pts[i][1], pts[i][2],
            pts[j][1], pts[j][2],
            col_convert(cr, cg, cb, 1),
            thickness
        )
    end
end

function render_favorite_button(i, btn_w, btn_h)
    local fav = favorites[i]

    if not fav then
        return
    end

    local display_name = favorite_display_name(fav)

    local btn_id = string.format("%s##fav_btn_%d", display_name, i)

    -- Colora il bottone in base al tipo
    local col_convert = reaper.ImGui_ColorConvertDouble4ToU32

    if fav.type == "action" then
        -- Bordo colorato, interno trasparente (Action — Bluastro/Grigio)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), col_convert(0.5, 0.55, 0.65, 1))
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), col_convert(0.15, 0.2, 0.3, 0))
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), col_convert(0.25, 0.3, 0.4, 0.2))
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), col_convert(0.1, 0.15, 0.2, 0))
    elseif fav.type == "fx" then
        -- Bordo colorato, interno trasparente (FX — Verde scuro)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), col_convert(0.3, 0.5, 0.35, 1))
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), col_convert(0.1, 0.2, 0.15, 0))
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), col_convert(0.15, 0.3, 0.2, 0.2))
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), col_convert(0.05, 0.15, 0.1, 0))
    end

    -- Se questo è il button hoverato nell'frame precedente: font ingrandito
    -- per dare un effetto "rilievo" (le dimensioni arrivano da
    -- render_favorites_flow, che centra il bottone nello slot) e bordo nativo
    -- trasparente: il bordo visibile è l'anelo di draw_palette_ring.
    -- In drag il button d'origine diventa "negativo": resta la sua sagoma —
    -- bordo + scritta grigi chiari (più chiari del bg della finestra),
    -- dimensione standard. Qui sopprime hover e press per lo stile
    -- (come in render_favorites_flow).
    local is_drag_src = (isDraggingFx and fav == draggedFx)
    local is_hover = (i == hovered_favorite_idx) and not is_drag_src
    local is_pressed = (i == pressed_favorite_idx) and not is_drag_src
    local n_pushed_col = 4
    if is_hover then
        local fs = reaper.ImGui_GetFontSize(ctx)
        reaper.ImGui_PushFont(ctx, nil, fs * FAV_HOVER_FONT)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), col_convert(0, 0, 0, 0))
        n_pushed_col = n_pushed_col + 1
    end
    if is_pressed then
        -- Feedback di pressione: riempimento e bordo più chiari (colore del tipo),
        -- font torna alla dimensione base (inverso del "rilievo" dell'hover)
        local fs = reaper.ImGui_GetFontSize(ctx)
        reaper.ImGui_PushFont(ctx, nil, fs)
        if fav.type == "action" then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), col_convert(0.7, 0.75, 0.9, 1))
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), col_convert(0.2, 0.28, 0.4, 0.35))
        else
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), col_convert(0.45, 0.75, 0.5, 1))
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), col_convert(0.2, 0.4, 0.25, 0.35))
        end
        n_pushed_col = n_pushed_col + 2
    end
    if is_drag_src then
        -- "Negativo": l'elemento è stato portato via, resta la sua sagoma —
        -- bordo e scritta grigi chiari (più chiari del bg della finestra),
        -- dimensione standard, nessun anello
        -- (il ring colorato sta solo sulla preview che segue il mouse).
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), col_convert(FAV_DRAG_SRC_GRAY, FAV_DRAG_SRC_GRAY, FAV_DRAG_SRC_GRAY, 1))
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), col_convert(FAV_DRAG_SRC_GRAY, FAV_DRAG_SRC_GRAY, FAV_DRAG_SRC_GRAY, 1))
        n_pushed_col = n_pushed_col + 2
    end

    -- FrameBorderSize esplicito: col default del tema (0) il bordo del
    -- bottone non si disegna e la copia nella preview drag non assomiglia
    -- all'originale.
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameBorderSize(), 1)
    local clicked =
        reaper.ImGui_Button(
        ctx,
        btn_id,
        btn_w,
        btn_h
    )
    reaper.ImGui_PopStyleVar(ctx, 1)
    local rect_min_x, rect_min_y = reaper.ImGui_GetItemRectMin(ctx)
    local rect_max_x, rect_max_y = reaper.ImGui_GetItemRectMax(ctx)

    -- Traccia il button premuto nel frame corrente: il feedback si applica dal
    -- frame prossimo, come per l'hover
    if reaper.ImGui_IsItemActive(ctx) then
        if pressed_favorite_idx ~= i then
            -- Primo frame della press: il mouse è fermo sul punto di presa.
            -- Si cattura qui, non all'attivazione del drag (1-2 frame dopo,
            -- quando in uno scatto è già spostato di 10-20px e quell'offset
            -- resterebbe per tutto il drag).
            local mx, my = reaper.ImGui_GetMousePos(ctx)
            drag_grab_x = mx - rect_min_x
            drag_grab_y = my - rect_min_y
            drag_grab_captured = true
        end
        current_pressed_idx = i
    end

    -- Press: pop prima il font (è stato spinto dopo quello dell'hover)
    if is_pressed then
        reaper.ImGui_PopFont(ctx)
    end

    -- Pop dei colori spinti sopra (4 base: Border, Button, Hovered, Active;
    -- +1 per il bordo trasparente se hover; +2 per i colori della pressione)
    reaper.ImGui_PopStyleColor(ctx, n_pushed_col)
    if is_hover then
        reaper.ImGui_PopFont(ctx)
    end

    -- L'anelo (spessore = base + extra) è arretrato di metà spessore: sta
    -- dentro al bordo del button, dove stava il vecchio bordo.
    if is_hover then
        local bw = FAV_HOVER_BORDER_BASE + FAV_HOVER_BORDER_EXTRA
        local rounding = reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding())
        local t = reaper.ImGui_GetTime(ctx) * 2 * math.pi / FAV_HOVER_PALETTE_PERIOD
        draw_palette_ring(
            ctx,
            rect_min_x + bw / 2, rect_min_y + bw / 2,
            rect_max_x - bw / 2, rect_max_y - bw / 2,
            math.max(0, rounding - bw / 2),
            bw,
            t
        )
    end

    -- Drag and Drop per gli FX: la preview è render_fx_drag_preview (finestra
    -- invisibile sopra la shelf); qui si registra lo stato. Il punto di presa
    -- è catturato al frame della press (vedi IsItemActive), col mouse ancora
    -- fermo sul punto in cui l'utente ha afferrato.
    if fav.type == "fx" then
        -- SourceNoPreviewTooltip: senza di esso BeginDragDropSource apre un
        -- tooltip integrato (etichetta + riquadro vuoto) sopra al vero bottone.
        if reaper.ImGui_BeginDragDropSource(ctx, reaper.ImGui_DragDropFlags_SourceNoPreviewTooltip()) then
            if not isDraggingFx and not drag_grab_captured then
                -- Fallback (non dovrebbe scattare): presa sul mouse corrente,
                -- comportamento precedente.
                local mx, my = reaper.ImGui_GetMousePos(ctx)
                drag_grab_x = mx - rect_min_x
                drag_grab_y = my - rect_min_y
            end
            isDraggingFx = true
            draggedFx = fav
            reaper.ImGui_EndDragDropSource(ctx)
        end
    end

    if clicked then
        local is_alt = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftAlt())

        if is_alt then
            table.insert(hasToBeRemoved, i)
            else
                if fav.type == "action" and fav.id and fav.id > 0 then
                    --reaper.ShowConsoleMsg("[MTT_Shelf] Action clicked: type='" .. fav.type .. "', id=" .. fav.id .. ", name='" .. fav.name .. "'\n")
                    reaper.defer(function() reaper.Main_OnCommand(fav.id, -1) end)
                elseif fav.type == "fx" and fav.ident then
                -- Nessuna azione al click: l'FX si aggiunge solo tramite drag-and-drop
                end
            end
        end

    -- Traccia il button attualmente hoverato (frame corrente)
    if reaper.ImGui_IsItemHovered(ctx) then
        current_hovered_idx = i
    end
end

-- Dopo il render di tutti i button: sincronizza `hovered_favorite_idx` col
-- button hoverato in questo frame, così il frame prossimo lo disegna col
-- bordo spesso; se il mouse non è su nessun button torna al bordo standard.
function reset_hovered_if_none()
    hovered_favorite_idx = current_hovered_idx
    current_hovered_idx = -1
end

-- Stesso sync per la pressione: dal frame prossimo il bottone è disegnato
-- premuto (ridotto + riempito) o torna normale se il mouse è stato rilasciato
function reset_pressed_if_none()
    pressed_favorite_idx = current_pressed_idx
    current_pressed_idx = -1
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

-- Barra di controllo fissa in cima alla finestra: due bottoni compatti per
-- aggiungere favorite, tenuti separati dai bottoni trascinabili del scaffale.
function draw_action_fx_buttons()
    reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + UPPER_SECTION_PAD_X)
    if reaper.ImGui_Button(ctx, "+Action") then
        add_favorite_action()
    end

    reaper.ImGui_SameLine(ctx, 0, UPPER_BTN_SP_X)

    -- Setta il flag; l'apertura avviene più avanti in main_loop, a livello
    -- window (ID stack coerente con BeginPopup).
    if reaper.ImGui_Button(ctx, "+Fx") then
        open_fx_popup = true
        fx_filter = ""
    end

    reaper.ImGui_SameLine(ctx, 0, UPPER_BTN_SP_X)

    -- Apre il menu preset (flag consumato in main_loop, a livello window)
    if reaper.ImGui_Button(ctx, "+Preset") then
        open_preset_popup = true
        preset_name_input = ""
    end
end

-- I favorite scorrono su righe che si riempono fino alla larghezza
-- disponibile e poi vanno a capo; quando le righe non entrano più, la child
-- (docked) fa apparire lo scrollbar verticale e quello orizzontale copre i
-- nomi troppo lunghi.
-- Ogni favorite occupa uno slot: il suo bottone + un extra costante, uguale
-- per tutti (il massimo extra hover, che cresce col font 1.1x del nome più
-- lungo). L'inserimento del bottone nello slot è quindi costante: lo spazio
-- tra due bottoni e il bordo sinistro di ogni riga sono gli stessi per tutte
-- le righe, indipendentemente dai nomi. L'hover cresce comunque in posto e i
-- bottoni alla destra non si spostano; le righe non si ricollocano mai perché
-- il wrapping usa sempre la dimensione slot.
function render_favorites_flow()
    reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + FAV_SECTION_PAD_X)
    local limit = reaper.ImGui_GetWindowWidth(ctx) - FAV_BTN_SP_X
    local _, row_sp_y = reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing())

    -- Extra orizzontale dell'hover (font 1.1x) per ogni nome: lo slot lo
    -- riserva a tutti, così l'inserimento del bottone centrato è costante.
    local fs = reaper.ImGui_GetFontSize(ctx)
    local max_extra = 0
    for i = 1, #favorites do
        local display_name = favorite_display_name(favorites[i])
        reaper.ImGui_PushFont(ctx, nil, fs * FAV_HOVER_FONT)
        local hover_w = reaper.ImGui_CalcTextSize(ctx, display_name)
        reaper.ImGui_PopFont(ctx)
        local extra = hover_w - reaper.ImGui_CalcTextSize(ctx, display_name)
        if extra > max_extra then
            max_extra = extra
        end
    end
    -- Condiviso con render_fx_drag_preview: il bottone della preview usa le
    -- dimensioni ingrandite (hover), non quelle base.
    fav_hover_extra = max_extra

    local row_origin_x, row_origin_y = reaper.ImGui_GetCursorPos(ctx)
    local row_used = 0   -- offset orizzontale del prossimo slot da row_origin_x
    local content_max_x = 0

    for i = 1, #favorites do
        local display_name = favorite_display_name(favorites[i])
        local is_drag_src = (isDraggingFx and favorites[i] == draggedFx)
        local is_hover = (i == hovered_favorite_idx) and not is_drag_src
        local is_pressed = (i == pressed_favorite_idx) and not is_drag_src

        local btn_w = reaper.ImGui_CalcTextSize(ctx, display_name) + FAV_BTN_PAD_X
        local btn_h = FAV_BTN_H
        -- Slot: bottone + extra costante. Per il nome più lungo coincide con le
        -- dimensioni hover; gli altri ci stanno dentro con un po' di respiro.
        local slot_w = btn_w + max_extra
        local slot_h = FAV_BTN_H + FAV_HOVER_H
        if is_hover then
            btn_w, btn_h = slot_w, slot_h
        end
        -- Pressione: riduci il bottone dentro lo slot (che resta di dimensioni
        -- costanti): nessun ricollocamento, i bottoni vicini non si spostano
        if is_pressed then
            btn_w = math.max(btn_w - FAV_PRESSED_SHRINK_X, 8)
            btn_h = math.max(btn_h - FAV_PRESSED_SHRINK_Y, 8)
        end
        if row_used > 0 and row_used + slot_w > limit then
            row_origin_y = row_origin_y + slot_h + row_sp_y
            row_used = 0
        end

        local slot_x = row_origin_x + row_used

        -- Centera il bottone nello slot (compensa la crescita dell'hover su
        -- entrambi gli assi: padding verticale e orizzontale attorno al bottone).
        reaper.ImGui_SetCursorPos(ctx, slot_x + (slot_w - btn_w) / 2, row_origin_y + (slot_h - btn_h) / 2)

        render_favorite_button(i, btn_w, btn_h)

        row_used = row_used + slot_w + FAV_BTN_SP_X
        content_max_x = math.max(content_max_x, slot_x + slot_w)
    end

    if #favorites > 0 then
        -- Il cursore finisce sul max del contenuto: gli scrollbar della child e
        -- l'altezza automatica (undocked) si dimensionano a tutti gli slot, non
        -- all'ultima riga (probabilmente più corta, 2px più bassa se non hover).
        reaper.ImGui_SetCursorPos(ctx, content_max_x, row_origin_y + FAV_BTN_H + FAV_HOVER_H)
        -- Un item a dimensione zero registra il cursore esteso come contenuto, altrimenti
        -- End/EndChild segnala che SetCursorPos ha allargato i confini senza nulla disegnato.
        reaper.ImGui_Dummy(ctx, 0, 0)
        -- Registra il cursore esteso come contenuto: senza un item dopo la
        -- SetCursorPos, End() lamenta che i confini sono stati estesi senza
        -- crescere la finestra.
        reaper.ImGui_Dummy(ctx, 0, 0)
    end
end

-- Preview del drag di un favorite FX: finestra invisibile (niente background,
-- bordo e padding) che contiene solo il bottone, posizionata a mouse - punto di
-- presa, così il centro del mouse resta sulle stesse coordinate relative del
-- bottone per tutto il drag. Il bottone usa le dimensioni ingrandite (stato
-- hover: nome a font 1.1x, larghezza e altezza slot), non quelle base del
-- button. Il quadratino visibile durante il drag è lui, non la finestra, che
-- resta trasparente.
function render_fx_drag_preview()
    local name = favorite_display_name(draggedFx)
    local btn_w = reaper.ImGui_CalcTextSize(ctx, name) + FAV_BTN_PAD_X + fav_hover_extra
    local btn_h = FAV_BTN_H + FAV_HOVER_H

    local mx, my = reaper.ImGui_GetMousePos(ctx)
    reaper.ImGui_SetNextWindowPos(ctx, mx - drag_grab_x, my - drag_grab_y, reaper.ImGui_Cond_Always())
    reaper.ImGui_SetNextWindowBgAlpha(ctx, 0)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowBorderSize(), 0)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 0, 0)
    -- Come su render_favorite_button: garante il bordo in ogni tema
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameBorderSize(), 1)

    -- Stesso aspetto della favorite FX in hover: bordo nativo trasparente,
    -- il bordo visibile è l'anello cromatico (come su render_favorite_button)
    local col_convert = reaper.ImGui_ColorConvertDouble4ToU32
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), col_convert(0, 0, 0, 0))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), col_convert(0.1, 0.2, 0.15, 0))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), col_convert(0.15, 0.3, 0.2, 0.2))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), col_convert(0.05, 0.15, 0.1, 0))

    local flags =
        reaper.ImGui_WindowFlags_NoDecoration() |
        reaper.ImGui_WindowFlags_NoBackground() |
        reaper.ImGui_WindowFlags_NoMove() |
        reaper.ImGui_WindowFlags_NoSavedSettings() |
        reaper.ImGui_WindowFlags_AlwaysAutoResize()

    if reaper.ImGui_Begin(ctx, "##ShelfDragPreview", true, flags) then
        local fs = reaper.ImGui_GetFontSize(ctx)
        reaper.ImGui_PushFont(ctx, nil, fs * FAV_HOVER_FONT)
        reaper.ImGui_Button(ctx, name .. "##shelf_drag_preview", btn_w, btn_h)
        reaper.ImGui_PopFont(ctx)

        -- Anello cromatico ruotato, identico a quello dell'hover sul bottone
        -- originale: spessore base+extra, arretrato di metà spessore.
        local bw = FAV_HOVER_BORDER_BASE + FAV_HOVER_BORDER_EXTRA
        local rx0, ry0 = reaper.ImGui_GetItemRectMin(ctx)
        local rx1, ry1 = reaper.ImGui_GetItemRectMax(ctx)
        local rounding = reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding())
        local t = reaper.ImGui_GetTime(ctx) * 2 * math.pi / FAV_HOVER_PALETTE_PERIOD
        draw_palette_ring(
            ctx,
            rx0 + bw / 2, ry0 + bw / 2,
            rx1 - bw / 2, ry1 - bw / 2,
            math.max(0, rounding - bw / 2),
            bw,
            t
        )

        reaper.ImGui_End(ctx)
    end

    reaper.ImGui_PopStyleColor(ctx, 4)
    reaper.ImGui_PopStyleVar(ctx, 3)
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
        -- Stile specifico per finestra docked: bordi netti, bottoni solo bordati,
        -- altezza ridotta, nessuna rotondità.
        local docked = reaper.ImGui_IsWindowDocked(ctx)
        if docked then
            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowBorderSize(), 1)
            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 0)
            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameBorderSize(), 1)
            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 4, 1)
        end
        hasToBeRemoved = {}

        draw_action_fx_buttons()

        if reaper.ImGui_IsWindowDocked(ctx) then
            -- La child riempie il resto della finestra; gli scrollbar
            -- appaiono solo quando le righe di favorite non ci stanno
                if
                reaper.ImGui_BeginChild(
                ctx,
                "##shelf",
                0,
                0,
                0,
                reaper.ImGui_WindowFlags_HorizontalScrollbar()
            )
            then
                render_favorites_flow()
                reset_hovered_if_none()
                reset_pressed_if_none()
                reaper.ImGui_EndChild(ctx)
            end
        else
            render_favorites_flow()
            reset_hovered_if_none()
            reset_pressed_if_none()
        end

        -- Rimozione DOPO il loop, in ordine inverso per non sballare gli indici
        for j = #hasToBeRemoved, 1, -1 do
            remove_favorite(hasToBeRemoved[j])
        end

        -- Fine del gesto: la presa catturata al frame della press vale solo
        -- per il gesto corrente
        if reaper.ImGui_IsMouseReleased(ctx, 0) then
            drag_grab_captured = false
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
                    local idx = reaper.TakeFX_AddByName(take, payload, -1)
                    if idx >= 0 then reaper.TakeFX_SetOpen(take, idx, true) end
                elseif track then
                    local idx = reaper.TrackFX_AddByName(track, payload, false, -1)
                    if idx >= 0 then reaper.TrackFX_SetOpen(track, idx, true) end
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
            if fx_visible(Fx) and fx_matches(Fx, fx_filter) then
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
                    if fx_visible(Fx) and fx_matches(Fx, fx_filter) then
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

        -- Menu preset: salva lo scaffale come istantanea nominata, elenca i preset
        -- (click = carica, x = elimina). Aperto a livello window come il popup FX.
        if open_preset_popup then
            reaper.ImGui_OpenPopup(ctx, "##PresetPopup")
            open_preset_popup = false
        end

        reaper.ImGui_SetNextWindowSize(ctx, 300, 0, reaper.ImGui_Cond_Appearing())

        if reaper.ImGui_BeginPopup(ctx, "##PresetPopup") then
            if reaper.ImGui_IsWindowAppearing(ctx) then
                reaper.ImGui_SetKeyboardFocusHere(ctx, 0)
            end

            reaper.ImGui_SetNextItemWidth(ctx, 170)
            local _, name_buf = reaper.ImGui_InputTextWithHint(ctx, "##preset_name", "Nome preset...", preset_name_input)
            preset_name_input = name_buf

            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, "Salva") then
                save_current_as_preset(preset_name_input)
                preset_name_input = ""
            end

            reaper.ImGui_Separator(ctx)

            if reaper.ImGui_BeginChild(ctx, "##preset_list", 0, 220) then
                local names = {}
                for _, name in ipairs(preset_names) do
                    table.insert(names, name)
                end

                if #names == 0 then
                    reaper.ImGui_Text(ctx, "Nessun preset salvato")
                end

                for _, name in ipairs(names) do
                    if reaper.ImGui_Selectable(ctx, name) then
                        load_preset(name)
                        reaper.ImGui_CloseCurrentPopup(ctx)
                    end

                    reaper.ImGui_SameLine(ctx)
                    if reaper.ImGui_Button(ctx, "x##preset_del_" .. name) then
                        delete_preset(name)
                    end
                end

                reaper.ImGui_EndChild(ctx)
            end

            if reaper.ImGui_MenuItem(ctx, "Annulla") then
                reaper.ImGui_CloseCurrentPopup(ctx)
            end

            reaper.ImGui_EndPopup(ctx)
        end

        if docked then
            reaper.ImGui_PopStyleVar(ctx, 4)
        end

        reaper.ImGui_End(ctx)

        -- Preview del drag FX: dopo l'End della shelf (così sta sopra),
        -- ancora dentro if visible, prima di pop_style()
        if isDraggingFx then
            render_fx_drag_preview()
        end
    end

    pop_style()

    if is_open then
        reaper.defer(main_loop)
    end
end

-- Start
load_format_filters()
load_presets()
SetButtonState(1)
main_loop()
reaper.atexit(onExit)
