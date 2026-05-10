#!/bin/bash

# ==============================================================================
# VAST.AI PROVISIONING SCRIPT FOR SD-FORGE
# ==============================================================================

echo "--- 🚀 Starte Provisioning Script ---"

# 1. System-Vorbereitung
# Wir installieren notwendige Tools und stellen sicher, dass Zertifikate aktuell sind
apt-get update
apt-get install -y aria2 git curl python3-pip python3-venv ca-certificates

# 2. Dynamische Pfad-Erkennung (Der Pfad-Finder)
# Forge liegt je nach Template an unterschiedlichen Stellen
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
curl -s -L -H "Authorization: token $GITHUB_PAT" "$LIST_URL" -o "$LIST_FILE"

# WICHTIG: CRLF-Bereinigung (entfernt Windows-Zeilenumbrüche)
sed -i 's/\r$//' "$LIST_FILE"

# 4. Download-Schleife
echo "--- Starte Downloads ---"
while IFS='|' read -r SOURCE TYPE NAME || [ -n "$SOURCE" ]; do
    # Kommentare und Leerzeilen ignorieren
    [[ "$SOURCE" =~ ^#.*$ ]] && continue
    [[ -z "$SOURCE" ]] && continue
    
    # Leerzeichen entfernen
    SOURCE=$(echo "$SOURCE" | xargs)
    TYPE=$(echo "$TYPE" | xargs)
    NAME=$(echo "$NAME" | xargs)

    # Sonderfall: Extensions (Git Repos)
    if [[ "$TYPE" == "extensions" ]]; then
        echo "--- Installiere Extension: $NAME ---"
        TARGET_EXT_DIR="extensions/$NAME"
        if [ ! -d "$TARGET_EXT_DIR" ]; then
            git clone "$SOURCE" "$TARGET_EXT_DIR"
        else
            echo "--- $NAME bereits vorhanden, überspringe ---"
        fi
    
    # Normalfall: Modelle / Loras / VAE / Upscaler
    else
        echo "--- Lade Modell: $NAME ---"
        mkdir -p "models/$TYPE"
        
        # Browser-Tarnung und Token-Logik (aria2c)
        if [[ "$SOURCE" =~ ^[0-9]+$ ]]; then
            # Civitai ID
            aria2c --console-log-level=warn -x 16 -s 16 -k 1M \
                   --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
                   --header="Referer: https://civitai.com/" \
                   -o "$NAME" -d "models/$TYPE" --allow-overwrite=true \
                   "https://civitai.com/api/download/models/${SOURCE}?token=${CIVITAI_KEY}"
        
        elif [[ "$SOURCE" == *"huggingface.co"* ]]; then
            # HuggingFace (Resolve-Fix ist in der install_list.txt URL nötig)
            aria2c --console-log-level=warn -x 16 -s 16 -k 1M \
                   --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
                   --header="Authorization: Bearer $HF_TOKEN" \
                   -o "$NAME" -d "models/$TYPE" --allow-overwrite=true \
                   "$SOURCE"
        
        else
            # Sonstige Direkte Links
            aria2c --console-log-level=warn -x 16 -s 16 -k 1M \
                   --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
                   -o "$NAME" -d "models/$TYPE" --allow-overwrite=true \
                   "$SOURCE"
        fi
    fi
done < "$LIST_FILE"

# 5. Abschluss und Start von Forge
echo "--- Provisioning beendet. Starte Forge ---"

# Fix für Python 3.12 und Optimierungen für Vast.ai (Cuda Malloc / Stream)
python3 launch.py --listen --port 7860 --xformers --pin-shared-memory \
                  --cuda-malloc-async --cuda-stream --skip-python-version-check
