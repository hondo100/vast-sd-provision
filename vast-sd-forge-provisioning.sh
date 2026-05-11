#!/bin/bash

# ==============================================================================
# 🚀 VAST.AI PROVISIONING SCRIPT – SD-FORGE (vastai/sd-forge:neo Image)
# Dieses Script wird vom Image automatisch aufgerufen.
# Forge startet danach automatisch via supervisorctl – KEIN webui.sh nötig!
# ==============================================================================

set -euo pipefail

# ── Log-Funktionen ─────────────────────────────────────────────────────────
log()     { echo "[$(date '+%H:%M:%S')] 📋 $*"; }
ok()      { echo "[$(date '+%H:%M:%S')] ✅ $*"; }
warn()    { echo "[$(date '+%H:%M:%S')] ⚠️  $*"; }
fail()    { echo "[$(date '+%H:%M:%S')] ❌ FEHLER: $*" >&2; }
section() { echo ""; echo "[$(date '+%H:%M:%S')] ══════════════════════════════════════"; \
            echo "[$(date '+%H:%M:%S')] 🔷 $*"; \
            echo "[$(date '+%H:%M:%S')] ══════════════════════════════════════"; }
step()    { echo "[$(date '+%H:%M:%S')] ▶️  $*"; }
debug()   { echo "[$(date '+%H:%M:%S')] 🔍 DEBUG: $*"; }

LOG_FILE="/var/log/provisioning.log"
SENTINEL="${WORKSPACE}/.provisioning_done"

exec > >(tee -a "$LOG_FILE") 2>&1

section "STARTE SD-FORGE PROVISIONING"
log "Hostname:    $(hostname)"
log "Datum/Zeit:  $(date)"
log "User:        $(whoami)"
log "WORKSPACE:   ${WORKSPACE}"
log "Log-Datei:   $LOG_FILE"
log "Script PID:  $$"

# ── Idempotenz – bei Neustart überspringen ────────────────────────────────
section "IDEMPOTENZ-CHECK"
if [ -f "$SENTINEL" ]; then
    log "✅ Provisioning bereits abgeschlossen ($(cat $SENTINEL)) – überspringe."
    log "   Lösche $SENTINEL manuell um das Provisioning erneut auszuführen."
    exit 0
fi
log "Kein Sentinel gefunden – starte vollständiges Provisioning."

# ── Workspace ──────────────────────────────────────────────────────────────
section "WORKSPACE SETUP"
FORGE_ROOT="${WORKSPACE}/stable-diffusion-webui-forge"
log "Forge Root:  $FORGE_ROOT"

step "Prüfe Workspace-Verzeichnis..."
if [ ! -d "${WORKSPACE}" ]; then
    fail "WORKSPACE-Verzeichnis existiert nicht: ${WORKSPACE}"
    exit 1
fi
ok "Workspace vorhanden: ${WORKSPACE}"

debug "Workspace-Inhalt:"
ls -la "${WORKSPACE}" | while read line; do debug "  $line"; done

step "Prüfe verfügbaren Speicherplatz..."
df -h "${WORKSPACE}" | while read line; do log "  $line"; done

# ── Tools sicherstellen ────────────────────────────────────────────────────
section "TOOL-INSTALLATION"
step "Prüfe aria2c..."
if ! command -v aria2c &>/dev/null; then
    log "aria2c nicht gefunden – installiere aria2..."
    apt-get install -y -qq aria2 \
        && ok "aria2 erfolgreich installiert" \
        || { fail "aria2 Installation fehlgeschlagen (apt-get exit code: $?)"; exit 1; }
else
    ok "aria2c bereits vorhanden: $(aria2c --version | head -1)"
fi

step "Prüfe git..."
if ! command -v git &>/dev/null; then
    fail "git nicht gefunden – kann nicht fortfahren"
    exit 1
fi
ok "git vorhanden: $(git --version)"

step "Prüfe curl..."
if ! command -v curl &>/dev/null; then
    fail "curl nicht gefunden – kann nicht fortfahren"
    exit 1
fi
ok "curl vorhanden: $(curl --version | head -1)"

step "Prüfe python..."
if ! command -v python &>/dev/null; then
    fail "python nicht gefunden – kann nicht fortfahren"
    exit 1
fi
ok "python vorhanden: $(python --version)"

