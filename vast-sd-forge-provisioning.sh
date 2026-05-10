#!/bin/bash

# ==============================================================================
# 🚀 VAST.AI PROVISIONING SCRIPT FOR SD-FORGE (UBUNTU 24.04 / PYTHON 3.12)
# ==============================================================================

echo "--- 🚀 Starte finales Provisioning Script ---"

# 1. SYSTEM-UPDATES & ESSENZIELLE TOOLS
# ------------------------------------------------------------------------------
apt-get update
apt-get install -y aria2 git curl unzip build-essential python3-dev ninja-build python-is-python3

# 2. PYTHON BUILD-UMGEBUNG REPARIEREN (Fix für Scikit-Image / Meson)
# ------------------------------------------------------------------------------
echo "--- Optimiere Python Umgebung für Forge ---"
python3 -m pip install --upgrade pip setuptools wheel --break-system-packages
# Vorinstallation von Scikit-Image als Binary, um Kompilierfehler zu vermeiden
python3 -m pip install scikit-image --only-binary=:all: --break-system-packages

# 3. VERZEICHNISSTRUKTUR ANLEGEN
# ------------------------------------------------------------------------------
WORKSPACE="/root/stable-diffusion-webui-forge"
cd /root

if [ ! -d "$WORKSPACE" ]; then
    echo "--- Klone Forge Repository ---"
    git clone https://github.com/lllyasviel/stable-diffusion-webui-forge.git
fi

cd "$WORKSPACE"

# 4. DOWNLOAD FUNKTION (Civitai via curl / Rest via aria2)
# ------------------------------------------------------------------------------
download_model() {
    local DEST_DIR="$1"
    local NAME="$2"
    local SOURCE="$3"

    mkdir -p "$DEST_DIR"

    # Prüfen, ob die Quelle eine Civitai-ID (nur Zahlen) ist
    if [[ "$SOURCE" =~ ^[0-9]+$ ]]; then
        echo "--- Lade Civitai ID: $SOURCE via curl: $NAME ---"
        curl -L -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0" \
             "https://civitai.com/api/download/models/${SOURCE}?token=$CIVITAI_API_KEY" \
             --output "$DEST_DIR/$NAME"
    else
        echo "--- Lade externe URL via aria2c: $NAME ---"
        aria2c --console-log-level=warn -x 16 -s 16 -k 1M --allow-overwrite=true \
               -o "$NAME" -d "$DEST_DIR" "${SOURCE}"
    fi
}

# 5. MODEL LISTE & DOWNLOADS
# ------------------------------------------------------------------------------
echo "--- Starte Model-Downloads ---"

# Checkpoints
download_model "$WORKSPACE/models/Stable-diffusion" "Juggernaut-XL-v9.safetensors" "357609"

# Loras
download_model "$WORKSPACE/models/Lora" "film_grain_cinematic.safetensors" "518040"
download_model "$WORKSPACE/models/Lora" "detail_tweaker_xl.safetensors" "135929"
download_model "$WORKSPACE/models/Lora" "real-vis-xl-enhancer.safetensors" "135010"
download_model "$WORKSPACE/models/Lora" "perfect_eyes_xl.safetensors" "128461"
download_model "$WORKSPACE/models/Lora" "skin_detail_xl.safetensors" "340833"

# Upscaler
download_model "$WORKSPACE/models/ESRGAN" "Siax_200k.pth" "2052724"

# 6. EXTENSIONS
# ------------------------------------------------------------------------------
echo "--- Installiere Extensions ---"
mkdir -p "$WORKSPACE/extensions"
cd "$WORKSPACE/extensions"

EXTENSIONS=(
    "https://github.com/tjm35/stable-diffusion-webui-wd14-tagger"
    "https://github.com/nonnonstop/sd-webui-aspect-ratio-helper"
    "https://github.com/Mikubill/sd-webui-controlnet"
)

for repo in "${EXTENSIONS[@]}"; do
    dir_name=$(basename "$repo")
    if [ ! -d "$dir_name" ]; then
        git clone "$repo"
    fi
done

# 7. FORGE STARTEN
# ------------------------------------------------------------------------------
echo "--- Starte Forge ---"
cd "$WORKSPACE"

# Forge Launch-Parameter für Vast.ai (ohne venv, da Docker)
python3 launch.py --listen --port 7860 --theme dark --enable-insecure-extension-access --no-download-sd-model
