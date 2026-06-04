#!/usr/bin/env bash
# =============================================================================
# find-cheapest-instance.sh | Version: 2026-06-04.12
# =============================================================================
#
# ZWECK
# -----
# Dieses Script sucht ueber die Vast.ai CLI nach guenstigen, fuer den eigenen
# Workflow geeigneten GPU-Angeboten. Die gefundenen Angebote werden durch
# scoring_engine.py ausgewertet, tabellarisch dargestellt und koennen optional
# direkt gebucht werden.
#
# SCHWERPUNKT DIESER FASSUNG
# -------------------------
# Diese Version haertet insbesondere den Buchungsfluss gegen Fehlkonfigurationen
# beim Einsatz von Vast-Templates und gegen Unterschiede zwischen alter und
# neuer Vast.ai CLI:
#
# - Template-Hash wird vor der Buchung optional validiert.
# - Die Validierung nutzt mehrere Fallbacks fuer unterschiedliche CLI-Versionen.
# - Es gibt keinen impliziten Disk-Override.
# - Ein explizites DISK_GB wird vorab gegen Sicherheitsgrenzen geprueft.
# - Nach der Buchung wird die reale Instanz optional nachgeprueft.
# - Falls die erzeugte Storage-Groesse kleiner als erwartet ist, kann die
#   Instanz automatisch sofort wieder zerstoert werden.
# - Ein ERR-Trap gibt bei Abbruechen Zeile, Exit-Code und letzten Befehl aus.
#
# HINTERGRUND
# -----------
# Vast-Templates liefern Standardwerte fuer die Instanzerstellung, koennen aber
# durch explizit uebergebene Request-Werte ueberschrieben werden. Die aktuelle
# Vast-Dokumentation beschreibt fuer `search templates` sowohl einen API-Weg mit
# Filterobjekten als auch in der CLI eine einfache Query-Syntax. Deshalb nutzt
# dieses Script mehrere Validierungswege, um mit unterschiedlichen CLI-Staenden
# robust zu bleiben. [web:488][web:566]
#
# Fuer die Instanzerstellung wird `--template_hash` verwendet, was in der Vast
# CLI dokumentiert und seit Produkt-Updates explizit unterstuetzt ist. [web:504][web:576]
#
# FUNKTIONSUEBERSICHT
# ------------------
# 1. Vast.ai CLI und lokale Dateien pruefen.
# 2. Angebote per Vast.ai laden.
# 3. Angebote mit scoring_engine.py bewerten.
# 4. Ergebnisse filtern und tabellarisch darstellen.
# 5. Optional ein Angebot auswaehlen und buchen.
# 6. Template-Hash vorab validieren, mit CLI-Fallbacks.
# 7. Gebuchte Instanz-ID extrahieren und speichern.
# 8. Storage der real erzeugten Instanz nachpruefen.
# 9. Bei zu kleiner Storage-Groesse optional automatisch zerstoeren.
#
# BENOETIGTE DATEIEN
# ------------------
# - ./scoring_engine.py
#   Bewertet Vast-Angebote und erzeugt tab-separierte Ergebniszeilen.
#
# - ./params.json
#   Eingabeparameter fuer scoring_engine.py.
#
# BENOETIGTE TOOLS
# ----------------
# - bash
# - python3
# - awk
# - mktemp
# - Vast.ai CLI: entweder `vastai` oder `vast`
#
# WICHTIGE UMGEBUNGSVARIABLEN
# --------------------------
# - QUERY
#   Vast-Angebotsfilter fuer `search offers`.
#
# - GPU_FILTER
#   Regex/Filter fuer erlaubte GPU-Modelle in der Scoring-Logik.
#
# - RESULTS
#   Maximale Anzahl an Ergebnissen, die angezeigt werden.
#
# - TEMPLATE_HASH
#   Hash-ID des Vast-Templates fuer `create instance --template_hash`.
#
# - VALIDATE_TEMPLATE_HASH
#   1 = Template-Hash vor Buchung pruefen
#   0 = keine Vorab-Pruefung
#
# - STRICT_TEMPLATE_VALIDATION
#   1 = Abbruch, wenn Template nicht bestaetigt werden kann
#   0 = Warnung, aber Fortsetzung
#
# - DISK_GB
#   Expliziter Disk-Override in GB. Leer = kein `--disk`, Template-Default
#   bleibt aktiv.
#
# - EXPECTED_TEMPLATE_DISK_GB
#   Erwartete Mindestgroesse der Storage, die nach Buchung erreicht sein soll.
#
# - MIN_DISK_GB
#   Sicherheitsgrenze fuer explizit gesetztes DISK_GB.
#
# - ENFORCE_DISK_GUARD
#   1 = hart abbrechen, wenn DISK_GB unter MIN_DISK_GB liegt
#   0 = nur warnen
#
# - POSTCHECK_INSTANCE
#   1 = erzeugte Instanz nach der Buchung pruefen
#   0 = kein Nachcheck
#
# - AUTO_DESTROY_BAD_STORAGE
#   1 = Instanz bei zu kleiner Storage automatisch zerstoeren
#   0 = nur Fehler melden
#
# - REQUIRE_EXPLICIT_CONFIRM
#   1 = vor Buchung interaktive Bestaetigung erzwingen
#   0 = ohne Zusatzbestaetigung fortfahren
#
# - STATE_FILE
#   Datei, in die die erzeugte Instanz-ID geschrieben wird.
#
# - DEBUG
#   true = aktiviert `set -x` fuer Bash-Trace.
#
# PROGRAMMABLAUF BEI BUCHUNG
# --------------------------
# 1. Template wird optional validiert.
# 2. Nutzer bestaetigt Offer, Modell und Template.
# 3. Instanz wird mit `create instance` erstellt.
# 4. Rueckgabe wird auf neue Contract-/Instanz-ID geparst.
# 5. Instanz-ID wird in STATE_FILE gespeichert.
# 6. Erzeugte Instanz wird auf Storage-Groesse geprueft.
# 7. Bei Untergroesse kann die Instanz automatisch zerstoert werden.
#
# AUSGABEN
# --------
# Das Script erzeugt:
# - eine tabellarische Uebersicht der bestbewerteten Vast-Angebote;
# - farbliche Kennzeichnung fuer Top Score und Best Test;
# - Logging fuer Validierung, Buchung und Post-Check;
# - optional einen gespeicherten Zustand in STATE_FILE.
#
# EXIT-VERHALTEN
# --------------
# - Exit 0: Erfolg oder bewusst abgebrochene Auswahl.
# - Exit 1: Fehler bei Validierung, Buchung oder Sicherheitspruefung.
# - Exit 2: Keine passenden Angebote nach Filterung vorhanden.
#
# BEISPIELE
# ---------
# Nur Angebote anzeigen:
#   bash find-cheapest-instance.sh
#
# Testmodus:
#   bash find-cheapest-instance.sh --test
#
# Dry-Run fuer Buchung:
#   bash find-cheapest-instance.sh --book 1 --dry-run
#
# Angebot Nr. 2 wirklich buchen:
#   bash find-cheapest-instance.sh --book 2
#
# Buchung mit explizitem Disk-Override:
#   DISK_GB=100 bash find-cheapest-instance.sh --book 1
#
# Bei alter CLI Template-Pruefung notfalls nur warnen:
#   STRICT_TEMPLATE_VALIDATION=0 bash find-cheapest-instance.sh --book 1
#
# DEBUG-MODUS:
#   DEBUG=true bash find-cheapest-instance.sh --book
#
# WARTUNGSHINWEIS
# ---------------
# Bei Aenderungen an Vast.ai CLI-Ausgaben oder JSON-Strukturen sollten vor allem
# diese Bereiche erneut geprueft werden:
# - validate_template_hash
# - extract_new_contract_id
# - postcheck_instance_storage
# - extract_storage_from_json
#
# DOKUMENTATIONSSTANDARD
# ---------------------
# Dieses Script verwendet bewusst einen ausfuehrlichen Datei-Header, damit
# Zweck, Risiken, Eingaben und Sicherheitsmechanismen direkt am Dateianfang
# sichtbar sind. Das entspricht ueblicher Bash-Best-Practice mit klarer
# Shebang, Header und strengem Fehlerhandling. [web:573][web:575]
#
# =============================================================================

