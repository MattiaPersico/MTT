#!/bin/bash

# Definisci i percorsi delle directory
dir1="/Applications/ReAG_Environment"
dir2="${HOME}/Library/Application Support/REAPER/Scripts/MTT"

# Verifica se il folder /Applications/ReAG_Environment esiste
if [ -d "$dir1" ]; then
    echo "Trovato l'ambiente ReAG. Disattivazione in corso..."
    # Se il folder esiste, disattiva l'ambiente
    source "$dir1/AG_P3Env_02/bin/deactivate"
    echo "Rimuovendo $dir1..."
    rm -rf "$dir1"
fi

# Verifica e rimuovi la seconda directory se esiste
if [ -d "$dir2" ]; then
    echo "Rimuovendo $dir2..."
    rm -rf "$dir2"
fi

echo "Operazioni completate."
