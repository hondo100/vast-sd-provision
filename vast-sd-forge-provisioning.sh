#!/bin/bash

# Pfade innerhalb der Vast.ai Instanz (Forge Standard)
# HINWEIS: Prüfe ob dein Pfad /stable-diffusion-webui oder /stable-diffusion-webui-forge ist!
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
        # Verzeichnis erstellen
        DEST_DIR="$MODELS_DIR/$TYPE"
        mkdir -p "$DEST_DIR"

        # Dynamisches Header-Management
        # Wir starten mit einem Browser-User-Agent (wichtig für Civitai)
        EXTRA_HEADERS="--header='User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'"

        if [[ "$SOURCE" =~ ^[0-9]+$ ]]; then
            # Es ist eine Civitai-ID
            DOWNLOAD_URL="https://civitai.com/api/download/models/${SOURCE}?token=${CIVITAI_KEY}"
        else
            # Es ist eine URL
            DOWNLOAD_URL="$SOURCE"
            # Falls HuggingFace, füge den Token hinzu
            if [[ "$SOURCE" == *"huggingface.co"* ]]; then
                EXTRA_HEADERS="--header='Authorization: Bearer $HF_TOKEN' --header='User-Agent: Mozilla/5.0'"
            fi
        fi

        echo "📥 Downloading $NAME to $TYPE/..."
        
        # aria2c Ausführung
        # eval wird genutzt, um die Header-Strings korrekt zu übergeben
        eval aria2c --console-log-level=warn -x 16 -s 16 -k 1M \
                "$EXTRA_HEADERS" \
                -o "$NAME" -d "$DEST_DIR" --allow-overwrite=true --summary-interval=10 \
                "'$DOWNLOAD_URL'"

        if [ $? -eq 0 ]; then
            echo "✅ [SUCCESS] Saved to $TYPE/$NAME"
        else
            echo "❌ [FAILED] $NAME - Check Link or Token!"
        fi
    fi
done < "$LIST_FILE"

echo "==========================================================="
echo "🎉 PROVISIONING COMPLETE - FORGE IS READY"
echo "==========================================================="
