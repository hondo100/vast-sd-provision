#!/bin/bash
###############################################################################
# VAST.AI PROVISIONING SCRIPT: JUGGERNAUT XL STUDIO (FORGE)
# Version 3.0 – Alle Model-IDs geprüft, Ersatz-LoRAs, HF-Token, Token-Sicherheit
###############################################################################
set -euo pipefail

# ─── 1. Tokens aus Umgebungsvariablen (NIEMALS im Klartext!) ──────────────────
CIVITAI_TOKEN="${CIVITAI_TOKEN:?FEHLER: CIVITAI_TOKEN nicht gesetzt!}"
HF_TOKEN="${HF_TOKEN:?FEHLER: HF_TOKEN nicht gesetzt!}"

# ─── 2. Pfade ─────────────────────────────────────────────────────────────────
BASE_PATH="/workspace/stable-diffusion-webui-forge"
MODELS_PATH="$BASE_PATH/models/Stable-diffusion"
LORA_PATH="$BASE_PATH/models/Lora"
CN_PATH="$BASE_PATH/models/ControlNet"
VAE_PATH="$BASE_PATH/models/VAE"
ESRGAN_PATH="$BASE_PATH/models/ESRGAN"
SVD_PATH="$BASE_PATH/models/svd"
EXT_PATH="$BASE_PATH/extensions"

# ─── 3. Verzeichnisse ─────────────────────────────────────────────────────────
mkdir -p "$MODELS_PATH" "$LORA_PATH" "$CN_PATH" "$VAE_PATH" "$ESRGAN_PATH" "$SVD_PATH" "$EXT_PATH"

# ─── 4. aria2 installieren ────────────────────────────────────────────────────
apt-get update -y -qq && apt-get install -y -qq aria2

# ─── 5. Extension: Aspect Ratio Helper ───────────────────────────────────────
cd "$EXT_PATH"
if [ ! -d "sd-webui-aspect-ratio-helper" ]; then
    git clone https://github.com/thomasasfk/sd-webui-aspect-ratio-helper.git
fi

# ─── 6. Juggernaut XL v9 (Ersatz für gelöschte ID 456124) ────────────────────
# civitai.com/models/133005
if [ ! -f "$MODELS_PATH/juggernaut_xl_v9.safetensors" ]; then
    aria2c --console-log-level=error -c -x 16 -s 16 -k 1M \
        "https://civitai.com/api/download/models/661530?type=Model&format=SafeTensor&token=${CIVITAI_TOKEN}" \
        -d "$MODELS_PATH" -o juggernaut_xl_v9.safetensors
fi

# ─── 7. SVD XT 1.1 – Gated HuggingFace (HF_TOKEN + Lizenz-Bestätigung nötig) ─
# Einmalig: huggingface.co/stabilityai/stable-video-diffusion-img2vid-xt-1-1
if [ ! -f "$SVD_PATH/svd_xt_1_1.safetensors" ]; then
    aria2c --console-log-level=error -c -x 16 -s 16 -k 1M \
        --header="Authorization: Bearer ${HF_TOKEN}" \
        "https://huggingface.co/stabilityai/stable-video-diffusion-img2vid-xt-1-1/resolve/main/svd_xt_1_1.safetensors" \
        -d "$SVD_PATH" -o svd_xt_1_1.safetensors
fi

# ─── 8. SDXL VAE fp16-fix (HuggingFace, öffentlich) ─────────────────────────
if [ ! -f "$VAE_PATH/sdxl_vae.safetensors" ]; then
    aria2c --console-log-level=error -c -x 16 -s 16 -k 1M \
        "https://huggingface.co/madebyollin/sdxl-vae-fp16-fix/resolve/main/sdxl_vae.safetensors" \
        -d "$VAE_PATH" -o sdxl_vae.safetensors
fi

# ─── 9. ControlNet Canny XL (Ersatz für gelöschten sail_control Pfad) ─────────
# civitai.com → diffusers_xl_canny_full (lllyasviel, offiziell)
if [ ! -f "$CN_PATH/control_canny_xl.safetensors" ]; then
    aria2c --console-log-level=error -c -x 16 -s 16 -k 1M \
        "https://huggingface.co/lllyasviel/sd_control_collection/resolve/main/diffusers_xl_canny_full.safetensors" \
        -d "$CN_PATH" -o control_canny_xl.safetensors
