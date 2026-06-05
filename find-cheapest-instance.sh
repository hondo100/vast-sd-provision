#!/usr/bin/env bash
# =============================================================================
# find-cheapest-instance.sh | Version: 2026-06-05.05
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
# Diese Version ist auf robuste, reproduzierbare Vast-Buchungen ausgelegt:
#
# - Die gewuenschte Disk-Groesse wird explizit im Create-Request gesetzt.
# - US-Instanzen werden zusammen mit CN bereits in der Search-Query ausgeschlossen.
# - Template-Hash wird optional vor der Buchung validiert.
# - Vor der Buchung wird das konkrete Offer per CLI auf `cuda_max_good >= 12.1`
#   geprueft.
# - Die CUDA-Pruefung nutzt einen kompatiblen Fallback-Ansatz:
#   1. `search offers --raw "id=<offer_id>"`
#   2. optionaler Fallback auf Query-Syntax-Varianten
# - Es wird bewusst nicht auf `show offer` vertraut, da dieser Befehl je nach
#   Vast-CLI-Version nicht verfuegbar oder nicht kompatibel sein kann.
# - Nach der Buchung wird die reale Instanz nachgeprueft.
# - Der Post-Check nutzt mehrere Fallbacks:
#   1. `show instance <id> --raw`
#   2. `show instances --raw`
#   3. Tabellen-Fallback aus `show instances`
# - Der Post-Check enthaelt eine Retry-Logik mit Sleep, um
#   Initialisierungsverzögerungen neuer Instanzen abzufangen.
# - Bei Parse-Problemen werden Debug-Dateien geschrieben.
# - Hilfsfunktionen enden explizit mit `return 0`, damit `set -e`/`trap ERR`
#   nicht durch harmlose Tests ausgelöst werden.
#
# HINTERGRUND
# -----------
# Vast erlaubt die Instanzerstellung ueber `create instance`; explizite
# Request-Parameter sind der zuverlaessigste Weg, um Werte wie die Disk-Groesse
# sicher festzulegen. Da die Disk-Groesse bei der Erstellung festgelegt wird und
# spaeter nicht einfach geaendert werden kann, erzwingt dieses Script `--disk`
# standardmaessig direkt im Buchungsbefehl. [web:502][web:618]
#
# Die CUDA-Vorabpruefung verwendet bewusst `search offers --raw` mit gezielter
# Offer-ID-Filterung statt `show offer`, weil `search offers` der dokumentierte
# und in der Praxis breit verfuegbare CLI-Pfad fuer Offer-Abfragen ist, waehrend
# `show offer` nicht in jeder CLI-Version zuverlaessig verfuegbar ist.
#
# Die Vast-CLI nutzt fuer Instanzen in der Ausgabe das Feld `disk_space` fuer
# die Storage-Spalte. Darum prueft der Post-Check gezielt auf mehrere moegliche
# Storage-Felder und nutzt notfalls einen Tabellen-Fallback. [web:614][web:579]
#
# Bash gibt fuer Funktionen standardmaessig den Exit-Status des letzten
# Kommandos zurueck. Unter `set -Eeuo pipefail` kann das bei rein optionalen
# Tests unerwuenschte Abbrueche ausloesen. Deshalb enden Hilfsfunktionen hier
# explizit mit `return 0`. [web:663][web:640]
#
# FUNKTIONSUEBERSICHT
# ------------------
# 1. Vast.ai CLI und lokale Dateien pruefen.
# 2. Angebote per Vast.ai laden.
# 3. Angebote mit scoring_engine.py bewerten.
# 4. Ergebnisse filtern und tabellarisch darstellen.
# 5. Optional ein Angebot auswaehlen und buchen.
# 6. Template-Hash vorab validieren.
# 7. Offer vor der Buchung via `search offers --raw` auf
#    `cuda_max_good >= 12.1` pruefen.
# 8. Instanz mit explizitem `--disk` erstellen.
# 9. Neue Instanz-ID extrahieren und speichern.
# 10. Storage der realen Instanz per Post-Check verifizieren.
# 11. Bei zu kleiner Storage optional automatisch zerstoeren.
#
# BENOETIGTE DATEIEN
# ------------------
# - ./scoring_engine.py
# - ./params.json
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
# - EXPECTED_TEMPLATE_DISK_GB
#   Erwartete Mindestgroesse der Storage.
#
# - DISK_GB
#   Explizite Disk-Groesse fuer den Create-Request.
#   Standard: faellt auf EXPECTED_TEMPLATE_DISK_GB zurueck.
#
# - MIN_DISK_GB
#   Sicherheitsgrenze fuer DISK_GB.
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
#   1 = interaktive Bestaetigung vor Buchung
#   0 = ohne Zusatzbestaetigung fortfahren
#
# - STATE_FILE
#   Datei fuer die erzeugte Instanz-ID.
#
# - POSTCHECK_DEBUG_DIR
#   Zielordner fuer Debug-Dateien bei Parse-Problemen.
#
# - DEBUG
#   true = aktiviert `set -x`.
#
# BEISPIELE
# ---------
# Nur Angebote anzeigen:
#   bash find-cheapest-instance.sh
#
# Buchung Dry-Run:
#   bash find-cheapest-instance.sh --book 1 --dry-run
#
# Wirklich buchen:
#   bash find-cheapest-instance.sh --book 1
#
# Andere Disk-Groesse erzwingen:
#   DISK_GB=100 bash find-cheapest-instance.sh --book 1
#
# =============================================================================

