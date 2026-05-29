#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# vast_search_optimizer.sh | Version: 2026-05-29.01 (Regression-Based Estimation)
# -----------------------------------------------------------------------------
export PATH=$PATH:~/.local/bin:/usr/local/bin:/usr/bin
set -eEuo pipefail

VERSION="2026-05-29.01"
RESULTS=10
QUERY='external=false rentable=true verified=true gpu_ram>=24 disk_space>=40'
GPU_FILTER='RTX (3090|4090|A5000|A6000|5000|6000)'
DISK_GB=40; TEMPLATE_HASH="ad0935fab3e1f781fa442c1604ed07e2"; MODEL_GB=20; SESSION_HOURS=3

# --- STARTPARAMETER FÜR DAS REGRESSIONSMODELL (ÜBER EXTERNES TOOL ANSTEUERBAR) ---
export REG_BETA_0="${REG_BETA_0:-165.0}"  # Basis-Overhead (Docker/Host Init) in Sek.
export REG_BETA_1="${REG_BETA_1:-1.38}"   # Netzwerk-Skalierungsfaktor (nominal vs real)
export REG_BETA_2="${REG_BETA_2:-52.0}"   # Venv-Härtung & Extension-Overhead in Sek.
export REG_BETA_3="${REG_BETA_3:-120.0}"  # Zuverlässigkeits-Malus bei schlechter Reliability

c() { printf '\033[%sm%s\033[0m\n' "$1" "$2"; }

vast_cmd() {
    if command -v vastai >/dev/null 2>&1; then vastai "$@"
    elif command -v vast >/dev/null 2>&1; then vast "$@"
    else echo "[ERROR] 'vastai' nicht gefunden."; exit 1; fi
}

