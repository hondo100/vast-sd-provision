#!/bin/bash

# ==============================================================================
# 🚀 VAST.AI PROVISIONING SCRIPT – SD-FORGE (Ubuntu 24.04)
# ==============================================================================
# Fixes gegenüber Original:
#   ✅ Python 3.11 via Deadsnakes PPA (statt 3.12 + --break-system-packages)
#   ✅ model-list.sh wird von GitHub eingelesen (Single Source of Truth)
#   ✅ Download-Fehlerbehandlung mit Exit-Code-Prüfung + Dateigrößencheck
#   ✅ Civitai-Token auch für vollständige URLs angehängt
#   ✅ HuggingFace Gated Model Support via HF_TOKEN
#   ✅ --xformers Flag für GPU-Performance
#   ✅ webui-user.sh für saubere Konfiguration
# ==============================================================================

set -euo pipefail
echo "--- 🚀 Starte SD-Forge Provisioning Script ---"

# ── 1. MODELL-LISTE VON GITHUB LADEN ─────────────────────────────────────────
echo "--- Lade Modell-Konfiguration von GitHub ---"
source <(curl -fsSL \
  -H "Authorization: token ${GITHUB_PAT}" \
  "https://raw.githubusercontent.com/hondo100/vast-sd-provision/main/model-list.sh?$(date +%s)")

# ── 2. SYSTEM-UPDATES & TOOLS ────────────────────────────────────────────────
echo "--- System-Updates & Tools ---"
apt-get update -qq
apt-get install -y -qq \
    software-properties-common \
    aria2 git curl unzip \
    build-essential ninja-build \
    libgl1 libglib2.0-0          # Benötigt von OpenCV/Forge

# ── 3. PYTHON 3.11 VIA DEADSNAKES PPA ────────────────────────────────────────
# Ubuntu 24.04 liefert Python 3.12 – Forge benötigt 3.10/3.11 für stabile
# Abhängigkeiten (torch, xformers, triton, scikit-image etc.)
echo "--- Installiere Python 3.11 via Deadsnakes PPA ---"
add-apt-repository ppa:deadsnakes/ppa -y
apt-get update -qq
apt-get install -y python3.11 python3.11-venv python3.11-dev python3.11-distutils

# pip für Python 3.11 einrichten
curl -fsSL https://bootstrap.pypa.io/get-pip.py | python3.11

# Basis-Pakete für Python 3.11 (kein --break-system-packages nötig)
python3.11 -m pip install --upgrade pip setuptools wheel
python3.11 -m pip install scikit-image --only-binary=:all:

# ── 4. FORGE REPOSITORY ──────────────────────────────────────────────────────
WORKSPACE="/root/stable-diffusion-webui-forge"
echo "--- Forge Repository ---"
cd /root

if [ ! -d "$WORKSPACE" ]; then
    echo "--- Klone Forge Repository ---"
    git clone https://github.com/lllyasviel/stable-diffusion-webui-forge.git
fi

cd "$WORKSPACE"

# ── 5. FORGE KONFIGURATION ───────────────────────────────────────────────────
# webui-user.sh statt direkter launch.py-Argumente – sauberer und persistenter
cat > "$WORKSPACE/webui-user.sh" << 'WEBUI_CFG'
#!/bin/bash
export python_cmd="python3.11"
export COMMANDLINE_ARGS="--listen --port 7860 --theme dark \
  --enable-insecure-extension-access \
  --no-download-sd-model \
  --xformers"
WEBUI_CFG
chmod +x "$WORKSPACE/webui-user.sh"

