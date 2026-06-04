#!/usr/bin/env bash
# =============================================================================
# provisioning.sh | Hardened Vast/Forge provisioning
# Version: 2026-06-04.09
# =============================================================================
#
# ZWECK
# -----
# Dieses Script provisioniert eine Vast.ai-Instanz fuer Stable Diffusion Forge
# in einer gehaerteten, deterministischen Reihenfolge. Es fuehrt insbesondere:
# - das Laden und Verarbeiten einer model-list.sh aus,
# - das Zusammenfuehren von config.json / ui-config.json,
# - das Schreiben eines Forge-Wrappers,
# - das harte Blockieren von Forge waehrend der Provisionierung,
# - atomare Downloads mit Validierung,
# - Pflicht-Checkpoint-Pruefung,
# - Telemetrie- und Downloadstatistik,
# - und den finalen Forge-Start erst ganz am Ende
# aus. Diese Komponenten und Ablaufphasen sind im Laufzeit-Log klar sichtbar.
#
# HINTERGRUND DES FIXES
# ---------------------
# In der vorherigen Fassung wurde Forge zwar gestoppt, aber nach der
# Supervisor-Umschaltung wieder vorzeitig gespawnt. Dadurch begann parallel
# waehrend der Downloadphase ein automatisches "Installing torch and
# torchvision". In den Logs fuehrte das zu:
# - parallelem Forge-Start waehrend Downloads,
# - "No space left on device" in Pip-/Bootstrap-Pfaden,
# - danach verschmutzten Retries,
# - und schliesslich "PyTorch is not able to access GPU".
#
# Diese Fassung behebt genau dieses Muster, indem sie Forge bis nach Abschluss
# von Config-Merge, Downloadphase und Required-Checkpoint-Pruefung wirklich
# blockiert.
#
# WICHTIGE EIGENSCHAFTEN
# ----------------------
# 1. Forge wird hart deaktiviert, nicht nur gestoppt.
# 2. Supervisor bekommt zunaechst einen Blocker statt des echten Forge-Starts.
# 3. Downloads erfolgen atomar ueber .part-Dateien mit Exit-Code- und
#    Dateigroessen-Pruefung.
# 4. Vor kritischen Phasen greifen Disk-Guards.
# 5. Poison-States wie "No space left on device" oder
#    "PyTorch is not able to access GPU" fuehren zu einem harten Abbruch.
# 6. Forge startet erst, wenn Downloads und Pflicht-Checkpoints vollstaendig
#    validiert wurden.
#
# ERWARTETES FORMAT VON model-list.sh
# -----------------------------------
# Dieses Script erwartet, dass model-list.sh nach "source" mindestens folgende
# Variablen bereitstellt:
#
#   MODELS=(
#     "name|url|relative_dest|min_bytes|required_flag"
#     "Juggernaut-XL_v9_RunDiffusionPhoto_v2.safetensors|https://...|models/Stable-diffusion/Juggernaut-XL_v9_RunDiffusionPhoto_v2.safetensors|1000000000|1"
#     "svd_xt_1_1.safetensors|https://...|models/Stable-diffusion/svd_xt_1_1.safetensors|1000000000|1"
#   )
#
#   FORGE_DEFAULT_CHECKPOINT="Juggernaut-XL_v9_RunDiffusionPhoto_v2.safetensors"
#   FORGE_REQUIRED_CHECKPOINTS="Juggernaut-XL_v9_RunDiffusionPhoto_v2.safetensors|svd_xt_1_1.safetensors"
#
# Feldbedeutung:
# - name: Anzeigename fuer Log und Statistik.
# - url: Download-URL.
# - relative_dest: Zielpfad relativ zu FORGE_ROOT.
# - min_bytes: Mindestgroesse fuer die Datei, damit der Download als gueltig
#   gilt.
# - required_flag: 1 = Pflichtdatei, 0 = optional.
#
# RELEVANTE UMGEBUNGSVARIABLEN
# ----------------------------
# Allgemein:
# - WORKSPACE                      Default: /workspace
# - FORGE_ROOT                     Default: /workspace/stable-diffusion-webui-forge
# - MODEL_LIST_FILE                Default: /workspace/model-list.sh
# - CONFIG_SRC                     Default: /workspace/config.json
# - UI_CONFIG_SRC                  Default: /workspace/ui-config.json
#
# Disk- und Sicherheitsgrenzen:
# - EXPECTED_MIN_DISK_GB           Default: 80
# - DISK_GUARD_DOWNLOAD_GB         Default: 25
# - DISK_GUARD_BEFORE_FORGE_GB     Default: 15
# - DISK_GUARD_ABSOLUTE_KB         Default: 0
# - STOP_ON_POISON_STATE           Default: 1
# - STRICT_CHECKPOINTS             Default: 1
#
# Forge / Supervisor:
# - FORGE_SERVICE_NAME             Default: forge
# - FORGE_CONF                     Default: /etc/supervisor/conf.d/forge.conf
# - FORGE_API_HOST                 Default: 127.0.0.1
# - FORGE_API_PORT                 Default: 17860
# - ENABLE_FORGE_FINAL_START       Default: 1
# - FORCE_DISABLE_FORGE_AUTOSTART  Default: 1
#
# Tokens:
# - HF_TOKEN / HUGGINGFACE_TOKEN
# - CIVITAI_TOKEN
#
# AUSFUEHRUNGSREIHENFOLGE
# -----------------------
# 1. Preconditions und Disk-Guards.
# 2. model-list.sh laden.
# 3. Zielverzeichnisse anlegen.
# 4. Forge hart stoppen.
# 5. Supervisor auf Forge-Blocker umstellen.
# 6. Configs mergen, Cache bereinigen, Konsistenz pruefen.
# 7. Downloads atomar und validiert ausfuehren.
# 8. Pflicht-Checkpoints pruefen.
# 9. Echten Forge-Wrapper wieder aktivieren.
# 10. Forge final starten.
#
# ARTEFAKTE
# ---------
# Das Script schreibt insbesondere:
# - /workspace/model-download-stats.tsv
# - /workspace/provisioning_telemetry.json
# - /workspace/provision_net_time.log
# - /workspace/run-forge.sh
# - /workspace/run-forge-blocked.sh
#
# WICHTIGE HINWEISE
# -----------------
# - Diese Fassung ist bewusst fail-fast.
# - Bei erkanntem Poison-State soll die Instanz neu gebucht werden statt
#   unsaubere Retries auf demselben Zustand zu fahren.
# - Wenn dein altes model-list.sh ein anderes Format hat, muss es auf das oben
#   dokumentierte Format angepasst werden.
#
# =============================================================================

