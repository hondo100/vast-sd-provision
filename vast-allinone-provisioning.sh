#!/bin/bash
set -euo pipefail

LOG_FILE="/workspace/vast-allinone-provisioning.log"
exec > >(tee -a "$LOG_FILE") 2>&1

: "${WORKSPACE:=/workspace}"
: "${GITHUB_PAT:?GITHUB_PAT is not set}"

ts() { date -Is; }
log() { echo "[$(ts)] [$1] ${*:2}"; }

log INFO "Provisioning started"

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

log INFO "Fetching model list"
MODEL_LIST_URL="https://raw.githubusercontent.com/hondo100/vast-sd-provision/refs/heads/main/modell-list.sh"
TMP_MODEL_LIST="$(mktemp)"

curl -fsSL \
  -H "Authorization: token ${GITHUB_PAT}" \
  "$MODEL_LIST_URL" \
  -o "$TMP_MODEL_LIST"

log INFO "Model list downloaded, sourcing it"
source "$TMP_MODEL_LIST"
rm -f "$TMP_MODEL_LIST"

download_civitai() {
  local dest="$1" name="$2" id="$3"
  mkdir -p "$dest"
  if [[ -s "$dest/$name" ]]; then
    log INFO "SKIP existing Civitai file: $name"
    return 0
  fi
  log INFO "Downloading Civitai file: $name (id=$id)"
  curl -fL --retry 3 "https://civitai.com/api/download/models/$id" -o "$dest/$name"
  log INFO "Finished: $name"
}

download_url() {
  local dest="$1" name="$2" url="$3"
  mkdir -p "$dest"
  if [[ -s "$dest/$name" ]]; then
    log INFO "SKIP existing URL file: $name"
    return 0
  fi
  log INFO "Downloading URL file: $name"
  curl -fL --retry 3 -o "$dest/$name" "$url"
  log INFO "Finished: $name"
}

download_gated() {
  local dest="$1" name="$2" path="$3"
  mkdir -p "$dest"
  if [[ -s "$dest/$name" ]]; then
    log INFO "SKIP existing HF gated file: $name"
    return 0
  fi
  if [[ -z "${HF_TOKEN:-}" ]]; then
    log WARN "HF_TOKEN missing, cannot download: $name"
    return 1
  fi
  log INFO "Downloading HF gated file: $name"
  curl -fL --retry 3 \
    -H "Authorization: Bearer ${HF_TOKEN}" \
    "https://huggingface.co/${path}" \
    -o "$dest/$name"
  log INFO "Finished: $name"
}

log INFO "Processing ${#DOWNLOADS[@]} downloads"
for entry in "${DOWNLOADS[@]}"; do
  IFS='|' read -r dest name src <<< "$entry"
  log INFO "Processing entry: $name -> $dest"
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

if declare -p EXTENSIONS >/dev/null 2>&1; then
  EXT_DIR="$WORKSPACE/extensions"
  mkdir -p "$EXT_DIR"
  cd "$EXT_DIR"
  log INFO "Processing ${#EXTENSIONS[@]} extensions"
  for repo in "${EXTENSIONS[@]}"; do
    dir="$(basename "$repo" .git)"
    if [[ -d "$dir" ]]; then
      log INFO "SKIP existing extension: $dir"
    else
      log INFO "Cloning extension: $repo"
      git clone "$repo" || log WARN "Clone failed: $repo"
    fi
  done
fi

log INFO "Provisioning complete"
