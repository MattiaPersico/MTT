#!/bin/bash

# Definisci i percorsi delle directory
dir1="/Applications/ReAG_Environment"
dir2="${HOME}/Library/Application Support/REAPER/Scripts/MTT"

# Lista dei file da rimuovere nel folder MTT
files_to_remove=(
    "mtt_global_functions.lua"
    "mtt_audioguide_paths.lua"
    "mtt_audioguide_functions.lua"
    "mtt_AudioGuide_Interface.lua"
)

# Verifica se il folder /Applications/ReAG_Environment esiste
if [ -d "$dir1" ]; then
    echo "Trovato l'ambiente ReAG. Disattivazione in corso..."
    # Se il folder esiste, disattiva l'ambiente
    source "$dir1/AG_P3Env_02/bin/deactivate"
    echo "Rimuovendo $dir1..."
    rm -rf "$dir1"
fi

# Verifica se il folder MTT esiste
if [ -d "$dir2" ]; then
    echo "Trovato il folder MTT. Rimozione dei file specifici in corso..."
    for file in "${files_to_remove[@]}"; do
        if [ -f "$dir2/$file" ]; then
            echo "Rimuovendo $file..."
            rm -f "$dir2/$file"
        else
            echo "Il file $file non esiste e non può essere rimosso."
        fi
    done
else
    echo "Il folder $dir2 non esiste. Nessuna operazione eseguita."
fi

echo "Operazioni completate."