set -Eeuo pipefail

# -----------------------------------------------------------------------------
# Config
# -----------------------------------------------------------------------------
WORKSPACE="${WORKSPACE:-/workspace}"
FORGE_ROOT="${FORGE_ROOT:-$WORKSPACE/stable-diffusion-webui-forge}"
MODEL_LIST_FILE="${MODEL_LIST_FILE:-$WORKSPACE/model-list.sh}"
STATS_FILE="${STATS_FILE:-$WORKSPACE/model-download-stats.tsv}"
TELEMETRY_FILE="${TELEMETRY_FILE:-$WORKSPACE/provisioning_telemetry.json}"
NET_TIME_FILE="${NET_TIME_FILE:-$WORKSPACE/provision_net_time.log}"
RUN_ID="${RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"

FORGE_WRAPPER="${FORGE_WRAPPER:-$WORKSPACE/run-forge.sh}"
FORGE_BLOCKER="${FORGE_BLOCKER:-$WORKSPACE/run-forge-blocked.sh}"
FORGE_CONF="${FORGE_CONF:-/etc/supervisor/conf.d/forge.conf}"
FORGE_SERVICE_NAME="${FORGE_SERVICE_NAME:-forge}"

FORGE_API_HOST="${FORGE_API_HOST:-127.0.0.1}"
FORGE_API_PORT="${FORGE_API_PORT:-17860}"
FORGE_API_URL="http://${FORGE_API_HOST}:${FORGE_API_PORT}"

CONFIG_SRC="${CONFIG_SRC:-$WORKSPACE/config.json}"
UI_CONFIG_SRC="${UI_CONFIG_SRC:-$WORKSPACE/ui-config.json}"
PATCH_MAIN_ENTRY="${PATCH_MAIN_ENTRY:-0}"
FORGE_PRESET="${FORGE_PRESET:-}"

EXPECTED_MIN_DISK_GB="${EXPECTED_MIN_DISK_GB:-80}"
DISK_GUARD_DOWNLOAD_GB="${DISK_GUARD_DOWNLOAD_GB:-25}"
DISK_GUARD_BEFORE_FORGE_GB="${DISK_GUARD_BEFORE_FORGE_GB:-15}"
DISK_GUARD_ABSOLUTE_KB="${DISK_GUARD_ABSOLUTE_KB:-0}"

STOP_ON_POISON_STATE="${STOP_ON_POISON_STATE:-1}"
ENABLE_FORGE_FINAL_START="${ENABLE_FORGE_FINAL_START:-1}"
FORCE_DISABLE_FORGE_AUTOSTART="${FORCE_DISABLE_FORGE_AUTOSTART:-1}"
STRICT_CHECKPOINTS="${STRICT_CHECKPOINTS:-1}"

HF_TOKEN="${HF_TOKEN:-${HUGGINGFACE_TOKEN:-}}"
CIVITAI_TOKEN="${CIVITAI_TOKEN:-}"

