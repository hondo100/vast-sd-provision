#!/usr/bin/env bash
set -euo pipefail

VERSION="2026-05-24.25"

: <<'SCRIPT_OVERVIEW'
========================================================================
SCRIPT ARGUMENTS / OPTIONEN
========================================================================

Zweck dieses Skripts
- Dieses Skript dient zur Auswahl wirtschaftlicher Vast-Angebote.
- Die eigentliche Buchung erfolgt anschliessend manuell im Vast-Webinterface.
- Dort kann gezielt das Template "SD WebUI Forge" ausgewaehlt werden.
- Dieses Skript bucht NICHT automatisch.

Grundmodi
- --test
  Rein informativer Modus. Aktuell identisch zum Normalmodus, da keine
  automatische Buchung mehr erfolgt.

- --dry-run
  Zeigt nur die Trefferliste und den Vorschlag an.

- --diag
  Fuehrt nur eine Rohdiagnose der Vast-CLI-Ausgabe aus:
  RC, stdout/stderr-Bytezahlen, kurze Vorschau und JSON-Pruefung.

Debug / Parseranalyse
- --debug-json
  Gibt die Keys der ersten Offer-Objekte und gekuerzte JSON-Rohobjekte
  auf stderr aus. Dient dazu, lokale Unterschiede im --raw-JSON-Schema
  sichtbar zu machen.

- --debug-json-limit N
  Anzahl der Offer-Objekte, die im Debug-Modus auf stderr ausgegeben
  werden sollen. Standard: 2

Such- und Bewertungsparameter
- --model-gb N
  Modellgroesse in GB. Wird fuer die geschaetzten initialen
  Downloadkosten (inet_down_cost) und die Storage-Kosten verwendet.
  Standard: 20

- --session-hours N
  Angenommene typische Nutzungsdauer pro Sitzung in Stunden.
  Die initialen Downloadkosten des Modells werden auf diese Dauer
  umgelegt, um realistischere Effektivkosten pro Stunde zu berechnen.
  Standard: 3

- --results N
  Anzahl der final anzuzeigenden geeigneten Treffer. Standard: 10

- --search-limit N
  Anzahl der Rohangebote, die von Vast geladen werden, bevor lokal
  gefiltert und sortiert wird. Standard: 60

Interaktives Verhalten
- Das Skript macht nur einen Vorschlag fuer die wirtschaftlichste
  Instanz.
- Die endgueltige Entscheidung und Buchung erfolgen manuell im Vast-UI.
- Dort kann z. B. das Template "SD WebUI Forge" gewaehlt werden.

Beispiele
- Nur anzeigen:
    bash ./find-cheapest-instance.sh --dry-run

- Rohdiagnose:
    bash ./find-cheapest-instance.sh --diag

- JSON-Debug:
    bash ./find-cheapest-instance.sh --dry-run --debug-json 2>/tmp/vast_debug.err
    sed -n '1,160p' /tmp/vast_debug.err

- Eigene Sitzungsdauer:
    bash ./find-cheapest-instance.sh --session-hours 2 --results 12

- Mehr Rohangebote laden:
    bash ./find-cheapest-instance.sh --search-limit 100 --results 15

========================================================================
GEWONNENE ERKENNTNISSE / LESSONS LEARNED
========================================================================

1) Bevorzugter stabiler Pfad
- Vast CLI statt rohe REST-Aufrufe bevorzugen.
- Nicht zu curl + /api/v0/bundles zurueckkehren, solange CLI + --raw
  verfuegbar sind.
- Der stabile Arbeitsweg ist:
    Vast CLI -> search offers --raw -> Rohausgabe pruefen ->
    JSON mit python3 parsen -> Bash-Ausgabe erzeugen

2) Tabellen-Parsing vermeiden
- `vastai search offers` ohne --raw liefert menschenlesbare Tabellen,
  die fuer Skripte zu fragil sind.
- Tabellen-Output nicht mit awk/Regex als primaeren Pfad parsen.
- Fuer Skripte immer JSON bevorzugen.

