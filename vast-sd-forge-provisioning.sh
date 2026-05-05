#!/bin/bash
###############################################################################
# github-provisioning.sh
# Version: 1.0 | Datum: 2026-05-05
# Zweck: Automatisches Provisioning einer Stable Diffusion Forge Umgebung
#        auf Vast.ai. Wird via GitHub Token aus privatem Repo geladen.
#
# Benoetigte Environment Variables im Vast-Template:
#   CIVITAI_TOKEN  = Civitai API Key
#   HF_TOKEN       = HuggingFace API Token
#
# Onstart-Befehl im Vast-Template:
#   bash <(curl -sH "Authorization: token ${GITHUB_TOKEN}" \
#     https://raw.githubusercontent.com/DEIN-USER/DEIN-REPO/main/github-provisioning.sh)
###############################################################################

set -euo pipefail
SCRIPT_VERSION="1.0"
LOG="/workspace/provisioning.log"
exec > >(tee -a "$LOG") 2>&1

echo "==================================================="
echo "[PROV] github-provisioning.sh - Version ${SCRIPT_VERSION}"
echo "[PROV] Start: $(date)"
echo "==================================================="

# ─── Token-Pruefung ───────────────────────────────────────────────────────────
if [ -z "${CIVITAI_TOKEN:-}" ]; then echo "[PROV] FEHLER: CIVITAI_TOKEN fehlt!"; exit 1; fi
if [ -z "${HF_TOKEN:-}" ]; then echo "[PROV] FEHLER: HF_TOKEN fehlt!"; exit 1; fi
echo "[PROV] Tokens gefunden."

# ─── Pfade (echte Forge-Verzeichnisse auf Vast) ───────────────────────────────
BASE="/workspace/stable-diffusion-webui-forge"
MODELS_PATH="$BASE/models/Stable-diffusion"
LORA_PATH="$BASE/models/Lora"
CN_PATH="$BASE/models/ControlNet"
VAE_PATH="$BASE/models/VAE"
ESRGAN_PATH="$BASE/models/ESRGAN"
SVD_PATH="$BASE/models/svd"
EXT_PATH="$BASE/extensions"

mkdir -p "$MODELS_PATH" "$LORA_PATH" "$CN_PATH" "$VAE_PATH" "$ESRGAN_PATH" "$SVD_PATH" "$EXT_PATH"
echo "[PROV] Verzeichnisse bereit."

# ─── aria2 pruefen ────────────────────────────────────────────────────────────
if ! command -v aria2c &> /dev/null; then
  echo "[PROV] aria2 nicht gefunden, installiere..."
  apt-get install -y aria2 >> "$LOG" 2>&1
fi
echo "[PROV] aria2: $(aria2c --version | head -1)"

# ─── Download-Funktion ────────────────────────────────────────────────────────
download() {
  local LABEL="$1" URL="$2" DIR="$3" FILE="$4"
  shift 4; local EXTRA_ARGS=("$@")
  if [ -f "$DIR/$FILE" ]; then
    echo "[PROV] SKIP ${LABEL} - $(du -sh "$DIR/$FILE" | cut -f1) bereits vorhanden."
    return 0
  fi
  echo "[PROV] LADE ${LABEL} ..."
  if aria2c --console-log-level=warn -c -x 16 -s 16 -k 1M "${EXTRA_ARGS[@]}" "$URL" -d "$DIR" -o "$FILE"; then
    echo "[PROV] OK ${LABEL} - $(du -sh "$DIR/$FILE" | cut -f1)"
  else
    echo "[PROV] FEHLER ${LABEL} - Pruefe Token oder URL."
    return 1
  fi
}

# ─── Checkpoint (kritisch – bei Fehler Script abbrechen) ──────────────────────
echo "[PROV] -- Checkpoint --"
download "Juggernaut XL v9" \
  "https://civitai.com/api/download/models/348913?type=Model&format=SafeTensor&size=full&fp=fp16&token=${CIVITAI_TOKEN}" \
  "$MODELS_PATH" "juggernaut_xl_v9.safetensors" || { echo "[PROV] KRITISCH: Checkpoint fehlt!"; exit 1; }

