#!/bin/bash
set -euo pipefail
set -E

LOG_FILE="/workspace/vast-sd-forge-provisioning.log"
mkdir -p /workspace
exec > >(tee -a "$LOG_FILE") 2>&1

START_TS=$(date +%s)

OK_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
DOWNLOAD_OK=0
DOWNLOAD_FAIL=0
DOWNLOAD_SKIP=0
EXT_OK=0
EXT_FAIL=0
EXT_SKIP=0
CFG_OK=0
CFG_FAIL=0
CFG_SKIP=0

FAILED_DOWNLOADS=()
FAILED_EXTENSIONS=()

VAST_INFO()    { echo -e "\033[1;34m[VAST][INFO]\033[0m  [$(date '+%H:%M:%S')] $*"; }
VAST_OK()      { echo -e "\033[1;32m[VAST][OK]\033[0m    [$(date '+%H:%M:%S')] $*"; }
VAST_WARN()    { echo -e "\033[1;33m[VAST][WARN]\033[0m  [$(date '+%H:%M:%S')] $*" ; }
VAST_ERROR()   { echo -e "\033[1;31m[VAST][ERROR]\033[0m [$(date '+%H:%M:%S')] $*" >&2; }
VAST_STEP()    { echo -e "\033[1;36m[VAST][STEP $1]\033[0m [$(date '+%H:%M:%S')] ${*:2}"; }
VAST_SECTION() {
  echo ""
  echo -e "\033[1;35m[VAST]══════════════════════════════════════════════\033[0m"
  echo -e "\033[1;35m[VAST] $*\033[0m"
  echo -e "\033[1;35m[VAST]══════════════════════════════════════════════\033[0m"
}

STEP_OK()   { echo -e "\033[1;32m[STEP][OK]\033[0m   [$(date '+%H:%M:%S')] $*"; ((OK_COUNT++)); }
STEP_FAIL() { echo -e "\033[1;31m[STEP][FAIL]\033[0m [$(date '+%H:%M:%S')] $*" >&2; ((FAIL_COUNT++)); }
STEP_SKIP() { echo -e "\033[1;33m[STEP][SKIP]\033[0m [$(date '+%H:%M:%S')] $*"; ((SKIP_COUNT++)); }

trap 'VAST_ERROR "Abbruch in Zeile $LINENO: $BASH_COMMAND"' ERR

_curl_dl() {
  curl -fL \
    --retry 3 --retry-delay 2 \
    --connect-timeout 15 \
    --speed-limit 102400 --speed-time 30 \
    "$@"
}

download_civitai() {
  local dest="$1" name="$2" id="$3"
  mkdir -p "$dest"
  if [[ -f "$dest/$name" && $(stat -c%s "$dest/$name" 2>/dev/null || echo 0) -gt 1048576 ]]; then
    VAST_INFO "SKIP: $name (bereits vorhanden)"
    ((DOWNLOAD_SKIP++))
    return 0
  fi
  VAST_INFO "Civitai: $name (id=$id)"
  if _curl_dl \
      -H "User-Agent: Mozilla/5.0" \
      "https://civitai.com/api/download/models/$id?token=${CIVITAI_TOKEN}" \
      -o "$dest/$name"; then
    VAST_OK "$name fertig ($(du -sh "$dest/$name" | cut -f1))"
    return 0
  else
    rm -f "$dest/$name"
    FAILED_DOWNLOADS+=("$name")
    VAST_ERROR "$name Download fehlgeschlagen"
    return 1
  fi
}

download_url() {
  local dest="$1" name="$2" url="$3"
  mkdir -p "$dest"
  if [[ -f "$dest/$name" && $(stat -c%s "$dest/$name" 2>/dev/null || echo 0) -gt 1048576 ]]; then
    VAST_INFO "SKIP: $name (bereits vorhanden)"
    ((DOWNLOAD_SKIP++))
    return 0
  fi
  VAST_INFO "URL: $name"
  if _curl_dl -o "$dest/$name" "$url"; then
    VAST_OK "$name fertig ($(du -sh "$dest/$name" | cut -f1))"
    return 0
  else
    rm -f "$dest/$name"
    FAILED_DOWNLOADS+=("$name")
    VAST_ERROR "$name Download fehlgeschlagen"
    return 1
  fi
}

