#!/bin/bash
###############################################################################
# VAST.AI PROVISIONING SCRIPT: JUGGERNAUT XL STUDIO (FORGE)
# Version:  3.1
# Datum:    2026-05-03
# Änderung: Korrekte Model-IDs, Ersatz-LoRAs, HF-Token, Token-Sicherheit,
#           Existenz-Checks, keine Script-Abbrüche bei 403-Fehlern
###############################################################################

SCRIPT_VERSION="3.1"
SCRIPT_DATE="2026-05-03"

echo "=============================================================================="
echo "[PROV] START: vast-sd-forge-provisioning.sh"
echo "[PROV] Version: ${SCRIPT_VERSION} (${SCRIPT_DATE})"
echo "[PROV] Prüfe ob dies die erwartete Version ist – bei Abweichung GitHub prüfen!"
echo "=============================================================================="

set -euo pipefail

# ─── 1. Tokens aus Umgebungsvariablen (NIEMALS im Klartext!) ─────────────────
CIVITAI_TOKEN="${CIVITAI_TOKEN:?FEHLER: CIVITAI_TOKEN ist nicht als Env-Variable gesetzt!}"
HF_TOKEN="${HF_TOKEN:?FEHLER: HF_TOKEN ist nicht als Env-Variable gesetzt!}"

# ─── 2. Pfade definieren ─────────────────────────────────────────────────────
BASE_PATH="/workspace/stable-diffusion-webui-forge"
MODELS_PATH="$BASE_PATH/models/Stable-diffusion"
LORA_PATH="$BASE_PATH/models/Lora"
CN_PATH="$BASE_PATH/models/ControlNet"
VAE_PATH="$BASE_PATH/models/VAE"
ESRGAN_PATH="$BASE_PATH/models/ESRGAN"
SVD_PATH="$BASE_PATH/models/svd"
EXT_PATH="$BASE_PATH/extensions"

# ─── 3. Verzeichnisstruktur sicherstellen ────────────────────────────────────
echo "[PROV] Bereite Verzeichnisse vor..."
mkdir -p "$MODELS_PATH" "$LORA_PATH" "$CN_PATH" "$VAE_PATH" "$ESRGAN_PATH" "$SVD_PATH" "$EXT_PATH"

# ─── 4. Download-Beschleuniger installieren ───────────────────────────────────
echo "[PROV] Installiere aria2..."
apt-get update -y -qq && apt-get install -y -qq aria2

# ─── 5. Extensions (Git Clones) ──────────────────────────────────────────────
echo "[PROV] Installiere Extensions..."
cd "$EXT_PATH"
if [ ! -d "sd-webui-aspect-ratio-helper" ]; then
    git clone https://github.com/thomasasfk/sd-webui-aspect-ratio-helper.git
    echo "[PROV] Extension aspect-ratio-helper installiert."
else
    echo "[PROV] Extension aspect-ratio-helper bereits vorhanden – übersprungen."
fi

# ─── 6. Juggernaut XL v9 ─────────────────────────────────────────────────────
# Ersatz für gelöschte ID 456124. Korrekte Version: v9, versionId=661530
# Civitai-Seite: civitai.com/models/133005
echo "[PROV] Lade Juggernaut XL v9..."
if [ ! -f "$MODELS_PATH/juggernaut_xl_v9.safetensors" ]; then
    aria2c --console-log-level=error -c -x 16 -s 16 -k 1M \
        "https://civitai.com/api/download/models/661530?type=Model&format=SafeTensor&token=${CIVITAI_TOKEN}" \
        -d "$MODELS_PATH" -o juggernaut_xl_v9.safetensors
    echo "[PROV] Juggernaut XL v9 geladen."
else
    echo "[PROV] Juggernaut XL v9 bereits vorhanden – übersprungen."
fi

# ─── 7. SVD XT 1.1 (HuggingFace Gated – HF_TOKEN erforderlich) ───────────────
# Voraussetzung: Lizenz einmalig im Browser akzeptieren:
# huggingface.co/stabilityai/stable-video-diffusion-img2vid-xt-1-1
echo "[PROV] Lade SVD XT 1.1..."
if [ ! -f "$SVD_PATH/svd_xt_1_1.safetensors" ]; then
    aria2c --console-log-level=error -c -x 16 -s 16 -k 1M \
        --header="Authorization: Bearer ${HF_TOKEN}" \
        "https://huggingface.co/stabilityai/stable-video-diffusion-img2vid-xt-1-1/resolve/main/svd_xt_1_1.safetensors" \
        -d "$SVD_PATH" -o svd_xt_1_1.safetensors
    echo "[PROV] SVD XT 1.1 geladen."
else
    echo "[PROV] SVD XT 1.1 bereits vorhanden – übersprungen."
fi

# ─── 8. SDXL VAE fp16-fix (öffentlich, kein Token nötig) ─────────────────────
echo "[PROV] Lade SDXL VAE..."
if [ ! -f "$VAE_PATH/sdxl_vae.safetensors" ]; then
    aria2c --console-log-level=error -c -x 16 -s 16 -k 1M \
        "https://huggingface.co/madebyollin/sdxl-vae-fp16-fix/resolve/main/sdxl_vae.safetensors" \
        -d "$VAE_PATH" -o sdxl_vae.safetensors
    echo "[PROV] SDXL VAE geladen."
else
    echo "[PROV] SDXL VAE bereits vorhanden – übersprungen."
fi