export PATH="$PATH:$HOME/.local/bin:/usr/local/bin:/usr/bin"
set -Eeuo pipefail
[[ "${DEBUG:-}" == "true" ]] && set -x

VERSION="${VERSION:-2026-06-05.05}"
RESULTS="${RESULTS:-10}"
QUERY="${QUERY:-external=false rentable=true verified=true gpu_ram>=24 disk_space>=40 geolocation notin [CN,US]}"
GPU_FILTER="${GPU_FILTER:-RTX (3090|4090|A5000|A6000|5000|6000)}"

EXPECTED_TEMPLATE_DISK_GB="${EXPECTED_TEMPLATE_DISK_GB:-80}"
DISK_GB="${DISK_GB:-$EXPECTED_TEMPLATE_DISK_GB}"
MIN_DISK_GB="${MIN_DISK_GB:-80}"
ENFORCE_DISK_GUARD="${ENFORCE_DISK_GUARD:-1}"
REQUIRE_EXPLICIT_CONFIRM="${REQUIRE_EXPLICIT_CONFIRM:-1}"
POSTCHECK_INSTANCE="${POSTCHECK_INSTANCE:-1}"
AUTO_DESTROY_BAD_STORAGE="${AUTO_DESTROY_BAD_STORAGE:-1}"
STRICT_TEMPLATE_VALIDATION="${STRICT_TEMPLATE_VALIDATION:-1}"
VALIDATE_TEMPLATE_HASH="${VALIDATE_TEMPLATE_HASH:-1}"

TEMPLATE_HASH="${TEMPLATE_HASH:-47911bdece931900f38147222e3765a8}"
MODEL_GB="${MODEL_GB:-20}"
SESSION_HOURS="${SESSION_HOURS:-3}"
PARAMS_JSON="${PARAMS_JSON:-./params.json}"
STATE_FILE="${STATE_FILE:-/home/werner/github-scripts/.current_instance}"
POSTCHECK_DEBUG_DIR="${POSTCHECK_DEBUG_DIR:-/tmp/vast_postcheck_debug}"

tmp_json=""
LAST_BOOKED_INSTANCE_ID=""

c() { printf '\033[%sm%s\033[0m\n' "$1" "$2"; }
log() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARNUNG] %s\n' "$*" >&2; }
ok() { printf '[SUCCESS] %s\n' "$*"; }
die() { printf '[FEHLER] %s\n' "$*" >&2; exit 1; }

cleanup() {
    rm -f -- "${tmp_json:-}"
    return 0
}

on_err() {
    local rc=$?
    echo "[FEHLER] Zeile ${BASH_LINENO[0]} | Exit-Code $rc | Befehl: ${BASH_COMMAND}" >&2
    exit "$rc"
}

trap cleanup EXIT
trap on_err ERR

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

compare_lt() {
    python3 - "$1" "$2" <<'PY'
import sys
a=float(sys.argv[1]); b=float(sys.argv[2])
raise SystemExit(0 if a < b else 1)
PY
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
    [[ "$DISK_GB" =~ ^[0-9]+$ ]] || die "DISK_GB muss eine ganze Zahl sein. Aktuell: $DISK_GB"

    if (( DISK_GB < MIN_DISK_GB )); then
        if [[ "$ENFORCE_DISK_GUARD" == "1" ]]; then
            die "DISK_GB=$DISK_GB ist kleiner als MIN_DISK_GB=$MIN_DISK_GB. Buchung aus Sicherheitsgruenden abgebrochen."
        else
            warn "DISK_GB=$DISK_GB ist kleiner als MIN_DISK_GB=$MIN_DISK_GB."
        fi
    fi

    if (( DISK_GB < EXPECTED_TEMPLATE_DISK_GB )); then
        warn "DISK_GB=$DISK_GB ist kleiner als EXPECTED_TEMPLATE_DISK_GB=$EXPECTED_TEMPLATE_DISK_GB."
    fi

    ok "Explizite Disk-Groesse fuer Create-Request aktiv: ${DISK_GB} GB"
    return 0
}