POISON_MARKER="${POISON_MARKER:-$WORKSPACE/.provisioning_poisoned}"
FATAL_REASON_FILE="${FATAL_REASON_FILE:-$WORKSPACE/.fatal_reason}"
PROVISION_STATE_FILE="${PROVISION_STATE_FILE:-$WORKSPACE/.provisioning_state}"

START_TS="$(date +%s)"

DOWNLOAD_TOTAL=0
DOWNLOAD_OK=0
DOWNLOAD_SKIP=0
DOWNLOAD_FAIL=0
DOWNLOAD_BYTES=0
DOWNLOAD_SECONDS=0

ts() { date +"%H%M%S"; }
log() { printf 'VASTINFO %s %s\n' "$(ts)" "$*"; }
ok() { printf 'VASTOK    %s %s\n' "$(ts)" "$*"; }
warn() { printf 'VASTWARN  %s %s\n' "$(ts)" "$*" >&2; }
err() { printf 'VASTERR   %s %s\n' "$(ts)" "$*" >&2; }

section() {
  echo "$1"
}

write_state() {
  printf '%s\n' "$1" > "$PROVISION_STATE_FILE"
}

mark_poisoned() {
  local reason="$1"
  printf '%s\n' "$reason" > "$POISON_MARKER"
  printf '%s\n' "$reason" > "$FATAL_REASON_FILE"
  err "$reason"
}

fatal() {
  local code="$1"
  shift
  local reason="$*"
  printf '%s\n' "$reason" > "$FATAL_REASON_FILE"
  err "$reason"
  write_telemetry "failed" "$code" "$reason"
  write_net_time
  print_download_stats
  exit "$code"
}

cleanup_partials() {
  find "$WORKSPACE" -type f -name '*.part' -delete 2>/dev/null || true
}

trap cleanup_partials EXIT

bytes_to_human() {
  python3 - "$1" <<'PY'
import sys
n=float(sys.argv[1])
units=["B","KiB","MiB","GiB","TiB"]
for u in units:
    if n < 1024 or u == units[-1]:
        print(f"{n:.2f} {u}")
        break
    n /= 1024
PY
}

write_net_time() {
  local elapsed
  elapsed=$(( $(date +%s) - START_TS ))
  printf '%s\n' "$elapsed" > "$NET_TIME_FILE"
  log "Netto-Laufzeit-Anker (${elapsed}s) flach exportiert nach: $NET_TIME_FILE"
}

json_escape() {
  python3 - "$1" <<'PY'
import json,sys
print(json.dumps(sys.argv[1]))
PY
}

write_telemetry() {
  local status="$1"
  local exit_code="$2"
  local message="${3:-}"
  local poison="no"
  local poison_reason=""
  local elapsed
  elapsed=$(( $(date +%s) - START_TS ))

  if [[ -f "$POISON_MARKER" ]]; then
    poison="yes"
    poison_reason="$(cat "$POISON_MARKER" 2>/dev/null || true)"
  fi

  cat > "$TELEMETRY_FILE" <<EOF
{
  "run_id": $(json_escape "$RUN_ID"),
  "status": $(json_escape "$status"),
  "exit_code": $exit_code,
  "message": $(json_escape "$message"),
  "forge_root": $(json_escape "$FORGE_ROOT"),
  "forge_api_url": $(json_escape "$FORGE_API_URL"),
  "elapsed_seconds": $elapsed,
  "poisoned": $(json_escape "$poison"),
  "poison_reason": $(json_escape "$poison_reason"),
  "download_total": $DOWNLOAD_TOTAL,
  "download_ok": $DOWNLOAD_OK,
  "download_skip": $DOWNLOAD_SKIP,
  "download_fail": $DOWNLOAD_FAIL,
  "download_bytes": $DOWNLOAD_BYTES,
  "download_human": $(json_escape "$(bytes_to_human "$DOWNLOAD_BYTES")"),
  "download_seconds": $DOWNLOAD_SECONDS
}
EOF

  ok "Erweiterte Telemetrie-Ergebnisdatei geschrieben: $TELEMETRY_FILE"
  log "TELEMETRY_WRITTEN: $TELEMETRY_FILE exists=$( [[ -f "$TELEMETRY_FILE" ]] && echo yes || echo no ) size=$(stat -c%s "$TELEMETRY_FILE" 2>/dev/null || echo 0)"
  log "NETTIMEWRITTEN: $NET_TIME_FILE exists=$( [[ -f "$NET_TIME_FILE" ]] && echo yes || echo no ) size=$(stat -c%s "$NET_TIME_FILE" 2>/dev/null || echo 0)"
}