export PATH="$PATH:$HOME/.local/bin:/usr/local/bin:/usr/bin"
set -Eeuo pipefail
[[ "${DEBUG:-}" == "true" ]] && set -x
trap 'rc=$?; echo "[FEHLER] Zeile $LINENO | Exit-Code $rc | Befehl: $BASH_COMMAND" >&2' ERR

VERSION="${VERSION:-2026-06-04.12}"
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

json_escape() {
    python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"
}

validate_template_hash() {
    [[ "$VALIDATE_TEMPLATE_HASH" == "1" ]] || return 0
    [[ -n "$TEMPLATE_HASH" ]] || die "TEMPLATE_HASH ist leer."

    local out=""
    local rc=0
    local escaped_hash=""
    local filter=""
    local tried=()

    escaped_hash="$(json_escape "$TEMPLATE_HASH")"
    filter="{\"hash_id\":{\"eq\":${escaped_hash}}}"

    tried+=("search templates --raw --select_filters '$filter'")
    out="$(vast_cmd search templates --raw --select_filters "$filter" 2>&1)" || rc=$?

    if [[ $rc -eq 0 && -n "$out" && "$out" != "[]" ]]; then
        ok "Template-Hash validiert via --select_filters: $TEMPLATE_HASH"
        return 0
    fi

    if [[ "$out" == *"unrecognized arguments: --select_filt"* || "$out" == *"unrecognized arguments: --select_filters"* ]]; then
        warn "CLI unterstuetzt --select_filters nicht; falle auf Query-Syntax zurueck."
    fi

    rc=0
    tried+=("search templates --raw 'hash_id=$TEMPLATE_HASH'")
    out="$(vast_cmd search templates --raw "hash_id=$TEMPLATE_HASH" 2>&1)" || rc=$?

    if [[ $rc -eq 0 && -n "$out" && "$out" != "[]" ]]; then
        ok "Template-Hash validiert via Query-Syntax: $TEMPLATE_HASH"
        return 0
    fi

    rc=0
    tried+=("search templates --raw '$TEMPLATE_HASH'")
    out="$(vast_cmd search templates --raw "$TEMPLATE_HASH" 2>&1)" || rc=$?

    if [[ $rc -eq 0 && -n "$out" && "$out" != "[]" ]]; then
        ok "Template-Hash plausibel gefunden via Freitextsuche: $TEMPLATE_HASH"
        return 0
    fi

    if [[ "$STRICT_TEMPLATE_VALIDATION" == "1" ]]; then
        die "Template-Hash konnte nicht bestaetigt werden. Versucht: ${tried[*]} | Letzte Ausgabe: $out"
    fi

    warn "Template-Hash konnte nicht bestaetigt werden, verwende ihn trotzdem fuer create instance: $TEMPLATE_HASH"
    return 0
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

get_instance_raw_json() {
    vast_cmd show instances --raw 2>/dev/null || return 1
}

get_instance_row() {
    local instance_id="$1"
    vast_cmd show instances 2>/dev/null | awk -v id="$instance_id" '
        $2 == id { print; found=1 }
        END { if (!found) exit 1 }
    '
}

extract_storage_from_json() {
    local raw_json="$1"
    local instance_id="$2"

    python3 - "$instance_id" <<'PY' <<< "$raw_json"
import json, sys

instance_id = str(sys.argv[1])
raw = sys.stdin.read().strip()
if not raw:
    raise SystemExit(1)

try:
    data = json.loads(raw)
except Exception:
    raise SystemExit(1)

def as_list(x):
    if isinstance(x, list):
        return x
    if isinstance(x, dict):
        for key in ("instances", "results", "data"):
            v = x.get(key)
            if isinstance(v, list):
                return v
    return []

items = as_list(data)

for item in items:
    iid = str(item.get("id", item.get("contract_id", item.get("new_contract", ""))))
    if iid != instance_id:
        continue

    candidates = [
        item.get("disk_space"),
        item.get("disk"),
        item.get("storage"),
        item.get("disk_gb"),
    ]

    machine = item.get("machine") or {}
    if isinstance(machine, dict):
        candidates.extend([
            machine.get("disk_space"),
            machine.get("disk"),
            machine.get("storage"),
        ])

    for val in candidates:
        if val is None:
            continue
        try:
            print(float(val))
            raise SystemExit(0)
        except Exception:
            pass

raise SystemExit(1)
PY
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

    local raw_json=""
    local row=""
    local storage_val=""

    if raw_json="$(get_instance_raw_json)"; then
        if storage_val="$(extract_storage_from_json "$raw_json" "$instance_id" 2>/dev/null)"; then
            log "Storage aus JSON-Post-Check extrahiert: ${storage_val} GB"
        fi
    fi

    if [[ -z "$storage_val" ]]; then
        if row="$(get_instance_row "$instance_id")"; then
            printf '%s\n' "$row"
            storage_val="$(extract_storage_from_row "$row")"
        fi
    fi

    if [[ -z "$storage_val" ]]; then
        warn "Storage-Wert konnte aus dem Post-Check nicht extrahiert werden."
        return 0
    fi

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
