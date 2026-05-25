#!/usr/bin/env bash
set -eEuo pipefail

# Skript-Name: find-cheapest-instance
VERSION="2026-05-25.25"

: <<'SCRIPT_OVERVIEW'
========================================================================
ZWECK: Suche, Bewertung und Buchung von Vast.ai-Instanzen.
PERFORMANCE: Monolithische Python-Pipeline (Scoring/DL/Filter in einem).
FEATURES: Interaktive Buchung, Dry-Run, Test-Simulation, Tabellen-Layout.
========================================================================
SCRIPT_OVERVIEW

# GLOBALE KONFIGURATION
RESULTS=10
SEARCH_LIMIT=120
QUERY='external=false rentable=true verified=true gpu_ram>=24 disk_space>=40'
SORT='dlperf_usd-'
GPU_FILTER='RTX (3090|4090|A5000|A6000|5000|6000)'
DISK_GB=40
TEMPLATE_HASH="ad0935fab3e1f781fa442c1604ed07e2"
MODEL_GB=20
SESSION_HOURS=3

# Parameter-Variablen
DO_BOOK=0; BOOK_INDEX=""; TEST_MODE=0; DRY_RUN=0

usage() { cat <<EOF
Usage: $0 [--test] [--dry-run] [--book [NUM]] [--gpu-filter REGEX] [--disk N]
EOF
}

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
      --disk) shift; DISK_GB="$1" ;;
      --gpu-filter) shift; GPU_FILTER="$1" ;;
      *) usage; exit 1 ;;
    esac
    shift
  done

  # Daten abrufen
  if [[ "$TEST_MODE" -eq 1 ]]; then
    echo "[TEST] Simulationsmodus aktiv."
    touch /tmp/vast_data.json
  else
    echo "[INFO] Suche Vast.ai Angebote..."
    vast_cmd search offers --raw "$QUERY" -o "$SORT" --limit "$SEARCH_LIMIT" >/tmp/vast_data.json
  fi

  # MONOLITHISCHE PIPELINE: Scoring + Ready-Time-Modellierung
  local parsed
  parsed="$(python3 - "/tmp/vast_data.json" "$SEARCH_LIMIT" "$GPU_FILTER" "$MODEL_GB" <<'PY'
import json, sys, re
try:
    with open(sys.argv[1], 'r') as f: data = json.load(f)
    offers = data if isinstance(data, list) else data.get('offers', [])
    rows = []
    for o in offers[:int(sys.argv[2])]:
        gpu = str(o.get('gpu_name', 'unk')).replace('\t', ' ')
        if not re.search(sys.argv[3], gpu, re.IGNORECASE): continue
        
        # Scoring-Logik
        price = float(o.get('dph_total', 0))
        vram = float(o.get('gpu_ram', 0))
        if vram > 200: vram /= 1024
        rel = float(o.get('reliability', 1))
        numg = float(o.get('num_gpus', 1))
        inet_down = max(float(o.get('inet_down', 1)), 1.0)
        
        cost_score = 1.0 / max(price, 0.0001)
        vram_score = 1.22 if vram > 80 else (1.18 if vram > 48 else (1.10 if vram > 32 else (0.95 if vram > 28 else (0.75 if vram > 24 else 0.0))))
        gpu_penalty = 1.0 if numg <= 1 else (0.82 if numg <= 2 else 0.68)
        score = (cost_score * 0.47 + vram_score * 0.16 + (rel**2) * 0.14) * gpu_penalty
        
        # Ready-Time Modellierung
        est_ready_min = ((float(sys.argv[4]) * 1024 * 8) / (inet_down * 0.75) / 60) + 7.0
        
        rows.append({'id': o.get('id'), 'model': gpu[:14], 'price': price, 'vram': vram, 'ready': est_ready_min, 'score': score})

    for r in sorted(rows, key=lambda x: x['score'], reverse=True):
        print(f"{r['id']}\t{r['model']}\t{r['price']:.6f}\t{r['vram']:.1f}\t{r['ready']:.0f}\t{r['score']:.4f}")
except Exception: sys.exit(1)
PY
  )"

  # Tabellenausgabe
  mapfile -t rows < <(printf '%s\n' "$parsed")
  printf '%-5s %-12s %-14s %-10s %-8s %-8s %-5s\n' "Nr" "ID" "Model" "$/hr" "VRAM" "ReadyM" "Score"
  printf '%s\n' "--------------------------------------------------------------------------"
  for i in "${!rows[@]}"; do
    [[ $i -ge "$RESULTS" ]] && break
    IFS=$'\t' read -r id model price vram ready score <<< "${rows[$i]}"
    line=$(printf '%-5d %-12s %-14s %-10.4f %-8.0f %-8.0f %-5.2f' "$((i+1))" "$id" "$model" "$price" "$vram" "$ready" "$score")
    case "$i" in 0) green "$line" ;; 1|2) yellow "$line" ;; *) printf '%s\n' "$line" ;; esac
  done

  # Buchung
  if [[ "$DO_BOOK" -eq 1 ]]; then
    [[ -z "$BOOK_INDEX" ]] && read -p "Nr zur Buchung wählen: " BOOK_INDEX
    if [[ "$DRY_RUN" -eq 1 ]]; then echo "[DRY-RUN] Instanz wäre gebucht."; exit 0; fi
    
    local target=$((BOOK_INDEX-1))
    IFS=$'\t' read -r oid model price vram ready score <<< "${rows[$target]}"
    echo "--- Sicherheitsabfrage: Buchung von $oid ($model) ---"
    read -p "Bestätigen [y/N]: " confirm
    [[ "$confirm" == [yY] ]] && vast_cmd create instance "$oid" --template_hash "$TEMPLATE_HASH" --disk "$DISK_GB" || echo "Abbruch."
  fi
}

main "$@"
