#!/usr/bin/env bash
# =============================================================================
# find-cheapest-instance.sh | Version: 2026-06-04.07
# =============================================================================
#
# ZWECK
# -----
# Dieses Script sucht ueber die Vast.ai CLI nach guenstigen, fuer den eigenen
# Workflow geeigneten GPU-Angeboten, bewertet sie ueber eine externe
# scoring_engine.py, zeigt die bestplatzierten Ergebnisse tabellarisch an und
# kann optional direkt eine Instanz buchen.
#
# Das Script ist fuer einen Ablauf ausgelegt, bei dem:
# 1. ein Rohsuchlauf ueber Vast.ai erfolgt,
# 2. die Rohdaten an scoring_engine.py uebergeben werden,
# 3. die besten Treffer formatiert angezeigt werden,
# 4. optional eine Instanz mit einem bekannten Template-Hash gebucht wird,
# 5. die neu erzeugte Instanz-ID lokal gespeichert wird.
#
# WICHTIG ZUM TEMPLATE
# --------------------
# Fuer die Buchung ist kein Template-Name erforderlich. Vast.ai unterstuetzt
# die Erstellung einer Instanz direkt ueber einen Template-Hash
# (--template_hash / hash_id). Das Template liefert die benoetigten Default-
# Werte, sodass kein menschenlesbarer Name bekannt sein muss.
#
# WICHTIGER HINWEIS ZUR TEMPLATE-PRUEFUNG
# --------------------------------------
# Vast.ai unterstuetzt das direkte Erzeugen einer Instanz ueber
#   vastai create instance <offer_id> --template_hash <hash>
# wobei der Template-Hash als maßgeblicher Buchungsparameter dient.
#
# Zusaetzlich bietet Vast.ai mit
#   vastai search templates
# eine Suchfunktion fuer Templates an. Diese Suche ist jedoch nicht in jedem
# praktischen Fall ein verlaesslicher Vorab-Check dafuer, ob ein spaeterer
# create-instance-Aufruf mit --template_hash erfolgreich sein wird.
#
# Hintergrund:
# - Laut Vast-Dokumentation koennen Templates ueber ihre hash_id verwendet
#   werden.
# - Laut Vast-Dokumentation unterstuetzt create instance die Option
#   --template_hash direkt.
# - Laut Vast-Dokumentation liefert search templates Suchergebnisse ueber
#   eigene und oeffentlich geteilte Templates.
#
# Daraus folgt fuer dieses Script:
# - Die Template-Suche wird nur als weiche Zusatzpruefung behandelt.
# - Wenn search templates den Hash nicht bestaetigen kann, wird dies als
#   Warnung protokolliert, aber nicht mehr als harter Abbruch gewertet.
# - Die eigentliche Wahrheit liefert der reale Buchungsversuch mit
#   create instance --template_hash.
#
# ROBUSTHEIT
# ----------
# Diese Version verbessert gegenueber einer einfacheren Fassung vor allem:
# - sichere Temp-Dateien statt fester /tmp-Pfade;
# - Vorab-Pruefung von CLI und Authentifizierung;
# - optionale weiche Validierung des Template-Hashs vor der Buchung;
# - defensive Behandlung leerer oder fehlerhafter Suchergebnisse;
# - robustere Extraktion der neu erzeugten Instanz-ID aus CLI-Ausgaben;
# - saubere Trennung von Suchphase, Bewertungsphase und Buchungsphase;
# - sicherer EXIT-Trap auch bei set -u / nounset.
#
# DATEIEN
# -------
# Standardmaessig werden diese lokalen Dateien verwendet:
# - PARAMS_JSON: Eingabe fuer scoring_engine.py
# - STATE_FILE:  Ziel fuer die gebuchte Instanz-ID
#
# Externe lokale Dateien:
# - ./scoring_engine.py muss vorhanden und ausfuehrbar via python3 sein
# - ./params.json sollte vorhanden sein, sofern scoring_engine.py dies erwartet
#
# STEUERUNGSVARIABLEN
# -------------------
# Diese Variablen koennen direkt im Script oder per Environment angepasst
# werden.
#
# Suche und Anzeige:
# - VERSION
#   Script-Version fuer Logging.
#
# - RESULTS
#   Maximale Anzahl ausgegebener Treffer.
#
# - QUERY
#   Vast.ai Suchquery fuer offers. Diese Query wird direkt an
#   "vastai search offers" uebergeben.
#
# - GPU_FILTER
#   Regex-Filter, der an scoring_engine.py durchgereicht wird.
#
# - MODEL_GB
#   Geschaetzte Modellgroesse in GiB fuer die Bewertung.
#
# - SESSION_HOURS
#   Erwartete Laufzeit der Session in Stunden fuer die Bewertung.
#
# - PARAMS_JSON
#   Parameterdatei fuer scoring_engine.py.
#
# Buchung:
# - TEMPLATE_HASH
#   Hash-ID des zu verwendenden Vast.ai Templates.
#
# - DISK_GB
#   Gewuenschte Disk-Groesse fuer die Instanz.
#
# - STATE_FILE
#   Datei, in die die neue Instanz-ID geschrieben wird.
#
# - VALIDATE_TEMPLATE_HASH
#   1 = Template-Hash vor Buchung weich via "search templates" pruefen.
#   0 = keine Vorab-Pruefung.
#
# - TEMPLATE_QUERY_MODE
#   Art der Hash-Pruefung. Standard ist ein einfacher Query-Ausdruck mit hash_id.
#
# MODI UND ARGUMENTE
# ------------------
# Das Script kennt diese Optionen:
#
# --test
#   Ueberspringt die echte Vast-Suche und arbeitet mit leerer/extern
#   vorbereiteter Testdatenbasis. Nuetzlich fuer Parser- und Format-Tests.
#
# --dry-run
#   Simuliert die Buchung, fuehrt aber kein "create instance" aus.
#
# --book [NUM]
#   Startet den Buchungsfluss. Wenn NUM angegeben ist, wird direkt der
#   entsprechende Listenplatz verwendet; sonst erfolgt eine Rueckfrage.
#
# HEURISTIKEN
# -----------
# - China wird bereits in der Vast-Query ausgeschlossen:
#     geolocation notin [CN]
# - Zusaetzlich werden lokal Zeilen verworfen, deren Geo-Feld nur aus ","
#   besteht, da solche Faelle in der Praxis als unbrauchbare/inkonsistente
#   Geo-Daten behandelt werden.
#
# ABLAUF
# ------
# 1. CLI und Python pruefen.
# 2. Vast-Authentifizierung per "show user" testen.
# 3. scoring_engine.py und params.json pruefen.
# 4. Angebotsdaten via "search offers --raw" laden.
# 5. Rohdaten an scoring_engine.py uebergeben.
# 6. Ergebniszeilen lokal nach Geo-Heuristik filtern.
# 7. Tabellenansicht erzeugen und Top-Angebote markieren.
# 8. Optional weiche Template-Pruefung ausfuehren.
# 9. Optional Buchung ausfuehren und neue Instanz-ID sichern.
# 10. Temp-Dateien robust bereinigen.
#
# BEISPIELE
# ---------
# Nur Suche und Anzeige:
#   bash find-cheapest-instance.sh
#
# Buchungsdialog starten:
#   bash find-cheapest-instance.sh --book
#
# Direkt Platz 2 buchen:
#   bash find-cheapest-instance.sh --book 2
#
# Buchung nur simulieren:
#   bash find-cheapest-instance.sh --book 1 --dry-run
#
# Template-Vorabpruefung deaktivieren:
#   VALIDATE_TEMPLATE_HASH=0 bash find-cheapest-instance.sh --book
#
# =============================================================================

