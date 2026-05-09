#!/bin/bash

# ======================================================================
# CONFIGURATION
# ======================================================================
# Falls aria2c fehlt, installieren wir es jetzt schnell
if ! command -v aria2c &> /dev/null; then
    echo "--- Installing aria2c ---"
    apt-get update && apt-get install -y aria2c
fi

GITHUB_USER="hondo100"
REPO_NAME="vast-sd-provision"
FILE_PATH="install_list.txt"

# PFAD-FINDER: Wir suchen, wo Forge liegt
if [ -d "/workspace/stable-diffusion-webui-forge" ]; then
    BASE_PATH="/workspace/stable-diffusion-webui-forge"
elif [ -d "/workspace/stable-diffusion-webui" ]; then
    BASE_PATH="/workspace/stable-diffusion-webui"
else
    # Falls gar nichts da ist, klonen wir Forge (Sicherheitsnetz)
    echo "--- Forge not found, cloning now ---"
    cd /workspace
    git clone https://github.com/lllyasviel/stable-diffusion-webui-forge.git
    BASE_PATH="/workspace/stable-diffusion-webui-forge"
fi

MODELS_DIR="$BASE_PATH/models"
EXTENSIONS_DIR="$BASE_PATH/extensions"
LIST_FILE="/tmp/install_list.txt"

echo "==========================================================="
echo "🚀 VAST.AI PROVISIONING: STARTING"
echo "==========================================================="

# 1. install_list.txt laden
LIST_URL="https://raw.githubusercontent.com/$GITHUB_USER/$REPO_NAME/main/$FILE_PATH"
curl -s -L -H "Authorization: token $GITHUB_PAT" "$LIST_URL" -o "$LIST_FILE"

# 2. Liste abarbeiten (wie gehabt)
while IFS='|' read -r SOURCE TYPE NAME || [ -n "$SOURCE" ]; do
    [[ "$SOURCE" =~ ^#.*$ ]] && continue
    [[ -z "$SOURCE" ]] && continue
    SOURCE=$(echo "$SOURCE" | xargs); TYPE=$(echo "$TYPE" | xargs); NAME=$(echo "$NAME" | xargs)

    if [[ "$TYPE" == "extensions" ]]; then
        echo "📦 Installing Extension: $NAME..."
        TARGET_DIR="$EXTENSIONS_DIR/$NAME"
        [ ! -d "$TARGET_DIR" ] && git clone "$SOURCE" "$TARGET_DIR"
    else
        DEST_DIR="$MODELS_DIR/$TYPE"
        mkdir -p "$DEST_DIR"
        EXTRA_HEADERS="--header='User-Agent: Mozilla/5.0'"
        if [[ "$SOURCE" =~ ^[0-9]+$ ]]; then
            DOWNLOAD_URL="https://civitai.com/api/download/models/${SOURCE}?token=${CIVITAI_KEY}"
        else
            DOWNLOAD_URL="$SOURCE"
            [[ "$SOURCE" == *"huggingface.co"* ]] && EXTRA_HEADERS="--header='Authorization: Bearer $HF_TOKEN' --header='User-Agent: Mozilla/5.0'"
        fi
        echo "📥 Downloading $NAME..."
        aria2c --console-log-level=warn -x 16 -s 16 -k 1M $EXTRA_HEADERS -o "$NAME" -d "$DEST_DIR" --allow-overwrite=true "$DOWNLOAD_URL"
    fi
done < "$LIST_FILE"

echo "==========================================================="
echo "🎉 STARTING FORGE"
echo "==========================================================="

cd $BASE_PATH
python3 launch.py --listen --port 7860 --enable-insecure-extension-access --theme dark --xformers