3) Rohdiagnose vor Parser- oder Ranking-Aenderungen
- Vor funktionalen Umbauten zuerst pruefen:
  a) Auth ok? -> `vastai show user`
  b) stdout leer?
  c) schreibt CLI nach stderr?
  d) ist stdout wirklich JSON?
- Wenn stdout leer ist, liegt das Problem vor dem Parser.
- Wenn stdout Daten enthaelt, aber kein JSON ist, liegt das Problem am
  lokalen --raw-Verhalten oder an einer CLI-Abweichung.

4) Lokale JSON-Abweichungen beachten
- Dokumentierte Felder koennen lokal unter leicht anderen Keys
  auftauchen.
- Das Preis/Leistungsfeld wurde lokal erfolgreich ueber
  `dlperf_per_dphtotal` statt nur ueber `dlperf_usd` gefunden.
- Der Status ist robuster ueber `verification` als nur ueber `verified`
  lesbar.
- Schlussfolgerung:
  Parser mit Feld-Aliasen bauen, nicht mit nur einem festen Key.

5) Wirtschaftlichkeitsbewertung nicht nur ueber Stundenpreis
- Fuer Modell-Hosting nicht nur dph/dph_total betrachten.
- Zusaetzlich beruecksichtigen:
  - VRAM
  - Reliability
  - initiale Downloadkosten (`inet_down_cost`)
  - monatliche Storage-Kosten (`storage_cost`)
  - DLPerf und DLPerf pro Dollar

6) Praktische Mindestanforderungen fuer ~20GB-Modelle
- 20GB Modellgroesse bedeutet in der Praxis nicht, dass exakt 20GB VRAM
  genuegen.
- 24GB VRAM als Mindestschwelle ist ein sinnvoller Startwert.
- Angebote unterhalb der Schwelle werden als ungeeignet ausgeschlossen.

7) Auswahlhilfe statt Auto-Buchung
- Das Skript soll einen Vorschlag machen, aber nicht automatisch buchen.
- Die endgueltige Buchung erfolgt bewusst im Vast-Webinterface.
- So kann dort gezielt ein passendes Template wie "SD WebUI Forge"
  ausgewaehlt werden.

8) Vast-Template hat eigene Laufzeitumgebung
- Wenn die Instanz spaeter im Vast-UI mit einem Template erstellt wird,
  bestimmt das Template die konkrete Laufzeitumgebung.
- Ein frueher im Skript gesetztes Docker-Image waere dafuer nicht
  massgeblich.
- Deshalb fokussiert dieses Skript nur auf Angebotsauswahl.

9) Bewertungssystem auf interaktives Arbeiten ausgerichtet
- Dieses Skript optimiert NICHT auf maximalen Batch-Durchsatz.
- Ziel ist längeres manuelles Arbeiten an einzelnen Bildern oder Videos.
- Deshalb werden niedrige Stundenpreise stärker gewichtet als rohe
  Spitzenleistung.
- Ausreichender VRAM und gute Reliability sind wichtiger als extreme
  Mehrleistung.
- Multi-GPU-Angebote werden leicht abgestraft, wenn sie fuer den Use
  Case voraussichtlich nur Mehrkosten statt echten Nutzen bringen.

10) Effektivkosten an reale Sitzungsdauer koppeln
- Fuer diesen Use Case sind kurze interaktive Sessions von ca. 3 Stunden
  realistischer als 24h-Dauerbetrieb.
- Die initialen Downloadkosten des Modells werden deshalb nicht auf 24h,
  sondern auf die angenommene Sitzungsdauer umgelegt.
- Dadurch werden Kurzsitzungen realistischer bewertet.

11) Mehr Rohangebote laden, lokal ungeeignete eliminieren
- Es ist sinnvoller, mehr Rohangebote von Vast zu laden und danach lokal
  ungeeignete Treffer auszuschliessen, als nur wenige Treffer zu laden
  und ungeeignete Kandidaten in der Endliste stehen zu lassen.
- Dadurch steigt die Chance, dass unter den final angezeigten Treffern
  wirklich nur brauchbare und wirtschaftliche Optionen erscheinen.