export PATH="$PATH:$HOME/.local/bin:/usr/local/bin:/usr/bin"
set -Eeuo pipefail

VERSION="${VERSION:-2026-06-04.06}"
RESULTS="${RESULTS:-10}"
QUERY="${QUERY:-external=false rentable=true verified=true gpu_ram>=24 disk_space>=40 geolocation notin [CN]}"
GPU_FILTER="${GPU_FILTER:-RTX (3090|4090|A5000|A6000|5000|6000)}"
DISK_GB="${DISK_GB:-15}"
TEMPLATE_HASH="${TEMPLATE_HASH:-47911bdece931900f38147222e3765a8}"
MODEL_GB="${MODEL_GB:-20}"
SESSION_HOURS="${SESSION_HOURS:-3}"
PARAMS_JSON="${PARAMS_JSON:-./params.json}"
STATE_FILE="${STATE_FILE:-/home/werner/github-scripts/.current_instance}"
VALIDATE_TEMPLATE_HASH="${VALIDATE_TEMPLATE_HASH:-1}"
TEMPLATE_QUERY_MODE="${TEMPLATE_QUERY_MODE:-hash_id}"

tmp_json=""

c() { printf '\033[%sm%s\033[0m\n' "$1" "$2"; }
log() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARNUNG] %s\n' "$*" >&2; }
ok() { printf '[SUCCESS] %s\n' "$*"; }
die() { printf '[FEHLER] %s\n' "$*" >&2; exit 1; }

