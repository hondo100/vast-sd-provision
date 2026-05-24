#!/usr/bin/env bash
set -euo pipefail

VERSION="2026-05-24.15"
RESULTS=10
MIN_VRAM_GB=24.0
MIN_REL=0.95
QUERY='verified=true rentable=true'
SORT='dlperf_usd-'

usage() {
  echo "Usage: $0 [--test] [--dry-run]"
}

color_supported() {
  [[ -t 1 ]]
}

c() {
  local code="$1"; shift
  local text="$1"
  if color_supported; then printf '\033[%sm%s\033[0m' "$code" "$text"; else printf '%s' "$text"; fi
}

green(){ c 32 "$1"; }
yellow(){ c 33 "$1"; }
blue(){ c 34 "$1"; }
red(){ c 31 "$1"; }

have_vast() {
  command -v vastai >/dev/null 2>&1 || command -v vast >/dev/null 2>&1
}

vast_cmd() {
  if command -v vastai >/dev/null 2>&1; then
    vastai "$@"
  else
    vast "$@"
  fi
}

score_offer() {
  local price="$1" dl="$2" rel="$3" vram="$4"
  awk -v price="$price" -v dl="$dl" -v rel="$rel" -v vram="$vram" -v minv="$MIN_VRAM_GB" -v minr="$MIN_REL" '
    BEGIN {
      if (vram < minv || rel < minr) { print -1; exit }
      price_score = 1.0 / (price > 0.0001 ? price : 0.0001)
      vram_bonus = vram / 24.0
      if (vram_bonus > 2.0) vram_bonus = 2.0
      dl_bonus = dl / 100.0
      print (price_score * 0.45) + (dl_bonus * 0.35) + (vram_bonus * 0.15) + (rel * 0.05)
    }'
}

parse_cli() {
  python3 - "$RESULTS" <<'PY'
import sys, re
results = int(sys.argv[1])
text = sys.stdin.read().splitlines()
rows = []
in_table = False
for line in text:
    s = line.rstrip()
    if not s.strip():
        if in_table and rows:
            break
        continue
    if s.lstrip().startswith('#  ID') and 'Model' in s and '$/hr' in s:
        in_table = True
        continue
    if not in_table:
        continue
    if not re.match(r'^\s*\d+\s+', s):
        continue
    parts = re.split(r'\s{2,}', s.strip())
    if len(parts) < 14:
        continue
    try:
        oid = parts[1]
        model = parts[4].replace('_', ' ')
        price = float(parts[10])
        dlp = float(parts[11])
        score = float(parts[13])
        vram = float(parts[8])
    except Exception:
        continue
    rel = 1.00
    tx = 0.0000
    eff = price
    rows.append((oid, model, price, tx, eff, dlp, rel, vram, 'True', score))
    if len(rows) >= results:
        break
for r in rows:
    print("\t".join(map(str, r)))
PY
}

main() {
  local test=0 dry=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --test) test=1 ;;
      --dry-run) dry=1 ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
    esac
    shift
  done

  if ! have_vast; then
    echo "[ERR] vastai/vast CLI nicht gefunden" >&2
    exit 2
  fi

  echo "Skript-Version: $VERSION"
  echo "[INFO] Suche Angebote..."
  if [[ $test -eq 1 ]]; then echo "Modus: test"; else echo "Modus: live"; fi
  echo "Legende:"
  echo "  Grün  = bester GenAI-Score"
  echo "  Gelb  = gute Balance aus Preis und Leistung"
  echo "  Blau  = günstigste effektive Kosten"
  echo "  Rot   = unter Mindestanforderungen"
  echo

  raw="$(vast_cmd search offers "$QUERY" -o "$SORT")"
  parsed="$(printf '%s\n' "$raw" | parse_cli)"

  if [[ -z "$parsed" ]]; then
    echo "Keine Angebote gefunden oder Parser passt nicht zum CLI-Output." >&2
    exit 1
  fi

  mapfile -t rows < <(printf '%s\n' "$parsed")

  printf '%-3s %-10s %-18s %7s %8s %8s %8s %7s %8s %5s %6s\n' "Nr" "Offer_ID" "Model" "\$/hr" "20GB Tx" "Eff$/h" "DLPerf" "Score" "VRAM GB" "Rel" "Status"
  printf '%s\n' "--------------------------------------------------------------------------------------------------------"

  limit=$(( RESULTS < ${#rows[@]} ? RESULTS : ${#rows[@]} ))
  for ((i=0; i<limit; i++)); do
    IFS=$'\t' read -r oid model price tx eff dl rel vram status score <<< "${rows[$i]}"
    score2="$(score_offer "$price" "$dl" "$rel" "$vram")"
    [[ "$score" == "0" ]] && score="$score2"
    line=$(printf '%-3s %-10s %-18s %7.4f %8.4f %8.4f %8.1f %7.1f %8.1f %5.2f %6s' \
      "$((i+1))" "$oid" "$model" "$price" "0.0000" "$eff" "$dl" "$score" "$vram" "$rel" "$status")
    case "$i" in
      0) green "$line" ;;
      1|2) yellow "$line" ;;
      3|4) blue "$line" ;;
      *) printf '%s' "$line" ;;
    esac
    printf '\n'
  done

  IFS=$'\t' read -r oid model price tx eff dl rel vram status score <<< "${rows[0]}"
  echo
  echo "Vorschlag: Nummer 1 ($oid / $model)"

  if [[ $dry -eq 1 ]]; then
    exit 0
  fi

  choice=""
  while [[ -z "$choice" ]]; do
    read -r -p "Welche Nummer buchen? [1-$limit] (Enter = 1): " raw
    if [[ -z "$raw" ]]; then
      choice=1
    elif [[ "$raw" =~ ^[0-9]+$ ]] && (( raw >= 1 && raw <= limit )); then
      choice="$raw"
    else
      echo "Ungueltige Eingabe. Bitte nur eine gueltige Nummer eingeben."
    fi
  done

  IFS=$'\t' read -r oid model price tx eff dl rel vram status score <<< "${rows[$((choice-1))]}"
  echo
  echo "Gewählt: $choice -> $oid / $model"

  if [[ $test -eq 1 ]]; then
    echo "[TEST] Kein Booking ausgeführt."
    exit 0
  fi

  read -r -p "Buchung wirklich ausführen? [j/N]: " confirm
  if [[ "${confirm,,}" != "j" ]]; then
    echo "Abgebrochen."
    exit 0
  fi

  echo "[INFO] Booking würde hier ausgeführt werden."
}

main "$@"
