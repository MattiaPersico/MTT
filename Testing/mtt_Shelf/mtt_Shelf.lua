-- mtt_Shelf.lua - Action Favorites Manager (Safe Styling)

package.path = reaper.ImGui_GetBuiltinPath() .. "/?.lua"
local ImGui = require "imgui" "0.10"
local ctx = reaper.ImGui_CreateContext("mtt_Shelf", reaper.ImGui_ConfigFlags_DockingEnable())
local FAVORITES_FILENAME = ".mtt_shelf.txt"
local favorites = {}

-- Sfondo dello scaffale: il background (col_main_bg) del tema REAPER attivo,
-- letto una sola volta all'avvio. -1 = lettura fallita: si usa #282828.
local theme_bg = reaper.GetThemeColor("col_main_bg")
local theme_bg_r, theme_bg_g, theme_bg_b = 0.157, 0.157, 0.157
if theme_bg ~= -1 then
    local c = theme_bg < 0 and theme_bg + 0x100000000 or theme_bg
    theme_bg_r = ((c >> 16) & 0xFF) / 255
    theme_bg_g = ((c >> 8) & 0xFF) / 255
    theme_bg_b = (c & 0xFF) / 255
end

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

-- Link: bottoni che aprono un URL (browser) o un file/cartella locale (app
-- predefinita). Popup "Link" per aggiungerne uno; popup "Missing link" quando
-- il percorso locale di un link non esiste più (nuovo percorso o elimina).
local open_link_popup = false
local link_target_input = ""
local link_name_input = ""
local open_missing_popup = false
local missing_link_fav = nil      -- il favorite (tabella, non indice) col percorso mancante
local missing_target_input = ""

-- Menu look: the shelf's popups (Fx, Preset, Link, Missing link) take the look
-- of FMOD Sync Mini and mtt_dock docked next to it: square corners, sans-serif
-- 13, their spacing, mtt_FmodSync's palette with the orange accent, and the
-- REAPER theme background a little lighter for popup, frames and buttons
-- (darker on a light theme). The buttons of the shelf itself keep their look.
local MENU_FONT_SIZE = 13
local MENU_ACCENT = 0xE89B3CFF
local MENU_SELECTED = 0x9A6322FF
local MENU_SELECTED_HOVER = 0xAE7229FF
local MENU_SELECTED_ACTIVE = 0x84541AFF
local MENU_LABEL_W = 70      -- left column of the label/field rows
local MENU_FIELD_W = 320
local menu_font = nil
do
    local ok, f = pcall(function()
        local font = reaper.ImGui_CreateFont("sans-serif")
        reaper.ImGui_Attach(ctx, font)
        return font
    end)
    if ok then
        menu_font = f
    end
end
local menu_pushed_colors = 0
local menu_pushed_vars = 0

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
local UPPER_BTN_SP_X = 4    -- distanza tra Action e Fx
local UPPER_BTN_FP_X = 2    -- padding orizzontale dei bottoni superiori (ridotto: li avvicina)
local UPPER_SECTION_PAD_X = 10  -- margine sinistro della sezione pulsanti superiori
local ADD_LABEL_SP_X = 4    -- distanza tra la label "Add:" e il primo bottone
local FAV_BTN_SP_X = 16     -- gap costante tra due favorite button: contiene la crescita
                             -- dell'hover (font 1.1x → ~5% per lato) senza overlap
