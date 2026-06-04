#!/usr/bin/env bash
# =============================================================================
# find-cheapest-instance.sh | Version: 2026-06-04.09
# =============================================================================
#
# ZWECK
# -----
# Dieses Script sucht ueber die Vast.ai CLI nach guenstigen, fuer den eigenen
# Workflow geeigneten GPU-Angeboten, bewertet sie ueber eine externe
# scoring_engine.py, zeigt die bestplatzierten Ergebnisse tabellarisch an und
# kann optional direkt eine Instanz buchen.
#
# Diese Fassung haertet den Buchungsfluss speziell gegen falsch uebernommene
# Template-Storage-Werte:
# - kein impliziter Disk-Override;
# - Sicherheitspruefung fuer explizites DISK_GB;
# - harter Post-Check der real erzeugten Instanz;
# - automatische Zerstoerung der Instanz bei zu kleiner Storage-Groesse;
# - Fehler, wenn der Template-Hash vorab nicht bestaetigt werden kann und
#   STRICT_TEMPLATE_VALIDATION=1 gesetzt ist.
#
# WICHTIG
# -------
# Vast-Templates liefern Default-Werte fuer die Instanzerstellung, koennen aber
# durch explizite Optionen ueberschrieben werden. [web:375][web:363]
# Disk/Storage ist nach der Erstellung nicht mehr aenderbar. [web:373][web:382]
# Falsch erzeugte Instanzen sollten daher sofort wieder zerstoert werden. [web:470]
#
# =============================================================================

export PATH="$PATH:$HOME/.local/bin:/usr/local/bin:/usr/bin"
set -Eeuo pipefail

VERSION="${VERSION:-2026-06-04.09}"
RESULTS="${RESULTS:-10}"
QUERY="${QUERY:-external=false rentable=true verified=true gpu_ram>=24 disk_space>=40 geolocation notin [CN]}"
GPU_FILTER="${GPU_FILTER:-RTX (3090|4090|A5000|A6000|5000|6000)}"

DISK_GB="${DISK_GB:-}"
EXPECTED_TEMPLATE_DISK_GB="${EXPECTED_TEMPLATE_DISK_GB:-80}"
MIN_DISK_GB="${MIN_DISK_GB:-80}"
ENFORCE_DISK_GUARD="${ENFORCE_DISK_GUARD:-1}"
REQUIRE_EXPLICIT_CONFIRM="${REQUIRE_EXPLICIT_CONFIRM:-1}"
POSTCHECK_INSTANCE="${POSTCHECK_INSTANCE:-1}"
AUTO_DESTROY_BAD_STORAGE="${AUTO_DESTROY_BAD_STORAGE:-1}"
STRICT_TEMPLATE_VALIDATION="${STRICT_TEMPLATE_VALIDATION:-1}"

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
        if [[ "$STRICT_TEMPLATE_VALIDATION" == "1" ]]; then
            die "Template-Suche fehlgeschlagen. STRICT_TEMPLATE_VALIDATION=1. Query: $query | Ausgabe: $out"
        fi
        warn "Template-Suche fehlgeschlagen, fahre trotzdem fort. Query: $query | Ausgabe: $out"
        return 0
    fi

    if [[ -z "$out" || "$out" == "[]" ]]; then
        if [[ "$STRICT_TEMPLATE_VALIDATION" == "1" ]]; then
            die "Template-Hash konnte per 'search templates' nicht bestaetigt werden: $TEMPLATE_HASH"
        fi
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

validate_disk_value_if_set() {
    if [[ -z "${DISK_GB:-}" ]]; then
        log "DISK_GB ist leer: Es wird kein --disk uebergeben, Template-Default bleibt aktiv."
        return 0
    fi

    [[ "$DISK_GB" =~ ^[0-9]+$ ]] || die "DISK_GB muss eine ganze Zahl sein oder leer. Aktuell: $DISK_GB"

    if (( DISK_GB < MIN_DISK_GB )); then
        if [[ "$ENFORCE_DISK_GUARD" == "1" ]]; then
            die "DISK_GB=$DISK_GB ist kleiner als MIN_DISK_GB=$MIN_DISK_GB. Buchung aus Sicherheitsgruenden abgebrochen."
        else
            warn "DISK_GB=$DISK_GB ist kleiner als MIN_DISK_GB=$MIN_DISK_GB."
        fi
    fi

    if (( DISK_GB < EXPECTED_TEMPLATE_DISK_GB )); then
        warn "DISK_GB=$DISK_GB ist kleiner als EXPECTED_TEMPLATE_DISK_GB=$EXPECTED_TEMPLATE_DISK_GB und kann das Template nach unten ueberschreiben."
    fi
}

