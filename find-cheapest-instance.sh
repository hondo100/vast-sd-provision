#!/usr/bin/env bash
set -eEuo pipefail

# Skript-Name: find-cheapest-instance
VERSION="2026-05-25.30"

: <<'SCRIPT_OVERVIEW'
========================================================================
ZWECK: Suche, Bewertung und Buchung von Vast.ai-Instanzen.
PERFORMANCE: Monolithische Python-Pipeline (Scoring/DL/Filter in einem).
FEATURES: Interaktive Buchung, Dry-Run, Test-Simulation, Tabellen-Layout.
========================================================================
SCRIPT_OVERVIEW

# KONFIGURATION
RESULTS=10
SEARCH_LIMIT=120
QUERY='external=false rentable=true verified=true gpu_ram>=24 disk_space>=40'
GPU_FILTER='RTX (3090|4090|A5000|A6000|5000|6000)'
DISK_GB=40
TEMPLATE_HASH="ad0935fab3e1f781fa442c1604ed07e2"
MODEL_GB=20
SESSION_HOURS=3

# Parameter
DO_BOOK=0; BOOK_INDEX=""; TEST_MODE=0; DRY_RUN=0

usage() { echo "Usage: $0 [--test] [--dry-run] [--book [NUM]] [--gpu-filter REGEX]"; }

# Hilfsfunktionen
color_supported() { [[ -t 1 ]]; }
c() { if color_supported; then printf '\033[%sm%s\033[0m' "$1" "$2"; else printf '%s' "$2"; fi; }
green() { c 32 "$1"; }
yellow() { c 33 "$1"; }
vast_cmd() { if command -v vastai >/dev/null 2>&1; then vastai "$@"; else vast "$@"; fi; }

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --test) TEST_MODE=1 ;;
      --dry-run) DRY_RUN=1 ;;
      --book) DO_BOOK=1; [[ $# -gt 1 && "$2" =~ ^[0-9]+$ ]] && BOOK_INDEX="$2" && shift ;;
      *) usage; exit 1 ;;
    esac
    shift
  done

  # Verbesserte Header-Ausgabe
  echo "============================================================"
  echo "Skript-Version: $VERSION"
  echo "Filter-Query:   $QUERY"
  echo "GPU-Filter:     $GPU_FILTER"
  echo "Disk-Größe:     ${DISK_GB}GB | Modell-Größe: ${MODEL_GB}GB"
  echo "============================================================"

  # Datenabruf
  [[ "$TEST_MODE" -ne 1 ]] && vast_cmd search offers --raw "$QUERY" -o 'dlperf_usd-' --limit "$SEARCH_LIMIT" >/tmp/vast_data.json || touch /tmp/vast_data.json
  
  # MONOLITHISCHE PIPELINE: Scoring + Alle Metriken
  local parsed
  parsed="$(python3 - "/tmp/vast_data.json" "$SEARCH_LIMIT" "$GPU_FILTER" "$MODEL_GB" "$SESSION_HOURS" <<'PY'
import json, sys, re
try:
    with open(sys.argv[1], 'r') as f: data = json.load(f)
    offers = data if isinstance(data, list) else data.get('offers', [])
    rows = []
    for o in offers[:int(sys.argv[2])]:
        gpu = str(o.get('gpu_name', 'unk'))
        if not re.search(sys.argv[3], gpu, re.IGNORECASE): continue
        
        # Scoring-Logik
        dph = float(o.get('dph_total', 0))
        init = float(o.get('inet_down_cost', 0))
        eff = dph + (init / float(sys.argv[5]))
        dl = float(o.get('inet_down', 1))
        ready = (float(sys.argv[4]) * 1024 * 8) / (dl * 0.75) / 60 + 7
        vram = float(o.get('gpu_ram', 0))
        rel = float(o.get('reliability', 1))
        numg = float(o.get('num_gpus', 1))
        
        cost_score = 1.0 / max(dph, 0.0001)
        vram_score = 1.22 if vram > 80 else (1.18 if vram > 48 else (1.10 if vram > 32 else (0.95 if vram > 28 else (0.75 if vram > 24 else 0.0))))
        gpu_penalty = 1.0 if numg <= 1 else (0.82 if numg <= 2 else 0.68)
        score = (cost_score * 0.47 + vram_score * 0.16 + (rel**2) * 0.14) * gpu_penalty
        
        rows.append((o.get('id'), gpu[:14], o.get('num_gpus'), dph, init, eff, dl, ready, vram/1024 if vram > 200 else vram, o.get('geolocation', 'US')[:2], score))
    
    for r in sorted(rows, key=lambda x: x[10], reverse=True):
        print(f"{r[0]}\t{r[1]}\t{r[2]}\t{r[3]:.2f}\t{r[4]:.2f}\t{r[5]:.2f}\t{r[6]:.0f}\t{r[7]:.0f}\t{r[8]:.0f}\t{r[9]}\t{r[10]:.2f}")
except: sys.exit(1)
PY
  )"

  # Tabellenausgabe
  printf "%-5s %-12s %-14s %-5s %-7s %-7s %-8s %-7s %-7s %-6s %-4s %-6s\n" "Nr" "ID" "Model" "GPUs" "$/hr" "Init$" "Eff$/h" "DLMB/s" "Ready" "VRAM" "Geo" "Score"
  printf '%s\n' "----------------------------------------------------------------------------------------------------"
  
  mapfile -t rows < <(printf '%s\n' "$parsed")
  for i in "${!rows[@]}"; do
    [[ $i -ge "$RESULTS" ]] && break
    IFS=$'\t' read -r id model ngpu dph init eff dl ready vram geo score <<< "${rows[$i]}"
    line=$(printf "%-5d %-12s %-14s %-5s %-7.2f %-7.2f %-8.2f %-7.0f %-7.0f %-6.0f %-4s %-6.2f" "$((i+1))" "$id" "$model" "$ngpu" "$dph" "$init" "$eff" "$dl" "$ready" "$vram" "$geo" "$score")
    case "$i" in 0) green "$line" ;; 1|2) yellow "$line" ;; *) printf '%s\n' "$line" ;; esac
  done

  # Buchung
  if [[ "$DO_BOOK" -eq 1 ]]; then
    [[ -z "$BOOK_INDEX" ]] && read -p "Nr zur Buchung wählen: " BOOK_INDEX
    [[ "$DRY_RUN" -eq 1 ]] && { echo "[DRY-RUN] Instanz wäre gebucht."; exit 0; }
    target=$((BOOK_INDEX-1))
    IFS=$'\t' read -r id model ngpu dph init eff dl ready vram geo score <<< "${rows[$target]}"
    read -p "Buchung $id ($model) bestätigen [y/N]: " confirm
    [[ "$confirm" == [yY] ]] && vast_cmd create instance "$id" --template_hash "$TEMPLATE_HASH" --disk "$DISK_GB"
  fi
}

main "$@"