# ─── Video-Modell ─────────────────────────────────────────────────────────────
echo "[PROV] -- Video-Modell --"
download "SVD XT 1.1" \
  "https://huggingface.co/stabilityai/stable-video-diffusion-img2vid-xt-1-1/resolve/main/svd_xt_1_1.safetensors" \
  "$SVD_PATH" "svd_xt_1_1.safetensors" \
  "--header=Authorization: Bearer ${HF_TOKEN}"

# ─── VAE ──────────────────────────────────────────────────────────────────────
echo "[PROV] -- VAE --"
download "SDXL VAE fp16-fix" \
  "https://huggingface.co/madebyollin/sdxl-vae-fp16-fix/resolve/main/sdxl_vae.safetensors" \
  "$VAE_PATH" "sdxl_vae.safetensors"

# ─── ControlNet ───────────────────────────────────────────────────────────────
echo "[PROV] -- ControlNet --"
download "ControlNet Canny XL" \
  "https://huggingface.co/lllyasviel/sd_control_collection/resolve/main/diffusers_xl_canny_full.safetensors" \
  "$CN_PATH" "control_canny_xl.safetensors"

# ─── LoRAs ────────────────────────────────────────────────────────────────────
echo "[PROV] -- LoRAs --"
download "Detail Tweaker XL" \
  "https://huggingface.co/AiWise/Detail-Tweaker-XL_v1/resolve/main/add-detail-xl.safetensors" \
  "$LORA_PATH" "detail_tweaker_xl.safetensors"

download "Realistic Skin Texture XL" \
  "https://huggingface.co/MarkBW/detailed-skin-xl/resolve/main/skin%20texture%20style%20v4.safetensors" \
  "$LORA_PATH" "skin_texture_realism.safetensors"

download "Face Helper SDXL" \
  "https://huggingface.co/ostris/face-helper-sdxl-lora/resolve/main/face_xl_v0_1.safetensors" \
  "$LORA_PATH" "realface_portrait.safetensors"

download "Film Grain SDXL" \
  "https://huggingface.co/artificialguybr/filmgrain-redmond-filmgrain-lora-for-sdxl/resolve/main/FilmGrainRedmond-FilmGrain-FilmGrainAF.safetensors" \
  "$LORA_PATH" "film_grain_style.safetensors"

# ─── Upscaler ─────────────────────────────────────────────────────────────────
echo "[PROV] -- Upscaler --"
download "4x-UltraSharp" \
  "https://huggingface.co/Kim2091/UltraSharp/resolve/main/4x-UltraSharp.safetensors" \
  "$ESRGAN_PATH" "4x-UltraSharp.pth"

# ─── Extensions ───────────────────────────────────────────────────────────────
echo "[PROV] -- Extensions --"
if [ ! -d "$EXT_PATH/sd-webui-aspect-ratio-helper" ]; then
  git clone https://github.com/thomasasfk/sd-webui-aspect-ratio-helper.git \
    "$EXT_PATH/sd-webui-aspect-ratio-helper"
  echo "[PROV] OK Extension aspect-ratio-helper geklont."
else
  cd "$EXT_PATH/sd-webui-aspect-ratio-helper" && git pull && cd -
  echo "[PROV] OK Extension aspect-ratio-helper aktualisiert."
fi

# ─── Forge starten ────────────────────────────────────────────────────────────
echo "[PROV] -- Forge Start --"
cd "$BASE"
python launch.py \
  --xformers \
  --opt-sdp-attention \
  --listen \
  --port 17861 \
  --api \
  --no-half-vae \
  --theme dark \
  >> "$LOG" 2>&1 &

echo "==================================================="
echo "[PROV] Provisioning abgeschlossen: $(date)"
echo "[PROV] Log: $LOG"
echo "==================================================="
