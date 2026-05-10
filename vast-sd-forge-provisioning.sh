#!/bin/bash

# ==============================================================================
# VAST.AI PROVISIONING SCRIPT FOR SD-FORGE (OPTIMIZED FOR WD14 & ZIP)
# ==============================================================================

echo "--- 🚀 Starte optimiertes Provisioning Script ---"

# 1. System-Vorbereitung
# unzip wird zusätzlich benötigt für die neuen WD14-Links
apt-get update
apt-get install -y aria2 git curl python3-pip python3-venv ca-certificates unzip

# 2. Dynamische Pfad-Erkennung
if [ -f "/workspace/launch.py" ]; then
    BASE_PATH="/workspace"
elif [ -d "/workspace/stable-diffusion-webui-forge" ]; then
    BASE_PATH="/workspace/stable-diffusion-webui-forge"
elif [ -d "/workspace/stable-diffusion-webui" ]; then
    BASE_PATH="/workspace/stable-diffusion-webui"
else
    echo "--- Forge nicht gefunden, klone Repository neu ---"
    cd /workspace
    git clone https://github.com/lllyasviel/stable-diffusion-webui-forge.git
    BASE_PATH="/workspace/stable-diffusion-webui-forge"
fi

echo "--- Zielverzeichnis: $BASE_PATH ---"
cd "$BASE_PATH"

# 3. Liste von GitHub laden
LIST_FILE="/tmp/install_list.txt"
LIST_URL="https://raw.githubusercontent.com/hondo100/vast-sd-provision/main/install_list.txt"

echo "--- Lade Installationsliste ---"
curl -s -L -H "Authorization: token $GITHUB_PAT" "$LIST_URL?$(date +%s)" -o "$LIST_FILE"

# CRLF-Bereinigung (Wichtig für Windows-Editoren)
sed -i 's/\r$//' "$LIST_FILE"

# 4. Download-Schleife
echo "--- Starte Downloads ---"
while IFS='|' read -r SOURCE TYPE NAME || [ -n "$SOURCE" ]; do
    [[ "$SOURCE" =~ ^#.*$ || -z "$SOURCE" ]] && continue
    
    # Trim Whitespaces
    SOURCE=$(echo "$SOURCE" | xargs)
    TYPE=$(echo "$TYPE" | xargs)
    NAME=$(echo "$NAME" | xargs)

    # --- SONDERFALL: EXTENSIONS ---
    if [[ "$TYPE" == "extensions" ]]; then
        TARGET_EXT_DIR="extensions/$NAME"
        if [ ! -d "$TARGET_EXT_DIR" ]; then
            echo "--- Installiere Extension: $NAME ---"
            
            # ZIP-Handling (für Kataragi/WD14 Forks)
            if [[ "$SOURCE" == *.zip ]]; then
                mkdir -p "$TARGET_EXT_DIR"
                curl -L -s -H "Authorization: token $GITHUB_PAT" "$SOURCE" -o "/tmp/temp.zip"
                mkdir -p "/tmp/extract_$NAME"
                unzip -q "/tmp/temp.zip" -d "/tmp/extract_$NAME"
                # Inhalt der ersten Unterebene verschieben
                cp -r /tmp/extract_$NAME/*/. "$TARGET_EXT_DIR/"
                rm -rf "/tmp/temp.zip" "/tmp/extract_$NAME"
            else
                # Klassisches Git Clone
                git clone "$SOURCE" "$TARGET_EXT_DIR"
            fi
        else
            echo "--- Extension $NAME bereits vorhanden ---"
        fi

    # --- NORMALFALL: MODELLE / LORAS / TORCH_DEEPDANBOORU ---
    else
        # Pfad-Korrektur: Verhindert doppelte 'models/' Präfixe
        CLEAN_TYPE=$(echo "$TYPE" | sed 's|^models/||')
        mkdir -p "models/$CLEAN_TYPE"
        DEST_DIR="models/$CLEAN_TYPE"

        if [ ! -f "$DEST_DIR/$NAME" ]; then
            echo "--- Lade Modell: $NAME nach $DEST_DIR ---"
            
            # Civitai ID
            if [[ "$SOURCE" =~ ^[0-9]+$ ]]; then
                aria2c --console-log-level=warn -x 16 -s 16 -k 1M \
                       --user-agent="Mozilla/5.0" \
                       --header="Referer: https://civitai.com/" \
                       -o "$NAME" -d "$DEST_DIR" --allow-overwrite=true \
                       "https://civitai.com/api/download/models/${SOURCE}?token=${CIVITAI_KEY}"
            
            # HuggingFace mit Bearer Token
            elif [[ "$SOURCE" == *"huggingface.co"* ]]; then
                aria2c --console-log-level=warn -x 16 -s 16 -k 1M \
                       --header="Authorization: Bearer $HF_TOKEN" \
                       -o "$NAME" -d "$DEST_DIR" --allow-overwrite=true \
                       "$SOURCE"
            
            # Direkte URL
            else
                aria2c --console-log-level=warn -x 16 -s 16 -k 1M \
                       -o "$NAME" -d "$DEST_DIR" --allow-overwrite=true \
                       "$SOURCE"
            fi
        else
            echo "--- $NAME bereits vorhanden ---"
        fi
    fi
done < "$LIST_FILE"

# 5. WD14 Tagger Requirements (Optional aber empfohlen)
if [ -f "extensions/wd14-tagger/requirements.txt" ]; then
    echo "--- Installiere Tagger Requirements ---"
    pip install -r extensions/wd14-tagger/requirements.txt --quiet
fi

echo "--- Provisioning beendet. Starte Forge ---"

# Startbefehl für Vast.ai
python3 launch.py --listen --port 7860 --xformers --pin-shared-memory \
                  --cuda-malloc-async --cuda-stream --skip-python-version-check
