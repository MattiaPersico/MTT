#!/bin/bash

REAG_DIR="/Applications/ReAG_Environment"

# Ottieni il nome utente
CURRENT_USER=$(whoami)

# Cambia il proprietario di REAG_DIR
chown -R "$CURRENT_USER" "$REAG_DIR"

# u+rwx: Imposta i permessi di lettura, scrittura ed esecuzione per l'utente
chmod -R u+rwx "$REAG_DIR"

# Aggiungi il percorso REAG_DIR e i suoi contenuti all'elenco delle applicazioni consentite
spctl --add --recursive "$REAG_DIR"

# Attiva l'ambiente
source /Applications/ReAG_Environment/AG_P3Env_02/bin/activate