download_hf_gated() {
  local dest="$1" name="$2" path="$3"
  mkdir -p "$dest"
  if [[ -f "$dest/$name" && $(stat -c%s "$dest/$name" 2>/dev/null || echo 0) -gt 1048576 ]]; then
    VAST_INFO "SKIP: $name (bereits vorhanden)"
    ((DOWNLOAD_SKIP++))
    return 0
  fi
  if [[ -z "${HF_TOKEN:-}" ]]; then
    VAST_WARN "HF_TOKEN fehlt – überspringe: $name"
    ((DOWNLOAD_SKIP++))
    return 1
  fi
  VAST_INFO "HF Gated: $name"
  if _curl_dl \
      -H "Authorization: Bearer ${HF_TOKEN}" \
      "https://huggingface.co/${path}" \
      -o "$dest/$name"; then
    VAST_OK "$name fertig ($(du -sh "$dest/$name" | cut -f1))"
    return 0
  else
    rm -f "$dest/$name"
    FAILED_DOWNLOADS+=("$name")
    VAST_ERROR "$name Download fehlgeschlagen"
    return 1
  fi
}

download_optional() {
  local dest="$1" name="$2" url="$3"
  mkdir -p "$dest"
  if [[ -f "$dest/$name" ]]; then
    VAST_INFO "SKIP: $name"
    ((CFG_SKIP++))
    return 0
  fi
  VAST_INFO "Optional: $name"
  local http_code
  http_code=$(curl -fsSL --retry 2 --connect-timeout 10 -o "$dest/$name" -w "%{http_code}" "$url" 2>/dev/null || echo "000")
  if [[ "$http_code" == "200" ]]; then
    VAST_OK "$name geladen"
    return 0
  else
    rm -f "$dest/$name"
    VAST_WARN "Nicht gefunden (HTTP $http_code) – übersprungen: $name"
    return 1
  fi
}

VAST_SECTION "START PROVISIONING"
VAST_INFO "Datum: $(date -Is)"
VAST_INFO "Log: $LOG_FILE"

: "${GITHUB_PAT:?GITHUB_PAT ist nicht gesetzt}"
: "${CIVITAI_TOKEN:?CIVITAI_TOKEN ist nicht gesetzt}"
: "${WORKSPACE:=/workspace}"

FORGE_MODELS="$WORKSPACE/stable-diffusion-webui-forge/models"
FORGE_EXTENSIONS="$WORKSPACE/stable-diffusion-webui-forge/extensions"
SENTINEL="$WORKSPACE/.provisioning_done"

VAST_INFO "WORKSPACE=$WORKSPACE"
VAST_INFO "FORGE_MODELS=$FORGE_MODELS"
VAST_INFO "FORGE_EXTENSIONS=$FORGE_EXTENSIONS"

VAST_SECTION "IDEMPOTENZ-CHECK"
if [[ -f "$SENTINEL" ]]; then
  VAST_INFO "Bereits provisioned – überspringe"
  exit 0
fi
VAST_OK "Kein Sentinel – starte vollständiges Provisioning"

VAST_STEP 1 "Erstelle Verzeichnisse"
mkdir -p \
  "$FORGE_MODELS/Stable-diffusion" \
  "$FORGE_MODELS/Lora" \
  "$FORGE_MODELS/VAE" \
  "$FORGE_MODELS/ControlNet" \
  "$FORGE_MODELS/ESRGAN" \
  "$FORGE_MODELS/embeddings" \
  "$FORGE_MODELS/torch_deepdanbooru" \
  "$WORKSPACE/outputs"
STEP_OK "Verzeichnisse bereit"

VAST_STEP 2 "Lade model-list.sh"
MODEL_LIST_URL="https://raw.githubusercontent.com/hondo100/vast-sd-provision/refs/heads/main/model-list.sh"
TMP_MODEL_LIST="$(mktemp)"
if curl -fsSL -H "Authorization: token ${GITHUB_PAT}" "$MODEL_LIST_URL" -o "$TMP_MODEL_LIST"; then
  STEP_OK "model-list.sh geladen"
else
  STEP_FAIL "model-list.sh konnte nicht geladen werden"
  exit 1
fi

VAST_STEP 3 "Source model-list.sh"
source "$TMP_MODEL_LIST"
rm -f "$TMP_MODEL_LIST"
VAST_OK "model-list.sh geladen: ${#DOWNLOADS[@]} Downloads, ${#EXTENSIONS[@]} Extensions"

VAST_SECTION "MODELL-DOWNLOADS (${#DOWNLOADS[@]} Einträge)"
COUNT=0
for entry in "${DOWNLOADS[@]}"; do
  IFS='|' read -r dest name src <<< "$entry"
  COUNT=$((COUNT + 1))
  VAST_INFO "[$COUNT/${#DOWNLOADS[@]}] Starte $name"
  case "$src" in
    HF_GATED:*)
      if download_hf_gated "$dest" "$name" "${src#HF_GATED:}"; then
        STEP_OK "$name"
        ((DOWNLOAD_OK++))
      else
        STEP_FAIL "$name"
        ((DOWNLOAD_FAIL++))
      fi
      ;;
    http://*|https://*)
      if download_url "$dest" "$name" "$src"; then
        STEP_OK "$name"
        ((DOWNLOAD_OK++))
      else
        STEP_FAIL "$name"
        ((DOWNLOAD_FAIL++))
      fi
      ;;
    [0-9]*)
      if download_civitai "$dest" "$name" "$src"; then
        STEP_OK "$name"
        ((DOWNLOAD_OK++))
      else
        STEP_FAIL "$name"
        ((DOWNLOAD_FAIL++))
      fi
      ;;
    *)
      STEP_SKIP "Unbekanntes Format: $name ($src)"
      ((DOWNLOAD_SKIP++))
      ;;
  esac
