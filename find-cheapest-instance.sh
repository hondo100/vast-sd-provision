#!/usr/bin/env bash
set -euo pipefail

VERSION="2026-05-24.13"
RESULTS=10
TX_GB=20.0
MIN_VRAM_GB=24.0
MIN_REL=0.95

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

  tmpfile="$(mktemp)"
  trap 'rm -f "$tmpfile"' EXIT

  query='gpu_name~=.* verified=true rentable=true'
  if ! vast_cmd search offers "$query" -o 'dlperf_usd-' > "$tmpfile" 2>/dev/null; then
    query='verified=true rentable=true'
    vast_cmd search offers "$query" -o 'dlperf_usd-' > "$tmpfile"
  fi

  echo "Hinweis: CLI-Ausgabe muss ggf. mit genauerem Parser an dein Format angepasst werden." >&2
  echo "Vorschlag: CLI-Suche ist angebunden, aber Output-Parsing ist noch generisch."

  if [[ $dry -eq 1 ]]; then
    exit 0
  fi
}

main "$@"
