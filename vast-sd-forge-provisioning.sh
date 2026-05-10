#!/bin/bash

# ==============================================================================
# VAST.AI PROVISIONING SCRIPT - FIXED PATHS & AUTH
# ==============================================================================

echo "--- 🚀 Starte finales Provisioning Script ---"

# --- 1. Pfad-Vorbereitung ---
# Wir erzwingen /workspace, da Vast-Instanzen dort persistenten Speicher haben
if [ -d "/workspace" ]; then
    BASE_DIR="/workspace"
else
    BASE_DIR="/root"
fi
cd "$BASE_DIR" || exit

# --- 2. Keys säubern ---
# WICHTIG: API-Keys dürfen keine versteckten Zeichen enthalten
export CIVITAI_API_KEY=$(echo "${CIVITAI_API_KEY:-$CIVITAI_KEY}" | tr -d '\r\n[:space:]')
export HF_TOKEN=$(echo "$HF_TOKEN" | tr -d '\r\n[:space:]')
export GITHUB_PAT=$(echo "$GITHUB_PAT" | tr -d '\r\n[:space:]')

# --- 3. System-Check ---
apt-get update && apt-get install -y aria2 git curl unzip --no-install-recommends

# --- 4. Forge Installation ---
if [ ! -d "stable-diffusion-webui-forge" ]; then
    echo "--- Klone Forge ---"
    git clone --depth 1 https://github.com/lllyasviel/stable-diffusion-webui-forge.git
fi

# Wir setzen den Pfad absolut, um '//launch.py' Fehler zu vermeiden
cd "$BASE_DIR/stable-diffusion-webui-forge" || exit
FORGE_ROOT=$(pwd)
echo "--- Arbeitsverzeichnis: $FORGE_ROOT ---"

# --- 5. Installationsliste laden ---
LIST_FILE="/tmp/install_list.txt"
LIST_URL="https://raw.githubusercontent.com/hondo100/vast-sd-provision/main/install_list.txt"

curl -s -L -H "Authorization: token $GITHUB_PAT" "$LIST_URL?$(date +%s)" -o "$LIST_FILE"
sed -i 's/\r$//' "$LIST_FILE" 

# --- 6. Downloads ---
echo "--- Starte Downloads ---"
sed 's/#.*//' "$LIST_FILE" | sed '/^\s*$/d' | while IFS='|' read -r SOURCE TYPE NAME || [ -n "$SOURCE" ]; do
    
    SOURCE=$(echo "$SOURCE" | xargs)
    TYPE=$(echo "$TYPE" | xargs)
    NAME=$(echo "$NAME" | xargs)

    # Pfadbereinigung
    CLEAN_TYPE=$(echo "$TYPE" | sed 's|^models/||')
    DEST_DIR="$FORGE_ROOT/models/$CLEAN_TYPE"
    [ "$TYPE" == "extensions" ] && DEST_DIR="$FORGE_ROOT/extensions/$NAME"
    
    mkdir -p "$DEST_DIR"

    if [ ! -f "$DEST_DIR/$NAME" ] || [ "$TYPE" == "extensions" ]; then
        echo "--- Lade: $NAME ---"
        
        if [[ "$SOURCE" =~ ^[0-9]+$ ]]; then
            echo "--- Lade Civitai ID: $SOURCE via curl ---"
            curl -L -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0" \
                 "https://civitai.com/api/download/models/${SOURCE}?token=$CIVITAI_API_KEY" \
                 --output "$DEST_DIR/$NAME"
        
        elif [[ "$SOURCE" == *"huggingface.co"* ]]; then
            aria2c --console-log-level=warn -x 16 -s 16 -k 1M \
                   --header="Authorization: Bearer $HF_TOKEN" \
                   -o "$NAME" -d "$DEST_DIR" --allow-overwrite=true \
                   "$SOURCE"
        
        elif [[ "$TYPE" == "extensions" ]]; then
            [ ! -d "$DEST_DIR" ] && git clone --depth 1 "$SOURCE" "$DEST_DIR"
        else
            aria2c --console-log-level=warn -x 16 -s 16 -k 1M -o "$NAME" -d "$DEST_DIR" "$SOURCE"
        fi
    fi
done

# --- 7. Start ---
echo "--- Starte Forge ---"
cd "$FORGE_ROOT" || exit
python3 launch.py --listen --port 7860 --enable-insecure-extension-access --xformers --skip-python-version-check $FORGE_ARGS