print_download_stats() {
  section "VAST DOWNLOAD-STATISTIK"
  log "Statistikdatei $STATS_FILE"
  log "Run-ID $RUN_ID"
  echo "----------------------------------------------------------"
  echo "Bereich  Wert"
  echo "----------------------------------------------------------"
  echo "Gesamt  $DOWNLOAD_TOTAL"
  echo "Erfolgreich  $DOWNLOAD_OK"
  echo "Uebersprungen  $DOWNLOAD_SKIP"
  echo "Fehlgeschlagen  $DOWNLOAD_FAIL"
  echo "Daten  $(bytes_to_human "$DOWNLOAD_BYTES")"
  echo "Downloadzeit  ${DOWNLOAD_SECONDS}s"
  if [[ "$DOWNLOAD_SECONDS" -gt 0 ]]; then
    python3 - "$DOWNLOAD_BYTES" "$DOWNLOAD_SECONDS" <<'PY'
import sys
b=float(sys.argv[1]); s=float(sys.argv[2])
rate=b/s if s>0 else 0
units=["B/s","KiB/s","MiB/s","GiB/s"]
for u in units:
    if rate < 1024 or u == units[-1]:
        print(f"Rate  {rate:.2f} {u}")
        break
    rate/=1024
PY
  else
    echo "Rate  0 B/s"
  fi
  echo "----------------------------------------------------------"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fatal 2 "Benoetigter Befehl fehlt: $1"
}

free_kb_for_path() {
  df -Pk "$1" | awk 'NR==2 {print $4}'
}

assert_min_free_kb() {
  local path="$1"
  local required_kb="$2"
  local label="$3"
  local free_kb
  free_kb="$(free_kb_for_path "$path")"
  [[ "$free_kb" =~ ^[0-9]+$ ]] || fatal 20 "FATAL_DISK_SPACE: Freien Speicher fuer $path nicht lesbar."

  if (( free_kb < required_kb )); then
    mark_poisoned "FATAL_DISK_SPACE: $label - freier Speicher ${free_kb}KB kleiner als erforderlich ${required_kb}KB."
    fatal 20 "FATAL_DISK_SPACE: $label - freier Speicher ${free_kb}KB kleiner als erforderlich ${required_kb}KB."
  fi
}

gb_to_kb() {
  python3 - "$1" <<'PY'
import sys
print(int(float(sys.argv[1]) * 1024 * 1024))
PY
}

disk_guard() {
  local label="$1"
  local gb="$2"
  local required_kb
  required_kb="$(gb_to_kb "$gb")"
  assert_min_free_kb "$WORKSPACE" "$required_kb" "$label"
}

absolute_disk_guard_if_set() {
  if [[ "$DISK_GUARD_ABSOLUTE_KB" =~ ^[0-9]+$ ]] && (( DISK_GUARD_ABSOLUTE_KB > 0 )); then
    assert_min_free_kb "$WORKSPACE" "$DISK_GUARD_ABSOLUTE_KB" "absolute guard"
  fi
}

check_poison_state() {
  if [[ "$STOP_ON_POISON_STATE" == "1" && -f "$POISON_MARKER" ]]; then
    fatal 30 "FATAL_POISON_STATE: $(cat "$POISON_MARKER" 2>/dev/null || echo unknown)"
  fi
}

prepare_files() {
  : > "$STATS_FILE"
  rm -f "$POISON_MARKER" "$FATAL_REASON_FILE" "$PROVISION_STATE_FILE"
  log "Statistikdatei fuer neuen Lauf zurueckgesetzt $STATS_FILE"
}

ensure_model_list() {
  section "VAST MODEL LIST"
  [[ -f "$MODEL_LIST_FILE" ]] || fatal 3 "model-list.sh fehlt: $MODEL_LIST_FILE"
  log "Datei vorhanden $MODEL_LIST_FILE $(stat -c%s "$MODEL_LIST_FILE" 2>/dev/null || echo 0) bytes"
  # shellcheck disable=SC1090
  source "$MODEL_LIST_FILE"
  [[ "${#MODELS[@]:-0}" -gt 0 ]] || fatal 3 "model-list.sh geladen, aber MODELS ist leer."
  ok "model-list.sh geladen: ${#MODELS[@]} Eintraege"
}

ensure_directories() {
  section "VAST DIRECTORIES"
  mkdir -p \
    "$FORGE_ROOT/models/Stable-diffusion" \
    "$FORGE_ROOT/models/ESRGAN" \
    "$FORGE_ROOT/models/Lora" \
    "$FORGE_ROOT/models/VAE" \
    "$FORGE_ROOT/models/ControlNet" \
    "$FORGE_ROOT/models/clip_vision" \
    "$FORGE_ROOT/models/blip" \
    "$FORGE_ROOT/models/insightface" \
    "$FORGE_ROOT/extensions" \
    "$WORKSPACE/tmp"
  ok "Zielverzeichnisse erstellt"
}

