#!/bin/bash

# ==============================================================================
# 🚀 VAST.AI PROVISIONING SCRIPT – SD-FORGE (verbesserte Version)
# Features:
# - AI-Dock kompatibel
# - CUDA-sicher (CPU-Fallback)
# - Alle Bugs gefixt
# - Auto-Forge-Start
# ==============================================================================

set -euo pipefail

# ── Log-Funktionen ─────────────────────────────────────────────────────────
log()     { echo "[$(date '+%H:%M:%S')] 📋 $*"; }
ok()      { echo "[$(date '+%H:%M:%S')] ✅ $*"; }
warn()    { echo "[$(date '+%H:%M:%S')] ⚠️  $*"; }
fail()    { echo "[$(date '+%H:%M:%S')] ❌ FEHLER: $*" >&2; }
section() {
    echo ""
    echo "[$(date '+%H:%M:%S')] ══════════════════════════════════════"
    echo "[$(date '+%H:%M:%S')] 🔷 $*"
    echo "[$(date '+%H:%M:%S')] ══════════════════════════════════════"
}
step()    { echo "[$(date '+%H:%M:%S')] ▶️  $*"; }

# ── Logging ────────────────────────────────────────────────────────────────
LOG_FILE="/var/log/provisioning.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# ══════════════════════════════════════════════════════════════════════════════
section "WORKSPACE DETECTION"
step "Warte 60s auf /workspace..."
WAITED=0
while [ $WAITED -lt 60 ]; do
    if mount | grep -q '/workspace'; then
        export WORKSPACE=/workspace
        ok "Volume /workspace gemountet"
        break
    fi
    sleep 5; WAITED=$((WAITED + 5))
done

[ -d "${WORKSPACE:-/data}" ] || mkdir -p /data && export WORKSPACE=/data
FORGE_ROOT="${WORKSPACE}/stable-diffusion-webui-forge"
SENTINEL="${WORKSPACE}/.provisioning_done"

log "WORKSPACE: $WORKSPACE | FORGE_ROOT: $FORGE_ROOT"

# ── IDEMPOTENZ ─────────────────────────────────────────────────────────────
section "IDEMPOTENZ-CHECK"
[ -f "$SENTINEL" ] && {
    log "Bereits provisioned – skip"
    exit 0
}

# ── TOOLS ──────────────────────────────────────────────────────────────────
section "TOOLS"
command -v aria2c >/dev/null || {
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y aria2
    ok "aria2c installiert"
}

# ── FORGE CLONE ───────────────────────────────────────────────────────────
section "FORGE NEO"
[ -f "$FORGE_ROOT/launch.py" ] || {
    git clone -b neo https://github.com/Haoming02/sd-webui-forge-classic.git "$FORGE_ROOT"
    ok "Forge Neo geklont"
}

# ── TOKENS ─────────────────────────────────────────────────────────────────
[ -n "${GITHUB_PAT:-}" ] || fail "GITHUB_PAT fehlt"
[ -n "${CIVITAI_API_KEY:-}" ] || fail "CIVITAI_API_KEY fehlt"

# ── MODEL-LIST ────────────────────────────────────────────────────────────
section "MODELL-KONFIG"
source <(curl -fsSL -H "Authorization: token $GITHUB_PAT" \
    "https://raw.githubusercontent.com/hondo100/vast-sd-provision/main/model-list.sh?$(date +%s)") || fail "model-list.sh failed"

ok "Geladen: ${#DOWNLOADS[@]} Modelle, ${#EXTENSIONS[@]} Extensions"

# ── DOWNLOAD-FUNKTION ──────────────────────────────────────────────────────
download_model() {
    local dest="$1" name="$2" src="$3"
    dest="${dest//stable-diffusion-webui-forge/$FORGE_ROOT}"
    mkdir -p "$(dirname "$dest/$name")"
    
    [ -f "$dest/$name" ] && [ "$(stat -c%s "$dest/$name")" -gt 1M ] && {
        ok "$name übersprungen (bereits da)"
        return 0
    }
    
    step "Download $name"
    if [[ "$src" =~ ^[0-9]+$ ]]; then
        curl -L -H "User-Agent: Mozilla/5.0" \
            "https://civitai.com/api/download/models/$src?token=$CIVITAI_API_KEY" \
            -o "$dest/$name"
    else
        aria2c -x16 -s16 --max-tries=3 "$src" -d "$dest" -o "$name"
    fi
    ok "$name OK ($(du -sh "$dest/$name" | cut -f1))"
}

# ── MODELLE ────────────────────────────────────────────────────────────────
section "MODELL-DOWNLOADS"
for entry in "${DOWNLOADS[@]}"; do
    IFS='|' read -r dest name src <<< "$entry"
    download_model "$dest" "$name" "$src" || warn "$name failed"
done

# ── EXTENSIONS ─────────────────────────────────────────────────────────────
section "EXTENSIONS"
cd "$FORGE_ROOT/extensions"
for repo in "${EXTENSIONS[@]}"; do
    dir=$(basename "$repo" .git)
    [ -d "$dir" ] || git clone "$repo" || warn "$dir skip"
done

# ── SAFE WEBUI-USER.SH ─────────────────────────────────────────────────────
section "CPU-SAFE START"
cat > "$FORGE_ROOT/webui-user.sh" << 'EOF'
export COMMANDLINE_ARGS="--always-cpu --skip-torch-cuda-test --skip-python-version-check --listen --port 17860 --api --enable-insecure-extension-access"
EOF
chmod +x "$FORGE_ROOT/webui-user.sh"

# ── FINISH ─────────────────────────────────────────────────────────────────
section "FERTIG ✅"
echo "$(date)" > "$SENTINEL"
log "Modelle: $(du -sh "$FORGE_ROOT/models/" 2>/dev/null | cut -f1)"
log "Start: cd $FORGE_ROOT && ./webui.sh"
log "Open: http://[IP]:7860"
exit 0