local FAV_SECTION_PAD_X = 0    -- margine sinistro della child window che contiene i favorite button
local FAV_HOVER_FONT = 1.1  -- font 1.1x all'hover (effetto "rilievo")
local FAV_HOVER_H = 4       -- extra di altezza dello slot per l'hover
local FAV_HOVER_PALETTE_PERIOD = 0.8 -- secondi per un giro completo della palette dell'anello hover
local FAV_HOVER_BORDER_BASE = 1   -- spessore bordo non hover (FrameBorderSize)
local FAV_HOVER_BORDER_EXTRA = 1  -- extra hover: 1 + 1 = 2px (spessore dell'anelo cromatico)
local FAV_PRESSED_SHRINK_X = 6  -- riduzione di larghezza del bottone alla pressione
local FAV_PRESSED_SHRINK_Y = 4  -- riduzione di altezza del bottone alla pressione
local FAV_DRAG_SRC_GRAY = 0.3  -- "negativo" in drag: luminosità di bordo + scritta del button d'origine

-- Scrollbar custom sul bordo sinistro (entrambi i modi): la nativa è
-- nascosta (WindowFlags_NoScrollbar, la wheel continua a scrollare); larghezza
-- del grab, distanza dal contenuto e colori (grigi, leggibili su tema chiaro e
-- scuro). sb_*: origine e altezza della regione di contenuto, prese ogni frame
-- in main_loop (undocked: finestra principale, docked: dentro la child) per il
-- disegno di fine frame. La striscia sta all'origine del contenuto; le righe
-- partono dopo (LEFT_SB_W + LEFT_SB_GAP, shift di render_favorites_flow).
-- La track è solo il bordo; il grab è più stretto e centrato nella striscia.
-- I colori sono 0xRRGGBBAA (ReaImGui, alpha nell'ultimo byte): i grigi vecchi
-- (0xFF808080 ecc.) erano in realtà rossi semi-trasparenti.
local LEFT_SB_W = 10
local LEFT_SB_GRAB_W = 4
local LEFT_SB_GAP = 2
local LEFT_SB_TRACK_COL = 0x80808050
local LEFT_SB_GRAB_COL = 0x404040FF
local LEFT_SB_GRAB_HOVER_COL = 0x606060FF
local LEFT_SB_TRACK_INSET_Y = 4  -- inset verticale della track (più corta dell'area)
local LEFT_SB_GRAB_MARGIN_Y = 2  -- il grab resta un filo più corto della track
local sb_top_x, sb_top_y, sb_avail_h = 0, 0, 0
local sb_press_on_grab = false  -- bottone sinistro trattenuto col punto dentro il grab (scartato al rilascio)
local sb_press_off_y = 0        -- offset del punto di pressione dentro il grab: evita lo snap all'inizio
local hovered_favorite_idx = -1  -- indice del button hoverato (frame precedente, per bordo grosso)
local current_hovered_idx = -1   -- indice del button attualmente hoverato (frame corrente)
local pressed_favorite_idx = -1  -- indice del button premuto (frame precedente, per il feedback di pressione)
local current_pressed_idx = -1   -- indice del button attualmente premuto (frame corrente)
local hovered_upper_btn = 0      -- Action/Fx/Preset hoverato (frame precedente, testo più chiaro)
local current_upper_btn = 0      -- Action/Fx/Preset/Link hoverato (frame corrente); 0=nessuno, 1=Action 2=Fx 3=Preset 4=Link
local isDraggingFx = false       -- un favorite FX è trattenuto (drag in corso)
local draggedFx = nil            -- favorite in corso di drag
local DRAG_PREVIEW_OFFSET_Y = 20 -- preview sotto il cursore: tiene il puntatore fuori dalla finestra

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

-- Script, SWS and custom actions get a new numeric command ID at every REAPER
-- launch (assigned in registration order), so a saved number can point to a
-- different action in the next session. Such actions are stored by their named
-- command ("_RS…", "_SWS_…") and re-resolved with NamedCommandLookup; only native
-- actions keep their number, which is stable.
local main_section = reaper.SectionFromUniqueID(MAIN_SECTION)
local action_ids_by_name = nil   -- lazy name -> id map, built once per resolve pass

function named_command_of(id)
    local named = reaper.ReverseNamedCommandLookup(id)
    if named and named ~= "" then
        return "_" .. named
    end
    return nil
end

function find_action_id_by_name(name)
    if not action_ids_by_name then
        action_ids_by_name = {}
        local idx = 0
        while true do
            local cmd = reaper.kbd_enumerateActions(main_section, idx)
            if not cmd or cmd == 0 then
                break
            end
            local text = reaper.kbd_getTextFromCmd(cmd, main_section)
            if text and text ~= "" and not action_ids_by_name[text] then
                action_ids_by_name[text] = cmd
            end
            idx = idx + 1
        end
    end
    return action_ids_by_name[name]
end

-- Sets fav.id to this session's command ID (0 = action not available now; the
-- entry stays on the shelf, inert, so it comes back if the script is reinstalled).
-- Returns true when fav.named was filled in, i.e. the file needs rewriting.
function resolve_action(fav)
    if fav.named then
        fav.id = reaper.NamedCommandLookup(fav.named)
        return false
    end
    -- No named command: a native action, or an entry saved by the old format
    -- (number only). A number that is not native is stale: find it by name.
    local id = fav.id or 0
    if id > 0 and not reaper.ReverseNamedCommandLookup(id)
       and (reaper.kbd_getTextFromCmd(id, main_section) or "") ~= "" then
        return false
    end
    local found = fav.name and find_action_id_by_name(fav.name)
    if found then
        fav.id = found
        fav.named = named_command_of(found)
        return fav.named ~= nil
    end
    fav.id = 0
    return false
end

-- Action fields shared by the favorites file and the presets file:
-- A|<id>|<named command or empty>|<name>
function parse_action_line(part2, part3, name_val)
    local id_val = tonumber(part2) or 0
    local named = (part3 ~= "" and part3) or nil
    if not name_val then
        return nil
    end
    return {type = "action", id = id_val, named = named, name = name_val}
end

function format_action_line(fav)
    return string.format("A|%d|%s|%s\n", fav.id or 0, fav.named or "", fav.name)
end

-- Link fields shared by the favorites file and the presets file:
-- L||<url or path>|<name>. A "|" inside the target is stored as %7C, so the
-- line still splits on the field separators (the name, last, may hold "|").
function parse_link_line(part3, name_val)
    if not part3 or part3 == "" or not name_val then
        return nil
    end
    return {type = "link", target = (part3:gsub("%%7C", "|")), name = name_val}
end

function format_link_line(fav)
    return "L||" .. (fav.target:gsub("|", "%%7C")) .. "|" .. fav.name .. "\n"
end

-- Un URL (schema://... o mailto:) si apre nel browser; tutto il resto è un
-- percorso locale (file o cartella), aperto con l'app predefinita.
function is_url(target)
    return target:match("^%a[%w+.-]*://") ~= nil or target:match("^mailto:") ~= nil
end

-- Pulisce quanto incollato nel campo: spazi e virgolette attorno, "www."
-- senza schema diventa https://, "~/" diventa la home (`os` è ombreggiato
-- da reaper.GetOS() in questo file: la libreria è _G.os).
function clean_link_target(s)
    s = (s or ""):match("^%s*(.-)%s*$")
    s = s:match('^"(.*)"$') or s:match("^'(.*)'$") or s
    if s:match("^www%.") then
        s = "https://" .. s
    elseif s:match("^~[/\\]") then
        local home = _G.os.getenv("HOME") or _G.os.getenv("USERPROFILE")
        if home then
            s = home .. s:sub(2)
        end
    end
    return s
end

-- Un percorso locale esiste se è un file o una cartella (io.open apre anche
-- una cartella su macOS; EnumerateFiles/Subdirectories la coprono altrove,
-- tranne una cartella vuota).
function link_exists(path)
    if reaper.file_exists(path) then
        return true
    end
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return reaper.EnumerateFiles(path, 0) ~= nil or reaper.EnumerateSubdirectories(path, 0) ~= nil
end

-- Nome di default del bottone: l'host per un URL (senza "www."), il nome del
-- file senza estensione (o della cartella) per un percorso locale.
function default_link_name(target)
    if is_url(target) then
        local host = target:match("^%a[%w+.-]*://([^/?#:]+)")
        if host then
            return (host:gsub("^www%.", ""))
        end
        return target
    end
    local base = target:match("([^/\\]+)[/\\]*$") or target
    local stem = base:gsub("%.%w+$", "")
    if stem == "" then
        return base
    end
    return stem
end

function add_link_favorite(target, name)
    target = clean_link_target(target)
    if target == "" or has_favorite(favorites, "link", target) then
        return
    end
    name = (name or ""):match("^%s*(.-)%s*$")
    if name == "" then
        name = default_link_name(target)
    end
    table.insert(favorites, {type = "link", target = target, name = name})
    save_favorites()
end

-- Click su un link: un percorso locale che non esiste più apre il popup
-- "Missing link" invece di passare un percorso morto al sistema. Gli URL non
-- si verificano. CF_ShellExecute (SWS, già richiesto dallo script per
-- BR_*AtMouseCursor) apre URL e file con l'app predefinita del sistema.
function open_link(fav)
    if not is_url(fav.target) and not link_exists(fav.target) then
        missing_link_fav = fav
        missing_target_input = fav.target
        open_missing_popup = true
        return
    end
    if reaper.APIExists("CF_ShellExecute") then
        reaper.CF_ShellExecute(fav.target)
    end
end

-- Dialoghi nativi per scegliere il bersaglio; la cartella solo con
-- js_ReaScriptAPI (il dialogo file di REAPER non sceglie cartelle).
function browse_link_file(initial_dir)
    local ok, path = reaper.GetUserFileNameForRead(initial_dir or "", "Link a file", "")
    if ok and path ~= "" then
        return path
    end
end

function browse_link_folder(initial_dir)
    if not reaper.APIExists("JS_Dialog_BrowseForFolder") then
        return
    end
    local ok, path = reaper.JS_Dialog_BrowseForFolder("Link a folder", initial_dir or "")
    if ok == 1 and path ~= "" then
        return path
    end
end

-- Row "Link" (URL or path) + File... / Folder... under it, shared by the Link
-- and Missing link popups: returns the updated value of the field.
function draw_link_target_field(id, value, initial_dir)
    menu_label("Link", "A web address (a Google Doc, a page...) or a file or folder on this computer.")
    reaper.ImGui_SetNextItemWidth(ctx, MENU_FIELD_W)
    local _, buf = reaper.ImGui_InputTextWithHint(ctx, "##" .. id, "URL or path", value)
    reaper.ImGui_SetCursorPosX(ctx, MENU_LABEL_W)
    if reaper.ImGui_Button(ctx, "File...##" .. id) then
        buf = browse_link_file(initial_dir) or buf
    end
    menu_tip("Pick a file.")
    if reaper.APIExists("JS_Dialog_BrowseForFolder") then
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Folder...##" .. id) then
            buf = browse_link_folder(initial_dir) or buf
        end
        menu_tip("Pick a folder.")
    end
    return buf
end

function parent_dir(path)
    return path:match("^(.*)[/\\][^/\\]*$") or ""
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

        -- Try new format first: A|id|named|name  OR  F||ident|name  OR  L||target|name
        local fav_type, part2, part3, name_val = line:match("^([AFL])|([^|]*)|([^|]*)|(.+)$")

        if fav_type then
            if fav_type == "A" then
                local fav = parse_action_line(part2, part3, name_val)
                if fav then
                    table.insert(favorites, fav)
                end
            elseif fav_type == "F" then
                -- part2 should be empty for FX, ident is in part3
                local fx_ident = part3
                if fx_ident and fx_ident ~= "" then
                    table.insert(favorites, {type = "fx", ident = fx_ident, name = name_val})
                end
            elseif fav_type == "L" then
                local fav = parse_link_line(part3, name_val)
                if fav then
                    table.insert(favorites, fav)
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

    action_ids_by_name = nil
    local migrated = false
    for _, fav in ipairs(favorites) do
        if fav.type == "action" and resolve_action(fav) then
            migrated = true
        end
    end
    if migrated then
        save_favorites()
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
        if fav.type == "action" and fav.name then
            -- Format: A|id|named|name (named empty for native actions). An action not
            -- found this session (id 0) is kept, so it resolves again if it returns.
            file:write(format_action_line(fav))
        elseif fav.type == "fx" and fav.ident and fav.name then
            -- Format: F||ident|name
            file:write(string.format("F||%s|%s\n", fav.ident, fav.name))
        elseif fav.type == "link" and fav.target and fav.name then
            file:write(format_link_line(fav))
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
-- identico a quello del file dei favorites (A|id|named|nome / F||ident|nome / L||target|nome).
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
            local fav_type, part2, part3, name_val = line:match("^([AFL])|([^|]*)|([^|]*)|(.+)$")
            if fav_type == "A" then
                local fav = parse_action_line(part2, part3, name_val)
                if fav then
                    table.insert(presets[current], fav)
                end
            elseif fav_type == "F" then
                local fx_ident = part3
                if fx_ident and fx_ident ~= "" then
                    table.insert(presets[current], {type = "fx", ident = fx_ident, name = name_val})
                end
            elseif fav_type == "L" then
                local fav = parse_link_line(part3, name_val)
                if fav then
                    table.insert(presets[current], fav)
                end
            end
        end

        ::continue::
    end

    action_ids_by_name = nil
    local migrated = false
    for _, name in ipairs(preset_names) do
        for _, fav in ipairs(presets[name]) do
            if fav.type == "action" and resolve_action(fav) then
                migrated = true
            end
        end
    end
    if migrated then
        save_presets_file()
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
            if fav.type == "action" and fav.name then
                file:write(format_action_line(fav))
            elseif fav.type == "fx" and fav.ident and fav.name then
                file:write(string.format("F||%s|%s\n", fav.ident, fav.name))
            elseif fav.type == "link" and fav.target and fav.name then
                file:write(format_link_line(fav))
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
        table.insert(copy, {type = fav.type, id = fav.id, named = fav.named, ident = fav.ident, target = fav.target, name = fav.name})
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
        table.insert(favorites, {type = fav.type, id = fav.id, named = fav.named, ident = fav.ident, target = fav.target, name = fav.name})
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
-- Inserisce un FX: item selezionati (alla take attiva), in loro assenza le tracce
-- selezionate; con drop_take (rilascio su un item), un item non selezionato
-- bersagliato conta da solo; con drop_track (rilascio su una traccia: track
-- panel o arrange, senza item sotto il cursore) l'FX va nella catena di
-- quella traccia, ignorando item e tracce selezionati.
function insert_fx(fx_ident, drop_take, drop_track)
    -- Drop su una traccia: solo la sua catena, le selezioni sono ignorate
    if drop_track then
        local idx = reaper.TrackFX_AddByName(drop_track, fx_ident, false, -1)
        if idx >= 0 then reaper.TrackFX_SetOpen(drop_track, idx, true) end
        return
    end

    -- Item sotto il puntatore al rilascio del drag (take -> item)
    local drop_item = drop_take and reaper.GetMediaItemTake_Item(drop_take)

    -- Dove finisce l'FX: drop su item non selezionato -> solo quello (non sui
    -- selezionati); drop su item selezionato o senza bersaglio (click) -> tutti
    -- gli item selezionati; nessuna selezione di item -> tracce selezionate.
    local items = {}
    local sel_count = reaper.CountSelectedMediaItems(0)
    if drop_item and reaper.GetMediaItemInfo_Value(drop_item, "B_UISEL") ~= 1 then
        items[1] = drop_item
    elseif sel_count > 0 then
        for i = 0, sel_count - 1 do
            items[i + 1] = reaper.GetSelectedMediaItem(0, i)
        end
    end

    if #items > 0 then
        for _, item in ipairs(items) do
            local take = reaper.GetActiveTake(item)
            local idx = reaper.TakeFX_AddByName(take, fx_ident, -1)
            if idx >= 0 then reaper.TakeFX_SetOpen(take, idx, true) end
        end
    else
        -- Nessuna selezione di item: inserisci nelle tracce selezionate
        local track_count = reaper.CountSelectedTracks(0)
        for i = 0, track_count - 1 do
            local track = reaper.GetSelectedTrack(0, i)
            local idx = reaper.TrackFX_AddByName(track, fx_ident, false, -1)
            if idx >= 0 then reaper.TrackFX_SetOpen(track, idx, true) end
        end
    end
end

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

-- Identificatore unico del favorite: id per un'azione, ident per un FX, target per un link. Prima di
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
            elseif fav_type == "link" then
                if fav.target == key then
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

    -- Sfondo dello scaffale: background del tema REAPER attivo, letto all'avvio (fallback #282828)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), col(theme_bg_r, theme_bg_g, theme_bg_b, 1))
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
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarBg(), col(0.09, 0.09, 0.09, 0))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrab(), col(0.3, 0.3, 0.3, 1))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrabActive(), col(0.2, 0.2, 0.2, 1))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrabHovered(), col(0.5, 0.5, 0.5, 1))

    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 7)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ScrollbarRounding(), 7)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_GrabRounding(), 7)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ChildRounding(), 7)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 0)
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
            table.insert(favorites, {type = "action", id = pending_action_id, named = named_command_of(pending_action_id), name = action_name})
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
    else
        -- Bordo colorato, interno trasparente (Link — Ambra)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), col_convert(0.75, 0.58, 0.3, 1))
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), col_convert(0.3, 0.22, 0.1, 0))
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), col_convert(0.4, 0.3, 0.15, 0.2))
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), col_convert(0.2, 0.15, 0.05, 0))
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
        elseif fav.type == "fx" then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), col_convert(0.45, 0.75, 0.5, 1))
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), col_convert(0.2, 0.4, 0.25, 0.35))
        else
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), col_convert(0.95, 0.8, 0.5, 1))
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), col_convert(0.4, 0.3, 0.15, 0.35))
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

    -- Link: il bersaglio (URL o percorso) nel tooltip, col ritardo standard
    if fav.type == "link" then
        reaper.ImGui_SetItemTooltip(ctx, fav.target)
    end

    -- Traccia il button premuto nel frame corrente: il feedback si applica dal
    -- frame prossimo, come per l'hover
    if reaper.ImGui_IsItemActive(ctx) then
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
    -- invisibile sopra la shelf, sotto il cursore); qui si registra lo stato.
    if fav.type == "fx" then
        -- SourceNoPreviewTooltip: senza di esso BeginDragDropSource apre un
        -- tooltip integrato (etichetta + riquadro vuoto) sopra al vero bottone.
        if reaper.ImGui_BeginDragDropSource(ctx, reaper.ImGui_DragDropFlags_SourceNoPreviewTooltip()) then
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
                if fav.type == "action" then
                    -- Named actions are looked up again at click time: the number
                    -- cached at load is only valid for this REAPER session.
                    local cmd = fav.named and reaper.NamedCommandLookup(fav.named) or fav.id or 0
                    if cmd > 0 then
                        reaper.defer(function() reaper.Main_OnCommand(cmd, -1) end)
                    end
                elseif fav.type == "fx" and fav.ident then
                    insert_fx(fav.ident)
                elseif fav.type == "link" and fav.target then
                    open_link(fav)
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