Kurzfazit
- Nicht Tabellen parsen.
- Nicht rohe Bundles-API priorisieren.
- Erst Rohdaten pruefen, dann Parser anpassen.
- Mehr Rohangebote laden, lokal ungeeignete eliminieren.
- Auswahl im Skript, Buchung bewusst im Vast-UI mit passendem Template.
SCRIPT_OVERVIEW

RESULTS=10
SEARCH_LIMIT=60
MODEL_GB=20
SESSION_HOURS=3
MIN_VRAM_GB=24.0
MIN_REL=0.95
MIN_DISK_GB=40
DEBUG_JSON=0
DEBUG_JSON_LIMIT=2

QUERY='external=false rentable=true verified=true gpu_ram>=24 disk_space>=40'
SORT='dlperf_usd-'

usage() {
  cat <<EOF
Usage: $0 [--test] [--dry-run] [--diag] [--debug-json] [--debug-json-limit N]
          [--model-gb N] [--session-hours N] [--results N] [--search-limit N]
EOF
}

color_supported() {
  [[ -t 1 ]]
}

c() {
  local code="$1"
  shift
  local text="$1"
  if color_supported; then
    printf '\033[%sm%s\033[0m' "$code" "$text"
  else
    printf '%s' "$text"
  fi
}

green()  { c 32 "$1"; }
yellow() { c 33 "$1"; }
blue()   { c 34 "$1"; }
red()    { c 31 "$1"; }

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

# ----------------------------------------------------------------------
# Bewertungssystem / Scoring-Modell
#
# Zielprofil dieses Skripts:
# - keine Batch- oder Massendurchsatz-Optimierung
# - stattdessen längeres manuelles/interaktives Arbeiten an einzelnen
#   Bildern oder Videos
# - deshalb ist ein niedriger Stundenpreis wichtiger als maximale rohe
#   DL-Leistung
#
# Bewertungsprinzipien:
# 1) Harte Ausschlusskriterien:
#    - VRAM < MIN_VRAM_GB      -> ungeeignet
#    - Reliability < MIN_REL  -> ungeeignet
#
# 2) Hohe Gewichtung auf niedrige effektive Stundenkosten:
#    - eff_hour = GPU-Kosten plus auf die angenommene typische
#      Sitzungsdauer umgelegte initiale Downloadkosten des Modells
#    - Standardannahme: kurze interaktive Sitzungen von ca. 3 Stunden
#    - Je niedriger eff_hour, desto besser
#
# 3) VRAM nur bis zu einer sinnvollen Reserve belohnen:
#    - 24 GB ist Mindestschwelle
#    - 24-32 GB ist gut
#    - 32-48 GB ist komfortabel
#    - deutlich mehr VRAM bringt fuer diesen Use Case nur noch kleinen
#      Zusatznutzen
#
# 4) Reliability wichtig:
#    - Fuer längeres manuelles Arbeiten ist Stabilität wichtiger als eine
#      kleine zusätzliche Benchmark-Leistung
#
# 5) Multi-GPU-Malus:
#    - 2+ GPUs sind für diesen interaktiven Use Case oft teurer als nötig
#    - Deshalb werden Mehr-GPU-Angebote leicht abgestraft
#
# 6) DLPerf / DLPerf pro Dollar nur schwach bis moderat gewichten:
#    - Leistung zählt weiterhin
#    - aber deutlich schwächer als Preis, VRAM-Eignung und Stability
#
# Interpretation:
# - Score ist ein lokaler Vergleichswert nur innerhalb dieser Ergebnisliste
# - Höher = besser für dieses Nutzungsszenario
# - -1 = unter Mindestanforderungen / ungeeignet
# ----------------------------------------------------------------------
score_offer() {
  local eff_hour="$1"
  local dl="$2"
  local dlu="$3"
  local rel="$4"
  local vram="$5"
  local numg="$6"

  python3 - "$eff_hour" "$dl" "$dlu" "$rel" "$vram" "$numg" "$MIN_VRAM_GB" "$MIN_REL" <<'PY'
import math
import sys

eff  = float(sys.argv[1])   # effektive Kosten pro Stunde
dl   = float(sys.argv[2])   # rohe DLPerf
dlu  = float(sys.argv[3])   # DLPerf pro Dollar
rel  = float(sys.argv[4])   # Reliability
vram = float(sys.argv[5])   # VRAM in GB
numg = float(sys.argv[6])   # Anzahl GPUs
minv = float(sys.argv[7])   # Mindest-VRAM
minr = float(sys.argv[8])   # Mindest-Reliability

if vram < minv or rel < minr:
    print(-1.0)
    raise SystemExit(0)

cost_score = 1.0 / max(eff, 0.0001)

if vram < 24:
    vram_score = 0.0
elif vram <= 28:
    vram_score = 0.75
elif vram <= 32:
    vram_score = 0.95
elif vram <= 48:
    vram_score = 1.10
elif vram <= 80:
    vram_score = 1.18
else:
    vram_score = 1.22

rel_score = rel * rel
dl_score = math.log(max(dl, 1.0))
dlu_score = math.log(max(dlu, 1.0))

if numg <= 1:
    gpu_penalty = 1.00
elif numg <= 2:
    gpu_penalty = 0.82
elif numg <= 4:
    gpu_penalty = 0.68
else:
    gpu_penalty = 0.55

score = (
    cost_score * 0.58 +
    vram_score * 0.17 +
    rel_score  * 0.15 +
    dlu_score  * 0.06 +
    dl_score   * 0.04
) * gpu_penalty

print(f"{score:.6f}")
PY
}

