#!/bin/bash

# ==============================================================================
# NAME: vast-sd-forge-provisioning.sh
# ZWECK: Automatisierte Einrichtung von SD-Forge auf Vast.ai
# ==============================================================================

# Pfad-Definitionen basierend auf dem Standard-Vast-Image
BASE_PATH="/workspace/stable-diffusion-webui-forge"
MODEL_PATH="$BASE_PATH/models/Stable-diffusion"
LORA_PATH="$BASE_PATH/models/Lora"
VAE_PATH="$BASE_PATH/models/VAE"
#!/bin/bash

# ==============================================================================
# PROVISIONING SCRIPT: ULTIMATIVE PERFORMANCE VERSION 2026
# ==============================================================================

# 1. DOWNLOAD-HELPER DEFINIEREN
# Installiert aria2 falls nötig und definiert die Hochgeschwindigkeits-Funktion
if ! command -v aria2c &> /dev/null; then
    echo "Installiere Download-Beschleuniger aria2..."
    apt-get update && apt-get install -y aria2
fi

download_asset() {
    local url=$1
    local dest=$2
    local filename=$3
    mkdir -p "$dest"
    if [ ! -f "$dest/$filename" ]; then
        echo "Downloade: $filename"
        # 16 Verbindungen, 1MB Split-Größe für maximalen Durchsatz
        aria2c -x 16 -s 16 -k 1M --console-log-level=error --summary-interval=10 "$url" -d "$dest" -o "$filename"
    else
        echo "Überspringe $filename (bereits vorhanden)."
    fi
}

# 2. PFADE & TOKEN
BASE_PATH="/workspace/stable-diffusion-webui"
EXT_PATH="$BASE_PATH/extensions"

# 3. EXTENSIONS
echo "Installiere Extensions..."
[ ! -d "$EXT_PATH/sd-webui-aspect-ratio-helper" ] && git clone https://github.com/thomasasfk/sd-webui-aspect-ratio-helper "$EXT_PATH/sd-webui-aspect-ratio-helper"

# 4. HIGH-SPEED DOWNLOADS
# Juggernaut XL
download_asset "https://civitai.com/api/download/models/456124?type=Model&format=SafeTensor&size=full&fp=fp16&token=$CIVITAI_TOKEN" \
               "$BASE_PATH/models/Stable-diffusion" \
               "juggernaut_ragnarok_v11.safetensors"

# Video (SVD-XT)
download_asset "https://civitai.com/api/download/models/245598?token=$CIVITAI_TOKEN" \
               "$BASE_PATH/models/svd" \
               "svd_xt_1_1.safetensors"

# Upscaler & VAE
download_asset "https://civitai.com/api/download/models/125843?type=Model&format=PickleTensor" \
               "$BASE_PATH/models/ESRGAN" \
               "4x-UltraSharp.pth"

download_asset "https://huggingface.co/madebyollin/sdxl-vae-fp16-fix/resolve/main/sdxl_vae.safetensors" \
               "$BASE_PATH/models/VAE" \
               "sdxl_vae.safetensors"

echo "Setup erfolgreich beendet."