-- Stesso sync a due frame per i bottoni "solo testo" della riga superiore
function reset_upper_hover()
    hovered_upper_btn = current_upper_btn
    current_upper_btn = 0
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

-- Bottone "solo testo" della riga superiore (Action/Fx/Preset): il label si
-- illumina all'hover, con lo stesso schema a due frame dei favorite
-- (hovered_upper_btn = frame precedente, current_upper_btn = frame corrente).
-- idx: 1=Action 2=Fx 3=Preset 4=Link. Sfondo e bordo già trasparenti dal chiamante.
local function draw_upper_text_button(label, idx)
    -- Il testo del tema è già bianco pieno: per far "crescere" la luminosità
    -- all'hover si abbassa quella a riposo (grigio) e si torna a bianco sotto il cursore.
    local col = reaper.ImGui_ColorConvertDouble4ToU32
    if hovered_upper_btn == idx then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), col(1, 1, 1, 1))
    else
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), col(0.7, 0.7, 0.7, 1))
    end
    local clicked = reaper.ImGui_Button(ctx, label)
    if reaper.ImGui_IsItemHovered(ctx) then
        current_upper_btn = idx
    end
    reaper.ImGui_PopStyleColor(ctx)
    return clicked
end

-- Barra di controllo fissa in cima alla finestra, tra due linee grigie: la
-- label "Add:" + i bottoni Action/Fx/Link a sinistra (per aggiungere favorite) e
-- Preset allineato al bordo destro, tenuti separati dai bottoni del scaffale.
function draw_action_fx_buttons()
    -- Linea grigia sopra la riga (colore da ImGui_Col_Separator)
    reaper.ImGui_Separator(ctx)

    -- Padding orizzontale ridotto solo per i bottoni della riga: la distanza
    -- visibile tra due bottoni è 2 * FramePadding.x, quindi li avvicina.
    local _, fp_y = reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding())
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), UPPER_BTN_FP_X, fp_y)

    reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + UPPER_SECTION_PAD_X)

    local col = reaper.ImGui_ColorConvertDouble4ToU32

    -- Label "Add:" grigia come i bottoni "solo testo"
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), col(0.7, 0.7, 0.7, 1))
    reaper.ImGui_Text(ctx, "Add:")
    reaper.ImGui_PopStyleColor(ctx)
    reaper.ImGui_SameLine(ctx, 0, ADD_LABEL_SP_X)

    -- Bottoni "solo testo": sfondo e bordo trasparenti, solo il label resta.
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), col(0, 0, 0, 0))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), col(0, 0, 0, 0))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), col(0, 0, 0, 0))
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameBorderSize(), 0)

    if draw_upper_text_button("Action", 1) then
        add_favorite_action()
    end

    reaper.ImGui_SameLine(ctx, 0, UPPER_BTN_SP_X)

    -- Setta il flag; l'apertura avviene più avanti in main_loop, a livello
    -- window (ID stack coerente con BeginPopup).
    if draw_upper_text_button("Fx", 2) then
        open_fx_popup = true
        fx_filter = ""
    end

    reaper.ImGui_SameLine(ctx, 0, UPPER_BTN_SP_X)

    -- Apre il popup Link (flag consumato in main_loop, a livello window)
    if draw_upper_text_button("Link", 4) then
        open_link_popup = true
        link_target_input = ""
        link_name_input = ""
    end

    -- Preset allineato al bordo destro della regione di contenuto:
    -- posizione X assoluta = (largo finestra - padding finestra) - larghezza bottone - margine.
    local win_w = reaper.ImGui_GetWindowSize(ctx)
    local win_pad_x = reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding())
    local fp_x = reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding())
    local preset_w = reaper.ImGui_CalcTextSize(ctx, "Preset") + fp_x * 2
    local preset_x = (win_w - win_pad_x) - preset_w - 2
    reaper.ImGui_SameLine(ctx, preset_x, 0)

    -- Apre il menu preset (flag consumato in main_loop, a livello window)
    if draw_upper_text_button("Preset", 3) then
        open_preset_popup = true
        preset_name_input = ""
    end

    reaper.ImGui_PopStyleVar(ctx)
    reaper.ImGui_PopStyleColor(ctx)
    reaper.ImGui_PopStyleColor(ctx)
    reaper.ImGui_PopStyleColor(ctx)

    reaper.ImGui_PopStyleVar(ctx)

    -- Linea grigia sotto la riga (colore da ImGui_Col_Separator)
    reaper.ImGui_Separator(ctx)