diag_raw() {
  local out_file err_file rc out_bytes err_bytes
  out_file="$(mktemp)"
  err_file="$(mktemp)"

  set +e
  vast_cmd search offers --raw "$QUERY" -o "$SORT" --limit "$SEARCH_LIMIT" >"$out_file" 2>"$err_file"
  rc=$?
  set -e

  out_bytes="$(wc -c <"$out_file" | tr -d ' ')"
  err_bytes="$(wc -c <"$err_file" | tr -d ' ')"

  echo "[DIAG] RC=$rc"
  echo "[DIAG] stdout bytes: $out_bytes"
  echo "[DIAG] stderr bytes: $err_bytes"
  echo

  echo "[DIAG] stdout preview:"
  head -c 1200 "$out_file" || true
  echo
  echo

  echo "[DIAG] stderr preview:"
  head -c 1200 "$err_file" || true
  echo
  echo

  if [[ "$out_bytes" -eq 0 ]]; then
    echo "[ERR] stdout ist leer. Problem liegt vor dem Parser."
    echo "Pruefe Auth mit: vastai show user"
    echo "Pruefe Hilfe mit: vastai search offers --help"
    rm -f "$out_file" "$err_file"
    return 1
  fi

  if ! python3 - "$out_file" <<'PY'
import json
import sys
p = sys.argv[1]
txt = open(p, "r", encoding="utf-8", errors="replace").read().strip()
json.loads(txt)
print("JSON_OK")
PY
  then
    echo "[ERR] stdout enthaelt Daten, aber kein gueltiges JSON."
    rm -f "$out_file" "$err_file"
    return 1
  fi

  echo "[OK] --raw liefert JSON."
  rm -f "$out_file" "$err_file"
}

