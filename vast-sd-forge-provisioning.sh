#!/bin/bash

echo "==========================================================="
echo "🚀 VAST.AI PROVISIONING: STARTING"
echo "==========================================================="

# 1. System-Tools sicherstellen
echo "--- Checking System Tools ---"
apt-get update && apt-get install -y aria2 git curl python3-pip python3-venv

# 2. Forge-Pfad Suche (Optimiert für Vast.ai Templates)
if [ -f "/workspace/launch.py" ]; then
    BASE_PATH="/workspace"
    echo "✅ Forge found directly in /workspace"
elif [ -d "/workspace/stable-diffusion-webui-forge" ]; then
    BASE_PATH="/workspace/stable-diffusion-webui-forge"
    echo "✅ Forge found in /workspace/stable-diffusion-webui-forge"
elif [ -d "/workspace/stable-diffusion-webui" ]; then
    BASE_PATH="/workspace/stable-diffusion-webui"
    echo "✅ Forge found in /workspace/stable-diffusion-webui"
else
    echo "⚠️ Forge not found. Installing fresh..."
    cd /workspace
    git clone https://github.com/lllyasviel/stable-diffusion-webui-forge.git
    BASE_PATH="/workspace/stable-diffusion-webui-forge"
fi

cd "$BASE_PATH"
MODELS_DIR="$BASE_PATH/models"
EXTENSIONS_DIR="$BASE_PATH/extensions"
LIST_FILE="/tmp/install_list.txt"

# 3. install_list.txt laden
echo "--- Fetching install_list.txt ---"
LIST_URL="https://raw.githubusercontent.com/hondo100/vast-sd-provision/main/install_list.txt"
curl -s -L -H "Authorization: token $GITHUB_PAT" "$LIST_URL" -o "$LIST_FILE"

# 4. Downloads mit Aria2 (Optimierte Logik)
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
        
        echo "📥 Downloading $NAME..."
        if [[ "$SOURCE" =~ ^[0-9]+$ ]]; then
            # Civitai Download
            aria2c --console-log-level=warn -x 16 -s 16 -k 1M -o "$NAME" -d "$DEST_DIR" --allow-overwrite=true "https://civitai.com/api/download/models/${SOURCE}?token=${CIVITAI_KEY}"
        elif [[ "$SOURCE" == *"huggingface.co"* ]]; then
            # HuggingFace Download mit Token
            aria2c --console-log-level=warn -x 16 -s 16 -k 1M --header="Authorization: Bearer $HF_TOKEN" -o "$NAME" -d "$DEST_DIR" --allow-overwrite=true "$SOURCE"
        else
            # Direkter Link
            aria2c --console-log-level=warn -x 16 -s 16 -k 1M -o "$NAME" -d "$DEST_DIR" --allow-overwrite=true "$SOURCE"
        fi
    fi
done < "$LIST_FILE"

echo "==========================================================="
echo "🎉 PROVISIONING COMPLETE - STARTING FORGE"
echo "==========================================================="

# Zurück in den Hauptordner
cd "$BASE_PATH"

# Startbefehl mit GPU-Optimierungen und Python 3.12 Fix
# Port 7860 ist Standard für Stable Diffusion
python3 launch.py \
    --listen \
    --port 7860 \
    --enable-insecure-extension-access \
    --theme dark \
    --xformers \
    --pin-shared-memory \
    --cuda-malloc-async \
    --cuda-stream \
    --skip-python-version-check
