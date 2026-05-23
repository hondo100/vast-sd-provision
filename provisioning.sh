#!/usr/bin/env bash
set -Eeuo pipefail

LOG_FILE="/workspace/vast-sd-forge-provisioning.log"
mkdir -p /workspace
exec > >(tee -a "$LOG_FILE") 2>&1

START_TS=$(date +%s)
FAILED_DOWNLOADS=()
FAILED_EXTENSIONS=()

info(){ echo -e "\033[1;34m[VAST][INFO]\033[0m  [$(date '+%H:%M:%S')] $*"; }
ok(){ echo -e "\033[1;32m[VAST][OK]\033[0m    [$(date '+%H:%M:%S')] $*"; }
warn(){ echo -e "\033[1;33m[VAST][WARN]\033[0m  [$(date '+%H:%M:%S')] $*"; }
err(){ echo -e "\033[1;31m[VAST][ERROR]\033[0m [$(date '+%H:%M:%S')] $*" >&2; }
section(){ echo; echo "[VAST] ===== $* ====="; }
trap 'err "Abbruch in Zeile $LINENO: $BASH_COMMAND"' ERR

: "${WORKSPACE:=/workspace}"
: "${FORGE_REPO:=stable-diffusion-webui-forge}"
: "${CIVITAI_TOKEN:=}"
: "${HF_TOKEN:=}"
: "${FORGE_RESTART_AFTER_PROVISION:=true}"

FORGE_ROOT="$WORKSPACE/$FORGE_REPO"
FORGE_MODELS="$FORGE_ROOT/models"
FORGE_EXTENSIONS="$FORGE_ROOT/extensions"
SENTINEL="$WORKSPACE/.provisioning_done"

ok_size(){ [[ -f "$1" && $(stat -c%s "$1" 2>/dev/null || echo 0) -gt 1048576 ]]; }
_curl(){ curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 --speed-limit 102400 --speed-time 30 "$@"; }

get_civitai(){
  local dest="$1" name="$2" id="$3"
  mkdir -p "$dest"
  if ok_size "$dest/$name"; then info "SKIP $name"; return 0; fi
  [[ -n "${CIVITAI_TOKEN:-}" ]] || { warn "CIVITAI_TOKEN fehlt – skip $name"; return 0; }
  _curl -H "User-Agent: Mozilla/5.0" "https://civitai.com/api/download/models/${id}?token=${CIVITAI_TOKEN}" -o "$dest/$name"
}

get_url(){
  local dest="$1" name="$2" url="$3"
  mkdir -p "$dest"
  if ok_size "$dest/$name"; then info "SKIP $name"; return 0; fi
  _curl -o "$dest/$name" "$url"
}

get_hf_gated(){
  local dest="$1" name="$2" path="$3"
  mkdir -p "$dest"
  if ok_size "$dest/$name"; then info "SKIP $name"; return 0; fi
  [[ -n "${HF_TOKEN:-}" ]] || { warn "HF_TOKEN fehlt – skip $name"; return 0; }
  _curl -H "Authorization: Bearer ${HF_TOKEN}" "https://huggingface.co/${path}" -o "$dest/$name"
}

get_optional(){
  local dest="$1" name="$2" src="$3"
  mkdir -p "$dest"
  [[ -f "$dest/$name" ]] && return 0
  cp "$src" "$dest/$name"
}

section "START"
info "WORKSPACE=$WORKSPACE"
info "FORGE_ROOT=$FORGE_ROOT"

if [[ -f "$SENTINEL" ]]; then
  info "Sentinel gefunden – Provisioning wird übersprungen"
  exit 0
fi

[[ -f "$WORKSPACE/model-list.sh" ]] || { err "model-list.sh fehlt"; exit 1; }
source "$WORKSPACE/model-list.sh"

mkdir -p \
  "$FORGE_MODELS/Stable-diffusion" \
  "$FORGE_MODELS/Lora" \
  "$FORGE_MODELS/VAE" \
  "$FORGE_MODELS/ControlNet" \
  "$FORGE_MODELS/ESRGAN" \
  "$FORGE_MODELS/embeddings" \
  "$FORGE_MODELS/torch_deepdanbooru" \
  "$WORKSPACE/outputs"

section "DOWNLOADS"
for entry in "${DOWNLOADS[@]}"; do
  IFS='|' read -r dest name src <<< "$entry"
  info "Lade $name"
  if [[ "$src" == HF_GATED:* ]]; then
    get_hf_gated "$dest" "$name" "${src#HF_GATED:}" || { rm -f "$dest/$name"; FAILED_DOWNLOADS+=("$name"); }
  elif [[ "$src" =~ ^https?:// ]]; then
    get_url "$dest" "$name" "$src" || { rm -f "$dest/$name"; FAILED_DOWNLOADS+=("$name"); }
  elif [[ "$src" =~ ^[0-9]+$ ]]; then
    get_civitai "$dest" "$name" "$src" || { rm -f "$dest/$name"; FAILED_DOWNLOADS+=("$name"); }
  else
    warn "Unbekanntes Format für $name: $src"
  fi
done

section "EXTENSIONS"
mkdir -p "$FORGE_EXTENSIONS"
cd "$FORGE_EXTENSIONS"
for repo in "${EXTENSIONS[@]}"; do
  dir="$(basename "$repo" .git)"
  if [[ -d "$dir" ]]; then
    info "SKIP extension $dir"
    continue
  fi
  git clone --depth=1 "$repo" "$dir" || FAILED_EXTENSIONS+=("$dir")
done

section "CONFIGS"
[[ -f "$WORKSPACE/config.json" ]] && get_optional "$FORGE_ROOT" "config.json" "$WORKSPACE/config.json"
[[ -f "$WORKSPACE/ui-config.json" ]] && get_optional "$FORGE_ROOT" "ui-config.json" "$WORKSPACE/ui-config.json"

echo "$(date -Is)" > "$SENTINEL"

if [[ "$FORGE_RESTART_AFTER_PROVISION" == "true" ]]; then
  if command -v supervisorctl >/dev/null 2>&1; then
    supervisorctl restart forge || warn "supervisorctl restart forge fehlgeschlagen"
  else
    warn "supervisorctl nicht gefunden"
  fi
fi

section "ENDE"
[[ ${#FAILED_DOWNLOADS[@]} -gt 0 ]] && warn "Fehlgeschlagene Downloads: ${FAILED_DOWNLOADS[*]}"
[[ ${#FAILED_EXTENSIONS[@]} -gt 0 ]] && warn "Fehlgeschlagene Extensions: ${FAILED_EXTENSIONS[*]}"
info "Laufzeit: $(( $(date +%s) - START_TS ))s"
ok "Provisioning abgeschlossen"