main() {
  local test=0
  local dry=0
  local diag=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --test)
        test=1
        ;;
      --dry-run)
        dry=1
        ;;
      --diag)
        diag=1
        ;;
      --debug-json)
        DEBUG_JSON=1
        ;;
      --debug-json-limit)
        shift
        DEBUG_JSON_LIMIT="${1:?Fehlender Wert fuer --debug-json-limit}"
        ;;
      --model-gb)
        shift
        MODEL_GB="${1:?Fehlender Wert fuer --model-gb}"
        ;;
      --session-hours)
        shift
        SESSION_HOURS="${1:?Fehlender Wert fuer --session-hours}"
        ;;
      --results)
        shift
        RESULTS="${1:?Fehlender Wert fuer --results}"
        ;;
      --search-limit)
        shift
        SEARCH_LIMIT="${1:?Fehlender Wert fuer --search-limit}"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        usage
        exit 2
        ;;
    esac
    shift
  done

  if ! have_vast; then
    echo "[ERR] vastai/vast CLI nicht gefunden" >&2
    exit 2
  fi

  echo "Skript-Version: $VERSION"
  echo "[INFO] Suchquery: $QUERY"
  echo "[INFO] Sortierung (Vast-Vorfilter): $SORT"
  echo "[INFO] Tabellensortierung lokal: Score absteigend"
  echo "[INFO] Modellgroesse fuer initiale Beladung: ${MODEL_GB} GB"
  echo "[INFO] Angenommene Sitzungsdauer: ${SESSION_HOURS} h"
  echo "[INFO] Anzahl Rohangebote von Vast: ${SEARCH_LIMIT}"
  echo "[INFO] Anzahl final angezeigter Angebote: ${RESULTS}"
  echo "[INFO] Ziel-Workflow: Auswahl im Skript, Buchung danach im Vast-UI mit Template (z. B. SD WebUI Forge)"
  if [[ $test -eq 1 ]]; then
    echo "Modus: test"
  else
    echo "Modus: live"
  fi
  if [[ $DEBUG_JSON -eq 1 ]]; then
    echo "[INFO] Debug-JSON: aktiv (stderr)"
  fi
  echo

  if [[ $diag -eq 1 ]]; then
    diag_raw
    exit $?
  fi

  echo "[INFO] Auth-Check..."
  if ! vast_cmd show user >/dev/null 2>&1; then
    echo "[ERR] vast CLI nicht authentifiziert oder API-Key ungueltig." >&2
    echo "Bitte pruefen mit: vastai show user" >&2
    exit 1
  fi

  local out_file err_file rc raw
  out_file="$(mktemp)"
  err_file="$(mktemp)"

  echo "[INFO] Suche Angebote..."
  set +e
  vast_cmd search offers --raw "$QUERY" -o "$SORT" --limit "$SEARCH_LIMIT" >"$out_file" 2>"$err_file"
  rc=$?
  set -e

  if [[ $rc -ne 0 ]]; then
    echo "[ERR] search offers fehlgeschlagen (RC=$rc)." >&2
    echo "--- stderr ---" >&2
    sed -n '1,80p' "$err_file" >&2 || true
    rm -f "$out_file" "$err_file"
    exit 1
  fi

  if [[ ! -s "$out_file" ]]; then
    echo "[ERR] Keine --raw-Ausgabe auf stdout erhalten." >&2
    echo "[INFO] stderr-Vorschau:" >&2
    sed -n '1,80p' "$err_file" >&2 || true
    echo "Diagnose: $0 --diag" >&2
    rm -f "$out_file" "$err_file"
    exit 1
  fi

  raw="$(cat "$out_file")"
  if [[ -s "$err_file" ]]; then
    echo "[WARN] vast search schrieb nach stderr (Auszug):" >&2
    sed -n '1,40p' "$err_file" >&2 || true
  fi
  rm -f "$out_file" "$err_file"

  parsed="$(
    RAW_JSON="$raw" DEBUG_JSON="$DEBUG_JSON" DEBUG_JSON_LIMIT="$DEBUG_JSON_LIMIT" \
    python3 - "$SEARCH_LIMIT" "$MODEL_GB" "$SESSION_HOURS" "$MIN_VRAM_GB" "$MIN_REL" <<'PY'
import json
import os
import sys

search_limit = int(sys.argv[1])
model_gb = float(sys.argv[2])
session_hours = float(sys.argv[3])
min_vram_gb = float(sys.argv[4])
min_rel = float(sys.argv[5])
debug_json = int(os.environ.get("DEBUG_JSON", "0"))
debug_limit = int(os.environ.get("DEBUG_JSON_LIMIT", "2"))
text = os.environ.get("RAW_JSON", "").strip()

if not text:
    sys.exit(0)

try:
    data = json.loads(text)
except Exception:
    sys.exit(0)

if isinstance(data, dict):
    offers = None
    for key in ("offers", "rows", "results"):
        if isinstance(data.get(key), list):
            offers = data[key]
            break
    if offers is None:
        offers = [data]
