#!/bin/bash

# ==============================================================================
# PROVISIONING SCRIPT: ULTIMATIVE PERFORMANCE VERSION (Master Tool 2026)
# Fokus: Fotorealismus, Videogenerierung & Körper-Realismus
# ==============================================================================

# 1. DOWNLOAD-HELPER DEFINIEREN
# Installiert aria2 für parallele Downloads (16 Verbindungen für maximalen Speed)
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
        # Nutzt 16 Verbindungen und 1MB Splits für maximale Bandbreitenausnutzung
        aria2c -x 16 -s 16 -k 1M --console-log-level=error --summary-interval=10 "$url" -d "$dest" -o "$filename"
    else
        echo "Überspringe $filename (bereits vorhanden)."
    fi
}

# 2. PFADE DEFINIEREN (Basierend auf ai-dock Forge Standard)
BASE_PATH="/workspace/stable-diffusion-webui"
MODEL_PATH="$BASE_PATH/models/Stable-diffusion"
LORA_PATH="$BASE_PATH/models/Lora"
SVD_PATH="$BASE_PATH/models/svd"
VAE_PATH="$BASE_PATH/models/VAE"
ESRGAN_PATH="$BASE_PATH/models/ESRGAN"
CONTROLNET_PATH="$BASE_PATH/models/ControlNet"
EXT_PATH="$BASE_PATH/extensions"

# 3. EXTENSIONS INSTALLIEREN
echo "Installiere Extensions..."
# Aspect Ratio Helper für einfache Formatanpassungen
[ ! -d "$EXT_PATH/sd-webui-aspect-ratio-helper" ] && \
    git clone https://github.com/thomasasfk/sd-webui-aspect-ratio-helper "$EXT_PATH/sd-webui-aspect-ratio-helper"

# 4. HAUPT-ASSETS DOWNLOADEN
echo "Starte High-Speed Downloads der Hauptmodelle..."

# Juggernaut XL (Ragnarok v11) - Das Basismodell für Fotorealismus
download_asset "https://civitai.com/api/download/models/456124?type=Model&format=SafeTensor&size=full&fp=fp16&token=$CIVITAI_TOKEN" \
               "$MODEL_PATH" \
               "juggernaut_ragnarok_v11.safetensors"

# Video-Modell (SVD-XT) - Für die Videogenerierung
download_asset "https://civitai.com/api/download/models/245598?token=$CIVITAI_TOKEN" \
               "$SVD_PATH" \
               "svd_xt_1_1.safetensors"

# 4x-UltraSharp Upscaler - Für knackscharfe 4K-Ergebnisse
download_asset "https://civitai.com/api/download/models/125843?type=Model&format=PickleTensor" \
               "$ESRGAN_PATH" \
               "4x-UltraSharp.pth"

# SDXL VAE Fix - Verhindert graue Schleier/Artefakte
download_asset "https://huggingface.co/madebyollin/sdxl-vae-fp16-fix/resolve/main/sdxl_vae.safetensors" \
               "$VAE_PATH" \
               "sdxl_vae.safetensors"

# ControlNet Canny XL - Für präzise Kompositionskontrolle
download_asset "https://huggingface.co/lllyasviel/sd_control_collection/resolve/main/diffusers_xl_canny_mid.safetensors" \
               "$CONTROLNET_PATH" \
               "control_canny_xl.safetensors"

# 5. REALISMUS-LORAS DOWNLOADEN (Schleifen-System)
# Liste der IDs und Namen für natürliche Körper & Hauttexturen
LORAS=(
    "135931:detail_tweaker_xl.safetensors"        # Für Hautporen & Details
    "257744:skin_texture_realism.safetensors"     # Gegen den Plastik-Look
    "218121:human_anatomy_fix.safetensors"       # Natürliche Proportionen
    "122832:film_grain_style.safetensors"         # Authentischer Kamera-Look
)

echo "Lade Realismus-LoRAs via aria2..."
for lora in "${LORAS[@]}"; do
    ID="${lora%%:*}"
    NAME="${lora#*:}"
    download_asset "https://civitai.com/api/download/models/$ID?token=$CIVITAI_TOKEN" "$LORA_PATH" "$NAME"
done

echo "=============================================================================="
echo "PROVISIONING ABGESCHLOSSEN: Juggernaut XL Studio ist einsatzbereit!"
echo "=============================================================================="
