#!/bin/bash
# Kernel-Skript mit erweiterter Fehlerprüfung und Logging

REAL_FORGE="/opt/workspace-internal/stable-diffusion-webui-forge"
VENV_PYTHON="/venv/main/bin/python3"
STORAGE_BASE="/workspace/models"
DEBUG_LOG="/workspace/provisioning_debug.log"

# Hilfsfunktion für Fehlermeldungen
log_error() {
    echo "[FEHLER] $(date +'%H:%M:%S'): $1" >> "$DEBUG_LOG"
}

echo "[INFO] Starte Kernel-Provisioning..." >> "$DEBUG_LOG"

# 1. System-Vorbereitung (Sleep gem. Doku)
sleep 20 [cite: 11]
apt-get update && apt-get install -y aria2 >> "$DEBUG_LOG" 2>&1
mkdir -p "$STORAGE_BASE/Stable-diffusion" "$STORAGE_BASE/Lora"

# 2. Liste laden
LIST_URL="https://raw.githubusercontent.com/hondo100/vast-sd-provision/main/install_list.txt"
curl -s -L -H "Authorization: token $GITHUB_PAT" "$LIST_URL" -o "/workspace/install_list.txt"

if [ ! -s "/workspace/install_list.txt" ]; then
    log_error "Modell-Liste (install_list.txt) konnte nicht geladen werden oder ist leer."
    exit 1
fi

# 3. Download-Schleife
while read -r line || [ -n "$line" ]; do
    [[ "$line" =~ ^#.* ]] || [[ -z "$line" ]] && continue
    
    SOURCE=$(echo $line | cut -d'|' -f1)
    TYPE=$(echo $line | cut -d'|' -f2)
    NAME=$(echo $line | cut -d'|' -f3)
    
    if [[ $SOURCE == http* ]]; then
        DOWNLOAD_URL="$SOURCE"
    else
        DOWNLOAD_URL="https://civitai.com/api/download/models/$SOURCE"
    fi

    TARGET_FILE="$STORAGE_BASE/$TYPE/$NAME"
    
    if [ ! -f "$TARGET_FILE" ]; then
        echo "[DOWNLOAD] Versuche $NAME zu laden..." >> "$DEBUG_LOG"
        
        # aria2 Start mit Log-Output
        aria2c -x 16 -s 16 -k 1M --user-agent="Mozilla/5.0" -o "$NAME" -d "$STORAGE_BASE/$TYPE" "$DOWNLOAD_URL" >> "$DEBUG_LOG" 2>&1
        STATUS=$?

        if [ $STATUS -eq 0 ]; then
            echo "[ERFOLG] $NAME erfolgreich heruntergeladen." >> "$DEBUG_LOG"
            chmod 666 "$TARGET_FILE" [cite: 22]
        else
            case $STATUS in
                22) log_error "Datei nicht gefunden (404) für $NAME. Prüfe die URL/ID: $SOURCE" ;;
                16) log_error "Netzwerkfehler/Timeout bei $NAME. Server ist evtl. überlastet." ;;
                *)  log_error "Download fehlgeschlagen für $NAME. aria2 Exit-Code: $STATUS" ;;
            esac
            # Falls Download fehlschlägt: lösche evtl. korrupte Teil-Dateien
            rm -f "$TARGET_FILE"
        fi
    fi
    
    # Symlink erstellen (Nur bei Erfolg)
    if [ -f "$TARGET_FILE" ]; then
        FORGE_DEST="$REAL_FORGE/models/$TYPE/$NAME"
        if [ ! -L "$FORGE_DEST" ] && [ ! -f "$FORGE_DEST" ]; then
            ln -s "$TARGET_FILE" "$FORGE_DEST" [cite: 26, 38]
        fi
    fi
done < "/workspace/install_list.txt"

# 4. Start-Konfiguration (Flags aus Doku)
ARGS="--listen --port 8080 --enable-insecure-extension-access --xformers --skip-python-version-check --cuda-malloc --cors-allow-origins=*" [cite: 29, 33]
echo "export COMMANDLINE_ARGS=\"$ARGS\"" > "$REAL_FORGE/webui-user.sh"

# 5. Start (via venv-Python)
cd "$REAL_FORGE" [cite: 32]
echo "[START] Forge wird jetzt initialisiert..." >> "$DEBUG_LOG"
$VENV_PYTHON launch.py $ARGS >> /workspace/forge_boot.log 2>&1 & [cite: 33, 42]