end

-- I favorite scorrono su righe che si riempono fino alla larghezza
-- disponibile e poi vanno a capo; quando le righe non entrano più in altezza,
-- a scrollare è la barra custom di sinistra (la nativa verticale è nascosta in
-- entrambi i modi).
-- Layout a flusso sequenziale: ogni bottone occupa la sua larghezza base più
-- un gap costante (FAV_BTN_SP_X): il gap non dipende dai nomi. L'hover
-- (font 1.1x) e la press cambiano solo la dimensione di disegno, centrata sul
-- rettangolo base: il bottone cresce in posto nei gap liberi, senza spostare
-- i vicini né ri-fluire; l'altezza di riga fissa (bottone + extra hover) lo
-- contiene.
function render_favorites_flow(extra_limit)
    -- extra_limit: la striscia riserbata a sinistra (scrollbar custom): le
    -- righe partono dopo di essa e il limite è la larghezza disponibile
    -- residua, così il bordo destro non esce dalla regione di contenuto.
    local shift = extra_limit or 0
    if #favorites > 0 then
        reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + FAV_SECTION_PAD_X + shift)
    end
    local _, row_sp_y = reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing())
    local fs = reaper.ImGui_GetFontSize(ctx)

    -- Padding sinistro: metà della crescita orizzontale più grande (font 1.1x
    -- del nome più lungo). Il primo bottone di ogni riga sta a metà della sua
    -- base; all'hover cresce di extra/2 a sinistra: così non arriva al bordo.
    local max_left_grow = 0
    for i = 1, #favorites do
        local display_name = favorite_display_name(favorites[i])
        reaper.ImGui_PushFont(ctx, nil, fs * FAV_HOVER_FONT)
        local hover_w = reaper.ImGui_CalcTextSize(ctx, display_name)
        reaper.ImGui_PopFont(ctx)
        local grow = (hover_w - reaper.ImGui_CalcTextSize(ctx, display_name)) / 2
        if grow > max_left_grow then
            max_left_grow = grow
        end
    end

    local limit = reaper.ImGui_GetContentRegionAvail(ctx) - max_left_grow

    local row_origin_x, row_origin_y = reaper.ImGui_GetCursorPos(ctx)
    row_origin_x = row_origin_x + max_left_grow
    local row_used = 0   -- offset orizzontale del prossimo slot da row_origin_x
    local content_max_x = 0

    for i = 1, #favorites do
        local display_name = favorite_display_name(favorites[i])
        local is_drag_src = (isDraggingFx and favorites[i] == draggedFx)
        local is_hover = (i == hovered_favorite_idx) and not is_drag_src
        local is_pressed = (i == pressed_favorite_idx) and not is_drag_src

        -- Le posizioni (wrapping, slot_x, avanzata) si calcolano SEMPRE sulla
        -- larghezza base: gap uniforme, primo bottone di ogni riga alla stessa
        -- X, e nessun ri-flusso all'hover (il bottone cresce in posto, nei gap
        -- liberi ai lati, senza spostare i vicini né andare a capo).
        local base_w = reaper.ImGui_CalcTextSize(ctx, display_name) + FAV_BTN_PAD_X

        if row_used > 0 and row_used + base_w > limit then
            row_origin_y = row_origin_y + FAV_BTN_H + FAV_HOVER_H + row_sp_y
            row_used = 0
        end

        local slot_x = row_origin_x + row_used

        -- Dimensione di disegno: base, poi hover (font 1.1x, più alto) e/o
        -- press. Il rettangolo cresce centrato su quello base: lo spostamento
        -- è extra/2 per lato, assorbito dal gap, i vicini restano fermi.
        local btn_w, btn_h = base_w, FAV_BTN_H
        if is_hover then
            reaper.ImGui_PushFont(ctx, nil, fs * FAV_HOVER_FONT)
            btn_w = reaper.ImGui_CalcTextSize(ctx, display_name) + FAV_BTN_PAD_X
            reaper.ImGui_PopFont(ctx)
            btn_h = FAV_BTN_H + FAV_HOVER_H
        end
        if is_pressed then
            btn_w = math.max(btn_w - FAV_PRESSED_SHRINK_X, 8)
            btn_h = math.max(btn_h - FAV_PRESSED_SHRINK_Y, 8)
        end

        -- Centrato sul rettangolo base; l'altezza di riga fissa (bottone +
        -- extra hover) fa sì che l'hover verticale stia dentro la riga.
        reaper.ImGui_SetCursorPos(
            ctx,
            slot_x + (base_w - btn_w) / 2,
            row_origin_y + (FAV_BTN_H + FAV_HOVER_H - btn_h) / 2
        )

        render_favorite_button(i, btn_w, btn_h)

        row_used = row_used + base_w + FAV_BTN_SP_X
        content_max_x = math.max(content_max_x, slot_x + base_w)
    end

    if #favorites > 0 then
        -- Il cursore finisce sul max del contenuto: gli scrollbar della child e
        -- l'altezza automatica (undocked) si dimensionano a tutti gli slot, non
        -- all'ultima riga (probabilmente più corta, 2px più bassa se non hover).
        reaper.ImGui_SetCursorPos(ctx, content_max_x, row_origin_y + FAV_BTN_H + FAV_HOVER_H)
        -- Un item a dimensione non nulla registra il cursore esteso come contenuto,
        -- altrimenti End/EndChild segnala che SetCursorPos ha allargato i confini
        -- senza nulla disegnato.
        reaper.ImGui_Dummy(ctx, 1, 1)
    end