validate_offer_cuda() {
    local offer_id="$1"
    [[ -n "$offer_id" ]] || die "Offer-ID fuer CUDA-Validierung ist leer."

    local raw=""
    local rc=0
    local cuda_max_good=""
    local tried=()

    tried+=("search offers --raw 'id=$offer_id'")
    raw="$(vast_cmd search offers --raw "id=$offer_id" 2>/dev/null)" || rc=$?

    if [[ $rc -ne 0 || -z "$raw" || "$raw" == "[]" ]]; then
        rc=0
        tried+=("search offers --raw 'id==$offer_id'")
        raw="$(vast_cmd search offers --raw "id==$offer_id" 2>/dev/null)" || rc=$?
    fi

    if [[ $rc -ne 0 || -z "$raw" || "$raw" == "[]" ]]; then
        rc=0
        tried+=("search offers --raw 'id in [$offer_id]'")
        raw="$(vast_cmd search offers --raw "id in [$offer_id]" 2>/dev/null)" || rc=$?
    fi

    if [[ $rc -ne 0 || -z "$raw" || "$raw" == "[]" ]]; then
        die "CUDA-Validierung fehlgeschlagen: Offer $offer_id konnte nicht per search offers geladen werden. Versucht: ${tried[*]}"
    fi

    if ! cuda_max_good="$(
        printf '%s' "$raw" | python3 - "$offer_id" <<'PY'
import ast, json, sys

offer_id = str(sys.argv[1] or "")
raw = sys.stdin.read().strip()
if not raw:
    raise SystemExit(1)

data = None
for parser in (json.loads, ast.literal_eval):
    try:
        data = parser(raw)
        break
    except Exception:
        pass

if data is None:
    raise SystemExit(1)

if isinstance(data, dict):
    items = data.get("offers") if isinstance(data.get("offers"), list) else [data]
elif isinstance(data, list):
    items = data
else:
    raise SystemExit(1)

for item in items:
    if not isinstance(item, dict):
        continue

    candidate_ids = []
    for key in ("id", "offer_id", "ask_id"):
        if item.get(key) is not None:
            candidate_ids.append(str(item.get(key)))

    if offer_id and candidate_ids and offer_id not in candidate_ids:
        continue

    for obj in (item, item.get("machine"), item.get("offer")):
        if isinstance(obj, dict) and obj.get("cuda_max_good") is not None:
            print(obj.get("cuda_max_good"))
            raise SystemExit(0)

raise SystemExit(1)
PY
    )"; then
        die "CUDA-Validierung fehlgeschlagen: Feld cuda_max_good fuer Offer $offer_id konnte nicht extrahiert werden."
    fi

    if python3 - "$cuda_max_good" <<'PY'
import sys
v = float(sys.argv[1])
raise SystemExit(0 if v >= 12.1 else 1)
PY
    then
        ok "CUDA-Validierung erfolgreich: Offer $offer_id (cuda=$cuda_max_good) ist kompatibel."
    else
        die "Offer $offer_id verworfen: cuda_max_good=$cuda_max_good < 12.1 (Inkompatibel mit Forge-Templates)."
    fi

    return 0
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
    echo "  Expliziter Disk-Override: ${DISK_GB} GB"
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

    read -r -p "Buchung $target_id ($model_name) mit Template $TEMPLATE_HASH und --disk $DISK_GB bestaetigen [y/N]: " conf
    [[ "$conf" == [yY] ]] || { echo "Abbruch."; exit 0; }
}

get_single_instance_raw_json() {
    local instance_id="$1"
    vast_cmd show instance "$instance_id" --raw 2>/dev/null || return 1
}

get_instances_raw_json() {
    vast_cmd show instances --raw 2>/dev/null || return 1
}

get_instance_row() {
    local instance_id="$1"
    vast_cmd show instances 2>/dev/null | awk -v id="$instance_id" '
        $2 == id { print; found=1 }
        END { if (!found) exit 1 }
    '
}

