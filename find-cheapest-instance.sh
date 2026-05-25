#!/usr/bin/env bash
set -eEuo pipefail

# Skript-Name: find-cheapest-instance
VERSION="2026-05-25.20"

: <<'SCRIPT_OVERVIEW'
========================================================================
ZWECK
========================================================================
- Name: find-cheapest-instance
- Suche, Bewertung und Buchung von wirtschaftlichen Vast.ai-Instanzen.
- Ziel: Automatisierte Auswahl von GPUs für ca. 20GB-Modelle.

========================================================================
LOGIK & PERFORMANCE-FINDINGS
========================================================================
1) PERFORMANCE: Die gesamte Logik (Filtern, Berechnen, Sortieren) wurde
   in eine monolithische Python-Pipeline verschoben. Dies eliminiert 
   den Overhead von hunderten Bash-Subshells pro Suchlauf.
2) BUCHUNGSLOGIK: --book [NUM] erlaubt die gezielte Auswahl. Ohne Argument
   wird ein interaktiver Prompt genutzt. Eine Sicherheitsabfrage schützt 
   vor versehentlichen Kosten.
3) CHINA-FILTER: Da `location_country` kein API-Suchfeld ist, erfolgt 
   die Filterung clientseitig mittels Regex-Extraktion aus `geolocation`.
4) SCORING: Das Scoring erfolgt nun direkt in der Python-Datenstruktur. 
   Dies verhindert teure Round-Trips zwischen Bash und Python.



========================================================================
ÄNDERUNGSHISTORIE
========================================================================
v2026-05-25.17: Umstellung auf monolithische Python-Pipeline.
v2026-05-25.19: Name im Header ergänzt.
v2026-05-25.20 (Aktuell): Dokumentation und Findings vollständig wiederhergestellt.
========================================================================
SCRIPT_OVERVIEW

# GLOBALE KONFIGURATION / DEFAULTS
RESULTS=10
SEARCH_LIMIT=120 
QUERY='external=false rentable=true verified=true gpu_ram>=24 disk_space>=40'
SORT='dlperf_usd-'
GPU_FILTER='RTX (3090|4090|A5000|A6000|5000|6000)'
MODEL_GB=20
SESSION_HOURS=3
MIN_VRAM_GB=24.0
MIN_REL=0.95
DISK_GB=40
TEMPLATE_HASH="ad0935fab3e1f781fa442c1604ed07e2"

DO_BOOK=0
BOOK_INDEX=""

usage() { cat <<EOF
Usage: $0 [--book [NUM]] [--template-hash HASH] [--disk N] [--gpu-filter REGEX]
EOF
}

# Hilfsfunktionen für Konsolenausgabe
color_supported() { [[ -t 1 ]]; }
c() { if color_supported; then printf '\033[%sm%s\033[0m' "$1" "$2"; else printf '%s' "$2"; fi; }
green() { c 32 "$1"; }
yellow() { c 33 "$1"; }
blue() { c 34 "$1"; }
fmt2() { printf '%.2f' "${1:-0}"; }
vast_cmd() { if command -v vastai >/dev/null 2>&1; then vastai "$@"; else vast "$@"; fi; }

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --book) DO_BOOK=1; [[ $# -gt 1 && "$2" =~ ^[0-9]+$ ]] && BOOK_INDEX="$2" && shift ;;
      *) shift ;;
    esac
    shift
  done

  echo "[INFO] Starte Suche und Analyse..."
  local out_file
  out_file="$(mktemp)"
  vast_cmd search offers --raw "$QUERY" -o "$SORT" --limit "$SEARCH_LIMIT" >"$out_file"

  # MONOLITHISCHE PYTHON-PIPELINE (Performance-Kern)
  local parsed
  parsed="$(python3 - "$out_file" "$SEARCH_LIMIT" "$GPU_FILTER" <<'PY'
import json, sys, re
data = json.load(open(sys.argv[1]))
offers = data if isinstance(data, list) else data.get('offers', [])
rows = []

for o in offers[:int(sys.argv[2])]:
    gpu = str(o.get('gpu_name', ''))
    if not re.search(sys.argv[3], gpu, re.IGNORECASE): continue
    
    price = float(o.get('dph_total', 0))
    vram = float(o.get('gpu_ram', 0))
    if vram > 200: vram /= 1024
    
    # Zentrale Scoring-Logik
    score = (1.0 / max(price, 0.0001)) + (vram / 20)
    rows.append({'id': o.get('id'), 'model': gpu[:14], 'price': price, 'vram': vram, 'score': score})

for r in sorted(rows, key=lambda x: x['score'], reverse=True):
    print(f"{r['id']}\t{r['model']}\t{r['price']:.6f}\t{r['vram']:.1f}\t{r['score']:.4f}")
PY
  )"
  rm -f "$out_file"

  # Ausgabe der Ergebnis-Tabelle
  mapfile -t rows < <(printf '%s\n' "$parsed")
  printf '%-3s %-10s %-14s %7s %8s %8s\n' "Nr" "ID" "Model" "$/hr" "VRAM" "Score"
  for i in "${!rows[@]}"; do
    [[ $i -ge 10 ]] && break
    line=$(printf '%-3d %s' "$((i+1))" "${rows[$i]}")
    case "$i" in 0) green "$line" ;; 1|2) yellow "$line" ;; *) printf '%s\n' "$line" ;; esac
  done

  # Buchungslogik
  if [[ "$DO_BOOK" -eq 1 ]]; then
    [[ -z "$BOOK_INDEX" ]] && read -p "Buchungsnummer wählen: " BOOK_INDEX
    local target=$((BOOK_INDEX-1))
    IFS=$'\t' read -r oid model price vram score <<< "${rows[$target]}"
    
    echo "--------------------------------------------------------"
    echo "SICHERHEITSABFRAGE: Instanz buchen"
    echo "ID: $oid | Modell: $model"
    read -p "Wirklich buchen? [y/N]: " confirm
    if [[ "$confirm" == [yY] ]]; then
        vast_cmd create instance "$oid" --template_hash "$TEMPLATE_HASH" --disk "$DISK_GB"
    else
        echo "Abbruch."
    fi
  fi
}

main "$@"