main() {
  local DO_BOOK=0; local BOOK_INDEX=""; local TEST_MODE=0; local DRY_RUN=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --test) TEST_MODE=1 ;; --dry-run) DRY_RUN=1 ;;
      --book) DO_BOOK=1; [[ $# -gt 1 && "$2" =~ ^[0-9]+$ ]] && BOOK_INDEX="$2" && shift ;;
      *) echo "Usage: $0 [--test] [--dry-run] [--book [NUM]]"; exit 1 ;;
    esac
    shift
  done

  echo "========================================================================"
  echo "Skript-Version: $VERSION | Filter: $GPU_FILTER"
  echo "Regressions-Startparameter: B0=${REG_BETA_0}s, B1=${REG_BETA_1}, B2=${REG_BETA_2}s"
  echo "========================================================================"

  [[ "$TEST_MODE" -ne 1 ]] && vast_cmd search offers --raw "$QUERY" -o 'dlperf_usd-' --limit 120 >/tmp/vast_data.json || touch /tmp/vast_data.json
  
  local parsed
  parsed="$(python3 - "/tmp/vast_data.json" "$GPU_FILTER" "$MODEL_GB" "$SESSION_HOURS" <<'PY'
import json, sys, re, os

try:
    with open(sys.argv[1], 'r') as f: data = json.load(f)
    offers = data if isinstance(data, list) else data.get('offers', [])
    rows = []
    
    # Injektion der Startparameter aus den Umgebungsvariablen
    b0 = float(os.environ.get('REG_BETA_0', 165.0))
    b1 = float(os.environ.get('REG_BETA_1', 1.38))
    b2 = float(os.environ.get('REG_BETA_2', 52.0))
    b3 = float(os.environ.get('REG_BETA_3', 120.0))
    
    model_gb = float(sys.argv[3])
    session_hours = float(sys.argv[4])

    for o in offers:
        gpu = str(o.get('gpu_name', 'unk'))
        if not re.search(sys.argv[2], gpu, re.IGNORECASE): continue
        
        dph, init = float(o.get('dph_total', 0)), float(o.get('inet_down_cost', 0))
        dl, vram = float(o.get('inet_down', 1)), float(o.get('gpu_ram', 0))
        if vram > 200: vram /= 1024
        
        rel = float(o.get('reliability', 1.0))
        numg = float(o.get('num_gpus', 1))
        
        # --- Angepasstes Regressionsmodell für die Bereitstellungszeit (in Minuten) ---
        # Umrechnung: Model_GB * 8192 konvertiert Gigabytes direkt in Megabits (Mbps-Äquivalent)
        net_download_seconds = (model_gb * 8192.0) / max(dl, 0.1)
        estimated_ready_seconds = b0 + b2 + (b1 * net_download_seconds) + (b3 * (1.0 - rel))
        ready = estimated_ready_seconds / 60.0
        
        # Score-Kalkulation (beibehalten, adjustiert auf Basis der dynamischen Variablen)
        score = ((1.0/max(dph, 0.0001))*0.47 + (1.22 if vram>80 else 0.75)*0.16 + (rel**2)*0.14) * (1.0 if numg<=1 else 0.82)
        test_cost = dph * 0.5 + init
        
        rows.append((o.get('id'), gpu[:14], numg, dph, init, (dph + init/session_hours), dl, ready, vram, o.get('geolocation', 'US')[:2], score, test_cost))
        
    for r in sorted(rows, key=lambda x: x[10], reverse=True):
        print(f"{r[0]}\t{r[1]}\t{r[2]:.0f}\t{r[3]:.2f}\t{r[4]:.2f}\t{r[5]:.2f}\t{r[6]:.0f}\t{r[7]:.0f}\t{r[8]:.0f}\t{r[9]}\t{r[10]:.2f}\t{r[11]:.2f}")
except Exception as e:
    sys.stderr.write(f"Python Error: {str(e)}\n")
    sys.exit(1)
PY
  )"

  printf "%-5s %-12s %-16s %-5s %-7s %-7s %-8s %-7s %-6s %-6s %-5s %-6s\n" "Nr" "ID" "Model" "GPUs" "$/hr" "Init$" "Eff$/h" "DLMB/s" "Ready" "VRAM" "Geo" "Score"
  printf '%s\n' "-------------------------------------------------------------------------------------------------------"
  
  local i=0; local rows=(); local cheapest_idx=-1; local min_test=999999
  mapfile -t lines <<< "$parsed"
  for j in "${!lines[@]}"; do
    [[ $j -ge $RESULTS ]] && break
    [[ -z "${lines[$j]}" ]] && continue
    IFS=$'\t' read -r _ _ _ _ _ _ _ _ _ _ _ test_c <<< "${lines[$j]}"
    if (( $(echo "$test_c < $min_test" | bc -l) )); then min_test=$test_c; cheapest_idx=$j; fi
  done

  for j in "${!lines[@]}"; do
    [[ $j -ge $RESULTS ]] && break
    [[ -z "${lines[$j]}" ]] && continue
    IFS=$'\t' read -r id model ngpu dph init eff dl ready vram geo score test_c <<< "${lines[$j]}"
    line=$(printf "%-5d %-12s %-16s %-5s %-7.2f %-7.2f %-8.2f %-7.0f %-6.0f %-6.0f %-5s %-6.2f" "$((j+1))" "$id" "$model" "$ngpu" "$dph" "$init" "$eff" "$dl" "$ready" "$vram" "$geo" "$score")
    if [ "$j" -eq 0 ] && [ "$j" -eq "$cheapest_idx" ]; then c 36 "$line (Top & Best Test)"
    elif [ "$j" -eq 0 ]; then c 32 "$line (Top Score)"
    elif [ "$j" -eq "$cheapest_idx" ]; then c 33 "$line (Best Test)"
    else printf '%s\n' "$line"; fi
    rows+=("$id|$model")
  done

  if [[ "$DO_BOOK" -eq 1 ]]; then
    read -p "Nr zur Buchung (oder 'q' zum Beenden): " BOOK_INDEX
    [[ "$BOOK_INDEX" == "q" ]] && { echo "Abbruch."; exit 0; }
    [[ "$DRY_RUN" -eq 1 ]] && { echo "[DRY-RUN] Instanz $BOOK_INDEX wäre gebucht."; exit 0; }
    local sel="${rows[$((BOOK_INDEX-1))]}"; read -p "Buchung ${sel%|*} (${sel#*|}) bestätigen [y/N]: " conf
    [[ "$conf" == [yY] ]] && vast_cmd create instance "${sel%|*}" --template_hash "$TEMPLATE_HASH" --disk "$DISK_GB"
  fi
}
main "$@"
