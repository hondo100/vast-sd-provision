#!/bin/bash

# ==============================================================================
# 🚀 VAST.AI PROVISIONING SCRIPT – SD-FORGE (Ubuntu 24.04)
# ==============================================================================

set -euo pipefail

# ── Log-Funktionen mit Zeitstempel ────────────────────────────────────────────
log()  { echo "[$(date '+%H:%M:%S')] $*"; }
ok()   { echo "[$(date '+%H:%M:%S')] ✅ $*"; }
warn() { echo "[$(date '+%H:%M:%S')] ⚠️  $*"; }
fail() { echo "[$(date '+%H:%M:%S')] ❌ FEHLER: $*" >&2; }

# Trap: Bei unerwartetem Abbruch genaue Zeile ausgeben
trap 'fail "Script abgebrochen in Zeile $LINENO (Exit-Code: $?). Letzter Befehl: $BASH_COMMAND"' ERR

WORKSPACE="/root/stable-diffusion-webui-forge"
LOG_FILE="/root/provisioning.log"
SENTINEL="/root/.provisioning_done"

# ── Fix 5: Alle Ausgaben auch in Log-Datei schreiben ─────────────────────────
exec > >(tee -a "$LOG_FILE") 2>&1
log "Log wird geschrieben nach: $LOG_FILE"
log "--- 🚀 Starte SD-Forge Provisioning Script ---"

# ── Fix 1: Idempotenz – bei Neustart nur Forge starten ───────────────────────
if [ -f "$SENTINEL" ]; then
    log "✅ Provisioning bereits abgeschlossen ($(cat $SENTINEL))"
    log "   Überspringe Installation – starte Forge direkt."
    log "   (Sentinel löschen mit: rm $SENTINEL)"
    cd "$WORKSPACE"
    while true; do
        bash webui.sh
        warn "Forge beendet (Exit-Code: $?) – Neustart in 10 Sekunden..."
        sleep 10
    done
    exit 0
fi

# ── 1. MODELL-LISTE VON GITHUB LADEN ─────────────────────────────────────────
log "Schritt 1/9: Lade Modell-Konfiguration von GitHub..."
# shellcheck source=/dev/null
if ! source <(curl -fsSL \
  -H "Authorization: token ${GITHUB_PAT}" \
  "https://raw.githubusercontent.com/hondo100/vast-sd-provision/main/model-list.sh?$(date +%s)"); then
    fail "Konnte model-list.sh nicht laden. GITHUB_PAT korrekt? Repo-Name korrekt?"
    exit 1
fi
ok "model-list.sh geladen (${#DOWNLOADS[@]} Modelle, ${#EXTENSIONS[@]} Extensions)"

# ── Fix 2: Disk-Space-Check ───────────────────────────────────────────────────
log "Schritt 2/9: Disk-Space prüfen..."
REQUIRED_GB=15
AVAILABLE_GB=$(df -BG /root | awk 'NR==2 {print $4}' | tr -d 'G')
log "   Verfügbar: ${AVAILABLE_GB} GB | Benötigt: ${REQUIRED_GB} GB"
if [ "$AVAILABLE_GB" -lt "$REQUIRED_GB" ]; then
    fail "Zu wenig Disk-Space: ${AVAILABLE_GB}GB verfügbar, mind. ${REQUIRED_GB}GB benötigt."
    fail "Instanz mit mehr Disk-Space starten (vast.ai → Edit Instance → Disk)."
    exit 1
fi
ok "Disk-Space ausreichend (${AVAILABLE_GB}GB verfügbar)"

# ── 3. SYSTEM-UPDATES & TOOLS ────────────────────────────────────────────────
log "Schritt 3/9: System-Updates & Tools installieren..."
apt-get update -qq || { fail "apt-get update fehlgeschlagen"; exit 1; }
apt-get install -y -qq \
    software-properties-common \
    aria2 git curl unzip \
    build-essential ninja-build \
    libgl1 libglib2.0-0 || { fail "apt-get install fehlgeschlagen – Netzwerk oder Mirror-Problem?"; exit 1; }
ok "System-Tools installiert"

# ── 4. PYTHON 3.11 VIA DEADSNAKES PPA ────────────────────────────────────────
log "Schritt 4/9: Python 3.11 via Deadsnakes PPA installieren..."
add-apt-repository ppa:deadsnakes/ppa -y || { fail "Deadsnakes PPA konnte nicht hinzugefügt werden"; exit 1; }
apt-get update -qq
apt-get install -y python3.11 python3.11-venv python3.11-dev python3.11-distutils || {
    fail "Python 3.11 Installation fehlgeschlagen"
    exit 1
}
ok "Python 3.11 installiert: $(python3.11 --version)"