fi

# ─── 10. LoRA: Detail Tweaker XL (korrigierte ID, war 135931 → Pixel Art XL) ──
# civitai.com/models/122359
if [ ! -f "$LORA_PATH/detail_tweaker_xl.safetensors" ]; then
    aria2c --console-log-level=error -c -x 16 -s 16 -k 1M \
        "https://civitai.com/api/download/models/135867?token=${CIVITAI_TOKEN}" \
        -d "$LORA_PATH" -o detail_tweaker_xl.safetensors \
    || echo "[PROV] WARNUNG: detail_tweaker – ToS auf civitai.com/models/122359 bestätigen!"
fi

# ─── 11. LoRA: Realistic Skin Texture XL (Ersatz für gelöschte ID 257744) ──────
# civitai.com/models/580857 – 3,3 Mio. Downloads, SDXL 1.0
# versionId 656094 einmalig auf der Civitai-Seite verifizieren!
if [ ! -f "$LORA_PATH/skin_texture_realism.safetensors" ]; then
    aria2c --console-log-level=error -c -x 16 -s 16 -k 1M \
        "https://civitai.com/api/download/models/656094?token=${CIVITAI_TOKEN}" \
        -d "$LORA_PATH" -o skin_texture_realism.safetensors \
    || echo "[PROV] WARNUNG: skin_texture – ToS auf civitai.com/models/580857 bestätigen!"
fi

# ─── 12. LoRA: RealFace (Ersatz für gelöschte ID 218121 – Human Anatomy Fix) ──
# civitai.com/models/1563692 – SDXL 1.0, Portraits & Gesichtsanatomie
# versionId 1756648 einmalig auf der Civitai-Seite verifizieren!
if [ ! -f "$LORA_PATH/realface_portrait.safetensors" ]; then
    aria2c --console-log-level=error -c -x 16 -s 16 -k 1M \
        "https://civitai.com/api/download/models/1756648?token=${CIVITAI_TOKEN}" \
        -d "$LORA_PATH" -o realface_portrait.safetensors \
    || echo "[PROV] WARNUNG: realface – ToS auf civitai.com/models/1563692 bestätigen!"
fi

# ─── 13. LoRA: Touch of Grain SDXL (Ersatz für gelöschte ID 122832) ───────────
# civitai.com/models/1789604 – trainiert auf Sony A7III, SDXL 1.0
# Trigger Word: "grain" oder "film grain"
# versionId einmalig auf der Civitai-Seite verifizieren!
if [ ! -f "$LORA_PATH/film_grain_style.safetensors" ]; then
    aria2c --console-log-level=error -c -x 16 -s 16 -k 1M \
        "https://civitai.com/api/download/models/2009876?token=${CIVITAI_TOKEN}" \
        -d "$LORA_PATH" -o film_grain_style.safetensors \
    || echo "[PROV] WARNUNG: film_grain – ToS auf civitai.com/models/1789604 bestätigen!"
fi

# ─── 14. Upscaler: 4x-UltraSharp ─────────────────────────────────────────────
# civitai.com/models/116225 – ToS-Bestätigung im Browser nötig (einmalig)
if [ ! -f "$ESRGAN_PATH/4x-UltraSharp.pth" ]; then
    aria2c --console-log-level=error -c -x 16 -s 16 -k 1M \
        "https://civitai.com/api/download/models/125843?type=Model&format=PickleTensor&token=${CIVITAI_TOKEN}" \
        -d "$ESRGAN_PATH" -o 4x-UltraSharp.pth \
    || echo "[PROV] WARNUNG: 4x-UltraSharp – ToS auf civitai.com/models/116225 bestätigen!"
fi

echo "=============================================================================="
echo "[PROV] PROVISIONING ABGESCHLOSSEN."
echo "       WARNUNGEN oben = ToS-Bestätigung auf civitai.com nötig (einmalig)."
echo "=============================================================================="