# ── Forge klonen ──────────────────────────────────────────────────────────
section "FORGE INSTALLATION"
step "Prüfe ob Forge vorhanden (launch.py)..."
if [ ! -f "$FORGE_ROOT/launch.py" ]; then
    warn "launch.py nicht gefunden in $FORGE_ROOT"
    log "Starte Forge Neo Clone von GitHub..."
    log "  Quelle: https://github.com/Haoming02/sd-webui-forge-classic (Branch: neo)"
    log "  Ziel:   /tmp/forge-neo"

    mkdir -p "$FORGE_ROOT"
    debug "Inhalt von $FORGE_ROOT vor Clone:"
    ls -la "$FORGE_ROOT" | while read line; do debug "  $line"; done

    if git clone -b neo \
        https://github.com/Haoming02/sd-webui-forge-classic.git \
        /tmp/forge-neo; then
        ok "Clone erfolgreich"
        debug "Größe /tmp/forge-neo: $(du -sh /tmp/forge-neo | cut -f1)"
    else
        fail "git clone fehlgeschlagen (exit code: $?)"
        fail "Prüfe Netzwerkverbindung und GitHub-Verfügbarkeit"
        exit 1
    fi

    step "Kopiere Forge-Dateien in $FORGE_ROOT (erhält bestehende model-Ordner)..."
    cp -r /tmp/forge-neo/. "$FORGE_ROOT/"
    ok "Kopieren abgeschlossen"

    step "Räume temporäres Clone-Verzeichnis auf..."
    rm -rf /tmp/forge-neo
    ok "Aufgeräumt"

    step "Verifiziere Installation..."
    if [ -f "$FORGE_ROOT/launch.py" ]; then
        ok "Forge Neo erfolgreich installiert"
        debug "Forge-Root-Inhalt:"
        ls -la "$FORGE_ROOT" | while read line; do debug "  $line"; done
    else
        fail "launch.py fehlt nach Clone – Installation fehlgeschlagen"
        exit 1
    fi
else
    ok "Forge bereits vorhanden: $FORGE_ROOT/launch.py"
    debug "Forge-Version:"
    grep -m1 "version" "$FORGE_ROOT/modules/shared_info.py" 2>/dev/null \
        | while read line; do debug "  $line"; done || true
fi

# ── Persistentes venv ─────────────────────────────────────────────────────
section "PERSISTENTES PYTHON VENV"
VENV_DIR="${WORKSPACE}/venv"
step "Prüfe venv unter $VENV_DIR..."
if [ ! -d "$VENV_DIR" ]; then
    log "venv nicht vorhanden – erstelle persistentes venv..."
    log "  Pfad: $VENV_DIR"
    if python -m venv "$VENV_DIR"; then
        ok "venv erfolgreich erstellt"
    else
        fail "python -m venv fehlgeschlagen (exit code: $?)"
        fail "Prüfe Python-Installation: $(python --version)"
        exit 1
    fi
else
    ok "Persistentes venv bereits vorhanden: $VENV_DIR"
    debug "venv Python: $("$VENV_DIR/bin/python" --version 2>&1)"
fi

step "Prüfe FORGE_ARGS auf --venv-dir..."
if [[ "${FORGE_ARGS:-}" != *"--venv-dir"* ]]; then
    export FORGE_ARGS="${FORGE_ARGS:-} --venv-dir ${VENV_DIR}"
    ok "--venv-dir zu FORGE_ARGS hinzugefügt"
    log "  Aktuelle FORGE_ARGS: $FORGE_ARGS"
else
    ok "--venv-dir bereits in FORGE_ARGS enthalten – kein Override nötig"
    debug "Aktuelle FORGE_ARGS: $FORGE_ARGS"
fi

# ── Umgebungsvariablen prüfen ─────────────────────────────────────────────
section "UMGEBUNGSVARIABLEN"
step "Prüfe erforderliche Tokens..."

if [ -z "${GITHUB_PAT:-}" ]; then
    fail "GITHUB_PAT ist nicht gesetzt – model-list.sh kann nicht geladen werden"
    exit 1
fi
ok "GITHUB_PAT: gesetzt (${#GITHUB_PAT} Zeichen)"

if [ -z "${CIVITAI_API_KEY:-}" ]; then
    warn "CIVITAI_API_KEY nicht gesetzt – Civitai-Downloads werden fehlschlagen"
else
    ok "CIVITAI_API_KEY: gesetzt (${#CIVITAI_API_KEY} Zeichen)"
fi

if [ -z "${HF_TOKEN:-}" ]; then
    warn "HF_TOKEN nicht gesetzt – HuggingFace Gated Downloads werden fehlschlagen"
