#!/bin/bash

# Definisci i percorsi delle directory
REAG_DIR="/Applications/ReAG_Environment"
MTT_SOURCE_DIR="/Users/Shared/MTT"
MTT_DEST_DIR="${HOME}/Library/Application Support/REAPER/Scripts"

# Sblocca tutti i permessi per il folder ReAG_Environment e il suo contenuto
echo "Sblocco dei permessi per $REAG_DIR..."
chmod -R u+rwx "$REAG_DIR"

# Sblocca tutti i permessi per il folder MTT e il suo contenuto
echo "Sblocco dei permessi per $MTT_SOURCE_DIR..."
chmod -R u+rwx "$MTT_SOURCE_DIR"

# Sposta il folder MTT con il suo contenuto
if [ ! -d "$MTT_DEST_DIR" ]; then
    echo "Creazione della directory di destinazione $MTT_DEST_DIR..."
    mkdir -p "$MTT_DEST_DIR"
fi
if [ -d "$MTT_SOURCE_DIR" ]; then
    echo "Spostamento di $MTT_SOURCE_DIR in $MTT_DEST_DIR..."
    mv "$MTT_SOURCE_DIR" "$MTT_DEST_DIR"
    echo "Spostamento completato."
else
    echo "La directory sorgente $MTT_SOURCE_DIR non esiste. Nessuna operazione eseguita."
fi

# Aggiungi le eccezioni del gatekeeper
echo "Aggiunta di $REAG_DIR alle eccezioni del Gatekeeper..."
spctl --add --recursive "$REAG_DIR"

# Attiva l'ambiente virtuale
echo "Attivazione dell'ambiente virtuale..."
source /Applications/ReAG_Environment/AG_P3Env_02/bin/activate

echo "Script completato."
