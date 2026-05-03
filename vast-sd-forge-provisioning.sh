#!/bin/bash

###############################################################################
# VAST.AI PROVISIONING SCRIPT: JUGGERNAUT XL STUDIO (FORGE)
###############################################################################

# 1. Pfade definieren (Absolut auf Forge Verzeichnisstruktur angepasst)
BASE_PATH="/workspace/stable-diffusion-webui-forge"
MODELS_PATH="$BASE_PATH/models/Stable-diffusion"
LORA_PATH="$BASE_PATH/models/Lora"
CN_PATH="$BASE_PATH/models/ControlNet"
VAE_PATH="$BASE_PATH/models/VAE"
ESRGAN_PATH="$BASE_PATH/models/ESRGAN"
SVD_PATH="$BASE_PATH/models/svd"
EXT_PATH="$BASE_PATH/extensions"

# 2. Civitai Authentifizierung (Aus Vast Env) 
# Du findest ihn auf Civitai.com unter Settings -> API Key
CIVITAI_TOKEN="${CIVITAI_TOKEN:?CIVITAI_TOKEN ist nicht gesetzt!}"

# 3. Verzeichnisstruktur sicherstellen
echo "Bereite Verzeichnisse vor..."
mkdir -p "$MODELS_PATH" "$LORA_PATH" "$CN_PATH" "$VAE_PATH" "$ESRGAN_PATH" "$SVD_PATH" "$EXT_PATH"

# 4. Download-Beschleuniger installieren
echo "Installiere aria2..."
apt-get update -y && apt-get install -y aria2

# 5. Extensions (Git Clones)
echo "Installiere Extensions..."
cd "$EXT_PATH"
if [ ! -d "sd-webui-aspect-ratio-helper" ]; then
    git clone https://github.com/thomasasfk/sd-webui-aspect-ratio-helper.git
fi

# 6. Hauptmodelle (Checkpoint & Video)
echo "Starte High-Speed Downloads der Hauptmodelle..."

# Juggernaut XL v11 (Ragnarok)
aria2c --console-log-level=error -c -x 16 -s 16 -k 1M \
  "https://civitai.com/api/download/models/456124?type=Model&format=SafeTensor&token=$CIVITAI_TOKEN" \
  -d "$MODELS_PATH" -o juggernaut_ragnarok_v11.safetensors

# SVD XT 1.1 (Video)
aria2c --console-log-level=error -c -x 16 -s 16 -k 1M \
  "https://huggingface.co/stabilityai/stable-video-diffusion-img2vid-xt-1-1/resolve/main/svd_xt_1_1.safetensors" \
  -d "$SVD_PATH" -o svd_xt_1_1.safetensors

# 7. Hilfsmodelle (VAE & ControlNet)
echo "Lade VAE und ControlNet..."

# SDXL VAE Fix
aria2c --console-log-level=error -c -x 16 -s 16 -k 1M \
  "https://huggingface.co/madebyollin/sdxl-vae-fp16-fix/resolve/main/sdxl_vae.safetensors" \
  -d "$VAE_PATH" -o sdxl_vae.safetensors

# Canny ControlNet XL
aria2c --console-log-level=error -c -x 16 -s 16 -k 1M \
  "https://huggingface.co/lllyasviel/sd_control_collection/resolve/main/sail_control_canny_sdxl.safetensors" \
  -d "$CN_PATH" -o control_canny_xl.safetensors

# 8. Realismus LoRAs
echo "Lade LoRAs..."

# Detail Tweaker XL
aria2c --console-log-level=error -c -x 16 -s 16 -k 1M \
  "https://civitai.com/api/download/models/135931?token=$CIVITAI_TOKEN" \
  -d "$LORA_PATH" -o detail_tweaker_xl.safetensors

# Skin Texture Realism
aria2c --console-log-level=error -c -x 16 -s 16 -k 1M \
  "https://civitai.com/api/download/models/257744?token=$CIVITAI_TOKEN" \
  -d "$LORA_PATH" -o skin_texture_realism.safetensors

# Human Anatomy Fix
aria2c --console-log-level=error -c -x 16 -s 16 -k 1M \
  "https://civitai.com/api/download/models/218121?token=$CIVITAI_TOKEN" \
  -d "$LORA_PATH" -o human_anatomy_fix.safetensors

# Film Grain & Photography Style
aria2c --console-log-level=error -c -x 16 -s 16 -k 1M \
  "https://civitai.com/api/download/models/122832?token=$CIVITAI_TOKEN" \
  -d "$LORA_PATH" -o film_grain_style.safetensors

# 9. Upscaler
echo "Lade Upscaler..."
aria2c --console-log-level=error -c -x 16 -s 16 -k 1M \
  "https://civitai.com/api/download/models/125843?type=Model&format=PickleTensor&token=$CIVITAI_TOKEN" \
  -d "$ESRGAN_PATH" -o 4x-UltraSharp.pth


echo "=============================================================================="
echo "PROVISIONING ERFOLGREICH: Alle Pfade korrigiert und Modelle geladen!"
echo "=============================================================================="