save_postcheck_debug() {
    local instance_id="$1"
    local single_raw="${2:-}"
    local list_raw="${3:-}"
    local row_raw="${4:-}"

    mkdir -p "$POSTCHECK_DEBUG_DIR"

    if [[ -n "$single_raw" ]]; then
        printf '%s\n' "$single_raw" > "${POSTCHECK_DEBUG_DIR}/instance_${instance_id}_single_raw.txt"
    fi

    if [[ -n "$list_raw" ]]; then
        printf '%s\n' "$list_raw" > "${POSTCHECK_DEBUG_DIR}/instance_${instance_id}_list_raw.txt"
    fi

    if [[ -n "$row_raw" ]]; then
        printf '%s\n' "$row_raw" > "${POSTCHECK_DEBUG_DIR}/instance_${instance_id}_table_row.txt"
    fi

    return 0
}

extract_storage_from_json() {
    local raw_json="$1"
    local instance_id="${2:-}"

    python3 - "$instance_id" <<'PY' <<< "$raw_json"
import ast, json, sys

instance_id = str(sys.argv[1] or "")
raw = sys.stdin.read().strip()
if not raw:
    raise SystemExit(1)

data = None

for parser in (
    lambda s: json.loads(s),
    lambda s: ast.literal_eval(s),
):
    try:
        data = parser(raw)
        break
    except Exception:
        pass

if data is None:
    raise SystemExit(1)

def to_items(x):
    if isinstance(x, list):
        return x
    if isinstance(x, dict):
        if instance_id and any(k in x for k in ("id", "contract_id", "new_contract", "instance_id")):
            return [x]
        for key in ("instances", "results", "data"):
            v = x.get(key)
            if isinstance(v, list):
                return v
        return [x]
    return []

def item_id(item):
    for key in ("id", "contract_id", "new_contract", "instance_id"):
        if key in item and item.get(key) is not None:
            return str(item.get(key))
    return ""

def nested_dicts(item):
    out = [item]
    for key in ("machine", "instance", "offer", "ask_contract", "contract"):
        v = item.get(key)
        if isinstance(v, dict):
            out.append(v)
    return out

def candidate_values(item):
    vals = []
    for obj in nested_dicts(item):
        vals.extend([
            obj.get("disk_space"),
            obj.get("disk"),
            obj.get("disk_gb"),
            obj.get("storage"),
            obj.get("storage_gb"),
            obj.get("disk_size"),
            obj.get("allocated_storage"),
            obj.get("image_disk_size"),
            obj.get("container_disk"),
            obj.get("container_disk_gb"),
        ])
    return vals

items = to_items(data)

for item in items:
    if not isinstance(item, dict):
        continue
    if instance_id:
        iid = item_id(item)
        if iid != instance_id:
            continue
    for val in candidate_values(item):
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
    awk '
        {
            n = 0
            for (i=1; i<=NF; i++) {
                if ($i ~ /^[0-9]+(\.[0-9]+)?$/) {
                    vals[++n] = $i
                } else if ($i ~ /^[0-9]+(\.[0-9]+)?GB$/) {
                    gsub(/GB/, "", $i)
                    vals[++n] = $i
                }
            }
            if (n >= 1) {
                print vals[n]
                exit
            }
        }
    ' <<< "$row"
}

destroy_bad_instance() {
    local instance_id="$1"
    warn "Zerstoere Instanz $instance_id wegen ungueltiger Storage-Groesse..."
    vast_cmd destroy instance "$instance_id" >/dev/null 2>&1 || warn "Destroy fuer Instanz $instance_id konnte nicht bestaetigt werden."
    return 0
}

