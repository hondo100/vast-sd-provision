#!/bin/bash
set -euo pipefail

# ==============================================================================
# VAST.AI PROVISIONING SCRIPT v3 – SD-Forge Template
# Neu in v3: Statistik-Auswertung am Ende
# ==============================================================================

LOG_FILE="/workspace/vast-sd-forge-provisioning.log"
mkdir -p /workspace
exec > >(tee -a "$LOG_FILE") 2>&1

VAST_INFO()    { echo -e "\033[1;34m[VAST][INFO]\033[0m  [$(date '+%H:%M:%S')] $*"; }
VAST_OK()      { echo -e "\033[1;32m[VAST][OK]\033[0m    [$(date '+%H:%M:%S')] $*"; }
VAST_WARN()    { echo -e "\033[1;33m[VAST][WARN]\033[0m  [$(date '+%H:%M:%S')] $*"; }
VAST_ERROR()   { echo -e "\033[1;31m[VAST][ERROR]\033[0m [$(date '+%H:%M:%S')] $*" >&2; }
VAST_STEP()    { echo -e "\033[1;36m[VAST][STEP $1]\033[0m [$(date '+%H:%M:%S')] ${*:2}"; }
VAST_SECTION() {
  echo ""
  echo -e "\033[1;35m[VAST]══════════════════════════════════════════════\033[0m"
  echo -e "\033[1;35m[VAST] $*\033[0m"
  echo -e "\033[1;35m[VAST]══════════════════════════════════════════════\033[0m"
}

# ── Statistik-Tracking ─────────────────────────────────────────────────────
STATS_FILE="$(mktemp)"
SCRIPT_START=$(date +%s)
DL_SUCCESS=0
DL_FAILED=0
DL_SKIPPED=0
EXT_SUCCESS=0
EXT_FAILED=0
EXT_SKIPPED=0
CONFIG_SUCCESS=0
CONFIG_SKIPPED=0
CONFIG_FAILED=0

stats_record() {
  # Format: TYPE|NAME|STATUS|BYTES|DURATION_S
  echo "$1|$2|$3|$4|$5" >> "$STATS_FILE"
}

VAST_SECTION "START PROVISIONING v3"
VAST_INFO "Datum: $(date -Is)"
VAST_INFO "Log: $LOG_FILE"

: "${GITHUB_PAT:?GITHUB_PAT ist nicht gesetzt}"
: "${CIVITAI_TOKEN:?CIVITAI_TOKEN ist nicht gesetzt}"
: "${WORKSPACE:=/workspace}"

FORGE_MODELS="$WORKSPACE/stable-diffusion-webui-forge/models"
SENTINEL="$WORKSPACE/.provisioning_done"

VAST_INFO "WORKSPACE=$WORKSPACE"
VAST_INFO "FORGE_MODELS=$FORGE_MODELS"

# ── Idempotenz ─────────────────────────────────────────────────────────────
VAST_SECTION "IDEMPOTENZ-CHECK"
if [[ -f "$SENTINEL" ]]; then
  VAST_INFO "Bereits provisioned – überspringe"
  exit 0
fi
VAST_OK "Kein Sentinel – starte vollständiges Provisioning"

# ── Verzeichnisse ──────────────────────────────────────────────────────────
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

# ── model-list.sh laden ────────────────────────────────────────────────────
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

# ── Download-Funktionen ────────────────────────────────────────────────────
_curl_dl() {
  curl -fL \
    --retry 3 --retry-delay 2 \
    --connect-timeout 15 \
    --speed-limit 102400 --speed-time 30 \
    "$@"
}