end

-- Scrollbar custom sul bordo sinistro (entrambi i modi): la nativa è
-- nascosta (WindowFlags_NoScrollbar, la wheel continua a scrollare); qui la
-- track e il grab seguono lo stesso stato scroll della finestra corrente
-- (undocked: finestra principale, docked: child). Si disegna sempre: con il
-- contenuto dentro (max_y <= 0) il grab riempie tutta la track e non risponde
-- al drag.
function draw_left_scrollbar()
    local max_y = reaper.ImGui_GetScrollMaxY(ctx)
    -- Track leggermente più corta dell'area: inset in alto e in basso. Il grab
    -- viaggia dentro e resta un filo più corto della track (margine per lato).
    local track_top = sb_top_y + LEFT_SB_TRACK_INSET_Y
    local track_bottom = sb_top_y + sb_avail_h - LEFT_SB_TRACK_INSET_Y
    local track_h = track_bottom - track_top
    local grab_h, grab_top_y
    if max_y > 0 then
        local scroll_y = reaper.ImGui_GetScrollY(ctx)
        grab_h = math.max(24, track_h * sb_avail_h / (sb_avail_h + max_y))
        grab_h = math.min(grab_h, track_h - 2 * LEFT_SB_GRAB_MARGIN_Y)
        -- Il grab viaggia dentro la track senza mai toccarne il bordo.
        grab_top_y = track_top + LEFT_SB_GRAB_MARGIN_Y
            + (scroll_y / max_y) * (track_h - 2 * LEFT_SB_GRAB_MARGIN_Y - grab_h)
    else
        grab_h = track_h - 2 * LEFT_SB_GRAB_MARGIN_Y
        grab_top_y = track_top + LEFT_SB_GRAB_MARGIN_Y
    end

    -- Il mouse e la posizione della finestra sono in coordinate schermo: passa
    -- il mouse a coordinate della finestra corrente (docked: la child; è lo
    -- stesso spazio di sb_*). win_x/win_y servono anche per i rettagli
    -- DrawList (vedi sotto).
    local win_x, win_y = reaper.ImGui_GetWindowPos(ctx)
    local mouse_lx, mouse_ly = reaper.ImGui_GetMousePos(ctx)
    mouse_lx, mouse_ly = mouse_lx - win_x, mouse_ly - win_y

    -- Hit test manuale contro i rettagli (niente widget invisibili: i bottoni
    -- riposizionati ogni frame con SetCursorPos rompevano IsItemActive, e la
    -- scroll si aggiornava solo al rilascio). La striscia non deve rispondere
    -- se un'altra finestra è davanti (popup aperti sopra lo scaffale) o se un
    -- drag di favorite FX è in corso.
    local win_free = reaper.ImGui_IsWindowHovered(ctx) and not isDraggingFx
    local in_strip_x = mouse_lx >= sb_top_x and mouse_lx <= sb_top_x + LEFT_SB_W
    local over_grab = win_free and in_strip_x
        and mouse_ly >= grab_top_y and mouse_ly <= grab_top_y + grab_h
    local over_track = win_free and in_strip_x
        and mouse_ly >= track_top and mouse_ly <= track_bottom

    -- Il punto p della track corrisponde a (p - sb_top_y) / (track_h - grab_h)
    -- * max_y, clampato.
    local function scroll_at(rel_y)
        local s = (rel_y - track_top - LEFT_SB_GRAB_MARGIN_Y)
            / (track_h - 2 * LEFT_SB_GRAB_MARGIN_Y - grab_h) * max_y
        return math.min(math.max(s, 0), max_y)
    end

    local mouse_down = reaper.ImGui_IsMouseDown(ctx, 0)
    if mouse_down and max_y > 0 then
        if not sb_press_on_grab and over_grab then
            -- Punto trattenuto dentro il grab: latcha l'offset di pressione
            -- (il punto resta fermo rispetto al grab) e la scroll lo segue su
            -- ogni frame: niente snap al primo frame.
            sb_press_on_grab = true
            sb_press_off_y = mouse_ly - grab_top_y
        end
        if sb_press_on_grab then
            reaper.ImGui_SetScrollY(ctx, scroll_at(mouse_ly - sb_press_off_y))
        elseif over_track then
            -- Trascinata sulla track (fuori dal grab): il centro del grab va
            -- sotto il cursore; la scroll insegue finché non si prende il grab.
            reaper.ImGui_SetScrollY(ctx, scroll_at(mouse_ly - grab_h / 2))
        end
    else
        sb_press_on_grab = false
    end

    -- Visivi: la track è solo il bordo, il grab grigio scuro più stretto
    -- (centrato nella striscia, chiaro all'hover).
    -- La DrawList della finestra vive in coordinate SCHERMO (la docs di
    -- GetCursorScreenPos: "more useful to work with the DrawList API"): i
    -- rettagli vanno spostati all'origine della finestra, altrimenti finiscono
    -- fuori dalla clip rect della finestra e non si disegna mai nulla.
    local grab_col = LEFT_SB_GRAB_COL
    if over_grab or sb_press_on_grab then
        grab_col = LEFT_SB_GRAB_HOVER_COL
    end
    local grab_x = sb_top_x + (LEFT_SB_W - LEFT_SB_GRAB_W) / 2
    local dl = reaper.ImGui_GetWindowDrawList(ctx)
    reaper.ImGui_DrawList_AddRect(dl, sb_top_x + win_x, track_top + win_y, sb_top_x + win_x + LEFT_SB_W, track_bottom + win_y, LEFT_SB_TRACK_COL, LEFT_SB_W / 2)
    reaper.ImGui_DrawList_AddRectFilled(dl, grab_x + win_x, grab_top_y + win_y, grab_x + win_x + LEFT_SB_GRAB_W, grab_top_y + grab_h + win_y, grab_col, LEFT_SB_GRAB_W / 2)
end

-- Preview del drag di un favorite FX: finestra invisibile (niente background,
-- bordo e padding) che contiene solo il bottone, con le dimensioni ingrandite
-- (stato hover: nome a font 1.1x, larghezza e altezza slot), non quelle base
-- del button. Il quadratino visibile durante il drag è lui, non la finestra,
-- che resta trasparente.
-- Posizione: come in mtt_envelope_stealer, sotto al mouse corrente (offset
-- fisso), così il puntatore resta fuori dalla finestra; REAPER continua a
-- ricevere i movimenti e il rilascio, l'arrange mantiene aggiornata la sua
-- posizione interna del mouse (quella che riferisce BR_*AtMouseCursor) e il
-- drop si risolve.
function render_fx_drag_preview()
    local name = favorite_display_name(draggedFx)
    local fs = reaper.ImGui_GetFontSize(ctx)
    reaper.ImGui_PushFont(ctx, nil, fs * FAV_HOVER_FONT)
    local btn_w = reaper.ImGui_CalcTextSize(ctx, name) + FAV_BTN_PAD_X
    reaper.ImGui_PopFont(ctx)
    local btn_h = FAV_BTN_H + FAV_HOVER_H

    local mx, my = reaper.ImGui_GetMousePos(ctx)
    reaper.ImGui_SetNextWindowPos(ctx, mx, my + DRAG_PREVIEW_OFFSET_Y, reaper.ImGui_Cond_Always())
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

-- Colours of the menu look: mtt_FmodSync's palette, then the theme shades
-- over it (as theme_palette in FMOD Sync Mini, read every time: the theme may
-- change while the shelf is open).
function menu_style_colors()
    local out = {
        {reaper.ImGui_Col_WindowBg(), 0x191A1BFF}, {reaper.ImGui_Col_PopupBg(), 0x202223FF},
        {reaper.ImGui_Col_TitleBg(), 0x202223FF}, {reaper.ImGui_Col_TitleBgActive(), 0x292B2CFF},
        {reaper.ImGui_Col_Text(), 0xECEEEBFF}, {reaper.ImGui_Col_TextDisabled(), 0xA6AAA8FF},
        {reaper.ImGui_Col_Separator(), 0x464A49FF}, {reaper.ImGui_Col_Border(), 0x464A49FF},
        {reaper.ImGui_Col_FrameBg(), 0x2D3031FF}, {reaper.ImGui_Col_FrameBgHovered(), 0x373B3CFF},
        {reaper.ImGui_Col_FrameBgActive(), 0x3C4142FF}, {reaper.ImGui_Col_Button(), 0x303435FF},
        {reaper.ImGui_Col_ButtonHovered(), 0x414948FF}, {reaper.ImGui_Col_ButtonActive(), 0x4D5956FF},
        {reaper.ImGui_Col_CheckMark(), MENU_ACCENT}, {reaper.ImGui_Col_Header(), 0x3A3328FF},
        {reaper.ImGui_Col_HeaderHovered(), 0x4D4129FF}, {reaper.ImGui_Col_HeaderActive(), MENU_SELECTED},
        {reaper.ImGui_Col_TextSelectedBg(), 0xE89B3C66},
        {reaper.ImGui_Col_ScrollbarBg(), 0x00000000},
        {reaper.ImGui_Col_ScrollbarGrab(), 0x58534AFF}, {reaper.ImGui_Col_ScrollbarGrabHovered(), 0x756A4FFF},
        {reaper.ImGui_Col_ScrollbarGrabActive(), MENU_ACCENT},
    }
    local native = reaper.GetThemeColor("col_main_bg", 0)
    if not native or native == -1 then
        return out
    end
    local r, g, b = reaper.ColorFromNative(native)
    local light = (0.299 * r + 0.587 * g + 0.114 * b) > 128
    local function shade(d)
        if light then
            d = -d
        end
        local function c(v)
            return math.max(0, math.min(255, v + d))
        end
        return (c(r) << 24) | (c(g) << 16) | (c(b) << 8) | 0xFF
    end
    local theme = {
        {reaper.ImGui_Col_WindowBg(), shade(0)}, {reaper.ImGui_Col_PopupBg(), shade(10)},
        {reaper.ImGui_Col_FrameBg(), shade(20)}, {reaper.ImGui_Col_FrameBgHovered(), shade(30)},
        {reaper.ImGui_Col_FrameBgActive(), shade(36)},
        {reaper.ImGui_Col_Button(), shade(26)}, {reaper.ImGui_Col_ButtonHovered(), shade(38)},
        {reaper.ImGui_Col_ButtonActive(), shade(48)},
        {reaper.ImGui_Col_Separator(), shade(34)}, {reaper.ImGui_Col_Border(), shade(30)},
    }
    for _, pair in ipairs(theme) do
        out[#out + 1] = pair
    end
    if light then
        out[#out + 1] = {reaper.ImGui_Col_Text(), 0x1E1F20FF}
        out[#out + 1] = {reaper.ImGui_Col_TextDisabled(), 0x5E6260FF}
    end
    return out
end

-- Pushed before the popups open (window padding, rounding and colours are
-- read at BeginPopup) and popped after the last one ends. Overrides the
-- docked shelf's bordered frames (FrameBorderSize 1, FramePadding 4,1).
function push_menu_style()
    reaper.ImGui_PushFont(ctx, menu_font, MENU_FONT_SIZE)
    local colors = menu_style_colors()
    for _, pair in ipairs(colors) do
        reaper.ImGui_PushStyleColor(ctx, pair[1], pair[2])
    end
    menu_pushed_colors = #colors
    local vars = {
        {reaper.ImGui_StyleVar_WindowRounding(), 0}, {reaper.ImGui_StyleVar_ChildRounding(), 0},
        {reaper.ImGui_StyleVar_PopupRounding(), 0}, {reaper.ImGui_StyleVar_ScrollbarRounding(), 0},
        {reaper.ImGui_StyleVar_GrabRounding(), 0}, {reaper.ImGui_StyleVar_FrameRounding(), 0},
        {reaper.ImGui_StyleVar_FrameBorderSize(), 0}, {reaper.ImGui_StyleVar_PopupBorderSize(), 1},
        {reaper.ImGui_StyleVar_WindowPadding(), 10, 8},
        {reaper.ImGui_StyleVar_ItemSpacing(), 8, 5},
        {reaper.ImGui_StyleVar_FramePadding(), 9, 3},
    }
    for _, v in ipairs(vars) do
        if v[3] then
            reaper.ImGui_PushStyleVar(ctx, v[1], v[2], v[3])
        else
            reaper.ImGui_PushStyleVar(ctx, v[1], v[2])
        end
    end
    menu_pushed_vars = #vars
end

function pop_menu_style()
    reaper.ImGui_PopStyleVar(ctx, menu_pushed_vars)
    reaper.ImGui_PopStyleColor(ctx, menu_pushed_colors)
    reaper.ImGui_PopFont(ctx)
end

-- The primary button of a menu, in the accent (accent_button in mtt_FmodSync).
function menu_accent_button(label)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), MENU_SELECTED)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), MENU_SELECTED_HOVER)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), MENU_SELECTED_ACTIVE)
    local clicked = reaper.ImGui_Button(ctx, label)
    reaper.ImGui_PopStyleColor(ctx, 3)
    return clicked