log "Schritt 4/9 (pip): pip für Python 3.11 einrichten..."
# ensurepip ist Debian-sicher – umgeht den RECORD-Datei-Konflikt mit apt-installierten Paketen
python3.11 -m ensurepip --upgrade || { fail "ensurepip fehlgeschlagen"; exit 1; }
# --ignore-installed überspringt apt-verwaltete Pakete ohne RECORD-Datei
python3.11 -m pip install --upgrade pip --ignore-installed || { fail "pip upgrade fehlgeschlagen"; exit 1; }
ok "pip installiert: $(python3.11 -m pip --version)"

log "Schritt 4/9 (deps): Basis-Pakete installieren..."
python3.11 -m pip install --upgrade setuptools wheel --ignore-installed || { fail "setuptools/wheel upgrade fehlgeschlagen"; exit 1; }
python3.11 -m pip install scikit-image --only-binary=:all: || { fail "scikit-image Installation fehlgeschlagen"; exit 1; }
ok "Python-Basis-Pakete installiert"

# ── 5. FORGE REPOSITORY ──────────────────────────────────────────────────────
log "Schritt 5/9: Forge Repository..."
cd /root
if [ ! -d "$WORKSPACE" ]; then
    log "Klone Forge Repository (kann 1-2 Min dauern)..."
    git clone https://github.com/lllyasviel/stable-diffusion-webui-forge.git || {
        fail "git clone fehlgeschlagen – Netzwerk-Problem oder GitHub nicht erreichbar?"
        exit 1
    }
    ok "Forge Repository geklont"
else
    ok "Forge Repository bereits vorhanden – überspringe Clone"
fi
cd "$WORKSPACE"

# ── 6. FORGE KONFIGURATION (webui-user.sh) ───────────────────────────────────
log "Schritt 6/9: webui-user.sh konfigurieren..."

# Fix 3: GPU-VRAM erkennen und FORGE_ARGS automatisch ergänzen
if command -v nvidia-smi &>/dev/null; then
    VRAM_GB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | awk '{print int($1/1024)}' | head -1)
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
    log "   GPU erkannt: $GPU_NAME (${VRAM_GB} GB VRAM)"
    if [ "$VRAM_GB" -le 8 ]; then
        AUTO_VRAM_ARGS="--medvram"
        warn "   Wenig VRAM (${VRAM_GB}GB) – setze --medvram automatisch"
    elif [ "$VRAM_GB" -le 12 ]; then
        AUTO_VRAM_ARGS="--medvram-sdxl"
        warn "   Mittleres VRAM (${VRAM_GB}GB) – setze --medvram-sdxl automatisch"
    else
        AUTO_VRAM_ARGS=""
        ok "   Ausreichend VRAM (${VRAM_GB}GB) – keine VRAM-Einschränkung nötig"
    fi
else
    warn "   nvidia-smi nicht gefunden – GPU-Erkennung übersprungen"
    AUTO_VRAM_ARGS=""
fi

# FORGE_ARGS aus Template + Auto-VRAM-Args kombinieren
BASE_ARGS="${FORGE_ARGS:---listen --port 7860 --theme dark --no-download-sd-model --xformers}"
RESOLVED_FORGE_ARGS="${BASE_ARGS} ${AUTO_VRAM_ARGS}"

cat > "$WORKSPACE/webui-user.sh" << WEBUI_CFG
#!/bin/bash
# Automatisch generiert von vast-sd-forge-provisioning.sh
# Argumente: FORGE_ARGS (Template) + automatische GPU-Erkennung
export python_cmd="python3.11"
export COMMANDLINE_ARGS="${RESOLVED_FORGE_ARGS}"
WEBUI_CFG
chmod +x "$WORKSPACE/webui-user.sh"
ok "webui-user.sh geschrieben mit Args: ${RESOLVED_FORGE_ARGS}"