postcheck_instance_storage() {
    local instance_id="$1"
    [[ "$POSTCHECK_INSTANCE" == "1" ]] || return 0

    echo ""
    log "Versuche Nachcheck der erzeugten Instanz-ID $instance_id ..."

    local single_raw=""
    local list_raw=""
    local row=""
    local storage_val=""
    local source_used=""
    local attempt=1
    local max_attempts=6
    local sleep_seconds=5

    while (( attempt <= max_attempts )); do
        single_raw=""
        list_raw=""
        row=""
        storage_val=""
        source_used=""

        if single_raw="$(get_single_instance_raw_json "$instance_id")"; then
            if storage_val="$(extract_storage_from_json "$single_raw" "$instance_id" 2>/dev/null)"; then
                source_used="show instance --raw"
                log "Storage aus gezieltem Instance-JSON extrahiert: ${storage_val} GB"
            fi
        fi

        if [[ -z "$storage_val" ]]; then
            if list_raw="$(get_instances_raw_json)"; then
                if storage_val="$(extract_storage_from_json "$list_raw" "$instance_id" 2>/dev/null)"; then
                    source_used="show instances --raw"
                    log "Storage aus Instanzlisten-JSON extrahiert: ${storage_val} GB"
                fi
            fi
        fi

        if [[ -z "$storage_val" ]]; then
            if row="$(get_instance_row "$instance_id")"; then
                printf '%s\n' "$row"
                storage_val="$(extract_storage_from_row "$row" || true)"
                if [[ -n "$storage_val" ]]; then
                    source_used="show instances table"
                fi
            fi
        fi

        if [[ -n "$storage_val" ]]; then
            break
        fi

        if (( attempt < max_attempts )); then
            warn "Post-Check-Versuch $attempt/$max_attempts lieferte noch keine Storage-Daten. Warte ${sleep_seconds}s auf Instanz-Initialisierung..."
            sleep "$sleep_seconds"
        fi

        ((attempt++))
    done

    if [[ -z "$storage_val" ]]; then
        save_postcheck_debug "$instance_id" "$single_raw" "$list_raw" "$row"
        warn "Storage-Wert konnte aus dem Post-Check nicht extrahiert werden."
        warn "Debug-Dateien geschrieben nach: $POSTCHECK_DEBUG_DIR"
        return 0
    fi

    log "Verwendete Post-Check-Quelle: ${source_used:-unbekannt}"

    if compare_lt "$storage_val" "$EXPECTED_TEMPLATE_DISK_GB"; then
        warn "Instanz hat zu wenig Storage: ${storage_val} GB < ${EXPECTED_TEMPLATE_DISK_GB} GB"

        if [[ "$AUTO_DESTROY_BAD_STORAGE" == "1" ]]; then
            destroy_bad_instance "$instance_id"
        fi

        die "Buchung verworfen: Tatsaechliche Storage-Groesse ist kleiner als erwartet."
    fi

    ok "Post-Check erfolgreich: Storage ${storage_val} GB >= ${EXPECTED_TEMPLATE_DISK_GB} GB"
    return 0
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
    echo "Disk-Override: $DISK_GB GB (explizit erzwungen)"
    echo "Expected Template Disk: $EXPECTED_TEMPLATE_DISK_GB GB"
    echo "========================================================================================="

    tmp_json="$(mktemp /tmp/vast_offers.XXXXXX.json)"

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
            log "Filtere Angebot mit Geo=',' heraus (China-Heuristik/ungueltige Geo-Angabe)."
            continue
        fi

        filtered_lines+=("$raw_line")
    done

    lines=("${filtered_lines[@]}")

    if [[ ${#lines[@]} -eq 0 ]]; then
        warn "Keine passenden Instanzen nach Filterung gefunden."
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

        if compare_lt "$test_c" "$min_test"; then
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

        local idx=$((BOOK_INDEX - 1))
        if [[ $idx -lt 0 || $idx -ge ${#rows[@]} ]]; then
            die "Ungueltige Auswahl."
        fi

        local sel="${rows[$idx]}"
        local target_id="${sel%|*}"
        local model_name="${sel#*|}"

        confirm_booking "$target_id" "$model_name"
        validate_offer_cuda "$target_id"

        local create_args=()
        create_args=(create instance "$target_id" --template_hash "$TEMPLATE_HASH" --disk "$DISK_GB")

        echo ""
        echo "[INFO] Finaler Vast-Befehl:"
        printf '  vastai'
        printf ' %q' "${create_args[@]}"
        printf '\n'

        if [[ "$DRY_RUN" -eq 1 ]]; then
            echo "[DRY-RUN] Instanz $BOOK_INDEX waere mit obigem Befehl gebucht worden."
            exit 0
        fi

        echo "[PROZESS] Sende Buchungsbefehl an Vast.ai..."

        local book_output=""
        local rc=0

        book_output="$(vast_cmd "${create_args[@]}" 2>&1)" || rc=$?
        echo "$book_output"

        if [[ $rc -ne 0 ]]; then
            die "Buchung fehlgeschlagen."
        fi

        local extracted_id=""
        extracted_id="$(extract_new_contract_id "$book_output")"

        if [[ -n "$extracted_id" ]]; then
            LAST_BOOKED_INSTANCE_ID="$extracted_id"
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
