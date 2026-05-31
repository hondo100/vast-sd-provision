#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# cleanup-and-optimize.sh | Version: 2026-05-31.09 (Non-Interactive SSH/SCP Fix)
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

# SSH-Einstellungen für nicht-interaktive Zugriffe
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa}"
SSH_USER="${SSH_USER:-root}"
SSH_CONNECT_TIMEOUT="${SSH_CONNECT_TIMEOUT:-15}"

# Globale Definition der Farbfunktion zur Vermeidung von POSIX-Parser-Fehlern
c() { printf '\033[31m%s\033[0m\n' "$1"; }

get_instance_ssh_target() {
    local instance_id="$1"
    local instance_json
    local host=""
    local port=""

    if ! instance_json="$(vastai show instance "$instance_id" --raw 2>/dev/null)"; then
        echo "[WARNUNG] Konnte Instanzdaten fuer SSH-Ziel nicht via vastai show instance abrufen." >&2
        return 1
    fi

    if command -v python3 >/dev/null 2>&1; then
        read -r host port < <(
            python3 - <<'PY' "$instance_json"
import json
import sys

raw = sys.argv[1]
host = ""
port = ""

try:
    data = json.loads(raw)
except Exception:
    print("", "")
    raise SystemExit(0)

candidates = []
if isinstance(data, dict):
    candidates.append(data)
    for key in ("instances", "results"):
        val = data.get(key)
        if isinstance(val, list):
            candidates.extend([x for x in val if isinstance(x, dict)])
        elif isinstance(val, dict):
            candidates.append(val)

for item in candidates:
    if not host:
        for k in ("public_ipaddr", "ssh_host", "host", "hostname", "public_ip"):
            v = item.get(k)
            if isinstance(v, str) and v.strip():
                host = v.strip()
                break

    if not port:
        direct_port = item.get("ssh_port")
        if isinstance(direct_port, int):
            port = str(direct_port)
        elif isinstance(direct_port, str) and direct_port.strip().isdigit():
            port = direct_port.strip()

    if (not port) and isinstance(item.get("ports"), dict):
        ports = item["ports"]
        direct = ports.get("22/tcp") or ports.get("22")
        if isinstance(direct, list) and direct:
            first = direct[0]
            if isinstance(first, int):
                port = str(first)
            elif isinstance(first, str) and first.strip().isdigit():
                port = first.strip()
        elif isinstance(direct, int):
            port = str(direct)
        elif isinstance(direct, str) and direct.strip().isdigit():
            port = direct.strip()

    if host and port:
        break

print(host, port)
PY
        )
    fi

    if [[ -z "${host:-}" || -z "${port:-}" ]]; then
        echo "[WARNUNG] SSH-Ziel konnte nicht automatisch ermittelt werden." >&2
        return 1
    fi

    printf '%s %s\n' "$host" "$port"
}

copy_from_instance_with_retry() {
    local instance_id="$1"
    local remote_path="$2"
    local local_path="$3"
    local label="$4"
    local max_attempts=5
    local attempt=1

    local ssh_host=""
    local ssh_port=""
    local ssh_opts=()

    rm -f "$COPY_LOG_FILE"

    if ! read -r ssh_host ssh_port < <(get_instance_ssh_target "$instance_id"); then
        echo "[WARNUNG] Kein SSH-Ziel fuer $label verfuegbar. Kopie wird uebersprungen."
        return 1
    fi

    if [[ ! -f "$SSH_KEY" ]]; then
        echo "[WARNUNG] SSH-Key nicht gefunden: $SSH_KEY"
        return 1
    fi

    ssh_opts=(
        -i "$SSH_KEY"
        -o IdentitiesOnly=yes
        -o PreferredAuthentications=publickey
        -o PubkeyAuthentication=yes
        -o PasswordAuthentication=no
        -o KbdInteractiveAuthentication=no
        -o ChallengeResponseAuthentication=no
        -o BatchMode=yes
        -o ConnectTimeout="$SSH_CONNECT_TIMEOUT"
        -o StrictHostKeyChecking=accept-new
    )

    while (( attempt <= max_attempts )); do
        echo "[INFO] Kopierversuch $attempt/$max_attempts fuer $label..."
        rm -f "$local_path"

        if scp -B "${ssh_opts[@]}" -P "$ssh_port" "${SSH_USER}@${ssh_host}:${remote_path}" "$local_path" >>"$COPY_LOG_FILE" 2>&1; then
            if [[ -s "$local_path" ]]; then
                echo "[INFO] $label erfolgreich lokal gesichert: $local_path"
                return 0
            fi
            echo "[WARNUNG] $label wurde ohne Inhalt kopiert. Neuer Versuch..."
        else
            echo "[WARNUNG] SCP-Kopierversuch fuer $label fehlgeschlagen. Versuche Fallback per SSH/cat..."
            rm -f "$local_path"
            if ssh "${ssh_opts[@]}" -p "$ssh_port" "${SSH_USER}@${ssh_host}" "cat '$remote_path'" >"$local_path" 2>>"$COPY_LOG_FILE"; then
                if [[ -s "$local_path" ]]; then
                    echo "[INFO] $label erfolgreich via SSH/cat lokal gesichert: $local_path"
                    return 0
                fi
                echo "[WARNUNG] $label wurde via SSH/cat ohne Inhalt geliefert. Neuer Versuch..."
            else
                echo "[WARNUNG] Fallback per SSH/cat fuer $label ebenfalls fehlgeschlagen. Neuer Versuch..."
            fi
        fi

        attempt=$((attempt + 1))
        sleep 3
    done

    echo "[WARNUNG] $label konnte nicht kopiert werden."
    if [[ -f "$COPY_LOG_FILE" ]]; then
        echo "[DEBUG] SSH/SCP-Log:"
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

# 2. Defensiver Pull über nicht-interaktives SSH/SCP statt vastai copy
if copy_from_instance_with_retry "$INSTANCE_ID" "$REMOTE_TELEMETRY_FILE" "$TELEMETRY_FILE" "Telemetriedaten"; then
    TELEMETRY_AVAILABLE=1
else
    echo "[WARNUNG] Telemetriedaten konnten nicht kopiert werden (Instanz evtl. nicht bereit, SSH nicht verfuegbar oder Datei fehlt)."
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
