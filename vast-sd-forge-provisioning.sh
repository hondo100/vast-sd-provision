#!/bin/bash

# ==============================================================================
# VAST.AI PROVISIONING SCRIPT - FULL EDITION (FORGE & WD14)
# ==============================================================================

echo "--- 🚀 Starte finales Provisioning Script ---"

# 1. System-Vorbereitung (Tools & Zertifikate)
apt-get update
apt-get install -y aria2 git curl python3-pip python3-venv ca-certificates unzip --no-install-recommends

# 2. Dynamische Pfad-Erkennung für Forge
if [ -f "/workspace/launch.py" ]; then
    BASE_PATH="/workspace"
elif [ -d "/workspace/stable-diffusion-webui-forge" ]; then
    BASE_PATH="/workspace/stable-diffusion-webui-forge"
elif [ -d "/workspace/stable-diffusion-webui" ]; then
    BASE_PATH="/workspace/stable-diffusion-webui"
else
    echo "--- Forge nicht gefunden, klone Repository neu ---"
    cd /workspace
    # Nutzt GITHUB_PAT für den Klon-Vorgang
    git clone --depth 1 https://$GITHUB_PAT@github.com/lllyasviel/stable-diffusion-webui-forge.git
    BASE_PATH="/workspace/stable-diffusion-webui-forge"
fi

echo "--- Zielverzeichnis: $BASE_PATH ---"
cd "$BASE_PATH"

# 3. Installationsliste laden (Cache-beating aktiv)
LIST_FILE="/tmp/install_list.txt"
LIST_URL="https://raw.githubusercontent.com/hondo100/vast-sd-provision/main/install_list.txt"

echo "--- Lade Installationsliste von GitHub ---"
curl -s -L -H "Authorization: token $GITHUB_PAT" "$LIST_URL?$(date +%s)" -o "$LIST_FILE"
sed -i 's/\r$//' "$LIST_FILE" # Entfernt Windows-Zeilenumbrüche

# 4. Download-Schleife mit In-Line Kommentar-Filter
echo "--- Starte Downloads ---"
# sed entfernt alles ab # und löscht leere Zeilen
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
                curl -L -H "Authorization: token $GITHUB_PAT" "$SOURCE" -o "/tmp/temp.zip"
                unzip -q -j "/tmp/temp.zip" -d "$TARGET_EXT_DIR" # -j flacht die Struktur ab
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
            echo "--- Lade Modell: $NAME ---"
            
            if [[ "$SOURCE" =~ ^[0-9]+$ ]]; then
                # Civitai Profi-Download
                aria2c --console-log-level=warn -x 16 -s 16 -k 1M \
                       --header="Authorization: Bearer $CIVITAI_API_KEY" \
                       -o "$NAME" -d "$DEST_DIR" \
                       "https://civitai.com/api/download/models/${SOURCE}"
            
            elif [[ "$SOURCE" == *"huggingface.co"* ]]; then
                aria2c --console-log-level=warn -x 16 -s 16 -k 1M \
                       --header="Authorization: Bearer $HF_TOKEN" \
                       -o "$NAME" -d "$DEST_DIR" "$SOURCE"
            else
                aria2c --console-log-level=warn -x 16 -s 16 -k 1M -o "$NAME" -d "$DEST_DIR" "$SOURCE"
            fi
        fi
    fi
done

# 5. WD14 Tagger Fix
if [ -d "extensions/wd14-tagger" ]; then
    echo "--- Installiere Tagger Requirements ---"
    pip install --no-cache-dir onnxruntime-gpu opencv-python-headless
fi

# 6. Start (mit dem wichtigen Flag für Vast.ai)
echo "--- Provisioning beendet. Starte Forge ---"
python3 launch.py \
    --listen --port 7860 \
    --enable-insecure-extension-access \
    --xformers --pin-shared-memory --cuda-malloc-async --cuda-stream \
    --skip-python-version-check
