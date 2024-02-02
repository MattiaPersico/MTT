#!/bin/bash

# Ottieni l'ultimo ID del commit dalla tua repository git
commit_id=$(git rev-parse HEAD)

# Ottieni il timestamp corrente in formato ISO 8601
timestamp=$(date --utc +%FT%TZ)

# File index.xml
file="index.xml"

# Sostituisci il placeholder dell'ID del commit e del timestamp nel tuo file index.xml
# Nota: assicurati che i placeholder 'your_commit_id_here' e 'your_timestamp_here' siano univoci e presenti nel tuo file XML
sed -i "s/your_commit_id_here/${commit_id}/g" $file
sed -i "s/your_timestamp_here/${timestamp}/g" $file

# Aggiungi qui altri comandi sed se necessario per sostituire altri valori

echo "Index.xml updated with the latest commit id and timestamp."
