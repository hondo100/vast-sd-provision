#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# cleanup-and-optimize.sh | Version: 2026-06-04.03
#
# ZWECK
# -----
# Dieses Script holt vor dem Zerstoeren einer Vast.ai-Instanz die vom
# Provisioning erzeugten Ergebnisdateien lokal ab, validiert die Telemetrie,
# startet optional die lokale Parameter-Optimierung und zerstoert danach die
# Instanz zur Kostenvermeidung.
#
# Es ist auf Provisioning-Laeufe abgestimmt, die ihre Ergebnisse nach
# /workspace schreiben, insbesondere:
# - /workspace/provisioning_telemetry.json
# - /workspace/provision_net_time.log
# - /workspace/model-download-stats.tsv
#
# ROBUSTHEIT
# ----------
# Das Script behandelt diese Problemfaelle explizit:
# - Instanz ist noch nicht sauber ueber vastai abfragbar
# - Remote-Datei ist noch nicht geschrieben
# - vastai copy meldet Erfolg, aber lokale Datei ist leer
# - Telemetrie-Datei existiert, ist aber kein valides JSON
# - optimizer.py schlaegt fehl; Telemetrie bleibt dann erhalten
#
# STEUERUNGSVARIABLEN
# -------------------
# - STATE_FILE
#   Datei mit der aktuell aktiven Instanz-ID.
#
# - PARAMS_FILE
#   Lokale JSON-Datei mit den zu optimierenden Parametern.
#
# - TELEMETRY_FILE
#   Lokaler Zielpfad fuer provisioning_telemetry.json.
#
# - NET_TIME_FILE
#   Lokaler Zielpfad fuer provision_net_time.log.
#
# - DOWNLOAD_STATS_FILE
#   Lokaler Zielpfad fuer model-download-stats.tsv.
#
# - COPY_LOG_FILE
#   Lokale Sammeldatei fuer vastai copy Logs.
#
# - REMOTE_TELEMETRY_FILE
#   Remote-Pfad zur Telemetrie-Datei auf der Instanz.
#
# - REMOTE_NET_TIME_FILE
#   Remote-Pfad zur Netto-Laufzeit-Datei auf der Instanz.
#
# - REMOTE_DOWNLOAD_STATS_FILE
#   Remote-Pfad zur Download-Statistik auf der Instanz.
#
# - RETRY_COUNT
#   Anzahl der Copy-/Existenz-Checks vor dem Aufgeben.
#
# - RETRY_DELAY
#   Wartezeit zwischen den Retries in Sekunden.
#
# - FETCH_DOWNLOAD_STATS
#   1 = Download-Statistik ebenfalls sichern.
#   0 = Download-Statistik ueberspringen.
#
# - RUN_OPTIMIZER
#   1 = optimizer.py nach erfolgreicher Telemetrie-Validierung starten.
#   0 = Optimierung ueberspringen.
#
# - KEEP_TELEMETRY_ON_SUCCESS
#   1 = lokale Telemetrie auch nach erfolgreichem optimizer.py behalten.
#   0 = lokale Telemetrie nach erfolgreichem optimizer.py loeschen.
#
# - DESTROY_ON_EXIT
#   1 = Instanz am Ende zerstoeren.
#   0 = Instanz nicht zerstoeren, nur Dateien sichern.
#
# ABLAUF
# ------
# 1. Zustand und benoetigte Commands pruefen.
# 2. Telemetrie-, Nettozeit- und optional Statistikdatei per vastai sichern.
# 3. Instanz optional zerstoeren.
# 4. Telemetrie lokal validieren und Metadaten ausgeben.
# 5. optimizer.py optional starten.
# 6. Zustandsdatei entfernen.
# -----------------------------------------------------------------------------

set -Eeuo pipefail

STATE_FILE="${STATE_FILE:-/home/werner/github-scripts/.current_instance}"
PARAMS_FILE="${PARAMS_FILE:-./params.json}"
TELEMETRY_FILE="${TELEMETRY_FILE:-./latest_telemetry.json}"
NET_TIME_FILE="${NET_TIME_FILE:-./latest_provision_net_time.log}"
DOWNLOAD_STATS_FILE="${DOWNLOAD_STATS_FILE:-./latest_model_download_stats.tsv}"
COPY_LOG_FILE="${COPY_LOG_FILE:-./latest_vast_copy.log}"

REMOTE_TELEMETRY_FILE="${REMOTE_TELEMETRY_FILE:-/workspace/provisioning_telemetry.json}"
REMOTE_NET_TIME_FILE="${REMOTE_NET_TIME_FILE:-/workspace/provision_net_time.log}"
REMOTE_DOWNLOAD_STATS_FILE="${REMOTE_DOWNLOAD_STATS_FILE:-/workspace/model-download-stats.tsv}"

RETRY_COUNT="${RETRY_COUNT:-12}"
RETRY_DELAY="${RETRY_DELAY:-10}"

