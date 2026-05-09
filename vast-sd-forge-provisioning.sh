#!/bin/bash

# Pfade innerhalb der Vast.ai Instanz (Forge Standard)
BASE_PATH="/workspace/stable-diffusion-webui"
MODELS_DIR="$BASE_PATH/models"
EXTENSIONS_DIR="$BASE_PATH/extensions"
LIST_FILE="/workspace/install_list.txt"

echo "==========================================================="
echo "🚀 VAST.AI PROVISIONING: MODELS, LORAS & EXTENSIONS"
echo "==========================================================="

# 1. install_list.txt von deinem GitHub laden
LIST_URL="https://api.github.com/repos/hondo100/vast-sd-provision/contents/install_list.txt"
curl -s -H "Authorization: token $GITHUB_PAT" \
     -H "Accept: application/vnd.github.v3.raw" \
     "$LIST_URL" -o "$LIST_FILE"

if [ ! -f "$LIST_FILE" ]; then
    echo "❌ CRITICAL ERROR: install_list.txt not found!"
    exit 1
fi

# 2. Liste abarbeiten
while IFS='|' read -r SOURCE TYPE NAME || [ -n "$SOURCE" ]; do
    # Kommentare und Leerzeilen überspringen
    [[ "$SOURCE" =~ ^#.*$ ]] && continue
    [[ -z "$SOURCE" ]] && continue

    # Whitespace entfernen
    SOURCE=$(echo "$SOURCE" | xargs)
    TYPE=$(echo "$TYPE" | xargs)
    NAME=$(echo "$NAME" | xargs)

    # UNTERSCHEIDUNG: Erweiterung vs. Modell
    if [[ "$TYPE" == "extensions" ]]; then
        echo "📦 Installing Extension: $NAME..."
        TARGET_DIR="$EXTENSIONS_DIR/$NAME"
        if [ ! -d "$TARGET_DIR" ]; then
            git clone "$SOURCE" "$TARGET_DIR"
            echo "✅ Extension $NAME installed."
        else
            echo "ℹ️ Extension $NAME already exists, skipping."
        fi
    else
        # Es ist ein Modell/LoRA/Upscaler
        DEST_DIR="$MODELS_DIR/$TYPE"
        mkdir -p "$DEST_DIR"

        # URL-Logik: HuggingFace vs Civitai ID
        if [[ "$SOURCE" == http* ]]; then
            DOWNLOAD_URL="$SOURCE"
            AUTH_HEADER="Authorization: Bearer $HF_TOKEN"
        else
            DOWNLOAD_URL="https://civitai.com/api/download/models/${SOURCE}?token=${CIVITAI_KEY}"
            AUTH_HEADER="User-Agent: Mozilla/5.0"
        fi

        echo "📥 Downloading $NAME to $TYPE/..."
        # -x 16 -s 16 für maximale Download-Geschwindigkeit
        aria2c --console-log-level=warn -x 16 -s 16 -k 1M \
               --header="$AUTH_HEADER" \
               -o "$NAME" -d "$DEST_DIR" --allow-overwrite=true "$DOWNLOAD_URL"

        if [ $? -eq 0 ]; then
            echo "✅ [SUCCESS] Saved to $TYPE/$NAME"
        else
            echo "❌ [FAILED] $NAME"
        fi
    fi
done < "$LIST_FILE"

echo "==========================================================="
echo "🎉 PROVISIONING COMPLETE - FORGE IS READY"
echo "==========================================================="
