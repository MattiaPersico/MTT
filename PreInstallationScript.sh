#!/bin/bash

# Definisci i percorsi dei file e delle cartelle da rimuovere
MTT_FOLDER="$HOME/Library/Application Support/REAPER/Scripts/MTT"
MTT_INTERFACE_FILE="$HOME/Library/Application Support/REAPER/Scripts/mtt_AudioGuide_Interface.lua"
REAG_ENVIRONMENT_FOLDER="/Applications/ReAG_Environment"

# Funzione per rimuovere una cartella con il suo contenuto
remove_folder() {
    if [ -d "$1" ]; then
        echo "Rimuovere la cartella: $1"
        rm -rf "$1"
    else
        echo "La cartella $1 non esiste e non sarà rimossa."
    fi
}

# Funzione per rimuovere un file
remove_file() {
    if [ -f "$1" ]; then
        echo "Rimuovere il file: $1"
        rm -f "$1"
    else
        echo "Il file $1 non esiste e non sarà rimosso."
    fi
}

# Chiama le funzioni per rimuovere le risorse
remove_folder "$MTT_FOLDER"
remove_file "$MTT_INTERFACE_FILE"
remove_folder "$REAG_ENVIRONMENT_FOLDER"

# Fine dello script
exit 0