FETCH_DOWNLOAD_STATS="${FETCH_DOWNLOAD_STATS:-1}"
RUN_OPTIMIZER="${RUN_OPTIMIZER:-1}"
KEEP_TELEMETRY_ON_SUCCESS="${KEEP_TELEMETRY_ON_SUCCESS:-1}"
DESTROY_ON_EXIT="${DESTROY_ON_EXIT:-1}"

c() { printf '\033[31m%s\033[0m\n' "$1"; }
log() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARNUNG] %s\n' "$*" >&2; }
ok() { printf '[SUCCESS] %s\n' "$*"; }

ensure_local_target_is_file_path() {
    local local_path="$1"
    local parent_dir

    if [[ -d "$local_path" ]]; then
        if [[ -z "$(ls -A "$local_path" 2>/dev/null)" ]]; then
            log "Zielpfad ist ein leeres Verzeichnis, wird entfernt: $local_path"
            rm -rf -- "$local_path"
        else
            warn "Zielpfad ist ein nicht-leeres Verzeichnis: $local_path"
            return 1
        fi
    fi

    parent_dir="$(dirname "$local_path")"
    [[ -d "$parent_dir" ]] || mkdir -p "$parent_dir"
    return 0
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        c "[FEHLER] Benoetigter Befehl fehlt: $1"
        exit 1
    }
}

instance_exists() {
    vastai show instance "$1" --raw >/dev/null 2>&1
}

remote_file_exists_via_vast() {
    local instance_id="$1"
    local remote_path="$2"
    local out

    out="$(vastai execute "$instance_id" "test -s '$remote_path' && echo EXISTS || echo MISSING" 2>/dev/null || true)"
    grep -q '^EXISTS$' <<< "$out"
}

copy_from_instance_with_retry() {
    local instance_id="$1"
    local remote_path="$2"
    local local_path="$3"
    local label="$4"

    local attempt=1
    local exists_state="unknown"

    rm -f -- "$COPY_LOG_FILE"
    ensure_local_target_is_file_path "$local_path" || return 1

    while (( attempt <= RETRY_COUNT )); do
        log "[$label] Versuch $attempt/$RETRY_COUNT"

        if ! instance_exists "$instance_id"; then
            warn "[$label] Instanz $instance_id ist via vastai aktuell nicht abfragbar."
        else
            if remote_file_exists_via_vast "$instance_id" "$remote_path"; then
                exists_state="present"
                log "[$label] Remote-Datei vorhanden: $remote_path"
                rm -f -- "$local_path"

                if vastai copy "${instance_id}:${remote_path}" "local:${local_path}" >>"$COPY_LOG_FILE" 2>&1; then
                    if [[ -s "$local_path" ]]; then
                        log "[$label] Erfolgreich lokal gesichert: $local_path"
                        return 0
                    fi
                    warn "[$label] vastai copy erfolgreich, aber lokale Datei leer oder fehlt."
                else
                    warn "[$label] vastai copy fehlgeschlagen."
                fi
            else
                exists_state="missing"
                warn "[$label] Remote-Datei noch nicht vorhanden: $remote_path"
            fi
        fi

        attempt=$((attempt + 1))
        if (( attempt <= RETRY_COUNT )); then
            sleep "$RETRY_DELAY"
        fi
    done

    if [[ "$exists_state" == "missing" ]]; then
        warn "[$label] Datei wurde innerhalb des Retry-Fensters nicht gefunden: $remote_path"
    else
        warn "[$label] Datei konnte nicht kopiert werden, obwohl Instanz/CLI zeitweise erreichbar war."
    fi

    if [[ -f "$COPY_LOG_FILE" ]]; then
        echo "[DEBUG] vastai copy Log (letzte 20 Zeilen):"
        tail -n 20 "$COPY_LOG_FILE" || true
    fi

    return 1
}

sanitize_line_endings_if_exists() {
    local f
    for f in "$@"; do
        [[ -f "$f" ]] && sed -i 's/\r$//' "$f"
    done
}

validate_telemetry_json() {
    local file="$1"
    python3 - "$file" <<'PY'
import json, sys
p = sys.argv[1]
with open(p, "r", encoding="utf-8") as f:
    obj = json.load(f)
if not isinstance(obj, dict):
    raise SystemExit(2)
print(obj.get("status", "unknown"))
PY
}

print_telemetry_summary() {
    local file="$1"
    python3 - "$file" <<'PY'
import json, sys
p = sys.argv[1]
with open(p, "r", encoding="utf-8") as f:
    d = json.load(f)

status = d.get("status", "unknown")
run_id = d.get("run_id", "unknown")
resolved = d.get("resolved_default_checkpoint", d.get("default_checkpoint", ""))
downloads = d.get("downloads", {})
counters = d.get("counters", {})

print(f"[INFO] Telemetrie-Status: {status}")
print(f"[INFO] Run-ID: {run_id}")
if resolved:
    print(f"[INFO] Resolved Default Checkpoint: {resolved}")

if isinstance(counters, dict) and counters:
    for key in ("download_ok", "download_skip", "download_fail", "ext_ok", "ext_skip", "ext_fail"):
        if key in counters:
            print(f"[INFO] Counter {key}: {counters[key]}")

if isinstance(downloads, dict) and downloads:
    for key in ("total", "ok", "skip", "fail", "bytes", "seconds"):
        if key in downloads:
            print(f"[INFO] Downloads {key}: {downloads[key]}")
PY
}

