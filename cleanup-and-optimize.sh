#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# cleanup-and-optimize.sh | Version: 2026-05-31.08 (Telemetry Copy Hardened)
# -----------------------------------------------------------------------------
set -euo pipefail

# Pfad zur persistenten Zustandsdatei
STATE_FILE="/home/werner/github-scripts/.current_instance"
PARAMS_FILE="./params.json"
TELEMETRY_FILE="./latest_telemetry.json"
NET_TIME_FILE="./latest_provision_net_time.log"
COPY_LOG_FILE="./latest_vast_copy.log"

# Remote-Dateien aus provisioning.sh
REMOTE_TELEMETRY_FILE="/workspace/provisioning_telemetry.json"
REMOTE_NET_TIME_FILE="/workspace/provision_net_time.log"

# Globale Definition der Farbfunktion zur Vermeidung von POSIX-Parser-Fehlern
c() { printf '\033[31m%s\033[0m\n' "$1"; }

copy_from_instance_with_retry() {
    local instance_id="$1"
    local remote_path="$2"
    local local_path="$3"
    local label="$4"
    local max_attempts=5
    local attempt=1

    rm -f "$COPY_LOG_FILE"

    while (( attempt <= max_attempts )); do
        echo "[INFO] Kopierversuch $attempt/$max_attempts fuer $label..."
        if vastai copy "$instance_id":"$remote_path" "local:$local_path" >>"$COPY_LOG_FILE" 2>&1; then
            if [[ -s "$local_path" ]]; then
                echo "[INFO] $label erfolgreich lokal gesichert: $local_path"
                return 0
            fi
            echo "[WARNUNG] $label wurde ohne Inhalt kopiert. Neuer Versuch..."
        else
            echo "[WARNUNG] Kopierversuch fuer $label fehlgeschlagen. Neuer Versuch..."
        fi
        attempt=$((attempt + 1))
        sleep 3
    done

    echo "[WARNUNG] $label konnte nicht kopiert werden."
    if [[ -f "$COPY_LOG_FILE" ]]; then
        echo "[DEBUG] Vast-Copy-Log:"
        tail -n 20 "$COPY_LOG_FILE" || true
    fi
    return 1
}

# 1. Validierung: Prüfen, ob eine aktive Instanz registriert ist
if [[ ! -f "$STATE_FILE" ]]; then
    c "[FEHLER] Keine aktive Zustandsdatei gefunden ($STATE_FILE)."
    echo "Es ist aktuell keine Instanz im System registriert oder der Cleanup wurde bereits ausgeführt."
    exit 1
fi

# Atomares Auslesen der Instance-ID
INSTANCE_ID=$(cat "$STATE_FILE")

echo "========================================================================================="
echo "Starte automatisierten Cleanup für Instanz-ID: $INSTANCE_ID"
echo "========================================================================================="

echo "Hole Telemetriedaten von Instanz $INSTANCE_ID vor dem Destroy..."

TELEMETRY_AVAILABLE=0
NET_TIME_AVAILABLE=0

# 2. Defensiver Pull über das Vast.ai API Gateway
if copy_from_instance_with_retry "$INSTANCE_ID" "$REMOTE_TELEMETRY_FILE" "$TELEMETRY_FILE" "Telemetriedaten"; then
    TELEMETRY_AVAILABLE=1
else
    echo "[WARNUNG] Telemetriedaten konnten nicht kopiert werden (Instanz evtl. nicht bereit oder Datei fehlt)."
fi

if copy_from_instance_with_retry "$INSTANCE_ID" "$REMOTE_NET_TIME_FILE" "$NET_TIME_FILE" "Netto-Laufzeitdatei"; then
    NET_TIME_AVAILABLE=1
else
    echo "[WARNUNG] Netto-Laufzeitdatei konnte nicht kopiert werden."
fi

# 3. Instanz zerstören (Garantierte Kostenvermeidung)
echo "Zerstöre Vast.ai-Instanz $INSTANCE_ID zur Kostenvermeidung..."
printf 'y\n' | vastai destroy instance "$INSTANCE_ID"

# 4. Parameter-Optimierung und Format-Sanitizing lokal ausführen
if [[ "$TELEMETRY_AVAILABLE" -eq 1 && -f "$TELEMETRY_FILE" ]]; then
    
    # --- NEU: CRLF zu LF Sanitizing-Stufe via sed ---
    echo "[PROZESS] Sanitiere Zeilenenden (CRLF -> LF) für JSON-Infrastruktur..."
    sed -i 's/\r$//' "$PARAMS_FILE" "$TELEMETRY_FILE"
    # ------------------------------------------------
    
    echo "Starte Parameter-Optimierung (optimizer.py) lokal..."
    python3 ./optimizer.py --telemetry "$TELEMETRY_FILE" --params "$PARAMS_FILE" --alpha 0.25
    rm -f "$TELEMETRY_FILE"
else
    # Falls das Telemetrie-File fehlt, zumindest die params.json vorsorglich bereinigen
    if [[ -f "$PARAMS_FILE" ]]; then
        sed -i 's/\r$//' "$PARAMS_FILE"
    fi
    echo "[INFO] Überspringe Optimierungsphase, da keine Telemetriedaten vorliegen."
fi

if [[ "$NET_TIME_AVAILABLE" -eq 1 && -f "$NET_TIME_FILE" ]]; then
    echo "[INFO] Netto-Laufzeitdatei gesichert: $NET_TIME_FILE"
fi

# 5. Zurücksetzen des Systemzustands
rm -f "$STATE_FILE"
echo "[SUCCESS] System erfolgreich bereinigt. Zustandsdatei entfernt."
