#!/bin/bash

echo "==========================================================="
echo "🚀 VAST.AI PROVISIONING: STARTING"
echo "==========================================================="

# 1. System-Tools (Aria2 Paketname ist 'aria2')
apt-get update && apt-get install -y aria2 git curl python3-pip python3-venv

# 2. Forge-Pfad prüfen oder installieren
if [ -d "/workspace/stable-diffusion-webui-forge" ]; then
    BASE_PATH="/workspace/stable-diffusion-webui-forge"
elif [ -d "/workspace/stable-diffusion-webui" ]; then
    BASE_PATH="/workspace/stable-diffusion-webui"
else
    cd /workspace
    git clone https://github.com/lllyasviel/stable-diffusion-webui-forge.git
    BASE_PATH="/workspace/stable-diffusion-webui-forge"
fi

cd "$BASE_PATH"
MODELS_DIR="$BASE_PATH/models"
EXTENSIONS_DIR="$BASE_PATH/extensions"
LIST_FILE="/tmp/install_list.txt"

# 3. install_list.txt laden
LIST_URL="https://raw.githubusercontent.com/hondo100/vast-sd-provision/main/install_list.txt"
curl -s -L -H "Authorization: token $GITHUB_PAT" "$LIST_URL" -o "$LIST_FILE"

# 4. Liste abarbeiten
while IFS='|' read -r SOURCE TYPE NAME || [ -n "$SOURCE" ]; do
    [[ "$SOURCE" =~ ^#.*$ ]] && continue
    [[ -z "$SOURCE" ]] && continue
    SOURCE=$(echo "$SOURCE" | xargs); TYPE=$(echo "$TYPE" | xargs); NAME=$(echo "$NAME" | xargs)

    if [[ "$TYPE" == "extensions" ]]; then
        echo "📦 Extension: $NAME"
        TARGET_DIR="$EXTENSIONS_DIR/$NAME"
        [ ! -d "$TARGET_DIR" ] && git clone "$SOURCE" "$TARGET_DIR"
    else
        DEST_DIR="$MODELS_DIR/$TYPE"
        mkdir -p "$DEST_DIR"
        
        # Vereinfachte Download-Logik ohne komplexe Header-Variablen
        if [[ "$SOURCE" =~ ^[0-9]+$ ]]; then
            DOWNLOAD_URL="https://civitai.com/api/download/models/${SOURCE}?token=${CIVITAI_KEY}"
            echo "📥 Downloading $NAME from Civitai..."
            aria2c --console-log-level=warn -x 16 -s 16 -k 1M -o "$NAME" -d "$DEST_DIR" --allow-overwrite=true "$DOWNLOAD_URL"
        elif [[ "$SOURCE" == *"huggingface.co"* ]]; then
            DOWNLOAD_URL="$SOURCE"
            echo "📥 Downloading $NAME from HuggingFace..."
            aria2c --console-log-level=warn -x 16 -s 16 -k 1M --header="Authorization: Bearer $HF_TOKEN" -o "$NAME" -d "$DEST_DIR" --allow-overwrite=true "$DOWNLOAD_URL"
        else
            DOWNLOAD_URL="$SOURCE"
            echo "📥 Downloading $NAME..."
            aria2c --console-log-level=warn -x 16 -s 16 -k 1M -o "$NAME" -d "$DEST_DIR" --allow-overwrite=true "$DOWNLOAD_URL"
        fi
    fi
done < "$LIST_FILE"

echo "==========================================================="
echo "🎉 STARTING FORGE"
echo "==========================================================="

cd "$BASE_PATH"
# --skip-python-version-check ist wichtig für Ubuntu 24.04 (Python 3.12)
python3 launch.py --listen --port 7860 --enable-insecure-extension-access --theme dark --xformers --skip-python-version-check