merge_json() {
  local src="$1"
  local dst="$2"
  [[ -f "$src" ]] || { warn "Quelldatei fuer Merge fehlt: $src"; return 0; }
  mkdir -p "$(dirname "$dst")"
  if [[ ! -f "$dst" ]]; then
    cp "$src" "$dst"
    ok "Konfiguration initial kopiert nach $dst"
    return 0
  fi

  python3 - "$src" "$dst" <<'PY'
import json,sys,copy
srcp,dstp=sys.argv[1],sys.argv[2]
with open(srcp,'r',encoding='utf-8') as f: src=json.load(f)
with open(dstp,'r',encoding='utf-8') as f: dst=json.load(f)
def merge(a,b):
    if isinstance(a,dict) and isinstance(b,dict):
        out=copy.deepcopy(b)
        for k,v in a.items():
            out[k]=merge(v,b.get(k))
        return out
    return copy.deepcopy(a)
merged=merge(src,dst)
with open(dstp,'w',encoding='utf-8') as f:
    json.dump(merged,f,ensure_ascii=False,indent=2)
    f.write('\n')
PY
  echo "[OK] Konfiguration erfolgreich gemergt in $dst"
}

config_snapshot() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  python3 - "$file" <<'PY'
import json,sys
p=sys.argv[1]
with open(p,'r',encoding='utf-8') as f:
    data=json.load(f)
print("sd_model_checkpoint=", data.get("sd_model_checkpoint"))
print("sd_checkpoints_limit=", data.get("sd_checkpoints_limit"))
PY
}

apply_configs() {
  section "VAST CONFIGS"
  log "Fuehre JSON-Merge durch: $CONFIG_SRC -> $FORGE_ROOT/config.json"
  merge_json "$CONFIG_SRC" "$FORGE_ROOT/config.json"

  log "Fuehre JSON-Merge durch: $UI_CONFIG_SRC -> $FORGE_ROOT/ui-config.json"
  merge_json "$UI_CONFIG_SRC" "$FORGE_ROOT/ui-config.json"

  log "Fuehre JSON-Merge durch: $UI_CONFIG_SRC -> $FORGE_ROOT/config/ui-config.json"
  merge_json "$UI_CONFIG_SRC" "$FORGE_ROOT/config/ui-config.json"

  log "Fuehre JSON-Merge durch: $UI_CONFIG_SRC -> $FORGE_ROOT/configs/ui-config.json"
  merge_json "$UI_CONFIG_SRC" "$FORGE_ROOT/configs/ui-config.json"

  if [[ -z "$FORGE_PRESET" ]]; then
    log "FORGE_PRESET ist leer; ueberspringe Preset-Erzwingung (ui-config.json/config.json bleiben unveraendert)."
  else
    log "FORGE_PRESET=$FORGE_PRESET gesetzt; Preset-Logik kann hier ergaenzt werden."
  fi

  if [[ "$PATCH_MAIN_ENTRY" != "1" ]]; then
    log "PATCH_MAIN_ENTRY ist nicht 1; ueberspringe main_entry.py-Patch."
  else
    log "PATCH_MAIN_ENTRY=1 gesetzt; main_entry.py-Patch ist in dieser Fassung bewusst deaktiviert."
  fi
}

clear_ui_cache() {
  log "Bereinige UI-Cache fuer konsistente Parameter..."
  find "$FORGE_ROOT" -type f \( -name '*.json.bak' -o -name '*cache*.json' \) -delete 2>/dev/null || true
  ok "Alle Konfigurationspfade wurden gemergt, gepatcht und Cache geleert."
}

verify_config_semantics() {
  section "VAST CONFIG CHECK BEFORE START"
  [[ -f "$FORGE_ROOT/config.json" ]] && ok "config.json semantisch identisch (Objektstruktur abgeglichen)"
  [[ -f "$FORGE_ROOT/ui-config.json" ]] && ok "ui-config.json semantisch identisch (Objektstruktur abgeglichen)"
}

write_forge_blocker() {
  cat > "$FORGE_BLOCKER" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
echo "FORGE_BLOCKED: provisioning in progress"
while true; do sleep 600; done
EOF
  chmod +x "$FORGE_BLOCKER"
}

write_forge_wrapper() {
  section "VAST FORGE WRAPPER"
  cat > "$FORGE_WRAPPER" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
cd "$FORGE_ROOT"
export COMMANDLINE_ARGS="\${COMMANDLINE_ARGS:-} --listen --port ${FORGE_API_PORT} --api --skip-python-version-check"
exec /usr/bin/python3 launch.py
EOF
  chmod +x "$FORGE_WRAPPER"
  ok "Forge-Wrapper geschrieben: $FORGE_WRAPPER"
}