# ─── 9. ControlNet Canny XL ──────────────────────────────────────────────────
# Ersatz für gelöschten Pfad sail_control_canny_sdxl.safetensors
echo "[PROV] Lade ControlNet Canny XL..."
if [ ! -f "$CN_PATH/control_canny_xl.safetensors" ]; then
    aria2c --console-log-level=error -c -x 16 -s 16 -k 1M \
        "https://huggingface.co/lllyasviel/sd_control_collection/resolve/main/diffusers_xl_canny_full.safetensors" \
        -d "$CN_PATH" -o control_canny_xl.safetensors
    echo "[PROV] ControlNet Canny XL geladen."
else
    echo "[PROV] ControlNet Canny XL bereits vorhanden – übersprungen."
fi

# ─── 10. LoRA: Detail Tweaker XL ─────────────────────────────────────────────
# Original ID 135931 lieferte falsches Modell (Pixel Art XL) → korrigiert auf 135867
# Civitai-Seite: civitai.com/models/122359
# ToS-Bestätigung: einmalig Download-Button auf civitai.com/models/122359 klicken
echo "[PROV] Lade Detail Tweaker XL LoRA..."
if [ ! -f "$LORA_PATH/detail_tweaker_xl.safetensors" ]; then
    aria2c --console-log-level=error -c -x 16 -s 16 -k 1M \
        "https://civitai.com/api/download/models/135867?token=${CIVITAI_TOKEN}" \
        -d "$LORA_PATH" -o detail_tweaker_xl.safetensors \
    || echo "[PROV] WARNUNG: detail_tweaker_xl – ToS auf civitai.com/models/122359 bestätigen!"
else
    echo "[PROV] Detail Tweaker XL bereits vorhanden – übersprungen."
fi

# ─── 11. LoRA: Realistic Skin Texture XL ─────────────────────────────────────
# Ersatz für gelöschte ID 257744. versionId=656094
# Civitai-Seite: civitai.com/models/580857
# ToS-Bestätigung: einmalig Download-Button klicken
echo "[PROV] Lade Realistic Skin Texture XL LoRA..."
if [ ! -f "$LORA_PATH/skin_texture_realism.safetensors" ]; then
    aria2c --console-log-level=error -c -x 16 -s 16 -k 1M \
        "https://civitai.com/api/download/models/656094?token=${CIVITAI_TOKEN}" \
        -d "$LORA_PATH" -o skin_texture_realism.safetensors \
    || echo "[PROV] WARNUNG: skin_texture – ToS auf civitai.com/models/580857 bestätigen!"
else
    echo "[PROV] Skin Texture XL bereits vorhanden – übersprungen."
fi

# ─── 12. LoRA: RealFace ───────────────────────────────────────────────────────
# Ersatz für gelöschte ID 218121. versionId=1756648
# Civitai-Seite: civitai.com/models/1563692
# ToS-Bestätigung: einmalig Download-Button klicken
echo "[PROV] Lade RealFace LoRA..."
if [ ! -f "$LORA_PATH/realface_portrait.safetensors" ]; then
    aria2c --console-log-level=error -c -x 16 -s 16 -k 1M \
        "https://civitai.com/api/download/models/1756648?token=${CIVITAI_TOKEN}" \
        -d "$LORA_PATH" -o realface_portrait.safetensors \
    || echo "[PROV] WARNUNG: realface – ToS auf civitai.com/models/1563692 bestätigen!"
else
    echo "[PROV] RealFace LoRA bereits vorhanden – übersprungen."
fi

# ─── 13. LoRA: Touch of Grain SDXL ───────────────────────────────────────────
# Ersatz für gelöschte ID 122832. versionId=2009876
# Civitai-Seite: civitai.com/models/1789604
# ToS-Bestätigung: einmalig Download-Button klicken
# HINWEIS: versionId einmalig auf der Civitai-Seite verifizieren!
echo "[PROV] Lade Touch of Grain XL LoRA..."
if [ ! -f "$LORA_PATH/film_grain_style.safetensors" ]; then
    aria2c --console-log-level=error -c -x 16 -s 16 -k 1M \
        "https://civitai.com/api/download/models/2009876?token=${CIVITAI_TOKEN}" \
        -d "$LORA_PATH" -o film_grain_style.safetensors \
    || echo "[PROV] WARNUNG: film_grain – ToS auf civitai.com/models/1789604 bestätigen!"
else
    echo "[PROV] Touch of Grain XL bereits vorhanden – übersprungen."
fi

# ─── 14. Upscaler: 4x-UltraSharp ─────────────────────────────────────────────
# Civitai-Seite: civitai.com/models/116225
# ToS-Bestätigung: einmalig Download-Button klicken
echo "[PROV] Lade 4x-UltraSharp Upscaler..."
if [ ! -f "$ESRGAN_PATH/4x-UltraSharp.pth" ]; then
    aria2c --console-log-level=error -c -x 16 -s 16 -k 1M \
        "https://civitai.com/api/download/models/125843?type=Model&format=PickleTensor&token=${CIVITAI_TOKEN}" \
        -d "$ESRGAN_PATH" -o 4x-UltraSharp.pth \
    || echo "[PROV] WARNUNG: 4x-UltraSharp – ToS auf civitai.com/models/116225 bestätigen!"
else
    echo "[PROV] 4x-UltraSharp bereits vorhanden – übersprungen."
fi

# ─── 15. Abschluss ───────────────────────────────────────────────────────────
echo "=============================================================================="
echo "[PROV] PROVISIONING ABGESCHLOSSEN – Version ${SCRIPT_VERSION} (${SCRIPT_DATE})"
echo "       WARNUNGEN oben = ToS-Bestätigung auf civitai.com nötig (einmalig)."
echo "=============================================================================""
