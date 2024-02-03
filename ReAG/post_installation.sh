#!/bin/bash

# Definisci i percorsi delle directory
REAG_DIR="/Applications/ReAG_Environment"
SHARED_DIR="/Users/Shared"
MTT_DEST_DIR="${HOME}/Library/Application Support/REAPER/Scripts/MTT"

# Lista dei file da spostare
files_to_move=(
    "mtt_global_functions.lua"
    "mtt_audioguide_paths.lua"
    "mtt_audioguide_functions.lua"
    "mtt_AudioGuide_Interface.lua"
)

# Sblocca tutti i permessi per il folder ReAG_Environment e il suo contenuto
echo "Sblocco dei permessi per $REAG_DIR..."
chmod -R u+rwx "$REAG_DIR"

# Crea la directory di destinazione se non esiste
if [ ! -d "$MTT_DEST_DIR" ]; then
    echo "Creazione della directory di destinazione $MTT_DEST_DIR..."
    mkdir -p "$MTT_DEST_DIR"
fi

# Sposta i file specifici
echo "Spostamento dei file specifici in $MTT_DEST_DIR..."
for file in "${files_to_move[@]}"; do
    if [ -f "$SHARED_DIR/$file" ]; then
        echo "Sblocco dei permessi per $file..."
        chmod u+rwx "$SHARED_DIR/$file"
        echo "Spostamento di $file in $MTT_DEST_DIR..."
        mv "$SHARED_DIR/$file" "$MTT_DEST_DIR"
    else
        echo "Il file $file non esiste in $SHARED_DIR e non può essere spostato."
    fi
done

# Aggiungi le eccezioni del gatekeeper
echo "Aggiunta di $REAG_DIR alle eccezioni del Gatekeeper..."
spctl --add --recursive "$REAG_DIR"

# Attiva l'ambiente virtuale
echo "Attivazione dell'ambiente virtuale..."
source /Applications/ReAG_Environment/AG_P3Env_02/bin/activate

echo "Script completato."
