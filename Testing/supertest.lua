-- Variabile globale per controllare la visibilità della finestra
local ctx = reaper.ImGui_CreateContext("supertest")

-- Struttura dati per i preferiti
local FAVORITES_FILENAME = ".reaper_supertest_favorites.txt"
local favorites = {} -- tabella con {action_id, action_name}
local hovered_button = -1 -- indice del bottone su cui il mouse è in hover (-1 = nessuno)
local right_click_held = false -- flag per rilevare click destro

-- Carica i preferiti dal file nel progetto corrente
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

    -- Parsing del file (formato: action_id|action_name per riga)
    favorites = {}
    for line in content:gmatch("[^\n]+") do
        local id_str, name = line:match("^(%d+)|(.+)$")
        if id_str and name then
            table.insert(favorites, {id = tonumber(id_str), name = name})
        end
    end
end

-- Salva i preferiti nel file del progetto
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

    -- Salviamo i dati come testo semplice (action_id|action_name per riga)
    for i, fav in ipairs(favorites) do
        file:write(string.format("%d|%s\n", fav.id, fav.name))
    end

    file:close()
end

-- Aggiunge un nuovo slot preferito
function add_favorite()
    -- Per ora creiamo un placeholder che l'utente potrà configurare
    table.insert(
        favorites,
        {
            id = 0, -- da compilare con l'action ID reale
            name = generate_random_string(4),
            --'Nuova Action',
            is_new = true -- flag per indicare che è appena stato aggiunto
        }
    )

    save_favorites()
end

-- Rimuove uno slot preferito
function remove_favorite(index)
    if index >= 1 and index <= #favorites then
        table.remove(favorites, index)
        save_favorites()
    end
end

-- Funzione per applicare lo stile "EnvelopeStealer"
function apply_style()
    -- Backgrounds
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

    -- Headers & Menus
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

    -- Buttons
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

    -- Resize Grip
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

    -- Title Bars
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

    -- Frames & Sliders
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

    -- Other Elements
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

    -- Scrollbars
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

    -- Rounding (Styling)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 7)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ScrollbarRounding(), 7)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_GrabRounding(), 7)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ChildRounding(), 7)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 5)
end

function pop_style()
    -- Rounding (5 PopVars)
    reaper.ImGui_PopStyleVar(ctx)
    reaper.ImGui_PopStyleVar(ctx)
    reaper.ImGui_PopStyleVar(ctx)
    reaper.ImGui_PopStyleVar(ctx)
    reaper.ImGui_PopStyleVar(ctx)

    -- Scrollbar Colors (4 PopColors)
    reaper.ImGui_PopStyleColor(ctx)
    reaper.ImGui_PopStyleColor(ctx)
    reaper.ImGui_PopStyleColor(ctx)
    reaper.ImGui_PopStyleColor(ctx)

    -- Scrollbar Size Var (1 PopVar)
    reaper.ImGui_PopStyleVar(ctx)

    -- Separator & Checkmark (2 PopColors)
    reaper.ImGui_PopStyleColor(ctx)
    reaper.ImGui_PopStyleColor(ctx)

    -- Frames & Sliders (5 PopColors)
    reaper.ImGui_PopStyleColor(ctx)
    reaper.ImGui_PopStyleColor(ctx)
    reaper.ImGui_PopStyleColor(ctx)
    reaper.ImGui_PopStyleColor(ctx)
    reaper.ImGui_PopStyleColor(ctx)

    -- Title Bars (3 PopColors)
    reaper.ImGui_PopStyleColor(ctx)
    reaper.ImGui_PopStyleColor(ctx)
    reaper.ImGui_PopStyleColor(ctx)

    -- Resize Grip (3 PopColors)
    reaper.ImGui_PopStyleColor(ctx)
    reaper.ImGui_PopStyleColor(ctx)
    reaper.ImGui_PopStyleColor(ctx)

    -- Buttons (3 PopColors)
    reaper.ImGui_PopStyleColor(ctx)
    reaper.ImGui_PopStyleColor(ctx)
    reaper.ImGui_PopStyleColor(ctx)

    -- Headers & Menus (4 PopColors)
    reaper.ImGui_PopStyleColor(ctx)
    reaper.ImGui_PopStyleColor(ctx)
    reaper.ImGui_PopStyleColor(ctx)
    reaper.ImGui_PopStyleColor(ctx)

    -- Backgrounds (3 PopColors)
    reaper.ImGui_PopStyleColor(ctx)
    reaper.ImGui_PopStyleColor(ctx)
    reaper.ImGui_PopStyleColor(ctx)
end

function generate_random_string(length)
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local result = ""

    for i = 1, length do
        -- Use math.random to get an index into the string 'chars'
        result = result .. tostring(math.random(0, 9))
    end

    return result
end

function render_wnd()
    apply_style()

    local visible, is_open = reaper.ImGui_Begin(ctx, "Action Favorites", true)

    if visible then
        -- Lista degli slot preferiti
        for i = 1, #favorites do
            local fav = favorites[i]

            -- Concatena ID al nome per il testo del bottone
            local btn_text = string.format("%s (ID: %d)", fav.name, fav.id)

            -- Ogni bottone deve avere un ID unico. Usiamo '##' per evitare collisioni con testi simili se possibile,
            -- ma ImGui Button accetta solo id se c'è ##, o label sola. Qui usiamo una combinazione unica.
            local unique_id = string.format(fav.name .. "##%d", i)

            local pressed = reaper.ImGui_Button(ctx, unique_id)

            -- CRITICO: Controlla IsItemHovered SUBITO dopo il Button creato per questo specifico indice
            local is_hovered = reaper.ImGui_IsItemHovered(ctx)

            if is_hovered then
                hovered_button = i -- Aggiorna solo se questo bottone è effettivamente in hover
            end

            if pressed then
                save_favorites()
                break
            end

            if is_hovered and reaper.ImGui_IsMouseClicked(ctx, 1) then
                remove_favorite(i)
                break
            end

            -- Opzionale: Tooltip per le favorite
            if is_hovered and not pressed then
                reaper.ImGui_SetTooltip(ctx, string.format("Click SX: Esegui\nClick DX: Rimuovi"))
            end
        end

        -- Bottone "+" per aggiungere nuovi slot (sempre in fondo)
        local add_btn_text = "+ ##add_button" -- ID unico per il bottone aggiungi
        local add_pressed = reaper.ImGui_Button(ctx, add_btn_text)

        local is_add_hovered = reaper.ImGui_IsItemHovered(ctx)

        if add_pressed then
            add_favorite()
        end

        if is_add_hovered then
            reaper.ImGui_SetTooltip(ctx, "Aggiungi una nuova action")
        end

        -- Non usare IsItemHovered globale per la variabile hovered_button
        -- perché confonde il ciclo precedente. Usa un flag separato o ignora hovered_button per il "+".

        reaper.ImGui_End(ctx)
    end

    pop_style()

    return is_open
end

-- Funzione principale che avvia il loop defer
function main()
    -- Carica i preferiti all'avvio
    if #favorites == 0 then
        load_favorites()
    end

    if not render_wnd() then
        return false -- Ferma il defer se la finestra è chiusa
    end

    reaper.defer(main) -- Richiama se stesso
end

-- Avvio iniziale (da chiamare una volta)
main()