print_booking_summary() {
    local target_id="$1"
    local model_name="$2"

    echo "-----------------------------------------------------------------------------------------"
    echo "Buchungs-Zusammenfassung"
    echo "  Offer-ID:                 $target_id"
    echo "  Modell:                   $model_name"
    echo "  Template-Hash:            $TEMPLATE_HASH"
    echo "  Erwartete Template-Disk:  ${EXPECTED_TEMPLATE_DISK_GB} GB"
    if [[ -n "${DISK_GB:-}" ]]; then
        echo "  Expliziter Disk-Override: ${DISK_GB} GB"
    else
        echo "  Expliziter Disk-Override: <kein Override, Template-Default aktiv>"
    fi
    echo "  Disk-Guard Minimum:       ${MIN_DISK_GB} GB"
    echo "  Query:                    $QUERY"
    echo "-----------------------------------------------------------------------------------------"
}

confirm_booking() {
    local target_id="$1"
    local model_name="$2"
    local conf=""

    print_booking_summary "$target_id" "$model_name"

    if [[ "$REQUIRE_EXPLICIT_CONFIRM" == "1" ]]; then
        read -r -p "Diese Werte wirklich fuer create instance verwenden? [y/N]: " conf
        [[ "$conf" == [yY] ]] || { echo "Abbruch."; exit 0; }
    fi

    read -r -p "Buchung $target_id ($model_name) mit Template $TEMPLATE_HASH bestaetigen [y/N]: " conf
    [[ "$conf" == [yY] ]] || { echo "Abbruch."; exit 0; }
}

get_instance_row() {
    local instance_id="$1"
    vast_cmd show instances 2>/dev/null | awk -v id="$instance_id" '
        $2 == id { print; found=1 }
        END { if (!found) exit 1 }
    '
}

extract_storage_from_row() {
    local row="$1"
    awk '{print $10}' <<< "$row" | tr -dc '0-9.'
}

destroy_bad_instance() {
    local instance_id="$1"
    warn "Zerstoere Instanz $instance_id wegen ungueltiger Storage-Groesse..."
    vast_cmd destroy instance "$instance_id" >/dev/null 2>&1 || warn "Destroy fuer Instanz $instance_id konnte nicht bestaetigt werden."
}

postcheck_instance_storage() {
    local instance_id="$1"
    [[ "$POSTCHECK_INSTANCE" == "1" ]] || return 0

    echo ""
    log "Versuche Nachcheck der erzeugten Instanz-ID $instance_id ..."

    local row=""
    local storage_val=""

    if ! row="$(get_instance_row "$instance_id")"; then
        warn "Post-Check konnte keine Zeile fuer Instanz $instance_id finden."
        return 0
    fi

    printf '%s\n' "$row"

    storage_val="$(extract_storage_from_row "$row")"
    if [[ -z "$storage_val" ]]; then
        warn "Storage-Wert konnte aus dem Post-Check nicht extrahiert werden."
        return 0
    fi

    log "Extrahierter Storage-Wert: ${storage_val} GB"

    if python3 - "$storage_val" "$EXPECTED_TEMPLATE_DISK_GB" <<'PY'
import sys
a=float(sys.argv[1]); b=float(sys.argv[2])
raise SystemExit(0 if a + 1e-9 < b else 1)
PY
    then
        warn "Instanz hat zu wenig Storage: ${storage_val} GB < ${EXPECTED_TEMPLATE_DISK_GB} GB"

        if [[ "$AUTO_DESTROY_BAD_STORAGE" == "1" ]]; then
            destroy_bad_instance "$instance_id"
        fi

        die "Buchung verworfen: Tatsaechliche Storage-Groesse ist kleiner als erwartet."
    fi

    ok "Post-Check erfolgreich: Storage ${storage_val} GB >= ${EXPECTED_TEMPLATE_DISK_GB} GB"
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
    require_cmd awk
    check_auth
    ensure_inputs
    validate_disk_value_if_set

    echo "========================================================================================="
    echo "Skript-Version: $VERSION | Filter: $GPU_FILTER"
    echo "Query: $QUERY"
    echo "Modus: Entkoppelte Inferenz mit automatisierter Status-Erfassung"
    echo "Template-Hash: $TEMPLATE_HASH"
    if [[ -n "${DISK_GB:-}" ]]; then
        echo "Disk-Override: $DISK_GB GB"
    else
        echo "Disk-Override: <kein Override, Template-Default>"
    fi
    echo "Expected Template Disk: $EXPECTED_TEMPLATE_DISK_GB GB"
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
        local model_name="${sel#*|}"

        confirm_booking "$target_id" "$model_name"

        echo "[PROZESS] Sende Buchungsbefehl an Vast.ai..."

        local book_output=""
        local rc=0
        local create_args=()

        create_args=(create instance "$target_id" --template_hash "$TEMPLATE_HASH")
        if [[ -n "${DISK_GB:-}" ]]; then
            create_args+=(--disk "$DISK_GB")
        fi

        book_output="$(vast_cmd "${create_args[@]}" 2>&1)" || rc=$?
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
            postcheck_instance_storage "$extracted_id"
        else
            warn "Instanz wurde moeglicherweise gestartet, aber die ID-Extraktion schlug fehl."
            warn "Bitte den Zustand manuell via 'vastai show instances' pruefen."
            exit 1
        fi
    fi
}

main "$@"
