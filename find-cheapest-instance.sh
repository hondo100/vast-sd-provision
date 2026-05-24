#!/usr/bin/env bash
set -euo pipefail

VERSION="2026-05-24.23"

: <<'SCRIPT_OVERVIEW'
========================================================================
SCRIPT ARGUMENTS / OPTIONEN
========================================================================

Grundmodi
- --test
  Fuehrt keine echte Buchung aus. Die Auswahl- und Anzeige-Logik laeuft,
  aber create instance wird nicht ausgefuehrt.

- --dry-run
  Zeigt nur die Trefferliste und den Vorschlag an. Es erfolgt keine
  Rueckfrage zur Auswahl und keine Buchung.

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

- --results N
  Anzahl der anzuzeigenden Treffer. Standard: 10

Booking-Parameter
- --image IMAGE
  Docker-Image fuer `vastai create instance`.
  Standard:
    pytorch/pytorch:2.4.0-cuda12.4-cudnn9-runtime

- --disk-gb N
  Zu buchender Disk-Speicher in GB fuer create instance.
  Standard: 40

- --onstart-cmd CMD
  Startup-Kommando fuer create instance.

- --no-ssh
  Bucht die Instanz ohne `--ssh`.

- --no-direct
  Bucht die Instanz ohne `--direct`.

Interaktives Verhalten
- Das Skript macht nur einen Vorschlag fuer die wirtschaftlichste
  Instanz, bucht aber NICHT automatisch den Top-Treffer.
- Der Benutzer waehlt die endgueltige Nummer selbst.
- Enter uebernimmt den Vorschlag.

Beispiele
- Nur anzeigen:
    bash ./find-cheapest-instance.sh --test --dry-run

- Rohdiagnose:
    bash ./find-cheapest-instance.sh --diag

- JSON-Debug:
    bash ./find-cheapest-instance.sh --test --dry-run --debug-json 2>/tmp/vast_debug.err
    sed -n '1,120p' /tmp/vast_debug.err

- Echte Buchung mit eigenem Image:
    bash ./find-cheapest-instance.sh \
      --image vllm/vllm-openai:latest \
      --disk-gb 80 \
      --onstart-cmd 'nvidia-smi && python -V'

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
- Angebote unterhalb der Schwelle werden im Score als ungeeignet
  markiert.

7) Buchung bewusst interaktiv halten
- Das Skript soll nur einen Vorschlag machen.
- Die endgueltige Buchungsentscheidung bleibt beim Benutzer.
- Keine automatische Buchung des Rang-1-Treffers.
- Enter uebernimmt den Vorschlag, aber jede angezeigte Nummer kann
  bewusst ausgewaehlt werden.

8) SSH / Lifecycle
- Vor Nutzung von `--ssh` sicherstellen, dass im Vast-Account ein
  SSH-Key hinterlegt ist.
- Nach erfolgreicher Buchung sind typischerweise relevant:
    vastai ssh-url INSTANCE_ID
    vastai show instance INSTANCE_ID
    vastai stop instance INSTANCE_ID
    vastai destroy instance INSTANCE_ID

9) Bewertungssystem auf interaktives Arbeiten ausgerichtet
- Dieses Skript optimiert NICHT auf maximalen Batch-Durchsatz.
- Ziel ist längeres manuelles Arbeiten an einzelnen Bildern oder Videos.
- Deshalb werden niedrige Stundenpreise stärker gewichtet als rohe
  Spitzenleistung.
- Ausreichender VRAM und gute Reliability sind wichtiger als extreme
  Mehrleistung.
- Multi-GPU-Angebote werden leicht abgestraft, wenn sie fuer den Use
  Case voraussichtlich nur Mehrkosten statt echten Nutzen bringen.

Kurzfazit
- Nicht Tabellen parsen.
- Nicht rohe Bundles-API priorisieren.
- Erst Rohdaten pruefen, dann Parser anpassen.
- Finale Buchung immer bewusst durch Benutzerwahl ausloesen.
SCRIPT_OVERVIEW

RESULTS=10
MODEL_GB=20
MIN_VRAM_GB=24.0
MIN_REL=0.95
MIN_DISK_GB=40
DEBUG_JSON=0
DEBUG_JSON_LIMIT=2

QUERY='external=false rentable=true verified=true gpu_ram>=24 disk_space>=40'
SORT='dlperf_usd-'

IMAGE="${IMAGE:-pytorch/pytorch:2.4.0-cuda12.4-cudnn9-runtime}"
DISK_GB="${DISK_GB:-40}"
ONSTART_CMD="${ONSTART_CMD:-echo hello && nvidia-smi}"
ENABLE_SSH="${ENABLE_SSH:-1}"
ENABLE_DIRECT="${ENABLE_DIRECT:-1}"