download_civitai() {
  local dest="$1" name="$2" id="$3"
  local t_start t_end size_bytes
  mkdir -p "$dest"
  if [[ -f "$dest/$name" && $(stat -c%s "$dest/$name" 2>/dev/null || echo 0) -gt 1048576 ]]; then
    VAST_INFO "SKIP: $name"
    stats_record "MODEL" "$name" "SKIP" "$(stat -c%s "$dest/$name" 2>/dev/null || echo 0)" "0"
    return 0
  fi
  VAST_INFO "Civitai: $name (id=$id)"
  t_start=$(date +%s)
  _curl_dl \
    -H "User-Agent: Mozilla/5.0" \
    "https://civitai.com/api/download/models/$id?token=${CIVITAI_TOKEN}" \
    -o "$dest/$name"
  t_end=$(date +%s)
  size_bytes=$(stat -c%s "$dest/$name" 2>/dev/null || echo 0)
  stats_record "MODEL" "$name" "OK" "$size_bytes" "$((t_end - t_start))"
  VAST_OK "$name fertig ($(du -sh "$dest/$name" | cut -f1), $((t_end - t_start))s)"
}

download_url() {
  local dest="$1" name="$2" url="$3"
  local t_start t_end size_bytes
  mkdir -p "$dest"
  if [[ -f "$dest/$name" && $(stat -c%s "$dest/$name" 2>/dev/null || echo 0) -gt 1048576 ]]; then
    VAST_INFO "SKIP: $name"
    stats_record "MODEL" "$name" "SKIP" "$(stat -c%s "$dest/$name" 2>/dev/null || echo 0)" "0"
    return 0
  fi
  VAST_INFO "URL: $name"
  t_start=$(date +%s)
  _curl_dl -o "$dest/$name" "$url"
  t_end=$(date +%s)
  size_bytes=$(stat -c%s "$dest/$name" 2>/dev/null || echo 0)
  stats_record "MODEL" "$name" "OK" "$size_bytes" "$((t_end - t_start))"
  VAST_OK "$name fertig ($(du -sh "$dest/$name" | cut -f1), $((t_end - t_start))s)"
}

download_hf_gated() {
  local dest="$1" name="$2" path="$3"
  local t_start t_end size_bytes
  mkdir -p "$dest"
  if [[ -f "$dest/$name" && $(stat -c%s "$dest/$name" 2>/dev/null || echo 0) -gt 1048576 ]]; then
    VAST_INFO "SKIP: $name"
    stats_record "MODEL" "$name" "SKIP" "$(stat -c%s "$dest/$name" 2>/dev/null || echo 0)" "0"
    return 0
  fi
  if [[ -z "${HF_TOKEN:-}" ]]; then
    VAST_WARN "HF_TOKEN fehlt – überspringe: $name"
    stats_record "MODEL" "$name" "FAIL" "0" "0"
    return 1
  fi
  VAST_INFO "HF Gated: $name"
  t_start=$(date +%s)
  _curl_dl \
    -H "Authorization: Bearer ${HF_TOKEN}" \
    "https://huggingface.co/${path}" \
    -o "$dest/$name"
  t_end=$(date +%s)
  size_bytes=$(stat -c%s "$dest/$name" 2>/dev/null || echo 0)
  stats_record "MODEL" "$name" "OK" "$size_bytes" "$((t_end - t_start))"
  VAST_OK "$name fertig ($(du -sh "$dest/$name" | cut -f1), $((t_end - t_start))s)"
}

download_optional() {
  local dest="$1" name="$2" url="$3"
  mkdir -p "$dest"
  if [[ -f "$dest/$name" ]]; then
    VAST_INFO "SKIP: $name"
    stats_record "CONFIG" "$name" "SKIP" "0" "0"
    return 0
  fi
  VAST_INFO "Optional: $name"
  local http_code
  http_code=$(curl -fsSL --retry 2 --connect-timeout 10 \
    -o "$dest/$name" -w "%{http_code}" "$url" 2>/dev/null || echo "000")
  if [[ "$http_code" == "200" ]]; then
    stats_record "CONFIG" "$name" "OK" "$(stat -c%s "$dest/$name" 2>/dev/null || echo 0)" "0"
    VAST_OK "$name geladen"
  else
    rm -f "$dest/$name"
    stats_record "CONFIG" "$name" "FAIL" "0" "0"
    VAST_WARN "Nicht gefunden (HTTP $http_code) – übersprungen: $name"
  fi
}