elif isinstance(data, list):
    offers = data
else:
    offers = []

def first_num(d, keys, default=0.0):
    for k in keys:
        if k in d and d[k] not in (None, ""):
            try:
                return float(d[k])
            except Exception:
                pass
    return float(default)

def first_str(d, keys, default=""):
    for k in keys:
        if k in d and d[k] not in (None, ""):
            return str(d[k])
    return default

if debug_json:
    print(f"#DEBUG offers_total={len(offers)}", file=sys.stderr)
    for idx, offer in enumerate(offers[:debug_limit]):
        if isinstance(offer, dict):
            print(f"#DEBUG offer[{idx}] keys={','.join(sorted(offer.keys()))}", file=sys.stderr)
            print(
                "#DEBUG offer[{idx}] json={json}".format(
                    idx=idx,
                    json=json.dumps(offer, ensure_ascii=False)[:4000]
                ),
                file=sys.stderr
            )
        else:
            print(f"#DEBUG offer[{idx}] type={type(offer).__name__} value={repr(offer)[:1000]}", file=sys.stderr)

rows = []
for o in offers[:search_limit]:
    if not isinstance(o, dict):
        continue

    oid = first_str(o, ["id", "offer_id"])
    model = first_str(o, ["gpu_name", "gpu", "model"], "unknown").replace("_", " ")
    num_gpus = first_num(o, ["num_gpus"], 1.0)

    price = first_num(o, ["dph_total", "dph", "price", "hourly_price"], 0.0)
    dlperf = first_num(o, ["dlperf", "dl_performance", "dlp"], 0.0)
    dlperf_usd = first_num(o, ["dlperf_usd", "dlperf_per_dphtotal", "flops_per_dphtotal", "score"], 0.0)
    rel = first_num(o, ["reliability", "reliability2", "rel", "r"], 1.0)
    vram = first_num(o, ["gpu_ram", "gpu_total_ram", "vram"], 0.0)
    inet_down = first_num(o, ["inet_down"], 0.0)
    inet_down_cost = first_num(o, ["inet_down_cost"], 0.0)
    storage_cost = first_num(o, ["storage_cost"], 0.0)
    disk_space = first_num(o, ["disk_space"], 0.0)
    direct_ports = first_num(o, ["direct_port_count"], 0.0)
    verified = first_str(o, ["verification", "verified"], "True")

    if vram > 200:
        vram = vram / 1024.0

    # Lokale Eliminierung ungeeigneter Angebote:
    # Diese Kandidaten sollen gar nicht erst in die finale Tabelle.
    if vram < min_vram_gb:
        continue
    if rel < min_rel:
        continue

    initial_load_cost = model_gb * inet_down_cost
    monthly_model_storage = model_gb * storage_cost
    eff_hour = price + (initial_load_cost / max(session_hours, 0.1))

    rows.append({
        "oid": oid,
        "model": model,
        "num_gpus": num_gpus,
        "price": price,
        "init_load_cost": initial_load_cost,
        "eff_hour": eff_hour,
        "monthly_storage": monthly_model_storage,
        "dlperf": dlperf,
        "dlperf_usd": dlperf_usd,
        "rel": rel,
        "vram": vram,
        "inet_down": inet_down,
        "inet_down_cost": inet_down_cost,
        "disk_space": disk_space,
        "direct_ports": direct_ports,
        "verified": verified,
    })

for r in rows:
    print("\t".join([
        str(r["oid"]),
        str(r["model"]),
        str(r["num_gpus"]),
        f'{r["price"]:.6f}',
        f'{r["init_load_cost"]:.6f}',
        f'{r["eff_hour"]:.6f}',
        f'{r["monthly_storage"]:.6f}',
        f'{r["dlperf"]:.6f}',
        f'{r["dlperf_usd"]:.6f}',
        f'{r["rel"]:.6f}',
        f'{r["vram"]:.6f}',
        f'{r["inet_down"]:.6f}',
        f'{r["inet_down_cost"]:.6f}',
        f'{r["disk_space"]:.6f}',
        f'{r["direct_ports"]:.6f}',
        str(r["verified"]),
    ]))