done
VAST_OK "Alle Downloads abgeschlossen"

VAST_SECTION "EXTENSIONS (${#EXTENSIONS[@]} Einträge)"
if declare -p EXTENSIONS >/dev/null 2>&1 && [[ ${#EXTENSIONS[@]} -gt 0 ]]; then
  mkdir -p "$FORGE_EXTENSIONS"
  cd "$FORGE_EXTENSIONS"
  EXT_COUNT=0
  for repo in "${EXTENSIONS[@]}"; do
    EXT_COUNT=$((EXT_COUNT + 1))
    dir="$(basename "$repo" .git)"
    VAST_INFO "[$EXT_COUNT/${#EXTENSIONS[@]}] Clone: $dir"
    if [[ -d "$dir" ]]; then
      STEP_SKIP "$dir schon vorhanden"
      ((EXT_SKIP++))
    else
      if git clone --depth=1 "$repo" "$dir"; then
        STEP_OK "$dir geklont"
        ((EXT_OK++))
      else
        STEP_FAIL "$dir konnte nicht geklont werden"
        ((EXT_FAIL++))
        FAILED_EXTENSIONS+=("$dir")
      fi
    fi
  done
  VAST_OK "Extensions abgeschlossen"
else
  STEP_SKIP "Keine Extensions definiert"
  ((EXT_SKIP++))
fi

VAST_SECTION "OPTIONALE CONFIGS"
if declare -p OPTIONAL_CONFIGS >/dev/null 2>&1 && [[ ${#OPTIONAL_CONFIGS[@]} -gt 0 ]]; then
  CFG_COUNT=0
  for entry in "${OPTIONAL_CONFIGS[@]}"; do
    CFG_COUNT=$((CFG_COUNT + 1))
    IFS='|' read -r dest name url <<< "$entry"
    VAST_INFO "[$CFG_COUNT/${#OPTIONAL_CONFIGS[@]}] Optional: $name"
    if download_optional "$dest" "$name" "$url"; then
      STEP_OK "$name geladen oder vorhanden"
      ((CFG_OK++))
    else
      STEP_SKIP "$name nicht vorhanden"
      ((CFG_SKIP++))
    fi
  done
  VAST_OK "Config-Block abgeschlossen"
else
  STEP_SKIP "Keine optionalen Configs definiert"
  ((CFG_SKIP++))
fi

echo "$(date -Is)" > "$SENTINEL"

END_TS=$(date +%s)
DURATION=$((END_TS - START_TS))

VAST_SECTION "STATISTIK"
VAST_INFO "Gesamt OK:   $OK_COUNT"
VAST_INFO "Gesamt FAIL: $FAIL_COUNT"
VAST_INFO "Gesamt SKIP: $SKIP_COUNT"
VAST_INFO "Downloads OK/FAIL/SKIP:  $DOWNLOAD_OK/$DOWNLOAD_FAIL/$DOWNLOAD_SKIP"
VAST_INFO "Extensions OK/FAIL/SKIP: $EXT_OK/$EXT_FAIL/$EXT_SKIP"
VAST_INFO "Configs OK/FAIL/SKIP:     $CFG_OK/$CFG_FAIL/$CFG_SKIP"
VAST_INFO "Laufzeit: ${DURATION}s"

VAST_SECTION "FEHLERLISTE"
if [[ ${#FAILED_DOWNLOADS[@]} -gt 0 ]]; then
  VAST_WARN "Fehlgeschlagene Downloads: ${FAILED_DOWNLOADS[*]}"
else
  VAST_INFO "Keine fehlgeschlagenen Downloads"
fi
if [[ ${#FAILED_EXTENSIONS[@]} -gt 0 ]]; then
  VAST_WARN "Fehlgeschlagene Extensions: ${FAILED_EXTENSIONS[*]}"
else
  VAST_INFO "Keine fehlgeschlagenen Extensions"
fi

VAST_SECTION "PROVISIONING ABGESCHLOSSEN"
VAST_OK "Sentinel: $SENTINEL"
VAST_INFO "Modelle: $(du -sh "$FORGE_MODELS" 2>/dev/null | cut -f1) gesamt"
VAST_INFO "Forge startet jetzt automatisch durch Supervisor"