usage() {
  cat <<EOF
Usage: $0 [--test] [--dry-run] [--diag] [--debug-json] [--debug-json-limit N] [--model-gb N] [--results N]
          [--image IMAGE] [--disk-gb N] [--onstart-cmd CMD] [--no-ssh] [--no-direct]
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
#    - eff_hour = GPU-Kosten plus auf 24h umgelegte initiale
#      Downloadkosten des Modells
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
  vast_cmd search offers --raw "$QUERY" -o "$SORT" --limit "$RESULTS" >"$out_file" 2>"$err_file"
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

create_instance() {
  local offer_id="$1"
  local tmp_out tmp_err rc create_args instance_id

  tmp_out="$(mktemp)"
  tmp_err="$(mktemp)"

  create_args=(create instance "$offer_id" --image "$IMAGE" --disk "$DISK_GB")
  if [[ -n "$ONSTART_CMD" ]]; then
    create_args+=(--onstart-cmd "$ONSTART_CMD")
  fi
  if [[ "$ENABLE_SSH" -eq 1 ]]; then
    create_args+=(--ssh)
  fi
  if [[ "$ENABLE_DIRECT" -eq 1 ]]; then
    create_args+=(--direct)
  fi

  echo "[INFO] Fuehre Booking aus..."
  echo "[INFO] Kommando: $(printf '%q ' "$(command -v vastai || command -v vast)" "${create_args[@]}")"

  set +e
  vast_cmd "${create_args[@]}" >"$tmp_out" 2>"$tmp_err"
  rc=$?
  set -e

  echo "[INFO] create instance stdout:"
  sed -n '1,120p' "$tmp_out" || true

  if [[ -s "$tmp_err" ]]; then
    echo "[INFO] create instance stderr:"
    sed -n '1,120p' "$tmp_err" || true
  fi

  if [[ $rc -ne 0 ]]; then
    echo "[ERR] Booking fehlgeschlagen (RC=$rc)." >&2
    rm -f "$tmp_out" "$tmp_err"
    return 1
  fi

  instance_id="$(
    python3 - "$tmp_out" <<'PY'
import json
import re
import sys

p = sys.argv[1]
txt = open(p, "r", encoding="utf-8", errors="replace").read().strip()

if not txt:
    raise SystemExit(0)

candidates = [txt]
if txt.splitlines():
    candidates.append(txt.splitlines()[-1])

for candidate in candidates:
    try:
        data = json.loads(candidate)
        if isinstance(data, dict):
            for k in ("new_contract", "instance_id", "id"):
                if k in data and data[k] not in (None, ""):
                    print(data[k])
                    raise SystemExit(0)
    except Exception:
        pass

m = re.search(r'\b(\d{6,})\b', txt)
if m:
    print(m.group(1))
PY
  )"

  if [[ -n "$instance_id" ]]; then
    echo "[OK] Instanz erstellt. Instance-ID: $instance_id"
    echo "[INFO] SSH-URL (falls verfuegbar):"
    vast_cmd ssh-url "$instance_id" 2>/dev/null || true
    echo "[INFO] Show:      vastai show instance $instance_id"
    echo "[INFO] Stoppen:   vastai stop instance $instance_id"
    echo "[INFO] Zerstoeren: vastai destroy instance $instance_id"
  else
    echo "[WARN] Booking erfolgreich, aber Instance-ID konnte nicht sicher aus der Ausgabe extrahiert werden."
  fi

  rm -f "$tmp_out" "$tmp_err"
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
      --results)
        shift
        RESULTS="${1:?Fehlender Wert fuer --results}"
        ;;
      --image)
        shift
        IMAGE="${1:?Fehlender Wert fuer --image}"
        ;;
      --disk-gb)
        shift
        DISK_GB="${1:?Fehlender Wert fuer --disk-gb}"
        ;;
      --onstart-cmd)
        shift
        ONSTART_CMD="${1:?Fehlender Wert fuer --onstart-cmd}"
        ;;
      --no-ssh)
        ENABLE_SSH=0
        ;;
      --no-direct)
        ENABLE_DIRECT=0
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
  echo "[INFO] Booking-Image: $IMAGE"
  echo "[INFO] Booking-Disk: ${DISK_GB} GB"
  echo "[INFO] Booking-SSH: $ENABLE_SSH"
  echo "[INFO] Booking-Direct: $ENABLE_DIRECT"
  if [[ -n "$ONSTART_CMD" ]]; then
    echo "[INFO] Booking-Onstart: $ONSTART_CMD"
  fi
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
  vast_cmd search offers --raw "$QUERY" -o "$SORT" --limit "$RESULTS" >"$out_file" 2>"$err_file"
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
    RAW_JSON="$raw" DEBUG_JSON="$DEBUG_JSON" DEBUG_JSON_LIMIT="$DEBUG_JSON_LIMIT" python3 - "$RESULTS" "$MODEL_GB" <<'PY'
import json
import os
import sys

results = int(sys.argv[1])
model_gb = float(sys.argv[2])
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
for o in offers:
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

    initial_load_cost = model_gb * inet_down_cost
    monthly_model_storage = model_gb * storage_cost
    eff_hour = price + (initial_load_cost / 24.0)

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

