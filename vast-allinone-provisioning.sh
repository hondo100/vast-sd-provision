#!/bin/bash
set -euo pipefail

LOG_FILE="/workspace/vast-allinone-provisioning.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "[INFO] Starting vast-allinone-provisioning.sh"

: "${WORKSPACE:=/workspace}"
: "${CIVITAI_API_KEY:=}"
: "${HF_TOKEN:=}"

mkdir -p "$WORKSPACE"

MODEL_LIST_URL="https://raw.githubusercontent.com/DEINUSER/DEINREPO/main/modell-list.sh"
echo "[INFO] Loading model list from $MODEL_LIST_URL"
source <(curl -fsSL "$MODEL_LIST_URL")

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