PY
  )"

  if [[ -z "$parsed" ]]; then
    echo "[ERR] Keine geeigneten Angebote nach lokalem Filter vorhanden." >&2
    echo "[HINWEIS] SEARCH_LIMIT erhoehen oder Filter lockern." >&2
    exit 1
  fi

  mapfile -t rows < <(printf '%s\n' "$parsed")

  echo "Legende:"
  echo "  Grün  = bester GenAI-Score"
  echo "  Gelb  = gute Balance"
  echo "  Blau  = günstig"
  echo "  Rot   = wird im Normalbetrieb nicht mehr angezeigt, da ungeeignete Angebote vorher ausgeschlossen werden"
  echo

  local scored_rows=()
  local i
  local oid model numg price tx eff month dl dlu rel vram inet_down inet_cost disk ports verified score line

  for ((i=0; i<${#rows[@]}; i++)); do
    IFS=$'\t' read -r oid model numg price tx eff month dl dlu rel vram inet_down inet_cost disk ports verified <<< "${rows[$i]}"
    score="$(score_offer "$eff" "$dl" "$dlu" "$rel" "$vram" "$numg")"
    scored_rows+=("${score}"$'\t'"${rows[$i]}")
  done

  mapfile -t rows < <(
    printf '%s\n' "${scored_rows[@]}" | sort -t $'\t' -k1,1gr | cut -f2- | head -n "$RESULTS"
  )

  local limit=${#rows[@]}
  if [[ "$limit" -le 0 ]]; then
    echo "[ERR] Nach Score-Sortierung sind keine finalen Angebote uebrig geblieben." >&2
    exit 1
  fi

  local best_idx=0

  printf '%-3s %-10s %-18s %4s %7s %8s %8s %8s %9s %8s %6s %7s %6s\n' \
    "Nr" "Offer_ID" "Model" "GPUx" "\$/hr" "20GB Tx" "Eff\$/h" "DLPerf" "DLP/\$" "VRAMGB" "Rel" "Ports" "Score"
  printf '%s\n' "------------------------------------------------------------------------------------------------------------------"

  for ((i=0; i<limit; i++)); do
    IFS=$'\t' read -r oid model numg price tx eff month dl dlu rel vram inet_down inet_cost disk ports verified <<< "${rows[$i]}"
    score="$(score_offer "$eff" "$dl" "$dlu" "$rel" "$vram" "$numg")"

    line=$(printf '%-3s %-10s %-18s %4.0f %7.4f %8.4f %8.4f %8.1f %9.3f %8.1f %6.2f %7.0f %6.2f' \
      "$((i+1))" "$oid" "$model" "$numg" "$price" "$tx" "$eff" "$dl" "$dlu" "$vram" "$rel" "$ports" "$score")

    case "$i" in
      0) green "$line" ;;
      1|2) yellow "$line" ;;
      3|4) blue "$line" ;;
      *) printf '%s' "$line" ;;
    esac
    printf '\n'
  done

  IFS=$'\t' read -r oid model numg price tx eff month dl dlu rel vram inet_down inet_cost disk ports verified <<< "${rows[$best_idx]}"

  echo
  echo "Vorschlag: Nummer $((best_idx+1)) ($oid / $model)"
  echo "  - Stundenpreis: ${price} $/h"
  echo "  - Initiale 20GB-Beladung: ${tx} $"
  echo "  - Effektivpreis bei ${SESSION_HOURS}h Sitzung: ${eff} $/h"
  echo "  - Monatliche Storage-Kosten fuer 20GB: ${month} $/Monat"
  echo "  - DLPerf: ${dl}, DLPerf/\$: ${dlu}, VRAM: ${vram} GB, Reliability: ${rel}, Ports: ${ports}"
  echo
  echo "[HINWEIS] Dieses Skript bucht nicht automatisch."
  echo "[HINWEIS] Nutze die Offer-ID $oid im Vast-Webinterface und waehle dort dein Template,"
  echo "          z. B. 'SD WebUI Forge'."

  if [[ $dry -eq 1 ]]; then
    exit 0
  fi
}

main "$@"