end

-- Tooltip for the item just drawn, also while disabled (tip in mtt_FmodSync).
function menu_tip(text)
    if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled()) then
        if reaper.ImGui_BeginTooltip(ctx) then
            reaper.ImGui_PushTextWrapPos(ctx, reaper.ImGui_GetFontSize(ctx) * 30)
            reaper.ImGui_Text(ctx, text)
            reaper.ImGui_PopTextWrapPos(ctx)
            reaper.ImGui_EndTooltip(ctx)
        end
    end
end

-- Label in the left column, the control after it (setting_label in mtt_FmodSync).
function menu_label(text, help)
    reaper.ImGui_AlignTextToFramePadding(ctx)
    reaper.ImGui_Text(ctx, text)
    if help then
        menu_tip(help)
    end
    reaper.ImGui_SameLine(ctx, MENU_LABEL_W)
end

-- File trascinati dal Finder/Explorer sulla shelf: ognuno diventa un link
-- (nome = nome del file, duplicati scartati). ReaImGui non ha un bersaglio
-- di drop a livello finestra (nessun BeginDragDropTargetCustom): serve un
-- item. Il bersaglio è un InvisibleButton grande quanto la finestra,
-- sottomesso solo mentre un drag di file è in corso (GetDragDropPayloadFile
-- risponde true solo allora): fuori dal drag non ruba hover e click ai
-- bottoni né lo spostamento della finestra dallo sfondo. Sottomesso nella
-- finestra principale anche da docked: BeginDragDropTarget confronta la
-- root della finestra hoverata, quindi vale anche col mouse sulla child.
function draw_file_drop_target()
    if not reaper.ImGui_GetDragDropPayloadFile(ctx, 0) then
        return
    end
    local win_x, win_y = reaper.ImGui_GetWindowPos(ctx)
    local win_w, win_h = reaper.ImGui_GetWindowSize(ctx)
    -- Entro il padding orizzontale: il bordo destro non allarga il contenuto
    local pad_x = reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding())
    reaper.ImGui_SetCursorScreenPos(ctx, win_x + pad_x, win_y)
    reaper.ImGui_InvisibleButton(ctx, "##shelf_file_drop", math.max(1, win_w - 2 * pad_x), math.max(1, win_h))
    if reaper.ImGui_BeginDragDropTarget(ctx) then
        local ok, count = reaper.ImGui_AcceptDragDropPayloadFiles(ctx)
        if ok then
            for i = 0, count - 1 do
                local got, file = reaper.ImGui_GetDragDropPayloadFile(ctx, i)
                if got then
                    add_link_favorite(file)
                end
            end
        end
        reaper.ImGui_EndDragDropTarget(ctx)
    end
