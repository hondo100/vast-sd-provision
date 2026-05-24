#!/usr/bin/env bash
set -euo pipefail

VERSION="2026-05-24.10"
RESULTS=10
TX_GB=20.0
MIN_VRAM_GB=24.0
MIN_REL=0.95
VAST_URL="https://console.vast.ai/api/v0/bundles"

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

get_auth() {
  if [[ -n "${VAST_AUTH:-}" ]]; then
    printf '%s' "$VAST_AUTH"
    return 0
  fi
  if command -v vast >/dev/null 2>&1; then
    vast show auth 2>/dev/null | tr -d '\r' | head -n1
    return 0
  fi
  return 1
}

get_json() {
  local auth="$1"
  local q
  q='{"verified":{"eq":true},"rentable":{"eq":true}}'
  curl -fsSL --max-time 30 \
    -H "Authorization: Bearer ${auth}" \
    --get \
    --data-urlencode "q=${q}" \
    --data-urlencode "limit=200" \
    --data-urlencode 'order=[["dlperf_per_dphtotal","desc"]]' \
    "$VAST_URL/"
}

score_offer() {
  local eff="$1" dl="$2" rel="$3" vram="$4"
  awk -v eff="$eff" -v dl="$dl" -v rel="$rel" -v vram="$vram" -v minv="$MIN_VRAM_GB" -v minr="$MIN_REL" '
    BEGIN {
      if (vram < minv || rel < minr) { print -1; exit }
      price_score = 1.0 / (eff > 0.0001 ? eff : 0.0001)
      vram_bonus = vram / 24.0
      if (vram_bonus > 2.0) vram_bonus = 2.0
      dl_bonus = dl / 100.0
      print (price_score * 0.45) + (dl_bonus * 0.35) + (vram_bonus * 0.15) + (rel * 0.05)
    }'
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

  echo "Skript-Version: $VERSION"
  echo "Pruefe Vast.ai Auth..."
  AUTH="$(get_auth || true)"
  if [[ -z "$AUTH" ]]; then
    echo "[ERR] Kein Vast.ai Auth-Token gefunden" >&2
    exit 2
  fi
  echo "[OK] VAST_AUTH_OK"
  echo
  echo "[INFO] Suche Angebote..."
  if [[ $test -eq 1 ]]; then echo "Modus: test"; else echo "Modus: live"; fi
  echo "Legende:"
  echo "  Grün  = bester GenAI-Score"
  echo "  Gelb  = gute Balance aus Preis und Leistung"
  echo "  Blau  = günstigste effektive Kosten"
  echo "  Rot   = unter Mindestanforderungen"
  echo

  json="$(get_json "$AUTH")"

  mapfile -t rows < <(printf '%s' "$json" | jq -r '
    def num($x): (try ($x|tonumber) catch 0);
    def val($a; $b): ($a[$b] // empty);
    [
      (val(. ; "id") // val(. ; "offer_id") // ""),
      (val(. ; "gpu_name") // val(. ; "gpu") // val(. ; "model") // "unknown"),
      num(val(. ; "dph_total") // val(. ; "price") // val(. ; "hourly_price")),
      num(.tx_cost_20gb // 0),
      (num(val(. ; "dph_total") // val(. ; "price") // val(. ; "hourly_price")) + num(.tx_cost_20gb // 0)),
      num(val(. ; "dlperf") // val(. ; "dl_performance")),
      num(val(. ; "reliability") // val(. ; "rel") // 1),
      (num(val(. ; "gpu_ram") // val(. ; "gpu_total_ram") // val(. ; "vram")) / 1024),
      (val(. ; "verified") // val(. ; "status") // true)
    ] | @tsv
  ')

  if [[ ${#rows[@]} -eq 0 ]]; then
    echo "Keine Angebote gefunden" >&2
    exit 1
  fi

  tmpfile="$(mktemp)"
  {
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "offer_id" "model" "price" "tx" "eff" "dl" "rel" "vram_gb" "status" "score"
    for row in "${rows[@]}"; do
      IFS=$'\t' read -r oid model price tx eff dl rel vram status <<< "$row"
      score="$(score_offer "$eff" "$dl" "$rel" "$vram")"
      printf '%s\t%s\t%.4f\t%.4f\t%.4f\t%.1f\t%.2f\t%.1f\t%s\t%.1f\n' \
        "$oid" "$model" "$price" "$tx" "$eff" "$dl" "$rel" "$vram" "$status" "$score"
    done
  } > "$tmpfile"

  mapfile -t sorted < <(tail -n +2 "$tmpfile" | sort -t $'\t' -k10,10nr -k5,5n)

  printf '%-3s %-10s %-18s %7s %8s %8s %8s %7s %8s %5s %6s\n' "Nr" "Offer_ID" "Model" "\$/hr" "20GB Tx" "Eff$/h" "DLPerf" "Score" "VRAM GB" "Rel" "Status"
  printf '%s\n' "--------------------------------------------------------------------------------------------------------"

  limit=$(( RESULTS < ${#sorted[@]} ? RESULTS : ${#sorted[@]} ))
  for ((i=0; i<limit; i++)); do
    IFS=$'\t' read -r oid model price tx eff dl rel vram status score <<< "${sorted[$i]}"
    line=$(printf '%-3s %-10s %-18s %7.4f %8.4f %8.4f %8.1f %7.1f %8.1f %5.2f %6s' \
      "$((i+1))" "$oid" "$model" "$price" "$tx" "$eff" "$dl" "$score" "$vram" "$rel" "$status")
    case "$i" in
      0) green "$line" ;;
      1|2) yellow "$line" ;;
      3|4) blue "$line" ;;
      *) printf '%s' "$line" ;;
    esac
    printf '\n'
  done

  IFS=$'\t' read -r oid model price tx eff dl rel vram status score <<< "${sorted[0]}"
  echo
  echo "Vorschlag: Nummer 1 ($oid / $model)"

  if [[ $dry -eq 1 ]]; then
    rm -f "$tmpfile"
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

  IFS=$'\t' read -r oid model price tx eff dl rel vram status score <<< "${sorted[$((choice-1))]}"
  echo
  echo "Gewählt: $choice -> $oid / $model"

  if [[ $test -eq 1 ]]; then
    echo "[TEST] Kein Booking ausgeführt."
    rm -f "$tmpfile"
    exit 0
  fi

  read -r -p "Buchung wirklich ausführen? [j/N]: " confirm
  if [[ "${confirm,,}" != "j" ]]; then
    echo "Abgebrochen."
    rm -f "$tmpfile"
    exit 0
  fi

  echo "[INFO] Booking würde hier ausgeführt werden."
  rm -f "$tmpfile"
}

main "$@"