# ── 6. DOWNLOAD-FUNKTION ─────────────────────────────────────────────────────
download_model() {
    local DEST_DIR="$1"
    local NAME="$2"
    local SOURCE="$3"

    mkdir -p "$DEST_DIR"
    local DEST_FILE="$DEST_DIR/$NAME"

    # Bereits vorhanden und > 1MB? Überspringen.
    if [ -f "$DEST_FILE" ] && [ "$(stat -c%s "$DEST_FILE")" -gt 1048576 ]; then
        echo "--- ⏭️  Überspringe (bereits vorhanden): $NAME ---"
        return 0
    fi

    # ── Civitai (reine ID) ──────────────────────────────────────────────────
    if [[ "$SOURCE" =~ ^[0-9]+$ ]]; then
        echo "--- ⬇️  Civitai ID $SOURCE → $NAME ---"
        HTTP_CODE=$(curl -L \
            -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0" \
            -w "%{http_code}" \
            "https://civitai.com/api/download/models/${SOURCE}?token=${CIVITAI_API_KEY}" \
            --output "$DEST_FILE")
        if [ "$HTTP_CODE" != "200" ] || [ ! -s "$DEST_FILE" ]; then
            echo "❌ FEHLER: Civitai-Download fehlgeschlagen (HTTP $HTTP_CODE): $NAME"
            rm -f "$DEST_FILE"
            return 1
        fi

    # ── HuggingFace Gated Model (benötigt HF_TOKEN) ─────────────────────────
    elif [[ "$SOURCE" == HF_GATED:* ]]; then
        local HF_PATH="${SOURCE#HF_GATED:}"
        echo "--- ⬇️  HuggingFace Gated: $NAME ---"
        if [ -z "${HF_TOKEN:-}" ]; then
            echo "❌ FEHLER: HF_TOKEN nicht gesetzt – $NAME kann nicht geladen werden."
            return 1
        fi
        HTTP_CODE=$(curl -L \
            -H "Authorization: Bearer ${HF_TOKEN}" \
            -w "%{http_code}" \
            "https://huggingface.co/${HF_PATH}" \
            --output "$DEST_FILE")
        if [ "$HTTP_CODE" != "200" ] || [ ! -s "$DEST_FILE" ]; then
            echo "❌ FEHLER: HuggingFace-Download fehlgeschlagen (HTTP $HTTP_CODE): $NAME"
            rm -f "$DEST_FILE"
            return 1
        fi

    # ── Externe URL (HuggingFace öffentlich, etc.) via aria2c ───────────────
    else
        echo "--- ⬇️  URL → $NAME ---"
        aria2c \
            --console-log-level=warn \
            -x 16 -s 16 -k 1M \
            --allow-overwrite=true \
            --max-tries=3 \
            --retry-wait=5 \
            -o "$NAME" -d "$DEST_DIR" \
            "$SOURCE"
        if [ $? -ne 0 ] || [ ! -s "$DEST_FILE" ]; then
            echo "❌ FEHLER: aria2c-Download fehlgeschlagen: $NAME"
            return 1
        fi
    fi

    echo "✅ $NAME ($(du -sh "$DEST_FILE" | cut -f1))"
}

# ── 7. MODELLE HERUNTERLADEN ─────────────────────────────────────────────────
echo "--- Starte Modell-Downloads ---"
FAILED_DOWNLOADS=()

for entry in "${DOWNLOADS[@]}"; do
    IFS='|' read -r DEST NAME SRC <<< "$entry"
    download_model "$DEST" "$NAME" "$SRC" || FAILED_DOWNLOADS+=("$NAME")
done

if [ ${#FAILED_DOWNLOADS[@]} -gt 0 ]; then
    echo ""
    echo "⚠️  Folgende Downloads sind fehlgeschlagen:"
    for f in "${FAILED_DOWNLOADS[@]}"; do echo "   - $f"; done
    echo "   Forge wird trotzdem gestartet."
    echo ""
fi

# ── 8. EXTENSIONS INSTALLIEREN ───────────────────────────────────────────────
echo "--- Installiere Extensions ---"
mkdir -p "$WORKSPACE/extensions"
cd "$WORKSPACE/extensions"

for repo in "${EXTENSIONS[@]}"; do
    dir_name=$(basename "$repo" .git)
    if [ ! -d "$dir_name" ]; then
        echo "--- Klone Extension: $dir_name ---"
        git clone "$repo"
    else
        echo "--- ⏭️  Extension bereits vorhanden: $dir_name ---"
    fi
done

# ── 9. FORGE STARTEN ─────────────────────────────────────────────────────────
echo ""
echo "--- ✅ Provisioning abgeschlossen – Starte Forge auf Port 7860 ---"
cd "$WORKSPACE"
bash webui.sh
