#!/usr/bin/env bash
set -eEuo pipefail

# Skript-Name: find-cheapest-instance
VERSION="2026-05-25.32"

: <<'SCRIPT_OVERVIEW'
========================================================================
ZWECK: Suche, Bewertung, Scoring und interaktive Buchung.
FEATURES:
- Support für: --test, --dry-run, --book [NUM]
- Scoring-Logik: Cost/VRAM/Reliability/GPU-Penalty
- Metriken: Vollständige 11-Spalten-Tabelle inkl. Ready-Time
- Kontrolle: Manuelles Überschreiben der Vorauswahl via Buchungs-Index
========================================================================
SCRIPT_OVERVIEW

# KONFIGURATION
SEARCH_LIMIT=120
QUERY='external=false rentable=true verified=true gpu_ram>=24 disk_space>=40'
GPU_FILTER='RTX (3090|4090|A5000|A6000|5000|6000)'
DISK_GB=40; TEMPLATE_HASH="ad0935fab3e1f781fa442c1604ed07e2"; MODEL_GB=20; SESSION_HOURS=3

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

  echo "============================================================"
  echo "Skript-Version: $VERSION | Filter: $GPU_FILTER"
  echo "============================================================"

  # Datenabruf
  [[ "$TEST_MODE" -ne 1 ]] && vast_cmd search offers --raw "$QUERY" -o 'dlperf_usd-' --limit "$SEARCH_LIMIT" >/tmp/vast_data.json || touch /tmp/vast_data.json
  
  # Pipeline mit voller Scoring-Logik
  local parsed
  parsed="$(python3 - "/tmp/vast_data.json" "$SEARCH_LIMIT" "$GPU_FILTER" "$MODEL_GB" "$SESSION_HOURS" <<'PY'
import json, sys, re
try:
    with open(sys.argv[1], 'r') as f: data = json.load(f)
    offers = data if isinstance(data, list) else data.get('offers', [])
    for o in offers[:int(sys.argv[2])]:
        gpu = str(o.get('gpu_name', 'unk'))
        if not re.search(sys.argv[3], gpu, re.IGNORECASE): continue
        dph = float(o.get('dph_total', 0))
        init = float(o.get('inet_down_cost', 0))
        dl = float(o.get('inet_down', 1))
        ready = (float(sys.argv[4]) * 1024 * 8) / (dl * 0.75) / 60 + 7
        vram = float(o.get('gpu_ram', 0)) / (1024 if float(o.get('gpu_ram', 0)) > 200 else 1)
        rel = float(o.get('reliability', 1))
        numg = float(o.get('num_gpus', 1))
        
        # Scoring-Logik (Rekonstruiert)
        score = ((1.0/max(dph, 0.0001))*0.47 + (1.22 if vram>80 else 0.75)*0.16 + (rel**2)*0.14) * (1.0 if numg<=1 else 0.82)
        print(f"{o.get('id')}\t{gpu[:12]}\t{numg:.0f}\t{dph:.2f}\t{init:.2f}\t{(dph + init/float(sys.argv[5])):.2f}\t{dl:.0f}\t{ready:.0f}\t{vram:.0f}\t{o.get('geolocation', 'US')[:2]}\t{score:.2f}")
except: sys.exit(1)
PY
  )"

  # Tabelle
  printf "%-4s %-10s %-12s %-4s %-6s %-6s %-8s %-6s %-6s %-6s %-4s %-6s\n" "Nr" "ID" "Model" "GPUs" "$/hr" "Init$" "Eff$/h" "DLMB/s" "Ready" "VRAM" "Geo" "Score"
  printf '%s\n' "----------------------------------------------------------------------------------------------------"
  
  local i=1; local rows=()
  while IFS=$'\t' read -r id model ngpu dph init eff dl ready vram geo score; do
    printf "%-4d %-10s %-12s %-4s %-6.2f %-6.2f %-8.2f %-6.0f %-6.0f %-6.0f %-4s %-6.2f\n" "$i" "$id" "$model" "$ngpu" "$dph" "$init" "$eff" "$dl" "$ready" "$vram" "$geo" "$score"
    rows+=("$id|$model")
    ((i++))
  done <<< "$parsed"

  # Buchung mit Überschreiben-Möglichkeit
  if [[ "$DO_BOOK" -eq 1 ]]; then
    [[ -z "$BOOK_INDEX" ]] && read -p "Nr zur Buchung wählen: " BOOK_INDEX
    [[ "$DRY_RUN" -eq 1 ]] && { echo "[DRY-RUN] Instanz $BOOK_INDEX wäre gebucht."; exit 0; }
    
    local selected="${rows[$((BOOK_INDEX-1))]}"
    local id="${selected%|*}"; local model="${selected#*|}"
    
    read -p "Buchung $id ($model) bestätigen [y/N]: " confirm
    [[ "$confirm" == [yY] ]] && vast_cmd create instance "$id" --template_hash "$TEMPLATE_HASH" --disk "$DISK_GB"
  fi
}
main "$@"