end

-- Link popup (adding) and Missing link modal (local path gone): opened at
-- window level as the FX and Preset popups, inside push_menu_style.
function draw_link_popups()
    if open_link_popup then
        reaper.ImGui_OpenPopup(ctx, "##LinkPopup")
        open_link_popup = false
    end

    if reaper.ImGui_BeginPopup(ctx, "##LinkPopup") then
        reaper.ImGui_SeparatorText(ctx, "Add a link")
        if reaper.ImGui_IsWindowAppearing(ctx) then
            -- Focus on the Link field (the next widget after its label)
            reaper.ImGui_SetKeyboardFocusHere(ctx, 0)
        end
        link_target_input = draw_link_target_field("link_target", link_target_input, reaper.GetProjectPath())

        menu_label("Name", "The text of the button. Empty: the file name, or the site for a web address.")
        reaper.ImGui_SetNextItemWidth(ctx, MENU_FIELD_W)
        local _, name_buf = reaper.ImGui_InputTextWithHint(ctx, "##link_name", "from the link", link_name_input)
        link_name_input = name_buf

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_SetCursorPosX(ctx, MENU_LABEL_W)
        local empty = clean_link_target(link_target_input) == ""
        reaper.ImGui_BeginDisabled(ctx, empty)
        if menu_accent_button("Add") then
            add_link_favorite(link_target_input, link_name_input)
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        reaper.ImGui_EndDisabled(ctx)
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Cancel##link") or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
            reaper.ImGui_CloseCurrentPopup(ctx)
        end

        reaper.ImGui_EndPopup(ctx)
    end

    if open_missing_popup then
        reaper.ImGui_OpenPopup(ctx, "Missing link##shelf_missing")
        open_missing_popup = false
    end

    if reaper.ImGui_BeginPopupModal(ctx, "Missing link##shelf_missing", nil, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
        -- The favorite is looked up by reference: if it was removed meanwhile
        -- or the project changed (list reloaded), the modal closes.
        local idx = nil
        for i, fav in ipairs(favorites) do
            if fav == missing_link_fav then
                idx = i
                break
            end
        end

        if not idx then
            missing_link_fav = nil
            reaper.ImGui_CloseCurrentPopup(ctx)
        else
            local fav = missing_link_fav
            reaper.ImGui_PushTextWrapPos(ctx, MENU_LABEL_W + MENU_FIELD_W)
            reaper.ImGui_Text(ctx, string.format('"%s" is no longer there:', fav.name))
            reaper.ImGui_TextDisabled(ctx, fav.target)
            reaper.ImGui_PopTextWrapPos(ctx)
            reaper.ImGui_Spacing(ctx)

            missing_target_input = draw_link_target_field("missing_target", missing_target_input, parent_dir(fav.target))

            reaper.ImGui_Spacing(ctx)
            reaper.ImGui_SetCursorPosX(ctx, MENU_LABEL_W)
            local new_target = clean_link_target(missing_target_input)
            reaper.ImGui_BeginDisabled(ctx, new_target == "")
            if menu_accent_button("Save and open") then
                fav.target = new_target
                save_favorites()
                missing_link_fav = nil
                reaper.ImGui_CloseCurrentPopup(ctx)
                open_link(fav)
            end
            reaper.ImGui_EndDisabled(ctx)
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, "Remove from shelf") then
                remove_favorite(idx)
                missing_link_fav = nil
                reaper.ImGui_CloseCurrentPopup(ctx)
            end
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, "Cancel##missing") or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
                missing_link_fav = nil
                reaper.ImGui_CloseCurrentPopup(ctx)
            end
        end

        reaper.ImGui_EndPopup(ctx)
    end