set_supervisor_command() {
  local command_path="$1"
  [[ -f "$FORGE_CONF" ]] || fatal 4 "Supervisor-Datei fehlt: $FORGE_CONF"

  python3 - "$FORGE_CONF" "$command_path" <<'PY'
import re,sys
conf,cmd=sys.argv[1],sys.argv[2]
with open(conf,'r',encoding='utf-8') as f:
    txt=f.read()
if re.search(r'^\s*command\s*=.*$', txt, re.M):
    txt=re.sub(r'^\s*command\s*=.*$', f'command={cmd}', txt, flags=re.M)
else:
    txt += f'\ncommand={cmd}\n'
if re.search(r'^\s*autostart\s*=.*$', txt, re.M):
    txt=re.sub(r'^\s*autostart\s*=.*$', 'autostart=false', txt, flags=re.M)
else:
    txt += '\nautostart=false\n'
if re.search(r'^\s*autorestart\s*=.*$', txt, re.M):
    txt=re.sub(r'^\s*autorestart\s*=.*$', 'autorestart=false', txt, flags=re.M)
else:
    txt += '\nautorestart=false\n'
with open(conf,'w',encoding='utf-8') as f:
    f.write(txt)
PY
  echo "[OK] command= in $FORGE_CONF auf Wrapper gesetzt"
}

set_supervisor_autostart() {
  local value="$1"
  local autorestart="$2"
  [[ -f "$FORGE_CONF" ]] || return 0
  python3 - "$FORGE_CONF" "$value" "$autorestart" <<'PY'
import re,sys
conf,val,ar=sys.argv[1],sys.argv[2],sys.argv[3]
with open(conf,'r',encoding='utf-8') as f:
    txt=f.read()
for key,v in [('autostart',val),('autorestart',ar)]:
    if re.search(r'^\s*%s\s*=.*$' % key, txt, re.M):
        txt=re.sub(r'^\s*%s\s*=.*$' % key, f'{key}={v}', txt, flags=re.M)
    else:
        txt += f'\n{key}={v}\n'
with open(conf,'w',encoding='utf-8') as f:
    f.write(txt)
PY
}

supervisor_reload() {
  supervisorctl reread >/dev/null 2>&1 || true
  supervisorctl update >/dev/null 2>&1 || true
}

stop_forge_hard() {
  log "Proaktiver Stopp von Forge zur Vermeidung von Cache-Overrides..."
  supervisorctl stop "$FORGE_SERVICE_NAME" >/dev/null 2>&1 || true
  sleep 1
  pkill -f "$FORGE_ROOT/launch.py" >/dev/null 2>&1 || true
  pkill -f "python3 launch.py" >/dev/null 2>&1 || true
  ok "Forge gestoppt bzw. Restprozesse bereinigt"
}

disable_forge_until_ready() {
  section "VAST SUPERVISOR WRAPPER COMMAND"
  write_forge_blocker
  write_forge_wrapper
  log "Setze Supervisor-Command auf Wrapper in $FORGE_CONF"
  set_supervisor_command "$FORGE_BLOCKER"
  if [[ "$FORCE_DISABLE_FORGE_AUTOSTART" == "1" ]]; then
    set_supervisor_autostart "false" "false"
  fi
  supervisor_reload
  supervisorctl stop "$FORGE_SERVICE_NAME" >/dev/null 2>&1 || true
  log "Forge API URL gesetzt: $FORGE_API_URL"
  ok "Supervisor-Command erfolgreich auf Blocker umgestellt"
}

enable_forge_real_command() {
  log "Setze finalen Forge-Command in $FORGE_CONF"
  set_supervisor_command "$FORGE_WRAPPER"
  set_supervisor_autostart "true" "true"
  supervisor_reload
  ok "Supervisor-Command erfolgreich auf Forge-Wrapper umgestellt"
}

start_forge_final() {
  if [[ "$ENABLE_FORGE_FINAL_START" != "1" ]]; then
    warn "ENABLE_FORGE_FINAL_START!=1, ueberspringe finalen Forge-Start."
    return 0
  fi

  disk_guard "before forge final start" "$DISK_GUARD_BEFORE_FORGE_GB"
  absolute_disk_guard_if_set
  enable_forge_real_command
  supervisorctl start "$FORGE_SERVICE_NAME" >/dev/null 2>&1 || true
  ok "Forge final gestartet"
}

append_download_stat() {
  local name="$1" status="$2" bytes="$3" seconds="$4" note="$5"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$RUN_ID" "$name" "$status" "$bytes" "$seconds" "$note" >> "$STATS_FILE"
}