rows = rows[:results]

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
    echo "[ERR] --raw wurde empfangen, aber das JSON-Format passte nicht zum Parser." >&2
    echo "Bitte zuerst Diagnose ausführen: $0 --diag" >&2
    exit 1
  fi

  mapfile -t rows < <(printf '%s\n' "$parsed")

  echo "Legende:"
  echo "  Grün  = bester GenAI-Score"
  echo "  Gelb  = gute Balance"
  echo "  Blau  = günstig"
  echo "  Rot   = unter Mindestanforderungen"
  echo

  local limit
  limit=$(( RESULTS < ${#rows[@]} ? RESULTS : ${#rows[@]} ))

  if [[ "$limit" -le 0 ]]; then
    echo "[ERR] Keine Angebote nach dem Parsen vorhanden."
    exit 1
  fi

  local scored_rows=()
  local i
  local oid model numg price tx eff month dl dlu rel vram inet_down inet_cost disk ports verified score line

  for ((i=0; i<limit; i++)); do
    IFS=$'\t' read -r oid model numg price tx eff month dl dlu rel vram inet_down inet_cost disk ports verified <<< "${rows[$i]}"
    score="$(score_offer "$eff" "$dl" "$dlu" "$rel" "$vram" "$numg")"
    scored_rows+=("${score}"$'\t'"${rows[$i]}")
  done

  mapfile -t rows < <(
    printf '%s\n' "${scored_rows[@]}" | sort -t $'\t' -k1,1gr | cut -f2-
  )

  limit=${#rows[@]}
  local best_idx=0

  printf '%-3s %-10s %-16s %4s %7s %8s %8s %8s %9s %8s %6s %7s %6s\n' \
    "Nr" "Offer_ID" "Model" "GPUx" "\$/hr" "20GB Tx" "Eff\$/h" "DLPerf" "DLP/\$" "VRAMGB" "Rel" "Ports" "Score"
  printf '%s\n' "----------------------------------------------------------------------------------------------------------------"

  for ((i=0; i<limit; i++)); do
    IFS=$'\t' read -r oid model numg price tx eff month dl dlu rel vram inet_down inet_cost disk ports verified <<< "${rows[$i]}"
    score="$(score_offer "$eff" "$dl" "$dlu" "$rel" "$vram" "$numg")"

    line=$(printf '%-3s %-10s %-16s %4.0f %7.4f %8.4f %8.4f %8.1f %9.3f %8.1f %6.2f %7.0f %6.2f' \
      "$((i+1))" "$oid" "$model" "$numg" "$price" "$tx" "$eff" "$dl" "$dlu" "$vram" "$rel" "$ports" "$score")

    if python3 - "$score" <<'PY'
import sys
sys.exit(0 if float(sys.argv[1]) < 0 else 1)
PY
    then
      red "$line"
    else
      case "$i" in
        0) green "$line" ;;
        1|2) yellow "$line" ;;
        3|4) blue "$line" ;;
        *) printf '%s' "$line" ;;
      esac
    fi
    printf '\n'
  done

  IFS=$'\t' read -r oid model numg price tx eff month dl dlu rel vram inet_down inet_cost disk ports verified <<< "${rows[$best_idx]}"

  echo
  echo "Vorschlag: Nummer $((best_idx+1)) ($oid / $model)"
  echo "  - Stundenpreis: ${price} $/h"
  echo "  - Initiale 20GB-Beladung: ${tx} $"
  echo "  - Effektivpreis erste 24h (vereinfacht): ${eff} $/h"
  echo "  - Monatliche Storage-Kosten fuer 20GB: ${month} $/Monat"
  echo "  - DLPerf: ${dl}, DLPerf/\$: ${dlu}, VRAM: ${vram} GB, Reliability: ${rel}, Ports: ${ports}"

  if [[ $dry -eq 1 ]]; then
    exit 0
  fi

  local choice=""
  local raw_choice=""
  while [[ -z "$choice" ]]; do
    read -r -p "Welche Nummer buchen? [1-$limit] (Enter = $((best_idx+1))): " raw_choice
    if [[ -z "$raw_choice" ]]; then
      choice="$((best_idx+1))"
    elif [[ "$raw_choice" =~ ^[0-9]+$ ]] && (( raw_choice >= 1 && raw_choice <= limit )); then
      choice="$raw_choice"
    else
      echo "Ungueltige Eingabe. Bitte nur eine gueltige Nummer eingeben."
    fi
  done

  IFS=$'\t' read -r oid model numg price tx eff month dl dlu rel vram inet_down inet_cost disk ports verified <<< "${rows[$((choice-1))]}"

  echo
  echo "Gewählt: $choice -> $oid / $model"
  echo "[INFO] Booking-Parameter:"
  echo "  - Offer-ID: $oid"
  echo "  - Image: $IMAGE"
  echo "  - Disk: $DISK_GB GB"
  echo "  - SSH: $ENABLE_SSH"
  echo "  - Direct: $ENABLE_DIRECT"
  echo "  - Onstart: $ONSTART_CMD"

  if [[ $test -eq 1 ]]; then
    echo "[TEST] Kein Booking ausgeführt."
    exit 0
  fi

  read -r -p "Buchung wirklich ausführen? [j/N]: " confirm
  if [[ "${confirm,,}" != "j" ]]; then
    echo "Abgebrochen."
    exit 0
  fi

  create_instance "$oid"
}

main "$@"
