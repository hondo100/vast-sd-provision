#!/bin/bash
set -euo pipefail

LOG_FILE="/workspace/vast-allinone-provisioning.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "[INFO] Starting vast-allinone-provisioning.sh"

: "${WORKSPACE:=/workspace}"
: "${GITHUB_PAT:=}"
: "${CIVITAI_API_KEY:=}"
: "${HF_TOKEN:=}"

if [[ -z "${GITHUB_PAT}" ]]; then
  echo "[WARN] GITHUB_PAT is not set. Private GitHub raw fetch may fail."
fi

mkdir -p \
  "$WORKSPACE/ComfyUI/models/checkpoints" \
  "$WORKSPACE/ComfyUI/models/loras" \
  "$WORKSPACE/ComfyUI/models/vae" \
  "$WORKSPACE/ComfyUI/models/controlnet" \
  "$WORKSPACE/ComfyUI/models/embeddings" \
  "$WORKSPACE/ComfyUI/models/upscale_models" \
  "$WORKSPACE/ComfyUI/models/ultralytics/bbox" \
  "$WORKSPACE/forge-models/Stable-diffusion" \
  "$WORKSPACE/forge-models/Lora" \
  "$WORKSPACE/forge-models/ESRGAN" \
  "$WORKSPACE/forge-models/torch_deepdanbooru" \
  "$WORKSPACE/outputs"

MODEL_LIST_URL="https://raw.githubusercontent.com/hondo100/vast-sd-provision/refs/heads/main/modell-list.sh"
echo "[INFO] Loading model list from $MODEL_LIST_URL"
source <(curl -fsSL -H "Authorization: token ${GITHUB_PAT}" "$MODEL_LIST_URL")

download_civitai() {
  local dest="$1"
  local name="$2"
  local id="$3"
  mkdir -p "$dest"
  if [[ -s "$dest/$name" ]]; then
    echo "[SKIP] $name already exists"
    return 0
  fi
  echo "[DL] Civitai $name"
  curl -fL --retry 3 \
    "https://civitai.com/api/download/models/$id?token=${CIVITAI_API_KEY}" \
    -o "$dest/$name"
}

download_url() {
  local dest="$1"
  local name="$2"
  local url="$3"
  mkdir -p "$dest"
  if [[ -s "$dest/$name" ]]; then
    echo "[SKIP] $name already exists"
    return 0
  fi
  echo "[DL] $name"
  aria2c -x16 -s16 --max-tries=3 -d "$dest" -o "$name" "$url"
}

download_gated() {
  local dest="$1"
  local name="$2"
  local path="$3"
  mkdir -p "$dest"
  if [[ -s "$dest/$name" ]]; then
    echo "[SKIP] $name already exists"
    return 0
  fi
  echo "[DL] Gated $name"
  curl -fL --retry 3 \
    -H "Authorization: Bearer ${HF_TOKEN}" \
    "https://huggingface.co/${path}" \
    -o "$dest/$name"
}

for entry in "${DOWNLOADS[@]}"; do
  IFS='|' read -r dest name src <<< "$entry"
  case "$src" in
    HF_GATED:*)
      gated_path="${src#HF_GATED:}"
      download_gated "$dest" "$name" "$gated_path"
      ;;
    http://*|https://*)
      download_url "$dest" "$name" "$src"
      ;;
    *)
      download_civitai "$dest" "$name" "$src"
      ;;
  esac
done

if [[ "${#EXTENSIONS[@]:-0}" -gt 0 ]]; then
  EXT_DIR="$WORKSPACE/extensions"
  mkdir -p "$EXT_DIR"
  cd "$EXT_DIR"
  for repo in "${EXTENSIONS[@]}"; do
    dir=$(basename "$repo" .git)
    if [[ -d "$dir" ]]; then
      echo "[SKIP] Extension exists: $dir"
    else
      echo "[CLONE] $repo"
      git clone "$repo" || true
    fi
  done
fi

echo "[INFO] Provisioning complete"
