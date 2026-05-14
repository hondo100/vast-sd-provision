#!/bin/bash
set -euo pipefail

# ==============================================================================
# VAST.AI PROVISIONING SCRIPT – SD-Forge Template
# - Läuft in Phase 9, VOR dem Forge-Start
# - Kein Forge-Clone (Template managed das)
# - Kein aria2c, kein WORKSPACE-Detection
# - WORKSPACE ist immer /workspace (gesetzt vom Template)
# ==============================================================================

LOG_FILE="/workspace/vast-sd-forge-provisioning.log"
mkdir -p /workspace
exec > >(tee -a "$LOG_FILE") 2>&1

# ── Log-Funktionen ─────────────────────────────────────────────────────────
VAST_INFO()    { echo -e "\033[1;34m[VAST][INFO]\033[0m  [$(date '+%H:%M:%S')] $*"; }
VAST_OK()      { echo -e "\033[1;32m[VAST][OK]\033[0m    [$(date '+%H:%M:%S')] $*"; }
VAST_WARN()    { echo -e "\033[1;33m[VAST][WARN]\033[0m  [$(date '+%H:%M:%S')] $*"; }
VAST_ERROR()   { echo -e "\033[1;31m[VAST][ERROR]\033[0m [$(date '+%H:%M:%S')] $*"; }
VAST_STEP()    { echo -e "\033[1;36m[VAST][STEP $1]\033[0m [$(date '+%H:%M:%S')] ${*:2}"; }
VAST_SECTION() {
  echo ""
  echo -e "\033[1;35m[VAST]══════════════════════════════════════════════\033[0m"
  echo -e "\033[1;35m[VAST] $*\033[0m"
  echo -e "\033[1;35m[VAST]══════════════════════════════════════════════\033[0m"
}

VAST_SECTION "START PROVISIONING"
VAST_INFO "Datum: $(date -Is)"
VAST_INFO "Log: $LOG_FILE"

: "${GITHUB_PAT:?GITHUB_PAT ist nicht gesetzt}"
: "${CIVITAI_TOKEN:?CIVITAI_TOKEN ist nicht gesetzt}"
: "${WORKSPACE:=/workspace}"

FORGE_MODELS="$WORKSPACE/stable-diffusion-webui-forge/models"
SENTINEL="$WORKSPACE/.provisioning_done"

VAST_INFO "WORKSPACE=$WORKSPACE"
VAST_INFO "FORGE_MODELS=$FORGE_MODELS"

VAST_SECTION "IDEMPOTENZ-CHECK"
if [[ -f "$SENTINEL" ]]; then
  VAST_INFO "Bereits provisioned – überspringe"
  exit 0
fi
VAST_OK "Kein Sentinel – starte vollständiges Provisioning"

VAST_STEP 1 "Erstelle Model-Verzeichnisse"
mkdir -p \
  "$FORGE_MODELS/Stable-diffusion" \
  "$FORGE_MODELS/Lora" \
  "$FORGE_MODELS/VAE" \
  "$FORGE_MODELS/ControlNet" \
  "$FORGE_MODELS/ESRGAN" \
  "$FORGE_MODELS/embeddings" \
  "$FORGE_MODELS/torch_deepdanbooru" \
  "$WORKSPACE/outputs"
VAST_OK "Verzeichnisse bereit"

VAST_STEP 2 "Lade model-list.sh von GitHub"
MODEL_LIST_URL="https://raw.githubusercontent.com/hondo100/vast-sd-provision/refs/heads/main/model-list.sh"
TMP_MODEL_LIST="$(mktemp)"
curl -fsSL \
  -H "Authorization: token ${GITHUB_PAT}" \
  "$MODEL_LIST_URL" \
  -o "$TMP_MODEL_LIST"

VAST_STEP 3 "Source model-list.sh"
source "$TMP_MODEL_LIST"
rm -f "$TMP_MODEL_LIST"
VAST_OK "model-list.sh geladen: ${#DOWNLOADS[@]} Downloads, ${#EXTENSIONS[@]} Extensions"

