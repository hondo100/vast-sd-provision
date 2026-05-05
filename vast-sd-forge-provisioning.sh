!/bin/bash
# =========================================================
# 1. KONFIGURATION & TOOLS
# =========================================================
TOKEN="${CIVITAI_TOKEN}"

echo "-------------------------------------------------------"
echo "START PROVISIONING: High-Speed 4K-Setup"
echo "-------------------------------------------------------"

# Schnell-Installation von aria2
apt-get update -qq && apt-get install -y -qq aria2

# Basis-Modelle
ID_JUGGERNAUT="453710"
ID_SVD_XT="290640"

# LORA-LISTE
LORAS=(
"135867:detail_tweaker_xl.safetensors"
"155700:skin_detail_xl.safetensors"
"121612:real-vis-xl-enhancer.safetensors"
"202640:film_grain_cinematic.safetensors"
"254051:perfect_eyes_xl.safetensors"
)

# Pfade (ai-dock)
BASE_PATH="/opt/stable-diffusion-webui-forge/models"
CHECKPOINT_DIR="$BASE_PATH/Stable-diffusion"
SVD_DIR="$BASE_PATH/svd"
LORA_DIR="$BASE_PATH/Lora"
UPSCALER_DIR="$BASE_PATH/ESRGAN"

mkdir -p "$CHECKPOINT_DIR" "$SVD_DIR" "$LORA_DIR" "$UPSCALER_DIR"

# =========================================================
# 2. HILFSFUNKTION FUER TURBO-DOWNLOADS
# =========================================================
function turbo_download() {
local id=$1
local dest=$2
local filename=$3
local url="https://civitai.com/api/download/models/$id"
local final_url=""

if [ -f "$dest/$filename" ]; then
echo ">> OK: $filename vorhanden."
else
echo ">> TURBO-START: $filename"

if [[ "$url" == *\?* ]]; then
final_url="${url}&token=${TOKEN}"
else
final_url="${url}?token=${TOKEN}"
fi

aria2c -x 16 -s 16 -k 1M --console-log-level=error --summary-interval=0 \
--check-certificate=false \
-d "$dest" -o "$filename" "$final_url" &
fi
}

# =========================================================
# 3. AUSFUEHRUNG (PARALLEL)
# =========================================================

# A. Hauptmodelle
turbo_download "$ID_JUGGERNAUT" "$CHECKPOINT_DIR" "juggernaut_xl.safetensors"
turbo_download "$ID_SVD_XT" "$SVD_DIR" "svd_xt_11.safetensors"

# B. LoRAs
echo "--- LoRAs werden parallel geladen ---"
for entry in "${LORAS[@]}"; do
IFS=":" read -r lora_id lora_name <<< "$entry"
turbo_download "$lora_id" "$LORA_DIR" "$lora_name"
done

# C. Upscaler
if [ ! -f "$UPSCALER_DIR/4x-UltraSharp.pth" ]; then
wget -q --show-progress -O "$UPSCALER_DIR/4x-UltraSharp.pth" \
"https://openmodeldb.info/models/4x-UltraSharp/download" &
fi

# =========================================================
# 4. FINALE
# =========================================================
echo "Warte auf Abschluss aller Downloads..."
wait

echo "-------------------------------------------------------"
echo "PROVISIONING BEENDET: System ist bereit!"
echo "READY TO GENERATE"
echo "-------------------------------------------------------"
