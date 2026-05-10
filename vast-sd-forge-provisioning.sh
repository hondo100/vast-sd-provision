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

# 4. Download-Schleife
echo "--- Starte Downloads ---"
while IFS='|' read -r SOURCE TYPE NAME || [ -n "$SOURCE" ]; do
    [[ "$SOURCE" =~ ^#.*$ || -z "$SOURCE" ]] && continue
    
    SOURCE=$(echo "$SOURCE" | xargs)
    TYPE=$(echo "$TYPE" | xargs)
    NAME=$(echo "$NAME" | xargs)

    # --- SONDERFALL: EXTENSIONS (ZIP oder Git) ---
    if [[ "$TYPE" == "extensions" ]]; then
        TARGET_EXT_DIR="extensions/$NAME"
        if [ ! -d "$TARGET_EXT_DIR" ]; then
            echo "--- Installiere Extension: $NAME ---"
            if [[ "$SOURCE" == *.zip ]]; then
                # ZIP-Download Logik (für Kataragi/WD14)
                mkdir -p "$TARGET_EXT_DIR"
                curl -L -s -H "Authorization: token $GITHUB_PAT" "$SOURCE" -o "/tmp/temp.zip"
                mkdir -p "/tmp/extract_$NAME"
                unzip -q "/tmp/temp.zip" -d "/tmp/extract_$NAME"
                cp -r /tmp/extract_$NAME/*/. "$TARGET_EXT_DIR/"
                rm -rf "/tmp/temp.zip" "/tmp/extract_$NAME"
            else
                git clone --depth 1 "$SOURCE" "$TARGET_EXT_DIR"
            fi
        else
            echo "--- Extension $NAME bereits vorhanden ---"
        fi

    # --- NORMALFALL: MODELLE / LORAS / TORCH_DEEPDANBOORU ---
    else
        # Pfad-Bereinigung (entfernt 'models/' falls es in der Liste steht)
        CLEAN_TYPE=$(echo "$TYPE" | sed 's|^models/||')
        DEST_DIR="models/$CLEAN_TYPE"
        mkdir -p "$DEST_DIR"

        if [ ! -f "$DEST_DIR/$NAME" ]; then
            echo "--- Lade Modell: $NAME nach $DEST_DIR ---"
            
            # Civitai mit Token
            if [[ "$SOURCE" =~ ^[0-9]+$ ]]; then
                aria2c --console-log-level=warn -x 16 -s 16 -k 1M \
                       --user-agent="Mozilla/5.0" \
                       --header="Referer: https://civitai.com/" \
                       -o "$NAME" -d "$DEST_DIR" --allow-overwrite=true \
                       "https://civitai.com/api/download/models/${SOURCE}?token=${CIVITAI_KEY}"
            
            # HuggingFace mit Bearer Token (SmilingWolf URL)
            elif [[ "$SOURCE" == *"huggingface.co"* ]]; then
                aria2c --console-log-level=warn -x 16 -s 16 -k 1M \
                       --user-agent="Mozilla/5.0" \
                       --header="Authorization: Bearer $HF_TOKEN" \
                       -o "$NAME" -d "$DEST_DIR" --allow-overwrite=true \
                       "$SOURCE"
            
            # Standard URL
            else
                aria2c --console-log-level=warn -x 16 -s 16 -k 1M \
                       --user-agent="Mozilla/5.0" \
                       -o "$NAME" -d "$DEST_DIR" --allow-overwrite=true \
                       "$SOURCE"
            fi
        else
            echo "--- $NAME bereits vorhanden ---"
        fi
    fi
done < "$LIST_FILE"

# 5. Abhängigkeiten für WD14 Tagger installieren
if [ -d "extensions/wd14-tagger" ]; then
    echo "--- Installiere Tagger Requirements ---"
    pip install -r extensions/wd14-tagger/requirements.txt --quiet --no-cache-dir
fi

# 6. Start von Forge
echo "--- Provisioning beendet. Starte Forge ---"
python3 launch.py \
    --listen \
    --port 7860 \
    --enable-insecure-extension-access \
    --xformers \
    --pin-shared-memory \
    --cuda-malloc-async \
    --cuda-stream \
    --skip-python-version-check