_run_download() {
  local dest="$1" name="$2" src="$3"
  case "$src" in
    HF_GATED:*)         download_hf_gated "$dest" "$name" "${src#HF_GATED:}" || { stats_record "MODEL" "$name" "FAIL" "0" "0"; VAST_WARN "Fehlgeschlagen: $name"; } ;;
    http://*|https://*) download_url      "$dest" "$name" "$src"             || { stats_record "MODEL" "$name" "FAIL" "0" "0"; VAST_WARN "Fehlgeschlagen: $name"; } ;;
    [0-9]*)             download_civitai  "$dest" "$name" "$src"             || { stats_record "MODEL" "$name" "FAIL" "0" "0"; VAST_WARN "Fehlgeschlagen: $name"; } ;;
    *)                  stats_record "MODEL" "$name" "FAIL" "0" "0"; VAST_WARN "Unbekanntes Format: $name ($src)" ;;
  esac
}

# ── Parallele Downloads ────────────────────────────────────────────────────
DL_PHASE_START=$(date +%s)
VAST_SECTION "MODELL-DOWNLOADS PARALLEL (${#DOWNLOADS[@]} Einträge)"
PIDS=()
COUNT=0
for entry in "${DOWNLOADS[@]}"; do
  IFS='|' read -r dest name src <<< "$entry"
  COUNT=$((COUNT + 1))
  VAST_INFO "Starte [$COUNT/${#DOWNLOADS[@]}]: $name"
  ( _run_download "$dest" "$name" "$src" ) &
  PIDS+=($!)
done

VAST_INFO "Warte auf ${#PIDS[@]} parallele Downloads..."
DL_FAIL_COUNT=0
for pid in "${PIDS[@]}"; do
  wait "$pid" || { DL_FAIL_COUNT=$((DL_FAIL_COUNT + 1)); }
done
DL_PHASE_END=$(date +%s)
DL_PHASE_DURATION=$((DL_PHASE_END - DL_PHASE_START))

if [[ $DL_FAIL_COUNT -gt 0 ]]; then
  VAST_WARN "$DL_FAIL_COUNT Download(s) fehlgeschlagen"
else
  VAST_OK "Alle Downloads abgeschlossen in ${DL_PHASE_DURATION}s"
fi