else
    ok "HF_TOKEN: gesetzt (${#HF_TOKEN} Zeichen)"
fi

# ── Modell-Konfiguration laden ─────────────────────────────────────────────
section "MODELL-KONFIGURATION"
MODEL_LIST_URL="https://raw.githubusercontent.com/hondo100/vast-sd-provision/main/model-list.sh?$(date +%s)"
step "Lade model-list.sh von GitHub..."
log "  URL: $MODEL_LIST_URL"

if ! source <(curl -fsSL \
  -H "Authorization: token ${GITHUB_PAT}" \
  "$MODEL_LIST_URL"); then
    fail "Konnte model-list.sh nicht laden"
    fail "Mögliche Ursachen:"
    fail "  - GITHUB_PAT ungültig oder abgelaufen"
    fail "  - Repository nicht erreichbar"
    fail "  - Datei nicht gefunden"
    exit 1
fi

ok "model-list.sh geladen"
log "  Modelle:    ${#DOWNLOADS[@]}"
log "  Extensions: ${#EXTENSIONS[@]}"

debug "Modell-Liste:"
for entry in "${DOWNLOADS[@]}"; do
    IFS='|' read -r DEST NAME SRC <<< "$entry"
    debug "  [$NAME] → $DEST"
done

# ── Download-Funktion ──────────────────────────────────────────────────────
download_model() {
    local DEST_DIR="$1"
    local NAME="$2"
    local SOURCE="$3"

    DEST_DIR="${DEST_DIR/\/root\/stable-diffusion-webui-forge/$FORGE_ROOT}"
    mkdir -p "$DEST_DIR"
    local DEST_FILE="$DEST_DIR/$NAME"

    step "Verarbeite: $NAME"
    log "    Ziel:   $DEST_FILE"
    log "    Quelle: ${SOURCE:0:60}..."

    if [ -f "$DEST_FILE" ] && [ "$(stat -c%s "$DEST_FILE")" -gt 1048576 ]; then
        log "    ⏭️  Bereits vorhanden ($(du -sh "$DEST_FILE" | cut -f1)) – überspringe"
        return 0
    elif [ -f "$DEST_FILE" ]; then
        warn "    Datei existiert aber ist zu klein ($(stat -c%s "$DEST_FILE") Bytes) – lade neu"
        rm -f "$DEST_FILE"
    fi

    if [[ "$SOURCE" =~ ^[0-9]+$ ]]; then
        log "    Methode: Civitai API (ID: $SOURCE)"
        HTTP_CODE=$(curl -L \
            -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0" \
            -w "%{http_code}" --silent \
            "https://civitai.com/api/download/models/${SOURCE}?token=${CIVITAI_API_KEY}" \
            --output "$DEST_FILE")
        if [ "$HTTP_CODE" != "200" ] || [ ! -s "$DEST_FILE" ]; then
            fail "    Civitai-Download fehlgeschlagen"
            fail "    HTTP-Code: $HTTP_CODE"
            fail "    Civitai-ID: $SOURCE"
            fail "    Prüfe CIVITAI_API_KEY und ob das Modell noch verfügbar ist"
            rm -f "$DEST_FILE"; return 1
        fi

    elif [[ "$SOURCE" == HF_GATED:* ]]; then
        local HF_PATH="${SOURCE#HF_GATED:}"
        log "    Methode: HuggingFace Gated"
        log "    HF-Pfad: $HF_PATH"
        if [ -z "${HF_TOKEN:-}" ]; then
            fail "    HF_TOKEN nicht gesetzt – $NAME wird übersprungen"
            return 1
        fi
        HTTP_CODE=$(curl -L \
            -H "Authorization: Bearer ${HF_TOKEN}" \
            -w "%{http_code}" --silent \
            "https://huggingface.co/${HF_PATH}" \
            --output "$DEST_FILE")
        if [ "$HTTP_CODE" != "200" ] || [ ! -s "$DEST_FILE" ]; then
            fail "    HuggingFace-Download fehlgeschlagen"
            fail "    HTTP-Code: $HTTP_CODE"
            fail "    HF-Pfad: $HF_PATH"
            fail "    Prüfe HF_TOKEN und Modell-Zugriffsrechte"
            rm -f "$DEST_FILE"; return 1
        fi

    else
        log "    Methode: aria2c (URL)"
        if ! aria2c \
            --console-log-level=warn \
            -x 16 -s 16 -k 1M \
            --allow-overwrite=true \
            --max-tries=3 --retry-wait=5 \
            -o "$NAME" -d "$DEST_DIR" \
            "$SOURCE"; then
            fail "    aria2c-Download fehlgeschlagen (exit code: $?)"
            fail "    URL: $SOURCE"
            fail "    Ziel: $DEST_FILE"
            return 1
        fi
    fi

    if [ -f "$DEST_FILE" ]; then
        ok "    $NAME heruntergeladen ($(du -sh "$DEST_FILE" | cut -f1))"
    else
        fail "    Datei nach Download nicht gefunden: $DEST_FILE"
        return 1
    fi
}

