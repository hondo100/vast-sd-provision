#!/usr/bin/env bash
set -eEuo pipefail

# Skript-Name: find-cheapest-instance
VERSION="2026-05-25.27"

: <<'SCRIPT_OVERVIEW'
========================================================================
ZWECK
========================================================================
- Suche, Bewertung und Buchung von Vast.ai-Instanzen.
- Performance: Monolithische Python-Pipeline für alle Berechnungen.
- Metriken: Vollständige Übersicht (GPUs, Preise, DL-Rate, Ready-Time).
- Sicherheit: Interaktive Bestätigung und Dry-Run Modus.

========================================================================
LOGIK & PERFORMANCE-FINDINGS
========================================================================
1) PERFORMANCE: Alle Berechnungen erfolgen direkt im Python-JSON-Objekt.
   Keine Bash-Subshell-Forks mehr pro Zeile.
2) FORMATIERUNG: Exakte Spaltenausrichtung mittels printf.
3) METRIKEN: Modellierung von Effektivpreis, Init-Kosten und DL-Zeit.
4) FILTER: Dynamische Regex-Filterung auf GPU-Namen.


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

# Parameter-Variablen
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

  echo "Skript-Version: $VERSION"
  echo "[INFO] Aktiver GPU-Modellfilter: $GPU_FILTER"

  # Daten abrufen
  if [[ "$TEST_MODE" -eq 1 ]]; then
    touch /tmp/vast_data.json
  else
    vast_cmd search offers --raw "$QUERY" -o 'dlperf_usd-' --limit "$SEARCH_LIMIT" >/tmp/vast_data.json
  fi

  # MONOLITHISCHE PIPELINE: Scoring + Alle Metriken
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
        eff = dph + (init / float(sys.argv[5]))
        dl = float(o.get('inet_down', 1))
        ready = (float(sys.argv[4]) * 1024 * 8) / (dl * 0.75) / 60 + 7
        vram = float(o.get('gpu_ram', 0))
        print(f"{o.get('id')}\t{gpu[:14]}\t{o.get('num_gpus')}\t{dph:.2f}\t{init:.2f}\t{eff:.2f}\t{dl:.0f}\t{ready:.0f}\t{vram:.0f}\t{o.get('geolocation', 'US')[:2]}")
except: sys.exit(1)
PY
  )"

  # Formatierte Tabellenausgabe
  printf "%-5s %-12s %-14s %-5s %-7s %-7s %-8s %-7s %-7s %-6s %-4s\n" "Nr" "ID" "Model" "GPUs" "$/hr" "Init$" "Eff$/h" "DLMB/s" "ReadyM" "VRAM" "Geo"
  printf '%s\n' "--------------------------------------------------------------------------------------------"
  
  mapfile -t rows < <(printf '%s\n' "$parsed")
  for i in "${!rows[@]}"; do
    [[ $i -ge "$RESULTS" ]] && break
    IFS=$'\t' read -r id model ngpu dph init eff dl ready vram geo <<< "${rows[$i]}"
    line=$(printf "%-5d %-12s %-14s %-5s %-7.2f %-7.2f %-8.2f %-7.0f %-7.0f %-6.0f %-4s" "$((i+1))" "$id" "$model" "$ngpu" "$dph" "$init" "$eff" "$dl" "$ready" "$vram" "$geo")
    case "$i" in 0) green "$line" ;; 1|2) yellow "$line" ;; *) printf '%s\n' "$line" ;; esac
  done

  # Buchungslogik
  if [[ "$DO_BOOK" -eq 1 ]]; then
    [[ -z "$BOOK_INDEX" ]] && read -p "Nr zur Buchung wählen: " BOOK_INDEX
    if [[ "$DRY_RUN" -eq 1 ]]; then echo "[DRY-RUN] Instanz $BOOK_INDEX wäre gebucht."; exit 0; fi
    local target=$((BOOK_INDEX-1))
    IFS=$'\t' read -r id model ngpu dph init eff dl ready vram geo <<< "${rows[$target]}"
    read -p "Buchung $id ($model) bestätigen [y/N]: " confirm
    [[ "$confirm" == [yY] ]] && vast_cmd create instance "$id" --template_hash "$TEMPLATE_HASH" --disk "$DISK_GB"
  fi
}

main "$@"
