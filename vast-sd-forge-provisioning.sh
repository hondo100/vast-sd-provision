#!/bin/bash
echo "--- Provisioning startet ---"
apt-get update && apt-get install -y aria2 git curl python3-pip python3-venv

# Dynamische Pfad-Erkennung
if [ -f "/workspace/launch.py" ]; then
    BASE_PATH="/workspace"
elif [ -d "/workspace/stable-diffusion-webui-forge" ]; then
    BASE_PATH="/workspace/stable-diffusion-webui-forge"
elif [ -d "/workspace/stable-diffusion-webui" ]; then
    BASE_PATH="/workspace/stable-diffusion-webui"
else
    cd /workspace
    git clone https://github.com/lllyasviel/stable-diffusion-webui-forge.git
    BASE_PATH="/workspace/stable-diffusion-webui-forge"
fi

cd "$BASE_PATH"
LIST_FILE="/tmp/install_list.txt"
LIST_URL="https://raw.githubusercontent.com/hondo100/vast-sd-provision/main/install_list.txt"

# Download der Liste und CRLF-Fix (Windows-Zeilenumbrüche entfernen)
curl -s -L -H "Authorization: token $GITHUB_PAT" "$LIST_URL" -o "$LIST_FILE"
sed -i 's/\r$//' "$LIST_FILE"

# Download-Logik
while IFS='|' read -r SOURCE TYPE NAME || [ -n "$SOURCE" ]; do
    [[ "$SOURCE" =~ ^#.*$ ]] && continue
    [[ -z "$SOURCE" ]] && continue
    
    SOURCE=$(echo "$SOURCE" | xargs); TYPE=$(echo "$TYPE" | xargs); NAME=$(echo "$NAME" | xargs)

    if [[ "$TYPE" == "extensions" ]]; then
        TARGET_DIR="extensions/$NAME"
        [ ! -d "$TARGET_DIR" ] && git clone "$SOURCE" "$TARGET_DIR"
    else
        mkdir -p "models/$TYPE"
        if [[ "$SOURCE" =~ ^[0-9]+$ ]]; then
            aria2c --console-log-level=warn -x 16 -s 16 -k 1M -o "$NAME" -d "models/$TYPE" --allow-overwrite=true "https://civitai.com/api/download/models/${SOURCE}?token=${CIVITAI_KEY}"
        elif [[ "$SOURCE" == *"huggingface.co"* ]]; then
            aria2c --console-log-level=warn -x 16 -s 16 -k 1M --header="Authorization: Bearer $HF_TOKEN" -o "$NAME" -d "models/$TYPE" --allow-overwrite=true "$SOURCE"
        else
            aria2c --console-log-level=warn -x 16 -s 16 -k 1M -o "$NAME" -d "models/$TYPE" --allow-overwrite=true "$SOURCE"
        fi
    fi
done < "$LIST_FILE"

# Startbefehl
python3 launch.py --listen --port 7860 --xformers --pin-shared-memory --cuda-malloc-async --cuda-stream --skip-python-version-check