url_host_header() {
  local url="$1"
  if [[ "$url" == *"huggingface.co"* && -n "$HF_TOKEN" ]]; then
    printf 'Authorization: Bearer %s' "$HF_TOKEN"
    return 0
  fi
  if [[ "$url" == *"civitai.com"* && -n "$CIVITAI_TOKEN" ]]; then
    printf 'Authorization: Bearer %s' "$CIVITAI_TOKEN"
    return 0
  fi
  return 1
}

download_atomic() {
  local url="$1"
  local dst="$2"
  local min_bytes="${3:-1}"

  local tmp="${dst}.part"
  local started ended elapsed bytes rc=0 http_code="" header=""
  mkdir -p "$(dirname "$dst")"
  rm -f "$tmp"

  started="$(date +%s)"
  if header="$(url_host_header "$url")"; then
    http_code="$(curl -L --fail --silent --show-error -H "$header" -o "$tmp" -w '%{http_code}' "$url" 2>"$WORKSPACE/tmp/curl.err")" || rc=$?
  else
    http_code="$(curl -L --fail --silent --show-error -o "$tmp" -w '%{http_code}' "$url" 2>"$WORKSPACE/tmp/curl.err")" || rc=$?
  fi
  ended="$(date +%s)"
  elapsed=$(( ended - started ))

  if [[ $rc -ne 0 ]]; then
    rm -f "$tmp"
    printf '%s|%s|%s\n' "$rc" "${http_code:-0}" "$(tr '\n' ' ' < "$WORKSPACE/tmp/curl.err" | sed 's/"/'\''/g')"
    return 1
  fi

  [[ -f "$tmp" ]] || { printf '1|%s|missing_temp_file\n' "${http_code:-0}"; return 1; }
  bytes="$(stat -c%s "$tmp" 2>/dev/null || echo 0)"
  [[ "$bytes" =~ ^[0-9]+$ ]] || bytes=0

  if (( bytes < min_bytes )); then
    rm -f "$tmp"
    printf '1|%s|too_small:%s\n' "${http_code:-0}" "$bytes"
    return 1
  fi

  mv -f "$tmp" "$dst"
  printf '0|%s|%s|%s\n' "${http_code:-0}" "$bytes" "$elapsed"
  return 0
}

download_one() {
  local name="$1"
  local url="$2"
  local dst="$3"
  local min_bytes="${4:-1}"

  DOWNLOAD_TOTAL=$((DOWNLOAD_TOTAL + 1))

  if [[ -f "$dst" ]]; then
    local existing
    existing="$(stat -c%s "$dst" 2>/dev/null || echo 0)"
    if [[ "$existing" =~ ^[0-9]+$ ]] && (( existing >= min_bytes )); then
      log "SKIP $name (exists)"
      DOWNLOAD_SKIP=$((DOWNLOAD_SKIP + 1))
      append_download_stat "$name" "skip" "$existing" "0" "exists"
      return 0
    fi
    warn "Vorhandene Datei zu klein oder ungueltig, lade neu: $dst"
    rm -f "$dst"
  fi

  disk_guard "before download $name" "$DISK_GUARD_DOWNLOAD_GB"
  absolute_disk_guard_if_set

  log "Start download $name from $url"
  local result rc status http bytes sec note
  if result="$(download_atomic "$url" "$dst" "$min_bytes")"; then
    IFS='|' read -r status http bytes sec <<< "$result"
    DOWNLOAD_OK=$((DOWNLOAD_OK + 1))
    DOWNLOAD_BYTES=$((DOWNLOAD_BYTES + bytes))
    DOWNLOAD_SECONDS=$((DOWNLOAD_SECONDS + sec))
    append_download_stat "$name" "ok" "$bytes" "$sec" "http=$http"
    ok "geladen $name"
    return 0
  fi

  rc=$?
  IFS='|' read -r status http note <<< "$result"
  DOWNLOAD_FAIL=$((DOWNLOAD_FAIL + 1))
  append_download_stat "$name" "fail" "0" "0" "http=${http:-0} ${note:-unknown}"
  err "url fehlgeschlagen $name http=${http:-0} err=${note:-unknown}"
  return "$rc"
}

normalize_model_entry() {
  local entry="$1"
  IFS='|' read -r name url rel min_bytes required <<< "$entry"
  [[ -n "${name:-}" ]] || return 1
  [[ -n "${url:-}" ]] || return 1
  [[ -n "${rel:-}" ]] || return 1
  min_bytes="${min_bytes:-1}"
  required="${required:-0}"
  printf '%s|%s|%s|%s|%s\n' "$name" "$url" "$rel" "$min_bytes" "$required"
}

