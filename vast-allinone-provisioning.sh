#!/bin/bash
set -euo pipefail

LOG_FILE="/workspace/vast-allinone-provisioning.log"
exec > >(tee -a "$LOG_FILE") 2>&1

: "${WORKSPACE:=/workspace}"
: "${GITHUB_PAT:?GITHUB_PAT is not set}"

echo "[INFO] Starting provisioning at $(date -Is)"

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
TMP_MODEL_LIST="$(mktemp)"

echo "[INFO] Fetching model list"
curl -fsSL \
  -H "Authorization: token ${GITHUB_PAT}" \
  "$MODEL_LIST_URL" \
  -o "$TMP_MODEL_LIST"

source "$TMP_MODEL_LIST"
rm -f "$TMP_MODEL_LIST"

download_civitai() {
  local dest="$1"
  local name="$2"
  local id="$3"
  mkdir -p "$dest"
  [[ -s "$dest/$name" ]] && { echo "[SKIP] $name already exists"; return 0; }
  echo "[DL] Civitai $name"
  curl -fL --retry 3 "https://civitai.com/api/download/models/$id" -o "$dest/$name"
}

download_url() {
  local dest="$1"
  local name="$2"
  local url="$3"
  mkdir -p "$dest"
  [[ -s "$dest/$name" ]] && { echo "[SKIP] $name already exists"; return 0; }
  echo "[DL] $name"
  curl -fL --retry 3 -o "$dest/$name" "$url"
}

download_gated() {
  local dest="$1"
  local name="$2"
  local path="$3"
  mkdir -p "$dest"
  [[ -s "$dest/$name" ]] && { echo "[SKIP] $name already exists"; return 0; }
  echo "[DL] HF gated $name"
  curl -fL --retry 3 \
    -H "Authorization: Bearer ${HF_TOKEN:-}" \
    "https://huggingface.co/${path}" \
    -o "$dest/$name"
}

if declare -p DOWNLOADS >/dev/null 2>&1; then
  for entry in "${DOWNLOADS[@]}"; do
    IFS='|' read -r dest name src <<< "$entry"
    case "$src" in
      HF_GATED:*)
        download_gated "$dest" "$name" "${src#HF_GATED:}"
        ;;
      http://*|https://*)
        download_url "$dest" "$name" "$src"
        ;;
      *)
        download_civitai "$dest" "$name" "$src"
        ;;
    esac
  done
fi

if declare -p EXTENSIONS >/dev/null 2>&1; then
  EXT_DIR="$WORKSPACE/extensions"
  mkdir -p "$EXT_DIR"
  cd "$EXT_DIR"
  for repo in "${EXTENSIONS[@]}"; do
    dir="$(basename "$repo" .git)"
    if [[ -d "$dir" ]]; then
      echo "[SKIP] Extension exists: $dir"
    else
      echo "[CLONE] $repo"
      git clone "$repo" || true
    fi
  done
fi

echo "[INFO] Provisioning complete"
