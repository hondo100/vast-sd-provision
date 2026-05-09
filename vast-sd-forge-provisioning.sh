#!/bin/bash

# --- KONFIGURATION (Wird über On-start Script befüllt) ---
# export GITHUB_PAT="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"
# export HF_TOKEN="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"
# export CIVITAI_KEY="dcd04020c1da7871d43d7f2c5fa0dbf2"

# Pfade innerhalb der Vast.ai Instanz (Standard für Forge/WebUI)
STORAGE_BASE="/workspace/stable-diffusion-webui/models"
LIST_FILE="/workspace/install_list.txt"

echo "-----------------------------------------------------------"
echo "Vast.ai Provisioning: Starting Model Setup"
echo "-----------------------------------------------------------"

# 1. install_list.txt von GitHub laden
LIST_URL="https://api.github.com/repos/hondo100/vast-sd-provision/contents/install_list.txt"
echo "Fetching install_list.txt..."

curl -s -H "Authorization: token $GITHUB_PAT" \
     -H "Accept: application/vnd.github.v3.raw" \
     "$LIST_URL" -o "$LIST_FILE"

if [ ! -f "$LIST_FILE" ]; then
    echo "ERROR: Could not load install_list.txt"
    exit 1
fi

# 2. Zeilenweise abarbeiten
while IFS='|' read -r SOURCE TYPE NAME || [ -n "$SOURCE" ]; do
    # Kommentare und Leerzeilen überspringen
    [[ "$SOURCE" =~ ^#.*$ ]] && continue
    [[ -z "$SOURCE" ]] && continue

    # Pfad säubern
    SOURCE=$(echo "$SOURCE" | xargs)
    TYPE=$(echo "$TYPE" | xargs)
    NAME=$(echo "$NAME" | xargs)

    echo "Processing: $NAME ..."

    # Zielverzeichnis erstellen
    DEST_DIR="$STORAGE_BASE/$TYPE"
    mkdir -p "$DEST_DIR"

    # URL bestimmen
    if [[ "$SOURCE" == http* ]]; then
        DOWNLOAD_URL="$SOURCE"
        # Header für HuggingFace falls nötig
        AUTH_HEADER="Authorization: Bearer $HF_TOKEN"
    else
        # Civitai Logik mit API Key
        DOWNLOAD_URL="https://civitai.com/api/download/models/${SOURCE}?token=${CIVITAI_KEY}"
        AUTH_HEADER="User-Agent: Mozilla/5.0"
    fi

    # Download mit aria2c (schnell und robust)
    echo "Downloading from: $DOWNLOAD_URL"
    aria2c --console-log-level=warn \
           -x 16 -s 16 -k 1M \
           --header="$AUTH_HEADER" \
           --summary-interval=10 \
           -o "$NAME" -d "$DEST_DIR" \
           "$DOWNLOAD_URL"

    if [ $? -eq 0 ]; then
        echo "[SUCCESS] $NAME installed in $TYPE"
    else
        echo "[ERROR] Failed to download $NAME"
    fi

done < "$LIST_FILE"

echo "-----------------------------------------------------------"
echo "Provisioning Complete!"
echo "-----------------------------------------------------------"
