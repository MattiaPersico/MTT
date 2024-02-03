#!/bin/bash

# Imposta la variabile REAG_DIR con il percorso della cartella target
REAG_DIR="/Applications/ReAG_Environment"

# Ottieni il nome utente dell'utente attuale
CURRENT_USER=$(whoami)

# Cambia il proprietario di REAG_DIR e di tutti i suoi contenuti all'utente attuale
chown -R "$CURRENT_USER" "$REAG_DIR"

# Imposta i permessi completi per il proprietario, il gruppo e gli altri
chmod -R 777 "$REAG_DIR"

# Rimuovi le eventuali ACL esistenti
chmod -R -N "$REAG_DIR"

# Verifica e modifica le ACL per dare pieni permessi a tutti
# Questo comando imposta l'ACL per garantire pieni permessi agli utenti 'everyone'
chmod +a "everyone allow read,write,execute,delete,append,file_inherit,directory_inherit" "$REAG_DIR"

# Attiva l'ambiente specificato
source /Applications/ReAG_Environment/AG_P3Env_02/bin/activate