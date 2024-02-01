#!/bin/bash

# Percorsi sorgente
SHARED_FOLDER="/Users/Shared"
MTT_FOLDER="$SHARED_FOLDER/MTT"
MTT_INTERFACE_FILE="$SHARED_FOLDER/mtt_AudioGuide_Interface.lua"

# Percorsi di destinazione
REAPER_SCRIPTS_FOLDER="$HOME/Library/Application Support/REAPER/Scripts"
DEST_MTT_FOLDER="$REAPER_SCRIPTS_FOLDER/MTT"
DEST_MTT_INTERFACE_FILE="$REAPER_SCRIPTS_FOLDER/mtt_AudioGuide_Interface.lua"

# Sposta la cartella MTT
mv "$MTT_FOLDER" "$DEST_MTT_FOLDER"

# Sposta il file mtt_AudioGuide_Interface.lua
mv "$MTT_INTERFACE_FILE" "$DEST_MTT_INTERFACE_FILE"

# Rimuovi il flag di quarantena dalla cartella ReAG_Environment
xattr -dr com.apple.quarantine "/Applications/ReAG_Environment"

# Cambia la proprietà e i permessi della cartella MTT e del suo contenuto
chown -R "$USER":staff "$DEST_MTT_FOLDER"
chmod -R u+rwX,go+rX "$DEST_MTT_FOLDER"

# Cambia la proprietà e i permessi del file mtt_AudioGuide_Interface.lua
chown "$USER":staff "$DEST_MTT_INTERFACE_FILE"
chmod u+rw,go+r "$DEST_MTT_INTERFACE_FILE"

# Cambia la proprietà e i permessi ricorsivamente di /Applications/ReAG_Environment
chown -R "$USER":staff "/Applications/ReAG_Environment"
chmod -R u+rwX,go+rX "/Applications/ReAG_Environment"

source /Applications/ReAG_Environment/AG_P3Env_02/bin/activate


# Controlla se ci sono stati errori
if [ $? -ne 0 ]; then
    echo "Si è verificato un errore durante l'esecuzione dello script."
    exit 1
else
    echo "Installazione completata con successo."
fi

exit 0