# ── 7. DOWNLOAD-FUNKTION ─────────────────────────────────────────────────────
download_model() {
    local DEST_DIR="$1"
    local NAME="$2"
    local SOURCE="$3"

    mkdir -p "$DEST_DIR"
    local DEST_FILE="$DEST_DIR/$NAME"

    if [ -f "$DEST_FILE" ] && [ "$(stat -c%s "$DEST_FILE")" -gt 1048576 ]; then
        log "⏭️  Überspringe (bereits vorhanden): $NAME ($(du -sh "$DEST_FILE" | cut -f1))"
        return 0
    fi

    if [[ "$SOURCE" =~ ^[0-9]+$ ]]; then
        log "⬇️  Civitai ID $SOURCE → $NAME"
        HTTP_CODE=$(curl -L \
            -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0" \
            -w "%{http_code}" --silent \
            "https://civitai.com/api/download/models/${SOURCE}?token=${CIVITAI_API_KEY}" \
            --output "$DEST_FILE")
        if [ "$HTTP_CODE" != "200" ] || [ ! -s "$DEST_FILE" ]; then
            fail "Civitai-Download fehlgeschlagen (HTTP $HTTP_CODE): $NAME"
            fail "  → ID $SOURCE gültig? CIVITAI_API_KEY gesetzt? Modell eingeschränkt?"
            rm -f "$DEST_FILE"; return 1
        fi

    elif [[ "$SOURCE" == HF_GATED:* ]]; then
        local HF_PATH="${SOURCE#HF_GATED:}"
        log "⬇️  HuggingFace Gated: $NAME"
        if [ -z "${HF_TOKEN:-}" ]; then
            fail "HF_TOKEN nicht gesetzt – $NAME wird übersprungen."
            fail "  → HF_TOKEN im vast.ai Account-Level setzen."
            return 1
        fi
        HTTP_CODE=$(curl -L \
            -H "Authorization: Bearer ${HF_TOKEN}" \
            -w "%{http_code}" --silent \
            "https://huggingface.co/${HF_PATH}" \
            --output "$DEST_FILE")
        if [ "$HTTP_CODE" != "200" ] || [ ! -s "$DEST_FILE" ]; then
            fail "HuggingFace-Download fehlgeschlagen (HTTP $HTTP_CODE): $NAME"
            fail "  → Lizenz auf huggingface.co akzeptiert? HF_TOKEN gültig?"
            rm -f "$DEST_FILE"; return 1
        fi

    else
        log "⬇️  URL → $NAME"
        if ! aria2c \
            --console-log-level=warn \
            -x 16 -s 16 -k 1M \
            --allow-overwrite=true \
            --max-tries=3 --retry-wait=5 \
            -o "$NAME" -d "$DEST_DIR" \
            "$SOURCE"; then
            fail "aria2c-Download fehlgeschlagen: $NAME"
            fail "  → URL erreichbar? Netzwerk stabil?"
            return 1
        fi
    fi

    ok "$NAME heruntergeladen ($(du -sh "$DEST_FILE" | cut -f1))"
}

# ── 8. MODELLE & EXTENSIONS ───────────────────────────────────────────────────
log "Schritt 7/9: Modell-Downloads starten (${#DOWNLOADS[@]} Dateien)..."
FAILED_DOWNLOADS=()

for entry in "${DOWNLOADS[@]}"; do
    IFS='|' read -r DEST NAME SRC <<< "$entry"
    download_model "$DEST" "$NAME" "$SRC" || FAILED_DOWNLOADS+=("$NAME")
done

if [ ${#FAILED_DOWNLOADS[@]} -gt 0 ]; then
    warn "${#FAILED_DOWNLOADS[@]} Downloads fehlgeschlagen:"
    for f in "${FAILED_DOWNLOADS[@]}"; do warn "   - $f"; done
    warn "Forge wird trotzdem gestartet – fehlende Modelle manuell nachladen."
else
    ok "Alle ${#DOWNLOADS[@]} Modelle erfolgreich heruntergeladen"
fi

log "Schritt 8/9: Extensions installieren (${#EXTENSIONS[@]} Repos)..."
mkdir -p "$WORKSPACE/extensions"
cd "$WORKSPACE/extensions"

for repo in "${EXTENSIONS[@]}"; do
    dir_name=$(basename "$repo" .git)
    if [ ! -d "$dir_name" ]; then
        log "Klone Extension: $dir_name"
        git clone "$repo" || warn "Extension konnte nicht geklont werden: $repo"
    else
        log "⏭️  Extension bereits vorhanden: $dir_name"
    fi
done
ok "Extensions installiert"

# ── Sentinel setzen: Provisioning erfolgreich abgeschlossen ──────────────────
echo "Abgeschlossen am $(date '+%Y-%m-%d %H:%M:%S')" > "$SENTINEL"
ok "Sentinel gesetzt: $SENTINEL"

# ── 9. FORGE STARTEN (Restart-Loop) ──────────────────────────
echo "[$(date +%T)] Schritt 9/9: Starte Forge..."

# pip auf kompatiblem Stand halten (pip 26+ bricht CLIP-Build)
"$WORKSPACE/venv/bin/python" -m pip install "pip<25" setuptools wheel \
    --quiet 2>/dev/null || true

bash webui.sh -f

log "Schritt 9/9: Starte Forge..."
log "   GPU:        ${GPU_NAME:-unbekannt} (${VRAM_GB:-?}GB VRAM)"
log "   Python:     $(python3.11 --version)"
log "   Args:       ${RESOLVED_FORGE_ARGS}"
log "   Log-Datei:  $LOG_FILE"

cd "$WORKSPACE"

while true; do
    bash webui.sh
    EXIT_CODE=$?
    warn "Forge beendet (Exit-Code: $EXIT_CODE) – Neustart in 10 Sekunden..."
    sleep 10
done