# ── Modelle herunterladen ──────────────────────────────────────────────────
section "MODELL-DOWNLOADS (${#DOWNLOADS[@]} Dateien)"
FAILED_DOWNLOADS=()
DOWNLOAD_COUNT=0

for entry in "${DOWNLOADS[@]}"; do
    IFS='|' read -r DEST NAME SRC <<< "$entry"
    DOWNLOAD_COUNT=$((DOWNLOAD_COUNT + 1))
    log "Modell $DOWNLOAD_COUNT/${#DOWNLOADS[@]}: $NAME"
    download_model "$DEST" "$NAME" "$SRC" || FAILED_DOWNLOADS+=("$NAME")
done

log ""
if [ ${#FAILED_DOWNLOADS[@]} -gt 0 ]; then
    warn "${#FAILED_DOWNLOADS[@]} von ${#DOWNLOADS[@]} Downloads fehlgeschlagen:"
    for f in "${FAILED_DOWNLOADS[@]}"; do warn "  - $f"; done
    warn "Provisioning wird trotzdem fortgesetzt."
else
    ok "Alle ${#DOWNLOADS[@]} Modelle erfolgreich heruntergeladen"
fi

step "Speicherverbrauch nach Downloads:"
du -sh "$FORGE_ROOT/models/"* 2>/dev/null | while read line; do log "  $line"; done

# ── Extensions installieren ────────────────────────────────────────────────
section "EXTENSIONS (${#EXTENSIONS[@]} Repos)"
mkdir -p "$FORGE_ROOT/extensions"
cd "$FORGE_ROOT/extensions"
log "Extensions-Verzeichnis: $FORGE_ROOT/extensions"
EXT_COUNT=0

for repo in "${EXTENSIONS[@]}"; do
    EXT_COUNT=$((EXT_COUNT + 1))
    dir_name=$(basename "$repo" .git)
    log "Extension $EXT_COUNT/${#EXTENSIONS[@]}: $dir_name"
    log "  Repo: $repo"
    if [ ! -d "$dir_name" ]; then
        if git clone "$repo"; then
            ok "  $dir_name geklont"
        else
            warn "  $dir_name konnte nicht geklont werden (exit code: $?)"
            warn "  Prüfe ob die URL erreichbar ist: $repo"
        fi
    else
        log "  ⏭️  Bereits vorhanden – überspringe"
    fi
done
ok "Extensions-Schritt abgeschlossen"

# ── Abschluss-Check ───────────────────────────────────────────────────────
section "ABSCHLUSS-CHECK"
step "Prüfe kritische Dateien..."
[ -f "$FORGE_ROOT/launch.py" ]    && ok "launch.py vorhanden"    || fail "launch.py FEHLT!"
[ -d "$FORGE_ROOT/models" ]       && ok "models/ vorhanden"      || warn "models/ fehlt"
[ -d "$FORGE_ROOT/extensions" ]   && ok "extensions/ vorhanden"  || warn "extensions/ fehlt"
[ -d "$VENV_DIR" ]                && ok "venv vorhanden"         || warn "venv fehlt"

step "Gesamter Speicherverbrauch Workspace:"
du -sh "${WORKSPACE}"/* 2>/dev/null | while read line; do log "  $line"; done

# ── Sentinel setzen ────────────────────────────────────────────────────────
section "FERTIG"
echo "Abgeschlossen am $(date '+%Y-%m-%d %H:%M:%S')" > "$SENTINEL"
ok "Sentinel gesetzt: $SENTINEL"
ok "Gesamtdauer: $((SECONDS / 60)) Minuten $((SECONDS % 60)) Sekunden"
ok "Provisioning abgeschlossen – Forge startet automatisch via supervisorctl."
log "Forge-Logs: supervisorctl tail -f forge  oder  tail -f /var/log/forge.log"

exit 0
