#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# cleanup-and-optimize.sh | Version: 2026-05-30.07 (Syntax Fixed)
# -----------------------------------------------------------------------------
set -euo pipefail

# Pfad zur persistenten Zustandsdatei
STATE_FILE="/home/werner/github-scripts/.current_instance"
PARAMS_FILE="./params.json"
TELEMETRY_FILE="./latest_telemetry.json"

# Globale Definition der Farbfunktion zur Vermeidung von POSIX-Parser-Fehlern
c() { printf '\033[31m%s\033[0m\n' "$1"; }

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

# 2. Defensiver Pull über das Vast.ai API Gateway
if vastai copy-from "$INSTANCE_ID":/workspace/provisioning_telemetry.json "$TELEMETRY_FILE" 2>/dev/null; then
    echo "[INFO] Telemetriedaten erfolgreich lokal gesichert."
else
    echo "[WARNUNG] Telemetriedaten konnten nicht kopiert werden (Instanz evtl. nicht bereit)."
fi

# 3. Instanz zerstören (Garantierte Kostenvermeidung)
echo "Zerstöre Vast.ai-Instanz $INSTANCE_ID zur Kostenvermeidung..."
vastai destroy instance "$INSTANCE_ID"

# 4. Parameter-Optimierung und Format-Sanitizing lokal ausführen
if [[ -f "$TELEMETRY_FILE" ]]; then
    
    # --- NEU: CRLF zu LF Sanitizing-Stufe via sed ---
    echo "[PROZESS] Sanitiere Zeilenenden (CRLF -> LF) für JSON-Infrastruktur..."
    sed -i 's/\r$//' "$PARAMS_FILE" "$TELEMETRY_FILE"
    # ------------------------------------------------
    
    echo "Starte Parameter-Optimierung (optimizer.py) lokal..."
    python3 ./optimizer.py --telemetry "$TELEMETRY_FILE" --params "$PARAMS_FILE" --alpha 0.25
    rm "$TELEMETRY_FILE"
else
    # Falls das Telemetrie-File fehlt, zumindest die params.json vorsorglich bereinigen
    if [[ -f "$PARAMS_FILE" ]]; then
        sed -i 's/\r$//' "$PARAMS_FILE"
    fi
    echo "[INFO] Überspringe Optimierungsphase, da keine Telemetriedaten vorliegen."
fi

# 5. Zurücksetzen des Systemzustands
rm "$STATE_FILE"
echo "[SUCCESS] System erfolgreich bereinigt. Zustandsdatei entfernt."