download_civitai() {
  local dest="$1" name="$2" id="$3"
  mkdir -p "$dest"
  if [[ -f "$dest/$name" && $(stat -c%s "$dest/$name" 2>/dev/null || echo 0) -gt 1048576 ]]; then
    VAST_INFO "SKIP (bereits vorhanden): $name"
    return 0
  fi
  VAST_INFO "Civitai: $name (id=$id)"
  curl -fL --retry 3 \
    -H "User-Agent: Mozilla/5.0" \
    "https://civitai.com/api/download/models/$id?token=${CIVITAI_TOKEN}" \
    -o "$dest/$name"
  VAST_OK "$name fertig ($(du -sh "$dest/$name" | cut -f1))"
}

download_url() {
  local dest="$1" name="$2" url="$3"
  mkdir -p "$dest"
  if [[ -f "$dest/$name" && $(stat -c%s "$dest/$name" 2>/dev/null || echo 0) -gt 1048576 ]]; then
    VAST_INFO "SKIP (bereits vorhanden): $name"
    return 0
  fi
  VAST_INFO "URL: $name"
  curl -fL --retry 3 -o "$dest/$name" "$url"
  VAST_OK "$name fertig ($(du -sh "$dest/$name" | cut -f1))"
}

download_hf_gated() {
  local dest="$1" name="$2" path="$3"
  mkdir -p "$dest"
  if [[ -f "$dest/$name" && $(stat -c%s "$dest/$name" 2>/dev/null || echo 0) -gt 1048576 ]]; then
    VAST_INFO "SKIP (bereits vorhanden): $name"
    return 0
  fi
  if [[ -z "${HF_TOKEN:-}" ]]; then
    VAST_WARN "HF_TOKEN fehlt – überspringe: $name"
    return 1
  fi
  VAST_INFO "HF Gated: $name"
  curl -fL --retry 3 \
    -H "Authorization: Bearer ${HF_TOKEN}" \
    "https://huggingface.co/${path}" \
    -o "$dest/$name"
  VAST_OK "$name fertig ($(du -sh "$dest/$name" | cut -f1))"
}

VAST_SECTION "MODELL-DOWNLOADS (${#DOWNLOADS[@]} Einträge)"
COUNT=0
for entry in "${DOWNLOADS[@]}"; do
  IFS='|' read -r dest name src <<< "$entry"
  COUNT=$((COUNT + 1))
  VAST_INFO "[$COUNT/${#DOWNLOADS[@]}] $name"
  case "$src" in
    HF_GATED:*)
      download_hf_gated "$dest" "$name" "${src#HF_GATED:}" || VAST_WARN "Fehlgeschlagen: $name"
      ;;
    http://*|https://*)
      download_url "$dest" "$name" "$src" || VAST_WARN "Fehlgeschlagen: $name"
      ;;
    [0-9]*)
      download_civitai "$dest" "$name" "$src" || VAST_WARN "Fehlgeschlagen: $name"
      ;;
    *)
      VAST_WARN "Unbekanntes Format: $name ($src)"
      ;;
  esac
done
VAST_OK "Alle Downloads abgeschlossen"

if declare -p EXTENSIONS >/dev/null 2>&1 && [[ ${#EXTENSIONS[@]} -gt 0 ]]; then
  VAST_SECTION "EXTENSIONS (${#EXTENSIONS[@]} Einträge)"
  EXT_DIR="$WORKSPACE/stable-diffusion-webui-forge/extensions"
  mkdir -p "$EXT_DIR"
  cd "$EXT_DIR"
  for repo in "${EXTENSIONS[@]}"; do
    dir="$(basename "$repo" .git)"
    if [[ -d "$dir" ]]; then
      VAST_INFO "SKIP (bereits vorhanden): $dir"
    else
      VAST_INFO "Clone: $repo"
      git clone "$repo" && VAST_OK "Geklont: $dir" || VAST_WARN "Clone fehlgeschlagen: $repo"
    fi
  done
fi

VAST_SECTION "PROVISIONING ABGESCHLOSSEN"
echo "$(date -Is)" > "$SENTINEL"
VAST_OK "Sentinel: $SENTINEL"
VAST_INFO "Modelle: $(du -sh "$FORGE_MODELS" 2>/dev/null | cut -f1) gesamt"
VAST_INFO "Forge startet jetzt automatisch durch Supervisor"