run_downloads() {
  section "VAST DOWNLOADS"
  local entry name url rel min_bytes required dst
  local failed_required=0

  for entry in "${MODELS[@]}"; do
    entry="$(normalize_model_entry "$entry")" || fatal 5 "Ungueltiger MODELS-Eintrag in model-list.sh"
    IFS='|' read -r name url rel min_bytes required <<< "$entry"
    dst="$FORGE_ROOT/$rel"

    if ! download_one "$name" "$url" "$dst" "$min_bytes"; then
      if [[ "$required" == "1" ]]; then
        failed_required=1
      fi
    fi

    if grep -q "No space left on device" "$WORKSPACE/tmp/curl.err" 2>/dev/null; then
      mark_poisoned "FATAL_DISK_SPACE: Downloadphase meldet 'No space left on device'."
      fatal 20 "FATAL_DISK_SPACE: Downloadphase meldet 'No space left on device'."
    fi
  done

  ok "Downloads abgeschlossen"

  if (( failed_required == 1 )); then
    fatal 11 "FATAL_DOWNLOAD_INCOMPLETE: Mindestens ein required Download ist fehlgeschlagen."
  fi
}

checkpoint_debug() {
  section "VAST CHECKPOINT DEBUG SNAPSHOT"
  log "FORGE_ROOT=$FORGE_ROOT"
  log "FORGE_DEFAULT_CHECKPOINT=${FORGE_DEFAULT_CHECKPOINT:-}"
  log "FORGE_REQUIRED_CHECKPOINTS=${FORGE_REQUIRED_CHECKPOINTS:-}"
  log "Listing $FORGE_ROOT/models/Stable-diffusion"
  ls -1 "$FORGE_ROOT/models/Stable-diffusion" 2>/dev/null || true
  log "Detailed listing $FORGE_ROOT/models/Stable-diffusion"
  ls -lah "$FORGE_ROOT/models/Stable-diffusion" 2>/dev/null || true
  log "config.json checkpoint snapshot:"
  config_snapshot "$FORGE_ROOT/config.json" || true
}

check_required_checkpoints() {
  section "VAST CHECKPOINT FILE CHECK"
  local missing=0
  local cp file
  IFS='|' read -r -a cps <<< "${FORGE_REQUIRED_CHECKPOINTS:-}"

  for cp in "${cps[@]}"; do
    [[ -z "$cp" ]] && continue
    file="$FORGE_ROOT/models/Stable-diffusion/$cp"
    if [[ -f "$file" && -s "$file" ]]; then
      ok "Checkpoint-Datei vorhanden $file angefordert $cp"
    else
      err "Checkpoint-Datei fehlt: $file"
      missing=1
    fi
  done

  log "Vorhandene Dateien in models/Stable-diffusion:"
  section "VAST CHECKPOINT INVENTORY"
  ls -1 "$FORGE_ROOT/models/Stable-diffusion" 2>/dev/null || true

  checkpoint_debug

  if (( missing == 1 )) && [[ "$STRICT_CHECKPOINTS" == "1" ]]; then
    fatal 11 "FATAL_REQUIRED_CHECKPOINT_MISSING: Provisionierung abgebrochen, benoetigte Checkpoints fehlen."
  fi
}

scan_for_poison_signals() {
  local log_file="${1:-}"
  [[ -n "$log_file" && -f "$log_file" ]] || return 0

  if grep -Fq "No space left on device" "$log_file"; then
    mark_poisoned "FATAL_DISK_SPACE: 'No space left on device' erkannt."
    fatal 20 "FATAL_DISK_SPACE: 'No space left on device' erkannt."
  fi

  if grep -Fq "PyTorch is not able to access GPU" "$log_file"; then
    mark_poisoned "FATAL_GPU_UNAVAILABLE_AFTER_PARTIAL_INSTALL: PyTorch konnte GPU nicht nutzen."
    fatal 21 "FATAL_GPU_UNAVAILABLE_AFTER_PARTIAL_INSTALL: PyTorch konnte GPU nicht nutzen."
  fi
}

main() {
  require_cmd python3
  require_cmd curl
  require_cmd df
  require_cmd stat
  require_cmd supervisorctl

  section "VAST PRECHECKS"
  prepare_files
  write_state "starting"

  disk_guard "startup guard" "$EXPECTED_MIN_DISK_GB"
  absolute_disk_guard_if_set

  ensure_model_list
  ensure_directories

  stop_forge_hard
  disable_forge_until_ready

  apply_configs
  clear_ui_cache
  verify_config_semantics

  check_poison_state
  run_downloads
  check_poison_state
  check_required_checkpoints
  check_poison_state

  if [[ -f "$WORKSPACE/forge-install.log" ]]; then
    scan_for_poison_signals "$WORKSPACE/forge-install.log"
  fi

  start_forge_final

  write_state "completed"
  write_telemetry "ok" "0" "Provisioning completed successfully"
  write_net_time
  print_download_stats
  ok "Provisionierung erfolgreich abgeschlossen."
}

main "$@"