end

function main_loop()
    -- I bottoni (e quindi IsItemHovered) vengono renderizzati solo se la
    -- finestra è visible: senza reset, un indice stale di un frame visible
    -- passato farebbe credere che il mouse sia sopra a un button.
    current_hovered_idx = -1

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

    -- NoScrollbar: nasconde la barra nativa a destra (la wheel continua a
    -- scrollare); in entrambi i modi il suo posto lo prende la scrollbar
    -- custom di sinistra (docked: sulla child).
    local window_flags = reaper.ImGui_WindowFlags_NoCollapse() | reaper.ImGui_WindowFlags_NoResize()
        | reaper.ImGui_WindowFlags_NoScrollbar()

    -- A filo in alto: zero il margine verticale della finestra (il padding
    -- orizzontale resta). Prima di Begin: la content rect si calcola lì.
    local win_pad_x = reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding())
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), win_pad_x, 0)

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
        else
            -- Undocked: ricorda l'origine della regione di contenuto (la
            -- striscia sta lì, al bordo) e solo poi sposta tutto il contenuto
            -- a destra della striscia.
            sb_top_x, sb_top_y = reaper.ImGui_GetCursorPos(ctx)
            reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + LEFT_SB_W + LEFT_SB_GAP)
            reaper.ImGui_Dummy(ctx, 1, 1)
            _, sb_avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
        end
        hasToBeRemoved = {}
        if docked then
            -- La riga in alto si allinea alla prima riga di favorite (che la
            -- child sposta di LEFT_SB_W + LEFT_SB_GAP): stessa striscia di
            -- sinistra, come in undocked, dove lo shift è fatto prima di tutto.
            reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + LEFT_SB_W + LEFT_SB_GAP)
            reaper.ImGui_Dummy(ctx, 1, 1)
        end

        draw_action_fx_buttons()
        reset_upper_hover()

        if docked then
            -- La child riempie il resto della finestra. La sua barra nativa
            -- verticale è nascosta (NoScrollbar, la wheel continua a
            -- scrollare): il suo posto lo prende la barra custom di sinistra,
            -- disegnata dentro la child sul suo stato scroll. Quella
            -- orizzontale resta solo come fallback per un' singola favorite più
            -- larga del dock (con il wrapping a larghezza non dovrebbe
            -- comparire).
                if
                reaper.ImGui_BeginChild(
                ctx,
                "##shelf",
                0,
                0,
                0,
                reaper.ImGui_WindowFlags_NoScrollbar() | reaper.ImGui_WindowFlags_HorizontalScrollbar()
            )
            then
                -- Origine della striscia = origine del contenuto della child;
                -- le righe si spostano da sole (render_favorites_flow) perché
                -- il cursore della child non ha subito reset di riga.
                sb_top_x, sb_top_y = reaper.ImGui_GetCursorPos(ctx)
                _, sb_avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
                render_favorites_flow(LEFT_SB_W + LEFT_SB_GAP)
                reset_hovered_if_none()
                reset_pressed_if_none()
                draw_left_scrollbar()
                reaper.ImGui_EndChild(ctx)
            end
        else
            render_favorites_flow(LEFT_SB_W + LEFT_SB_GAP)
            reset_hovered_if_none()
            reset_pressed_if_none()
            draw_left_scrollbar()
        end

        draw_file_drop_target()

        -- Rimozione DOPO il loop, in ordine inverso per non sballare gli indici
        for j = #hasToBeRemoved, 1, -1 do
            remove_favorite(hasToBeRemoved[j])
        end

        -- Gestione del drop FX sulla finestra
        if ImGui.IsMouseReleased(ctx, 0) and isDraggingFx == true then

            isDraggingFx = false

            local payload = draggedFx.ident

            -- Drop sulla shelf stessa: no-op. IsWindowHovered non può dirlo:
            -- la preview drag (una finestra) sta sopra la shelf, e la famiglia
            -- AllowWhenOverlapped* è un flag di IsItemHovered — passarla a
            -- IsWindowHovered fa esplodere "Invalid flags for IsWindowHovered()!"
            -- (e il guard, falsato, lasciava passare l'inserimento). Hit test
            -- col rettangolo, come in draw_left_scrollbar (mouse e posizione
            -- della finestra sono in coordinate schermo): il puntatore sopra la
            -- shelf "resta" nell'arrange (BR_Take/TrackAtMouseCursor sono per
            -- posizione), quindi senza questo controllo un drop sulla shelf
            -- inseriva l'FX nelle tracce selezionate.
            local win_x, win_y = reaper.ImGui_GetWindowPos(ctx)
            local win_w, win_h = reaper.ImGui_GetWindowSize(ctx)
            local mx, my = reaper.ImGui_GetMousePos(ctx)
            local over_shelf =
                mx >= win_x and mx <= win_x + win_w and my >= win_y and my <= win_y + win_h

            if not over_shelf and payload then
                -- Si interroga per posizione, come in mtt_envelope_stealer:
                -- la posizione restituita è quella interna dell'arrange, che
                -- vale solo se l'arrange ha ricevuto gli eventi — il puntatore
                -- resta fuori dalla preview (sotto il cursore), quindi gli
                -- eventi arrivano all'arrange (vedi render_fx_drag_preview).
                local take = reaper.BR_TakeAtMouseCursor()
                if take then reaper.ValidatePtr(take, "MediaItem_Take*") end
                local track, context = reaper.BR_TrackAtMouseCursor()
                if track then reaper.ValidatePtr(track, "MediaTrack*") end

                if take then
                    -- Con la take del drop, insert_fx sceglie tra item
                    -- selezionati e l'item effettivamente bersagliato
                    insert_fx(payload, take)
                -- 0 = TCP (track panel), 1 = MCP, 2 = Arrange: drop su una
                -- traccia (track panel o arrange, senza item sotto il cursore)
                -- -> catena di quella traccia, ignorando le selezioni
                elseif track and (context == 0 or context == 2) then
                    insert_fx(payload, nil, track)
                else
                    --reaper.ShowConsoleMsg("No track found under cursor.\n")
                end
            end
        end

        -- Menu look for every popup below (Fx, Preset, Link, Missing link):
        -- pushed before their Begin, popped after the last End.
        push_menu_style()

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

        draw_link_popups()

        pop_menu_style()

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

    -- Ripristina il WindowPadding spinto prima di Begin (a filo in alto)
    reaper.ImGui_PopStyleVar(ctx)

    pop_style()

    -- Cursore sui favorite FX trascinabili: Dear ImGui non espone manina
    -- aperta/chiusa (l'unico "hand" è quello che punta il dito, come per gli
    -- hyperlink): si usa quindi quello sia sull'hover del button sia durante
    -- il drag, e la freccia in tutti gli altri casi (SetMouseCursor è
    -- per-frame: va resettata ad Arrow ogni frame).
    -- Si legge hovered_favorite_idx, non current_hovered_idx: quest'ultimo è
    -- già stato consumato (reset a -1) da reset_hovered_if_none più su in
    -- main_loop, e l'hover che conta è quello sincronizzato.
    local cursor = reaper.ImGui_MouseCursor_Arrow()
    local hovered_fav = favorites[hovered_favorite_idx]
    if isDraggingFx or (hovered_fav and (hovered_fav.type == "fx" or hovered_fav.type == "link")) then
        cursor = reaper.ImGui_MouseCursor_Hand()
    end
    reaper.ImGui_SetMouseCursor(ctx, cursor)

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
