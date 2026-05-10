#!/bin/bash

# ==============================================================================
# VAST.AI PROVISIONING SCRIPT - ULTIMATE EDITION
# ==============================================================================

echo "--- 🚀 Starte finales Provisioning Script ---"

# --- 1. Konfiguration & Keys (Mapping von Vast-Env zu Script) ---
# Wir mappen hier flexibel, falls du im Vast-Interface andere Namen nutzt
export CIVITAI_API_KEY="${CIVITAI_API_KEY:-$CIVITAI_KEY}"
export HF_TOKEN="${HF_TOKEN}"
export GITHUB_PAT="${GITHUB_PAT}"

# --- 2. System-Vorbereitung ---
apt-get update
apt-get install -y aria2 git curl python3-pip python3-venv ca-certificates unzip --no-install-recommends

# --- 3. Dynamische Pfad-Erkennung für Forge ---
if [ -f "/workspace/launch.py" ]; then
    BASE_PATH="/workspace"
elif [ -d "/workspace/stable-diffusion-webui-forge" ]; then
    BASE_PATH="/workspace/stable-diffusion-webui-forge"
else
    echo "--- Forge nicht gefunden, klone Repository neu ---"
    cd /workspace
    # Nutzt den PAT für den Klonvorgang, falls das Repo privat wäre
    git clone --depth 1 https://github.com/lllyasviel/stable-diffusion-webui-forge.git
    BASE_PATH="/workspace/stable-diffusion-webui-forge"
fi

echo "--- Zielverzeichnis: $BASE_PATH ---"
cd "$BASE_PATH"

# --- 4. Installationsliste laden (Cache-beating) ---
LIST_FILE="/tmp/install_list.txt"
LIST_URL="https://raw.githubusercontent.com/hondo100/vast-sd-provision/main/install_list.txt"

echo "--- Lade Installationsliste von GitHub ---"
# Auth-Header wird mitgesendet, falls das Repo privat ist
curl -s -L -H "Authorization: token $GITHUB_PAT" "$LIST_URL?$(date +%s)" -o "$LIST_FILE"
sed -i 's/\r$//' "$LIST_FILE" 

# --- 5. Download-Schleife mit Auto-Kommentar-Filter ---
echo "--- Starte Downloads ---"
# Filtert In-Line Kommentare (#) und leere Zeilen
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
                curl -L -s "$SOURCE" -o "/tmp/temp.zip"
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
            
            # Civitai (ID-basiert)
            if [[ "$SOURCE" =~ ^[0-9]+$ ]]; then
                aria2c --console-log-level=warn -x 16 -s 16 -k 1M \
                       --header="Authorization: Bearer $CIVITAI_API_KEY" \
                       -o "$NAME" -d "$DEST_DIR" --allow-overwrite=true \
                       "https://civitai.com/api/download/models/${SOURCE}"
            
            # HuggingFace (mit Auth)
            elif [[ "$SOURCE" == *"huggingface.co"* ]]; then
                aria2c --console-log-level=warn -x 16 -s 16 -k 1M \
                       --header="Authorization: Bearer $HF_TOKEN" \
                       -o "$NAME" -d "$DEST_DIR" --allow-overwrite=true \
                       "$SOURCE"
            
            # Andere URLs
            else
                aria2c --console-log-level=warn -x 16 -s 16 -k 1M \
                       -o "$NAME" -d "$DEST_DIR" --allow-overwrite=true \
                       "$SOURCE"
            fi
        fi
    fi
done

# --- 6. WD14 Tagger Fix ---
if [ -d "extensions/wd14-tagger" ]; then
    echo "--- Installiere Tagger Requirements ---"
    pip install --no-cache-dir onnxruntime-gpu opencv-python-headless
fi

# --- 7. Start von Forge ---
echo "--- Provisioning beendet. Starte Forge ---"
# Wir kombinieren deine gewünschten Flags mit den FORGE_ARGS aus dem Vast-Interface (Screenshot)
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
