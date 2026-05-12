#!/bin/bash
set -euo pipefail

LOG_FILE="/workspace/vast-allinone-provisioning.log"
exec > >(tee -a "$LOG_FILE") 2>&1

: "${WORKSPACE:=/workspace}"
: "${GITHUB_PAT:?GITHUB_PAT is not set}"

VAST_INFO()  { echo -e "\033[1;34m[VAST][INFO]\033[0m $*"; }
VAST_WARN()  { echo -e "\033[1;33m[VAST][WARN]\033[0m $*"; }
VAST_ERROR() { echo -e "\033[1;31m[VAST][ERROR]\033[0m $*"; }
VAST_OK()    { echo -e "\033[1;32m[VAST][OK]\033[0m $*"; }
VAST_STEP()  { echo -e "\033[1;36m[VAST][STEP $1]\033[0m ${*:2}"; }

VAST_INFO "Provisioning started"

VAST_STEP 1 "creating directories"
set -x
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
set +x
VAST_OK "directories ready"

VAST_STEP 2 "fetching model list"
set -x
MODEL_LIST_URL="https://raw.githubusercontent.com/hondo100/vast-sd-provision/refs/heads/main/modell-list.sh"
TMP_MODEL_LIST="$(mktemp)"
curl -fsSL \
  -H "Authorization: token ${GITHUB_PAT}" \
  "$MODEL_LIST_URL" \
  -o "$TMP_MODEL_LIST"
set +x
VAST_OK "model list fetched"

VAST_STEP 3 "loading model list"
set -x
source "$TMP_MODEL_LIST"
rm -f "$TMP_MODEL_LIST"
set +x
VAST_OK "model list loaded"

download_civitai() {
  local dest="$1" name="$2" id="$3"
  mkdir -p "$dest"
  if [[ -s "$dest/$name" ]]; then
    VAST_INFO "SKIP existing Civitai file: $name"
    return 0
  fi
  VAST_INFO "Downloading Civitai: $name (id=$id)"
  curl -fL --retry 3 "https://civitai.com/api/download/models/$id" -o "$dest/$name"
  VAST_OK "Downloaded: $name"
}

download_url() {
  local dest="$1" name="$2" url="$3"
  mkdir -p "$dest"
  if [[ -s "$dest/$name" ]]; then
    VAST_INFO "SKIP existing URL file: $name"
    return 0
  fi
  VAST_INFO "Downloading URL: $name"
  curl -fL --retry 3 -o "$dest/$name" "$url"
  VAST_OK "Downloaded: $name"
}

download_gated() {
  local dest="$1" name="$2" path="$3"
  mkdir -p "$dest"
  if [[ -s "$dest/$name" ]]; then
    VAST_INFO "SKIP existing HF gated file: $name"
    return 0
  fi
  if [[ -z "${HF_TOKEN:-}" ]]; then
    VAST_WARN "HF_TOKEN is missing, cannot download: $name"
    return 1
  fi
  VAST_INFO "Downloading HF gated: $name"
  curl -fL --retry 3 \
    -H "Authorization: Bearer ${HF_TOKEN}" \
    "https://huggingface.co/${path}" \
    -o "$dest/$name"
  VAST_OK "Downloaded: $name"
}

VAST_STEP 4 "processing downloads (${#DOWNLOADS[@]})"
for entry in "${DOWNLOADS[@]}"; do
  IFS='|' read -r dest name src <<< "$entry"
  VAST_INFO "Processing: $name"
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
VAST_OK "downloads processed"

if declare -p EXTENSIONS >/dev/null 2>&1; then
  VAST_STEP 5 "processing extensions (${#EXTENSIONS[@]})"
  EXT_DIR="$WORKSPACE/extensions"
  mkdir -p "$EXT_DIR"
  cd "$EXT_DIR"
  for repo in "${EXTENSIONS[@]}"; do
    dir="$(basename "$repo" .git)"
    if [[ -d "$dir" ]]; then
      VAST_INFO "SKIP existing extension: $dir"
    else
      VAST_INFO "Cloning extension: $repo"
      git clone "$repo" || VAST_WARN "Clone failed: $repo"
      [[ -d "$dir" ]] && VAST_OK "Cloned: $dir"
    fi
  done
fi

VAST_OK "Provisioning complete"
