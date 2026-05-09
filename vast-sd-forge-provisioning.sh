#!/bin/bash

# ======================================================================
# CONFIGURATION
# ======================================================================
GITHUB_USER="hondo100"
REPO_NAME="vast-sd-provision"
FILE_PATH="install_list.txt"

# PFAD-ANPASSUNG (Basierend auf deinem Terminal-Check)
BASE_PATH="/workspace/stable-diffusion-webui-forge"
MODELS_DIR="$BASE_PATH/models"
EXTENSIONS_DIR="$BASE_PATH/extensions"
LIST_FILE="/tmp/install_list.txt"

echo "==========================================================="
echo "🚀 VAST.AI PROVISIONING: $REPO_NAME"
echo "==========================================================="

# 1. install_list.txt RAW von GitHub laden
echo "--- Fetching install_list.txt ---"
LIST_URL="https://raw.githubusercontent.com/$GITHUB_USER/$REPO_NAME/main/$FILE_PATH"

# Download der Liste (nutzt das exportierte GITHUB_PAT)
curl -s -L -H "Authorization: token $GITHUB_PAT" "$LIST_URL" -o "$LIST_FILE"

# Sicherheitscheck: Falls Download fehlgeschlagen
if [ ! -s "$LIST_FILE" ] || grep -q "404" "$LIST_FILE" || grep -q "Invalid request" "$LIST_FILE"; then
    echo "❌ CRITICAL ERROR: Could not fetch install_list.txt from GitHub!"
    echo "Check URL: $LIST_URL"
    exit 1
fi

# 2. Liste abarbeiten
while IFS='|' read -r SOURCE TYPE NAME || [ -n "$SOURCE" ]; do
    # Kommentare und Leerzeilen überspringen
    [[ "$SOURCE" =~ ^#.*$ ]] && continue
    [[ -z "$SOURCE" ]] && continue

    # Whitespace säubern
    SOURCE=$(echo "$SOURCE" | xargs)
    TYPE=$(echo "$TYPE" | xargs)
    NAME=$(echo "$NAME" | xargs)

    if [[ "$TYPE" == "extensions" ]]; then
        echo "📦 Installing Extension: $NAME..."
        TARGET_DIR="$EXTENSIONS_DIR/$NAME"
        if [ ! -d "$TARGET_DIR" ]; then
            git clone "$SOURCE" "$TARGET_DIR"
        else
            echo "ℹ️ Extension $NAME already exists, skipping clone."
        fi
    else
        # Modell-Ordner vorbereiten
        DEST_DIR="$MODELS_DIR/$TYPE"
        mkdir -p "$DEST_DIR"

        # Standard Header (Mozilla Tarnung für Civitai)
        EXTRA_HEADERS="--header='User-Agent: Mozilla/5.0'"

        if [[ "$SOURCE" =~ ^[0-9]+$ ]]; then
            # FALL A: Civitai ID (rein numerisch)
            DOWNLOAD_URL="https://civitai.com/api/download/models/${SOURCE}?token=${CIVITAI_KEY}"
        else
            # FALL B: Direkte URL
            DOWNLOAD_URL="$SOURCE"
            if [[ "$SOURCE" == *"huggingface.co"* ]]; then
                EXTRA_HEADERS="--header='Authorization: Bearer $HF_TOKEN' --header='User-Agent: Mozilla/5.0'"
            fi
        fi

        echo "📥 Downloading $NAME to $TYPE/..."
        
        # aria2c Download
        eval aria2c --console-log-level=warn -x 16 -s 16 -k 1M \
                "$EXTRA_HEADERS" \
                -o "'$NAME'" -d "$DEST_DIR" --allow-overwrite=true "'$DOWNLOAD_URL'"

        [ $? -eq 0 ] && echo "✅ [SUCCESS] $NAME" || echo "❌ [FAILED] $NAME"
    fi
done < "$LIST_FILE"

echo "==========================================================="
echo "🎉 PROVISIONING COMPLETE - STARTING FORGE"
echo "==========================================================="

# 3. START VON FORGE (Nutzt python3 für Ubuntu Noble)
cd $BASE_PATH
python3 launch.py --listen --port 3000 --enable-insecure-extension-access --theme dark --xformers