# ── Extensions parallel ────────────────────────────────────────────────────
EXT_PHASE_START=$(date +%s)
if declare -p EXTENSIONS >/dev/null 2>&1 && [[ ${#EXTENSIONS[@]} -gt 0 ]]; then
  VAST_SECTION "EXTENSIONS PARALLEL (${#EXTENSIONS[@]} Einträge)"
  EXT_DIR="$WORKSPACE/stable-diffusion-webui-forge/extensions"
  mkdir -p "$EXT_DIR"
  EXT_PIDS=()
  for repo in "${EXTENSIONS[@]}"; do
    dir="$(basename "$repo" .git)"
    if [[ -d "$EXT_DIR/$dir" ]]; then
      VAST_INFO "SKIP: $dir"
      stats_record "EXT" "$dir" "SKIP" "0" "0"
    else
      VAST_INFO "Clone (depth=1): $dir"
      t_ext_start=$(date +%s)
      ( git clone --depth=1 "$repo" "$EXT_DIR/$dir" \
          && t_ext_end=$(date +%s) \
          && stats_record "EXT" "$dir" "OK" "0" "$((t_ext_end - t_ext_start))" \
          && VAST_OK "Geklont: $dir" \
          || { stats_record "EXT" "$dir" "FAIL" "0" "0"; VAST_WARN "Clone fehlgeschlagen: $repo"; } ) &
      EXT_PIDS+=($!)
    fi
  done
  for pid in "${EXT_PIDS[@]}"; do wait "$pid" || true; done
fi
EXT_PHASE_END=$(date +%s)
EXT_PHASE_DURATION=$((EXT_PHASE_END - EXT_PHASE_START))
VAST_OK "Extensions abgeschlossen in ${EXT_PHASE_DURATION}s"

# ── Optionale Configs ──────────────────────────────────────────────────────
if declare -p OPTIONAL_CONFIGS >/dev/null 2>&1 && [[ ${#OPTIONAL_CONFIGS[@]} -gt 0 ]]; then
  VAST_SECTION "OPTIONALE CONFIGS (${#OPTIONAL_CONFIGS[@]} Einträge)"
  for entry in "${OPTIONAL_CONFIGS[@]}"; do
    IFS='|' read -r dest name url <<< "$entry"
    download_optional "$dest" "$name" "$url" || true
  done
  VAST_OK "Config-Block abgeschlossen"
fi

# ── Sentinel ───────────────────────────────────────────────────────────────
echo "$(date -Is)" > "$SENTINEL"

# ══════════════════════════════════════════════════════════════════════════════
# STATISTIK-AUSWERTUNG
# ══════════════════════════════════════════════════════════════════════════════
SCRIPT_END=$(date +%s)
TOTAL_DURATION=$((SCRIPT_END - SCRIPT_START))

VAST_SECTION "PROVISIONING STATISTIK"

# Zähler und Bytes aus Stats-File
TOTAL_BYTES=0
MODEL_OK=0; MODEL_FAIL=0; MODEL_SKIP=0
EXT_OK=0;   EXT_FAIL=0;   EXT_SKIP_C=0
CFG_OK=0;   CFG_FAIL=0;   CFG_SKIP_C=0
SLOWEST_NAME=""; SLOWEST_S=0
FASTEST_NAME=""; FASTEST_S=999999

while IFS='|' read -r type name status bytes duration; do
  case "$type" in
    MODEL)
      [[ "$status" == "OK"   ]] && { MODEL_OK=$((MODEL_OK+1));   TOTAL_BYTES=$((TOTAL_BYTES+bytes)); }
      [[ "$status" == "FAIL" ]] && MODEL_FAIL=$((MODEL_FAIL+1))
      [[ "$status" == "SKIP" ]] && { MODEL_SKIP=$((MODEL_SKIP+1)); TOTAL_BYTES=$((TOTAL_BYTES+bytes)); }
      if [[ "$status" == "OK" && "$duration" -gt 0 ]]; then
        [[ "$duration" -gt "$SLOWEST_S" ]] && { SLOWEST_S=$duration; SLOWEST_NAME="$name"; }
        [[ "$duration" -lt "$FASTEST_S" ]] && { FASTEST_S=$duration; FASTEST_NAME="$name"; }
      fi
      ;;
    EXT)
      [[ "$status" == "OK"   ]] && EXT_OK=$((EXT_OK+1))
      [[ "$status" == "FAIL" ]] && EXT_FAIL=$((EXT_FAIL+1))
      [[ "$status" == "SKIP" ]] && EXT_SKIP_C=$((EXT_SKIP_C+1))
      ;;
    CONFIG)
      [[ "$status" == "OK"   ]] && CFG_OK=$((CFG_OK+1))
      [[ "$status" == "FAIL" ]] && CFG_FAIL=$((CFG_FAIL+1))
      [[ "$status" == "SKIP" ]] && CFG_SKIP_C=$((CFG_SKIP_C+1))
      ;;
  esac
done < "$STATS_FILE"
rm -f "$STATS_FILE"

# Bytes → GB/MB
TOTAL_GB=$(echo "scale=2; $TOTAL_BYTES / 1073741824" | bc 2>/dev/null || echo "?")
AVG_SPEED_MBS="?"
if [[ $DL_PHASE_DURATION -gt 0 && $TOTAL_BYTES -gt 0 ]]; then
  AVG_SPEED_MBS=$(echo "scale=1; $TOTAL_BYTES / 1048576 / $DL_PHASE_DURATION" | bc 2>/dev/null || echo "?")
fi

# Gesamtzeit formatieren
fmt_duration() {
  local s=$1
  local m=$((s/60)) r=$((s%60))
  [[ $m -gt 0 ]] && echo "${m}m ${r}s" || echo "${r}s"
}

echo ""
echo -e "\033[1;36m  ┌─────────────────────────────────────────────┐\033[0m"
echo -e "\033[1;36m  │          PROVISIONING ABGESCHLOSSEN          │\033[0m"
echo -e "\033[1;36m  ├─────────────────────────────────────────────┤\033[0m"
echo -e "\033[1;36m  │ Gesamtlaufzeit        \033[1;33m$(fmt_duration $TOTAL_DURATION)\033[1;36m$(printf '%*s' $((21 - ${#$(fmt_duration $TOTAL_DURATION)})) '')│\033[0m"
echo -e "\033[1;36m  │ Davon Download-Phase  \033[1;33m$(fmt_duration $DL_PHASE_DURATION)\033[1;36m$(printf '%*s' $((21 - ${#$(fmt_duration $DL_PHASE_DURATION)})) '')│\033[0m"
echo -e "\033[1;36m  │ Davon Extension-Phase \033[1;33m$(fmt_duration $EXT_PHASE_DURATION)\033[1;36m$(printf '%*s' $((21 - ${#$(fmt_duration $EXT_PHASE_DURATION)})) '')│\033[0m"
echo -e "\033[1;36m  ├─────────────────────────────────────────────┤\033[0m"
echo -e "\033[1;36m  │ Modelle heruntergeladen \033[1;32m${MODEL_OK}\033[1;36m / Fehler \033[1;31m${MODEL_FAIL}\033[1;36m / Skipped \033[0;37m${MODEL_SKIP}\033[1;36m  │\033[0m"
echo -e "\033[1;36m  │ Extensions installiert  \033[1;32m${EXT_OK}\033[1;36m / Fehler \033[1;31m${EXT_FAIL}\033[1;36m / Skipped \033[0;37m${EXT_SKIP_C}\033[1;36m  │\033[0m"
echo -e "\033[1;36m  │ Configs geladen         \033[1;32m${CFG_OK}\033[1;36m / Fehler \033[1;31m${CFG_FAIL}\033[1;36m / Skipped \033[0;37m${CFG_SKIP_C}\033[1;36m  │\033[0m"
echo -e "\033[1;36m  ├─────────────────────────────────────────────┤\033[0m"
echo -e "\033[1;36m  │ Gesamtvolumen         \033[1;33m${TOTAL_GB} GB\033[1;36m$(printf '%*s' $((18 - ${#TOTAL_GB})) '')│\033[0m"
echo -e "\033[1;36m  │ Ø Download-Speed      \033[1;33m${AVG_SPEED_MBS} MB/s\033[1;36m$(printf '%*s' $((16 - ${#AVG_SPEED_MBS})) '')│\033[0m"
echo -e "\033[1;36m  ├─────────────────────────────────────────────┤\033[0m"
[[ -n "$SLOWEST_NAME" ]] && echo -e "\033[1;36m  │ Langsamster DL  \033[0;37m${SLOWEST_NAME:0:20}\033[1;36m (${SLOWEST_S}s)$(printf '%*s' $((5 - ${#SLOWEST_S})) '')│\033[0m"
[[ -n "$FASTEST_NAME" ]] && echo -e "\033[1;36m  │ Schnellster DL  \033[0;37m${FASTEST_NAME:0:20}\033[1;36m (${FASTEST_S}s)$(printf '%*s' $((5 - ${#FASTEST_S})) '')│\033[0m"
echo -e "\033[1;36m  ├─────────────────────────────────────────────┤\033[0m"
echo -e "\033[1;36m  │ Disk Modelle  \033[1;33m$(du -sh "$FORGE_MODELS" 2>/dev/null | cut -f1)\033[1;36m$(printf '%*s' $((30 - ${#$(du -sh "$FORGE_MODELS" 2>/dev/null | cut -f1)})) '')│\033[0m"
echo -e "\033[1;36m  │ Disk /workspace  \033[1;33m$(du -sh "$WORKSPACE" 2>/dev/null | cut -f1)\033[1;36m$(printf '%*s' $((27 - ${#$(du -sh "$WORKSPACE" 2>/dev/null | cut -f1)})) '')│\033[0m"
echo -e "\033[1;36m  │ Sentinel      \033[1;32m$(cat "$SENTINEL")\033[1;36m  │\033[0m"
echo -e "\033[1;36m  └─────────────────────────────────────────────┘\033[0m"
echo ""

VAST_INFO "Log vollständig: $LOG_FILE"
VAST_INFO "Forge startet jetzt automatisch durch Supervisor"