vast_cmd() {
    if command -v vastai >/dev/null 2>&1; then
        vastai "$@"
    elif command -v vast >/dev/null 2>&1; then
        vast "$@"
    else
        die "'vastai' CLI nicht gefunden."
    fi
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Benoetigter Befehl fehlt: $1"
}

check_auth() {
    vast_cmd show user >/dev/null 2>&1 || die "Vast.ai CLI ist nicht authentifiziert oder aktuell nicht erreichbar."
    ok "Vast.ai CLI/Auth-Pruefung erfolgreich."
}

ensure_inputs() {
    [[ -f "./scoring_engine.py" ]] || die "scoring_engine.py nicht gefunden."
    [[ -f "$PARAMS_JSON" ]] || die "Parameterdatei nicht gefunden: $PARAMS_JSON"
    ok "Lokale Eingabedateien vorhanden."
}

validate_template_hash() {
    [[ "$VALIDATE_TEMPLATE_HASH" == "1" ]] || return 0
    [[ -n "$TEMPLATE_HASH" ]] || die "TEMPLATE_HASH ist leer."

    local query=""
    local out=""
    local rc=0

    if [[ "$TEMPLATE_QUERY_MODE" == "hash_id" ]]; then
        query="hash_id=='$TEMPLATE_HASH'"
    else
        query="$TEMPLATE_HASH"
    fi

    out="$(vast_cmd search templates --raw "$query" 2>&1)" || rc=$?

    if [[ $rc -ne 0 ]]; then
        warn "Template-Suche fehlgeschlagen, fahre trotzdem fort. Query: $query | Ausgabe: $out"
        return 0
    fi

    if [[ -z "$out" || "$out" == "[]" ]]; then
        warn "Template-Hash konnte per 'search templates' nicht bestaetigt werden, verwende ihn trotzdem fuer create instance: $TEMPLATE_HASH"
        return 0
    fi

    ok "Template-Hash validiert: $TEMPLATE_HASH"
}

