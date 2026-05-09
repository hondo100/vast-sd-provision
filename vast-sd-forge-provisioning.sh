#!/bin/bash

echo "==========================================================="
echo "🚀 VAST.AI PROVISIONING: STARTING"
echo "==========================================================="

# 1. System-Tools nachinstallieren
echo "--- Checking System Tools ---"
apt-get update && apt-get install -y aria2c git curl python3-pip

# 2. Forge-Pfad prüfen oder Forge installieren
if [ -d "/workspace/stable-diffusion-webui-forge" ]; then
    BASE_PATH="/workspace/stable-diffusion-webui-forge"
    echo "✅ Forge found in /workspace/stable-diffusion-webui-forge"
elif [ -d "/workspace/stable-diffusion-webui" ]; then
    BASE_PATH="/workspace/stable-diffusion-webui"
    echo "✅ Forge found in /workspace/stable-diffusion-webui"
else
    echo "⚠️ Forge not found. Installing Forge now..."
    cd /workspace
    git clone https://github.com/lllyasviel/stable-diffusion-webui-forge.git
    BASE_PATH="/workspace/stable-diffusion-webui-forge"
fi

MODELS_DIR="$BASE_PATH/models"
EXTENSIONS_DIR="$BASE_PATH/extensions"
LIST_FILE="/tmp/install_list.txt"

# 3. install_list.txt laden
echo "--- Fetching install_list.txt ---"
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
        
        # Download-Logik
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
# Sicherstellen, dass Anforderungen installiert sind (falls Forge neu geklont wurde)
if [ ! -f "venv/bin/python3" ]; then
    pip install -r requirements.txt
fi

python3 launch.py --listen --port 7860 --enable-insecure-extension-access --theme dark --xformers
