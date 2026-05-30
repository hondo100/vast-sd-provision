#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# find-cheapest-instance.sh | Version: 2026-05-30.02 (Automated State Engine)
# -----------------------------------------------------------------------------
export PATH=$PATH:~/.local/bin:/usr/local/bin:/usr/bin
set -eEuo pipefail

VERSION="2026-05-30.02"
RESULTS=10
QUERY='external=false rentable=true verified=true gpu_ram>=24 disk_space>=40'
GPU_FILTER='RTX (3090|4090|A5000|A6000|5000|6000)'
DISK_GB=40
TEMPLATE_HASH="ad0935fab3e1f781fa442c1604ed07e2"
MODEL_GB=20
SESSION_HOURS=3
PARAMS_JSON="./params.json"
STATE_FILE="/home/werner/github-scripts/.current_instance"

c() { printf '\033[%sm%s\033[0m\n' "$1" "$2"; }

vast_cmd() {
    if command -v vastai >/dev/null 2>&1; then vastai "$@"
    elif command -v vast >/dev/null 2>&1; then vast "$@"
    else echo "[ERROR] 'vastai' CLI nicht gefunden."; exit 1; fi
}

main() {
  local DO_BOOK=0; local BOOK_INDEX=""; local TEST_MODE=0; local DRY_RUN=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --test) TEST_MODE=1 ;; 
      --dry-run) DRY_RUN=1 ;;
      --book) DO_BOOK=1; [[ $# -gt 1 && "$2" =~ ^[0-9]+$ ]] && BOOK_INDEX="$2" && shift ;;
      *) echo "Usage: $0 [--test] [--dry-run] [--book [NUM]]"; exit 1 ;;
    esac
    shift
  done

  echo "========================================================================================="
  echo "Skript-Version: $VERSION | Filter: $GPU_FILTER"
  echo "Modus: Entkoppelte Inferenz mit automatisierter Status-Erfassung"
  echo "========================================================================================="

  # Datenbeschaffung
  if [[ "$TEST_MODE" -ne 1 ]]; then
      vast_cmd search offers --raw "$QUERY" -o 'dlperf_usd-' --limit 120 > /tmp/vast_data.json
  else
      touch /tmp/vast_data.json
  fi
  
  # Stream-Verarbeitung über Standard-Unix-Pipe
  local parsed
  parsed="$(cat /tmp/vast_data.json | python3 ./scoring_engine.py \
      --gpu_filter "$GPU_FILTER" \
      --model_gb "$MODEL_GB" \
      --session_hours "$SESSION_HOURS" \
      --params "$PARAMS_JSON")"

  # Tabellenkopf (Schnittstellen-Breiten exakt bewahrt)
  printf "%-5s %-12s %-16s %-5s %-7s %-7s %-8s %-7s %-6s %-5s %-6s %-4s %-6s\n" "Nr" "ID" "Model" "GPUs" "$/hr" "Init$" "Eff$/h" "DLMB/s" "Ready" "VRAM" "DskBW" "Geo" "Score"
  printf '%s\n' "-----------------------------------------------------------------------------------------------------------------"
  
  local i=0; local rows=(); local cheapest_idx=-1; local min_test=999999
  
  # Erster Durchlauf: Günstigste Instanz für Test-Kosten ermitteln
  mapfile -t lines <<< "$parsed"
  for j in "${!lines[@]}"; do
    [[ $j -ge $RESULTS ]] && break
    [[ -z "${lines[$j]}" ]] && continue
    IFS=$'\t' read -r _ _ _ _ _ _ _ _ _ _ _ _ test_c <<< "${lines[$j]}"
    if (( $(echo "$test_c < $min_test" | bc -l) )); then 
        min_test=$test_c
        cheapest_idx=$j
    fi
  done

  # Zweiter Durchlauf: Formatierte und farbkodierte Ausgabe
  for j in "${!lines[@]}"; do
    [[ $j -ge $RESULTS ]] && break
    [[ -z "${lines[$j]}" ]] && continue
    IFS=$'\t' read -r id model ngpu dph init eff dl ready vram dbw geo score test_c <<< "${lines[$j]}"
    
    line=$(printf "%-5d %-12s %-16s %-5s %-7.2f %-7.2f %-8.2f %-7.0f %-6.0f %-5.0f %-6.0f %-4s %-6.2f" "$((j+1))" "$id" "$model" "$ngpu" "$dph" "$init" "$eff" "$dl" "$ready" "$vram" "$dbw" "$geo" "$score")
    
    if [ "$j" -eq 0 ] && [ "$j" -eq "$cheapest_idx" ]; then c 36 "$line (Top & Best Test)"
    elif [ "$j" -eq 0 ]; then c 32 "$line (Top Score)"
    elif [ "$j" -eq "$cheapest_idx" ]; then c 33 "$line (Best Test)"
    else printf '%s\n' "$line"; fi
    rows+=("$id|$model")
  done

  # Interaktive Buchungslogik
  if [[ "$DO_BOOK" -eq 1 ]]; then
    if [[ -z "$BOOK_INDEX" ]]; then
        echo ""
        read -p "Nr zur Buchung (oder 'q' zum Beenden): " BOOK_INDEX
    fi
    [[ "$BOOK_INDEX" == "q" ]] && { echo "Abbruch."; exit 0; }
    [[ "$DRY_RUN" -eq 1 ]] && { echo "[DRY-RUN] Instanz $BOOK_INDEX wäre gebucht."; exit 0; }
    
    local idx=$((BOOK_INDEX-1))
    if [[ $idx -lt 0 || $idx -ge ${#rows[@]} ]]; then
        echo "[FEHLER] Ungültige Auswahl."
        exit 1
    fi
    
    local sel="${rows[$idx]}"
    local target_id="${sel%|*}"
    read -p "Buchung $target_id (${sel#*|}) bestätigen [y/N]: " conf
    if [[ "$conf" == [yY] ]]; then
        echo "[PROZESS] Sende Buchungsbefehl an Vast.ai..."
        
        # Abfangen des CLI-Response-Strings (Kopplung von stdout und stderr)
        local book_output
        book_output=$(vast_cmd create instance "$target_id" --template_hash "$TEMPLATE_HASH" --disk "$DISK_GB" 2>&1)
        echo "$book_output"
        
        # Stufe 1: Extraktion via Perl-compatible Regular Expressions (PCRE)
        local extracted_id=""
        if command -v grep >/dev/null 2>&1; then
            extracted_id=$(echo "$book_output" | grep -oP 'contract #\K\d+' || true)
        fi
        
        # Stufe 2: Fallback via POSIX-sed, falls PCRE-grep im WSL blockiert ist
        if [[ -z "$extracted_id" ]]; then
            extracted_id=$(echo "$book_output" | sed -n 's/.*contract #\([0-9]\+\).*/\1/p')
        fi
        
        # Stufe 3: Zustandsspeicherung evaluieren
        if [[ -n "$extracted_id" ]]; then
            echo "$extracted_id" > "$STATE_FILE"
            echo "[INFO] Instanz-ID $extracted_id wurde vollautomatisch in $STATE_FILE gesichert."
        else
            echo "[WARNUNG] Instanz wurde gestartet, aber die ID-Extraktion schlug fehl."
            echo "Bitte prüfen Sie den Zustand manuell via 'vastai show instances-v1'."
        fi
    fi
  fi
}
main "$@"
