#!/bin/bash

# ==============================================================================
# 🚀 VAST.AI PROVISIONING SCRIPT – SD-FORGE (vastai/sd-forge:neo Image)
# Dieses Script wird vom Image automatisch aufgerufen.
# Forge startet danach automatisch via supervisorctl – KEIN webui.sh nötig!
# ==============================================================================

set -euo pipefail

# ── Log-Funktionen ─────────────────────────────────────────────────────────
log()  { echo "[$(date '+%H:%M:%S')] $*"; }
ok()   { echo "[$(date '+%H:%M:%S')] ✅ $*"; }
warn() { echo "[$(date '+%H:%M:%S')] ⚠️  $*"; }
fail() { echo "[$(date '+%H:%M:%S')] ❌ FEHLER: $*" >&2; }

LOG_FILE="/var/log/provisioning.log"
SENTINEL="${WORKSPACE}/.provisioning_done"

exec > >(tee -a "$LOG_FILE") 2>&1
log "--- 🚀 Starte SD-Forge Provisioning Script ---"

# ── Idempotenz – bei Neustart überspringen ────────────────────────────────
if [ -f "$SENTINEL" ]; then
    log "✅ Provisioning bereits abgeschlossen ($(cat $SENTINEL)) – überspringe."
    exit 0
fi

# ── Workspace ──────────────────────────────────────────────────────────────
# vastai/sd-forge:neo Image nutzt /workspace/
FORGE_ROOT="${WORKSPACE}/stable-diffusion-webui-forge"
log "Forge Root: $FORGE_ROOT"

# ── Tools sicherstellen ────────────────────────────────────────────────────
if ! command -v aria2c &>/dev/null; then
    log "Installiere aria2..."
    apt-get install -y -qq aria2 || { fail "aria2 Installation fehlgeschlagen"; exit 1; }
fi

# ── Modell-Konfiguration laden ─────────────────────────────────────────────
log "Lade Modell-Konfiguration von GitHub..."
if ! source <(curl -fsSL \
  -H "Authorization: token ${GITHUB_PAT}" \
  "https://raw.githubusercontent.com/hondo100/vast-sd-provision/main/model-list.sh?$(date +%s)"); then
    fail "Konnte model-list.sh nicht laden."
    exit 1
fi
ok "model-list.sh geladen (${#DOWNLOADS[@]} Modelle, ${#EXTENSIONS[@]} Extensions)"

# ── Download-Funktion ──────────────────────────────────────────────────────
download_model() {
    local DEST_DIR="$1"
    local NAME="$2"
    local SOURCE="$3"

    # Pfade auf /workspace/ umschreiben falls noch /root/ drin steht
    DEST_DIR="${DEST_DIR/\/root\/stable-diffusion-webui-forge/$FORGE_ROOT}"

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
            rm -f "$DEST_FILE"; return 1
        fi

    elif [[ "$SOURCE" == HF_GATED:* ]]; then
        local HF_PATH="${SOURCE#HF_GATED:}"
        log "⬇️  HuggingFace Gated: $NAME"
        if [ -z "${HF_TOKEN:-}" ]; then
            fail "HF_TOKEN nicht gesetzt – $NAME wird übersprungen."
            return 1
        fi
        HTTP_CODE=$(curl -L \
            -H "Authorization: Bearer ${HF_TOKEN}" \
            -w "%{http_code}" --silent \
            "https://huggingface.co/${HF_PATH}" \
            --output "$DEST_FILE")
        if [ "$HTTP_CODE" != "200" ] || [ ! -s "$DEST_FILE" ]; then
            fail "HuggingFace-Download fehlgeschlagen (HTTP $HTTP_CODE): $NAME"
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
            return 1
        fi
    fi

    ok "$NAME heruntergeladen ($(du -sh "$DEST_FILE" | cut -f1))"
}

# ── Modelle herunterladen ──────────────────────────────────────────────────
log "Modell-Downloads starten (${#DOWNLOADS[@]} Dateien)..."
FAILED_DOWNLOADS=()

for entry in "${DOWNLOADS[@]}"; do
    IFS='|' read -r DEST NAME SRC <<< "$entry"
    download_model "$DEST" "$NAME" "$SRC" || FAILED_DOWNLOADS+=("$NAME")
done

if [ ${#FAILED_DOWNLOADS[@]} -gt 0 ]; then
    warn "${#FAILED_DOWNLOADS[@]} Downloads fehlgeschlagen:"
    for f in "${FAILED_DOWNLOADS[@]}"; do warn "   - $f"; done
else
    ok "Alle ${#DOWNLOADS[@]} Modelle erfolgreich heruntergeladen"
fi

# ── Extensions installieren ────────────────────────────────────────────────
log "Extensions installieren (${#EXTENSIONS[@]} Repos)..."
mkdir -p "$FORGE_ROOT/extensions"
cd "$FORGE_ROOT/extensions"

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

# ── Sentinel setzen ────────────────────────────────────────────────────────
echo "Abgeschlossen am $(date '+%Y-%m-%d %H:%M:%S')" > "$SENTINEL"
ok "Sentinel gesetzt: $SENTINEL"
ok "Provisioning abgeschlossen – Forge startet automatisch via supervisorctl."

exit 0