destroy_instance() {
    local instance_id="$1"
    log "Zerstoere Vast.ai-Instanz $instance_id zur Kostenvermeidung..."
    printf 'y\n' | vastai destroy instance "$instance_id"
}

if [[ ! -f "$STATE_FILE" ]]; then
    c "[FEHLER] Keine aktive Zustandsdatei gefunden ($STATE_FILE)."
    echo "Es ist aktuell keine Instanz registriert oder der Cleanup wurde bereits ausgefuehrt."
    exit 1
fi

require_cmd vastai
require_cmd python3

INSTANCE_ID="$(cat "$STATE_FILE")"

echo "========================================================================================="
echo "Starte automatisierten Cleanup fuer Instanz-ID: $INSTANCE_ID"
echo "========================================================================================="

echo "Hole Ergebnisdateien von Instanz $INSTANCE_ID vor dem Destroy..."

TELEMETRY_AVAILABLE=0
NET_TIME_AVAILABLE=0
DOWNLOAD_STATS_AVAILABLE=0
TELEMETRY_VALID=0
OPTIMIZER_OK=0

if copy_from_instance_with_retry "$INSTANCE_ID" "$REMOTE_TELEMETRY_FILE" "$TELEMETRY_FILE" "Telemetriedaten"; then
    TELEMETRY_AVAILABLE=1
else
    warn "Telemetriedaten konnten nicht kopiert werden."
fi

if copy_from_instance_with_retry "$INSTANCE_ID" "$REMOTE_NET_TIME_FILE" "$NET_TIME_FILE" "Netto-Laufzeitdatei"; then
    NET_TIME_AVAILABLE=1
else
    warn "Netto-Laufzeitdatei konnte nicht kopiert werden."
fi

if [[ "$FETCH_DOWNLOAD_STATS" == "1" ]]; then
    if copy_from_instance_with_retry "$INSTANCE_ID" "$REMOTE_DOWNLOAD_STATS_FILE" "$DOWNLOAD_STATS_FILE" "Download-Statistik"; then
        DOWNLOAD_STATS_AVAILABLE=1
    else
        warn "Download-Statistik konnte nicht kopiert werden."
    fi
fi

if [[ "$DESTROY_ON_EXIT" == "1" ]]; then
    destroy_instance "$INSTANCE_ID"
else
    log "DESTROY_ON_EXIT=0, Instanz bleibt bestehen."
fi

sanitize_line_endings_if_exists "$PARAMS_FILE" "$TELEMETRY_FILE" "$NET_TIME_FILE" "$DOWNLOAD_STATS_FILE"

if [[ "$TELEMETRY_AVAILABLE" -eq 1 && -f "$TELEMETRY_FILE" ]]; then
    if validate_telemetry_json "$TELEMETRY_FILE" >/dev/null 2>&1; then
        TELEMETRY_VALID=1
        print_telemetry_summary "$TELEMETRY_FILE"
    else
        warn "Telemetriedatei ist vorhanden, aber kein valides JSON: $TELEMETRY_FILE"
    fi
fi

if [[ "$TELEMETRY_VALID" -eq 1 && "$RUN_OPTIMIZER" == "1" ]]; then
    echo "Starte Parameter-Optimierung (optimizer.py) lokal..."
    if python3 ./optimizer.py --telemetry "$TELEMETRY_FILE" --params "$PARAMS_FILE" --alpha 0.25; then
        OPTIMIZER_OK=1
        ok "optimizer.py erfolgreich ausgefuehrt."
        if [[ "$KEEP_TELEMETRY_ON_SUCCESS" == "0" ]]; then
            rm -f -- "$TELEMETRY_FILE"
            log "Lokale Telemetrie nach erfolgreicher Optimierung entfernt."
        else
            log "Lokale Telemetrie bleibt fuer Diagnosezwecke erhalten."
        fi
    else
        warn "optimizer.py ist fehlgeschlagen; Telemetrie bleibt lokal erhalten."
    fi
else
    if [[ "$RUN_OPTIMIZER" != "1" ]]; then
        echo "[INFO] Ueberspringe Optimierungsphase, da RUN_OPTIMIZER=0 gesetzt ist."
    else
        echo "[INFO] Ueberspringe Optimierungsphase, da keine valide Telemetrie vorliegt."
    fi
fi

if [[ "$NET_TIME_AVAILABLE" -eq 1 && -f "$NET_TIME_FILE" ]]; then
    echo "[INFO] Netto-Laufzeitdatei gesichert: $NET_TIME_FILE"
fi

if [[ "$DOWNLOAD_STATS_AVAILABLE" -eq 1 && -f "$DOWNLOAD_STATS_FILE" ]]; then
    echo "[INFO] Download-Statistik gesichert: $DOWNLOAD_STATS_FILE"
fi

rm -f "$STATE_FILE"
echo "[SUCCESS] System erfolgreich bereinigt. Zustandsdatei entfernt."
