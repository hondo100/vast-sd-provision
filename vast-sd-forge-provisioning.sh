#!/bin/bash

# ==============================================================================
# VAST.AI PROVISIONING SCRIPT - ULTIMATE REBOOT-SAFE EDITION
# ==============================================================================

echo "--- 🚀 Starte finales Provisioning Script ---"

# --- 1. Pfad-Vorbereitung & Keys ---
# Robustere Erkennung: Falls /workspace (noch) nicht da ist, nutzen wir $HOME
if [ -d "/workspace" ]; then
    BASE_DIR="/workspace"
else
    BASE_DIR="$HOME"
fi
cd "$BASE_DIR" || exit

# Keys aus Umgebungsvariablen laden und von Leerzeichen befreien (wichtig für Civitai)
export CIVITAI_API_KEY=$(echo "${CIVITAI_API_KEY:-$CIVITAI_KEY}" | xargs)
export HF_TOKEN=$(echo "$HF_TOKEN" | xargs)
export GITHUB_PAT=$(echo "$GITHUB_PAT" | xargs)

# --- 2. System-Vorbereitung ---
apt-get update
apt-get install -y aria2 git curl python3-pip python3-venv ca-certificates unzip --no-install-recommends

# --- 3. Forge Installation / Update ---
if [ ! -d "stable-diffusion-webui-forge" ]; then
    echo "--- Forge nicht gefunden, klone Repository ---"
    git clone --depth 1 https://github.com/lllyasviel/stable-diffusion-webui-forge.git
fi

cd "stable-diffusion-webui-forge" || exit
BASE_PATH=$(pwd)
echo "--- Zielverzeichnis: $BASE_PATH ---"

# --- 4. Installationsliste laden (Private Repo Support) ---
LIST_FILE="/tmp/install_list.txt"
LIST_URL="https://raw.githubusercontent.com/hondo100/vast-sd-provision/main/install_list.txt"

echo "--- Lade Installationsliste von GitHub ---"
# Nutzt den GITHUB_PAT, falls die Liste im privaten Repo liegt
curl -s -L -H "Authorization: token $GITHUB_PAT" "$LIST_URL?$(date +%s)" -o "$LIST_FILE"
sed -i 's/\r$//' "$LIST_FILE" 

# --- 5. Download-Schleife mit In-Line Filter & Error Handling ---
echo "--- Starte Downloads ---"
sed 's/#.*//' "$LIST_FILE" | sed '/^\s*$/d' | while IFS='|' read -r SOURCE TYPE NAME || [ -n "$SOURCE" ]; do
    
    SOURCE=$(echo "$SOURCE" | xargs)
    TYPE=$(echo "$TYPE" | xargs)
    NAME=$(echo "$NAME" | xargs)

    # --- SONDERFALL: EXTENSIONS ---
    if [[ "$TYPE" == "extensions" ]]; then
        TARGET_EXT_DIR="extensions/$NAME"
        if [ ! -d "$TARGET_EXT_DIR" ]; then
            echo "--- Installiere Extension: $NAME ---"
            if [[ "$SOURCE" == *.zip ]]; then
                mkdir -p "$TARGET_EXT_DIR"
                curl -L -s -H "Authorization: token $GITHUB_PAT" "$SOURCE" -o "/tmp/temp.zip"
                unzip -q -j "/tmp/temp.zip" -d "$TARGET_EXT_DIR" 
                rm "/tmp/temp.zip"
            else
                git clone --depth 1 "$SOURCE" "$TARGET_EXT_DIR"
            fi
        fi

    # --- NORMALFALL: MODELLE ---
    else
        CLEAN_TYPE=$(echo "$TYPE" | sed 's|^models/||')
        DEST_DIR="models/$CLEAN_TYPE"
        mkdir -p "$DEST_DIR"

        if [ ! -f "$DEST_DIR/$NAME" ]; then
            echo "--- Lade: $NAME nach $DEST_DIR ---"
            
            # A: Civitai (ID-basiert)
            if [[ "$SOURCE" =~ ^[0-9]+$ ]]; then
                aria2c --console-log-level=warn -x 16 -s 16 -k 1M \
                       --header="Authorization: Bearer $CIVITAI_API_KEY" \
                       --check-certificate=false \
                       -o "$NAME" -d "$DEST_DIR" --allow-overwrite=true \
                       "https://civitai.com/api/download/models/${SOURCE}"
            
            # B: HuggingFace (mit Auth)
            elif [[ "$SOURCE" == *"huggingface.co"* ]]; then
                aria2c --console-log-level=warn -x 16 -s 16 -k 1M \
                       --header="Authorization: Bearer $HF_TOKEN" \
                       -o "$NAME" -d "$DEST_DIR" --allow-overwrite=true \
                       "$SOURCE"
            
            # C: Standard URL
            else
                aria2c --console-log-level=warn -x 16 -s 16 -k 1M \
                       -o "$NAME" -d "$DEST_DIR" --allow-overwrite=true \
                       "$SOURCE"
            fi
        else
            echo "--- $NAME bereits vorhanden, überspringe ---"
        fi
    fi
done

# --- 6. WD14 Tagger Fix (Optional) ---
if [ -d "extensions/wd14-tagger" ]; then
    echo "--- Installiere Tagger Requirements ---"
    pip install --no-cache-dir onnxruntime-gpu opencv-python-headless
fi

# --- 7. Start von Forge ---
echo "--- Provisioning beendet. Starte Forge ---"
# --listen ist essenziell für Vast.ai Erreichbarkeit
# Nutzt zusätzlich FORGE_ARGS aus dem Vast-Interface
python3 launch.py \
    --listen \
    --port 7860 \
    --enable-insecure-extension-access \
    --xformers \
    --pin-shared-memory \
    --cuda-malloc-async \
    --cuda-stream \
    --skip-python-version-check \
    $FORGE_ARGS