extract_new_contract_id() {
    local text="$1"
    local extracted=""

    if command -v grep >/dev/null 2>&1; then
        extracted="$(printf '%s\n' "$text" | grep -oP "(contract #|'new_contract':\s*|\"new_contract\":\s*)\K\d+" | head -n1 || true)"
    fi

    if [[ -z "$extracted" ]]; then
        extracted="$(printf '%s\n' "$text" | sed -n -E "s/.*(contract #|'new_contract':[[:space:]]*|\"new_contract\":[[:space:]]*)([0-9]+).*/\2/p" | head -n1)"
    fi

    printf '%s' "$extracted"
}

main() {
    local DO_BOOK=0
    local BOOK_INDEX=""
    local TEST_MODE=0
    local DRY_RUN=0
    local parsed=""
    local line=""
    local raw_line=""
    local geo_field=""
    local i=0
    local cheapest_idx=-1
    local min_test="999999999"
    local j=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --test) TEST_MODE=1 ;;
            --dry-run) DRY_RUN=1 ;;
            --book)
                DO_BOOK=1
                if [[ $# -gt 1 && "${2:-}" =~ ^[0-9]+$ ]]; then
                    BOOK_INDEX="$2"
                    shift
                fi
                ;;
            *)
                echo "Usage: $0 [--test] [--dry-run] [--book [NUM]]"
                exit 1
                ;;
        esac
        shift
    done

    require_cmd python3
    require_cmd mktemp
    check_auth
    ensure_inputs

    echo "========================================================================================="
    echo "Skript-Version: $VERSION | Filter: $GPU_FILTER"
    echo "Query: $QUERY"
    echo "Modus: Entkoppelte Inferenz mit automatisierter Status-Erfassung"
    echo "Template-Hash: $TEMPLATE_HASH"
    echo "========================================================================================="

    tmp_json="$(mktemp /tmp/vast_offers.XXXXXX.json)"
    trap 'rm -f -- "${tmp_json:-}"' EXIT

    if [[ "$TEST_MODE" -ne 1 ]]; then
        log "Lade Angebotsdaten via Vast.ai..."
        vast_cmd search offers --raw "$QUERY" -o 'dlperf_usd-' --limit 120 > "$tmp_json"
    else
        log "TEST_MODE=1, verwende leere Testdatenbasis."
        : > "$tmp_json"
    fi

    log "Bewerte Angebote via scoring_engine.py..."
    parsed="$(python3 ./scoring_engine.py \
        --gpu_filter "$GPU_FILTER" \
        --model_gb "$MODEL_GB" \
        --session_hours "$SESSION_HOURS" \
        --params "$PARAMS_JSON" < "$tmp_json")"

    mapfile -t lines <<< "$parsed"

    local filtered_lines=()
    for raw_line in "${lines[@]}"; do
        [[ -z "$raw_line" ]] && continue
        IFS=$'\t' read -r _ _ _ _ _ _ _ _ _ _ _ geo_field _ <<< "$raw_line"

        if [[ "$geo_field" =~ ^[[:space:]]*,[[:space:]]*$ ]]; then
            log "Filtere Angebot mit Geo=',' heraus (China-Heuristik)."
            continue
        fi

        filtered_lines+=("$raw_line")
    done

    lines=("${filtered_lines[@]}")

    if [[ ${#lines[@]} -eq 0 ]]; then
        warn "Keine passenden nicht-chinesischen Instanzen nach Filterung gefunden."
        exit 2
    fi

    printf "%-5s %-12s %-16s %-5s %-7s %-7s %-8s %-7s %-6s %-5s %-6s %-4s %-6s\n" \
        "Nr" "ID" "Model" "GPUs" "$/hr" "Init$" "Eff$/h" "DLMB/s" "Ready" "VRAM" "DskBW" "Geo" "Score"
    printf '%s\n' "-----------------------------------------------------------------------------------------------------------------"

    local rows=()

    for j in "${!lines[@]}"; do
        [[ $j -ge $RESULTS ]] && break
        [[ -z "${lines[$j]}" ]] && continue

        local test_c=""
        IFS=$'\t' read -r _ _ _ _ _ _ _ _ _ _ _ _ test_c <<< "${lines[$j]}"

        if python3 - "$test_c" "$min_test" <<'PY'
import sys
a=float(sys.argv[1]); b=float(sys.argv[2])
raise SystemExit(0 if a < b else 1)
PY
        then
            min_test="$test_c"
            cheapest_idx="$j"
        fi
    done

    for j in "${!lines[@]}"; do
        [[ $j -ge $RESULTS ]] && break
        [[ -z "${lines[$j]}" ]] && continue

        local id="" model="" ngpu="" dph="" init="" eff="" dl="" ready="" vram="" dbw="" geo="" score="" test_c=""
        IFS=$'\t' read -r id model ngpu dph init eff dl ready vram dbw geo score test_c <<< "${lines[$j]}"

        line="$(printf "%-5d %-12s %-16s %-5s %-7.2f %-7.2f %-8.2f %-7.0f %-6.0f %-5.0f %-6.0f %-4s %-6.2f" \
            "$((j+1))" "$id" "$model" "$ngpu" "$dph" "$init" "$eff" "$dl" "$ready" "$vram" "$dbw" "$geo" "$score")"

        if [[ "$j" -eq 0 && "$j" -eq "$cheapest_idx" ]]; then
            c 36 "$line (Top & Best Test)"
        elif [[ "$j" -eq 0 ]]; then
            c 32 "$line (Top Score)"
        elif [[ "$j" -eq "$cheapest_idx" ]]; then
            c 33 "$line (Best Test)"
        else
            printf '%s\n' "$line"
        fi

        rows+=("$id|$model")
        i=$((i + 1))
    done

    if [[ ${#rows[@]} -eq 0 ]]; then
        warn "Keine darstellbaren Angebote vorhanden."
        exit 2
    fi

    if [[ "$DO_BOOK" -eq 1 ]]; then
        validate_template_hash

        if [[ -z "$BOOK_INDEX" ]]; then
            echo ""
            read -r -p "Nr zur Buchung (oder 'q' zum Beenden): " BOOK_INDEX
        fi

        [[ "$BOOK_INDEX" == "q" ]] && { echo "Abbruch."; exit 0; }
        [[ "$BOOK_INDEX" =~ ^[0-9]+$ ]] || die "Ungueltige Auswahl: $BOOK_INDEX"

        if [[ "$DRY_RUN" -eq 1 ]]; then
            echo "[DRY-RUN] Instanz $BOOK_INDEX waere gebucht worden."
            exit 0
        fi

        local idx=$((BOOK_INDEX - 1))
        if [[ $idx -lt 0 || $idx -ge ${#rows[@]} ]]; then
            die "Ungueltige Auswahl."
        fi

        local sel="${rows[$idx]}"
        local target_id="${sel%|*}"

        read -r -p "Buchung $target_id (${sel#*|}) mit Template $TEMPLATE_HASH bestaetigen [y/N]: " conf
        if [[ "$conf" == [yY] ]]; then
            echo "[PROZESS] Sende Buchungsbefehl an Vast.ai..."

            local book_output=""
            local rc=0

            book_output="$(vast_cmd create instance "$target_id" --template_hash "$TEMPLATE_HASH" --disk "$DISK_GB" 2>&1)" || rc=$?
            echo "$book_output"

            if [[ $rc -ne 0 ]]; then
                die "Buchung fehlgeschlagen."
            fi

            local extracted_id=""
            extracted_id="$(extract_new_contract_id "$book_output")"

            if [[ -n "$extracted_id" ]]; then
                mkdir -p "$(dirname "$STATE_FILE")"
                echo "$extracted_id" > "$STATE_FILE"
                ok "Instanz-ID $extracted_id wurde in $STATE_FILE gesichert."
            else
                warn "Instanz wurde moeglicherweise gestartet, aber die ID-Extraktion schlug fehl."
                warn "Bitte pruefen Sie den Zustand manuell via 'vastai show instances'."
                exit 1
            fi
        else
            echo "Abbruch."
        fi
    fi
}

main "$@"
