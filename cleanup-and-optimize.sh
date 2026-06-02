#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# cleanup-and-optimize.sh | Version: 2026-06-02.02
# Gehaertet:
# - vastai execute statt direktem SSH fuer Dateipruefung
# - vastai copy statt scp fuer Telemetrie-Download
# - echte Retry-Logik vor Destroy
# - klare Trennung zwischen "Datei fehlt" und "Instanz/CLI noch nicht bereit"
# -----------------------------------------------------------------------------
set -Eeuo pipefail

STATE_FILE="/home/werner/github-scripts/.current_instance"
PARAMS_FILE="./params.json"
TELEMETRY_FILE="./latest_telemetry.json"
NET_TIME_FILE="./latest_provision_net_time.log"
COPY_LOG_FILE="./latest_vast_copy.log"

REMOTE_TELEMETRY_FILE="/workspace/provisioning_telemetry.json"
REMOTE_NET_TIME_FILE="/workspace/provision_net_time.log"

RETRY_COUNT="${RETRY_COUNT:-12}"
RETRY_DELAY="${RETRY_DELAY:-10}"

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

echo "Hole Telemetriedaten von Instanz $INSTANCE_ID vor dem Destroy..."

TELEMETRY_AVAILABLE=0
NET_TIME_AVAILABLE=0

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

destroy_instance "$INSTANCE_ID"

if [[ "$TELEMETRY_AVAILABLE" -eq 1 && -f "$TELEMETRY_FILE" ]]; then
    echo "[PROZESS] Sanitiere Zeilenenden (CRLF -> LF) fuer JSON-Infrastruktur..."
    for f in "$PARAMS_FILE" "$TELEMETRY_FILE"; do
        [[ -f "$f" ]] && sed -i 's/\r$//' "$f"
    done

    echo "Starte Parameter-Optimierung (optimizer.py) lokal..."
    python3 ./optimizer.py --telemetry "$TELEMETRY_FILE" --params "$PARAMS_FILE" --alpha 0.25
    rm -f "$TELEMETRY_FILE"
else
    [[ -f "$PARAMS_FILE" ]] && sed -i 's/\r$//' "$PARAMS_FILE"
    echo "[INFO] Ueberspringe Optimierungsphase, da keine Telemetriedaten vorliegen."
fi

if [[ "$NET_TIME_AVAILABLE" -eq 1 && -f "$NET_TIME_FILE" ]]; then
    echo "[INFO] Netto-Laufzeitdatei gesichert: $NET_TIME_FILE"
fi

rm -f "$STATE_FILE"
echo "[SUCCESS] System erfolgreich bereinigt. Zustandsdatei entfernt."
