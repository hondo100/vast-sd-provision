#!/usr/bin/env bash
set -euo pipefail

VERSION="2026-05-25.12"

# ============================================================================ #
# GLOBALE KONFIGURATION / DEFAULTS
# ============================================================================ #

RESULTS=10
SEARCH_LIMIT=60
QUERY='external=false rentable=true verified=true gpu_ram>=24 disk_space>=40'
SORT='dlperf_usd-'

MODEL_GB=20
SESSION_HOURS=3
MIN_VRAM_GB=24.0
MIN_REL=0.95
MIN_DISK_GB=40

DOWNLOAD_EFFICIENCY=0.75
BASE_BOOT_OVERHEAD_MIN=1.0
REF_DL_MBPS=1370.0
REF_TOTAL_OVERHEAD_MIN=7.0

DO_BOOK=0
DISK_GB=40
TEMPLATE_HASH="ad0935fab3e1f781fa442c1604ed07e2"

DEBUG_JSON=0
DEBUG_JSON_LIMIT=2
COLOR_ENABLED_AUTO=1

: <<'SCRIPT_OVERVIEW'
========================================================================
ZWECK
========================================================================
- Dieses Skript sucht wirtschaftliche Vast-Angebote fuer ca. 20GB-Modelle.
- Es kann nach Benutzerauswahl OPTIONAL direkt buchen.
- Es bewertet die geschaetzte Downloadzeit fuer 20GB
  sowie die geschaetzte Gesamt-Bereitstellungszeit.

- Es filtert chinesische Angebote nur clientseitig im Python-Parser.
- Serverseitig werden nur von Vast unterstuetzte Suchfilter verwendet.
- Die Bereitstellungszeit-Schaetzung nutzt eine empirische Referenz:
  bei 1370 Mb/s betrug der Initial-Overhead ca. 7 Minuten.

========================================================================
ENTDECKUNGEN / FINDINGS / LOGIK
========================================================================
1) EMPIRISCHE BEWERTUNG:
   - Bei 1370 Mb/s habe ich beobachtet:
     - 20GB-Download selbst dauert kurz,
     - aber die Gesamt-Bereitstellung (inkl. Setup, Datei-/Model-I/O) ca. 7 Minuten.

2) MODELL:
   - Download-Zeit = reine Netzzeit.
   - Zusatz-Overhead steigt bei schnelleren Verbindungen nicht weiter an,
     sondern bleibt an der Referenz orientiert.

3) CHINA-FILTER:
   - location_country ist KEIN gueltiges Vast-Suchfeld.
   - Deshalb keine serverseitige China-Filterung.
   - Clientseitig werden Angebote mit geolocation/location auf CN / China gefiltert.

4) TABELLENFORMAT:
   - Jede Zeile wird in exakt dieselbe Spaltenreihenfolge ausgegeben,
     damit keine Verschiebung mehr entsteht.
   - verified hat eine eigene Spalte am Ende.

========================================================================
WICHTIGE ERKENNTNISSE / PROBLEME / SPEZIALLOGIK
========================================================================
1) Vast CLI + --raw ist der bevorzugte Suchpfad.
2) location_country ist KEIN gültiges Suchfeld: nicht in QUERY verwenden.
3) Tabellen-Parsing vermeiden, JSON bevorzugen.
4) Rohdiagnose vor Parserumbauten.
5) Grosse JSON-Daten nie per Environment-Variable an Python uebergeben.
6) Fuer ~20GB-Modelle ist 24GB VRAM eine sinnvolle Mindestschwelle.
7) Downloadgeschwindigkeit (`inet_down`) ist fuer die tatsaechliche
   Time-to-Ready relevant und fliesst in Bewertung und Tabelle ein.
8) Die angezeigte Bereitstellungszeit ist eine SCHAETZUNG:
   - aus inet_down (Mb/s),
   - multipliziert mit einem Effizienzfaktor,
   - plus einem netzwerkhaengigen Initial-Overhead (7 Minuten bei 1370 Mb/s).
9) `reliability` wird weiter intern im Score verwendet, aber nicht
   mehr in der Tabelle angezeigt.
10) Template-Buchung bedeutet:
    - Offer-ID bleibt Pflicht
    - template_hash liefert die Basiskonfiguration
    - disk sollte explizit gesetzt werden
11) GEOLOCATION / LAND:
    - Die API liefert kein flaches Feld 'location_country'. Die Information
      befindet sich im Feld 'geolocation' (z.B. "Frankfurt, DE"). Das Skript
      extrahiert das ISO-Kürzel am Ende dieses Strings via Regex.
12) Nach jedem groesseren Edit:
     bash -n ./find-cheapest-instance.sh
SCRIPT_OVERVIEW

usage() {
  cat <<EOF
Usage: $0 [--test] [--dry-run] [--diag] [--debug-json] [--debug-json-limit N]
          [--model-gb N] [--session-hours N] [--results N] [--search-limit N]
          [--book] [--template-hash HASH] [--disk N]
EOF
}

color_supported() { [[ "${COLOR_ENABLED_AUTO}" -eq 1 && -t 1 ]]; }
c() {
  local code="$1"; shift
  local text="$1"
  if color_supported; then printf '\033[%sm%s\033[0m' "$code" "$text"; else printf '%s' "$text"; fi
}
green()  { c 32 "$1"; }
yellow() { c 33 "$1"; }
blue()   { c 34 "$1"; }
red()    { c 31 "$1"; }

have_vast() { command -v vastai >/dev/null 2>&1 || command -v vast >/dev/null 2>&1; }
vast_bin() { if command -v vastai >/dev/null 2>&1; then echo "vastai"; else echo "vast"; fi; }
vast_cmd() { if command -v vastai >/dev/null 2>&1; then vastai "$@"; else vast "$@"; fi; }
fmt2() { printf '%.2f' "${1:-0}"; }

score_offer() {
  local eff_hour="$1" dl="$2" dlu="$3" rel="$4" vram="$5" numg="$6" ready_min="$7" dl_mbps="$8"
  python3 - "$eff_hour" "$dl" "$dlu" "$rel" "$vram" "$numg" "$ready_min" "$dl_mbps" "$MIN_VRAM_GB" "$MIN_REL" <<'PY'
import math, sys
eff=float(sys.argv[1]); dl=float(sys.argv[2]); dlu=float(sys.argv[3]); rel=float(sys.argv[4]); vram=float(sys.argv[5]); numg=float(sys.argv[6]); ready_min=float(sys.argv[7]); dl_mbps=float(sys.argv[8]); minv=float(sys.argv[9]); minr=float(sys.argv[10])
if vram < minv or rel < minr:
    print(-1.0)
    raise SystemExit(0)
cost_score = 1.0 / max(eff, 0.0001)
if vram < 24: vram_score = 0.0
elif vram <= 28: vram_score = 0.75
elif vram <= 32: vram_score = 0.95
elif vram <= 48: vram_score = 1.10
elif vram <= 80: vram_score = 1.18
else: vram_score = 1.22
rel_score = rel * rel
dl_score = math.log(max(dl, 1.0))
dlu_score = math.log(max(dlu, 1.0))
net_score = math.log(max(dl_mbps, 1.0))
ready_penalty = 1.0 / max(ready_min, 1.0)
if numg <= 1: gpu_penalty = 1.00
elif numg <= 2: gpu_penalty = 0.82
elif numg <= 4: gpu_penalty = 0.68
else: gpu_penalty = 0.55
score = (cost_score * 0.47 + vram_score * 0.16 + rel_score * 0.14 + ready_penalty * 0.12 + dlu_score * 0.05 + dl_score * 0.03 + net_score * 0.03) * gpu_penalty
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
  if [[ "$out_bytes" -eq 0 ]]; then
    echo "[ERR] stdout ist leer."
    rm -f "$out_file" "$err_file"
    return 1
  fi
  rm -f "$out_file" "$err_file"
}

main() {
  local test=0 dry=0 diag=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --test) test=1 ;;
      --dry-run) dry=1 ;;
      --diag) diag=1 ;;
      --debug-json) DEBUG_JSON=1 ;;
      --debug-json-limit) shift; DEBUG_JSON_LIMIT="${1:?Fehlender Wert fuer --debug-json-limit}" ;;
      --model-gb) shift; MODEL_GB="${1:?Fehlender Wert fuer --model-gb}" ;;
      --session-hours) shift; SESSION_HOURS="${1:?Fehlender Wert fuer --session-hours}" ;;
      --results) shift; RESULTS="${1:?Fehlender Wert fuer --results}" ;;
      --search-limit) shift; SEARCH_LIMIT="${1:?Fehlender Wert fuer --search-limit}" ;;
      --book) DO_BOOK=1 ;;
      --template-hash) shift; TEMPLATE_HASH="${1:?Fehlender Wert fuer --template-hash}" ;;
      --disk) shift; DISK_GB="${1:?Fehlender Wert fuer --disk}" ;;
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
  if [[ $diag -eq 1 ]]; then
    diag_raw
    exit $?
  fi

  echo "[INFO] Auth-Check..."
  if ! vast_cmd show user >/dev/null 2>&1; then
    echo "[ERR] vast CLI nicht authentifiziert." >&2
    exit 1
  fi

  local out_file err_file rc
  out_file="$(mktemp)"
  err_file="$(mktemp)"

  echo "[INFO] Suche Angebote..."
  set +e
  vast_cmd search offers --raw "$QUERY" -o "$SORT" --limit "$SEARCH_LIMIT" >"$out_file" 2>"$err_file"
  rc=$?
  set -e

  if [[ $rc -ne 0 || ! -s "$out_file" ]]; then
    echo "[ERR] search offers fehlgeschlagen." >&2
    rm -f "$out_file" "$err_file"
    exit 1
  fi
  rm -f "$err_file"

  local parsed
  parsed="$(
    DEBUG_JSON="$DEBUG_JSON" DEBUG_JSON_LIMIT="$DEBUG_JSON_LIMIT" \
    python3 - "$out_file" "$SEARCH_LIMIT" "$MODEL_GB" "$SESSION_HOURS" "$MIN_VRAM_GB" "$MIN_REL" "$BASE_BOOT_OVERHEAD_MIN" "$DOWNLOAD_EFFICIENCY" "$REF_DL_MBPS" "$REF_TOTAL_OVERHEAD_MIN" <<'PY'
import json, os, re, sys
json_path = sys.argv[1]
search_limit = int(sys.argv[2])
model_gb = float(sys.argv[3])
session_hours = float(sys.argv[4])
min_vram_gb = float(sys.argv[5])
min_rel = float(sys.argv[6])
base_boot_overhead_min = float(sys.argv[7])
download_efficiency = float(sys.argv[8])
ref_dl_mbps = float(sys.argv[9])
ref_total_overhead_min = float(sys.argv[10])

def first_str(d, keys, default=''):
    for k in keys:
        if k in d and d[k] not in (None, ''): return str(d[k])
    return default

def first_num(d, keys, default=0.0):
    for k in keys:
        if k in d and d[k] not in (None, ''):
            try: return float(d[k])
            except Exception: pass
    return float(default)

def extract_country(o):
    geo = str(o.get('geolocation', o.get('location', ''))).strip()
    if not geo or geo.lower() in ('none', 'unknown', 'null'):
        return 'US'
    
    u = geo.upper()
    m = re.search(r'\b([A-Z]{2})\b\s*$', u)
    if m: return m.group(1)
    
    countries = {'USA': 'US', 'GERMANY': 'DE', 'SPAIN': 'ES', 'FRANCE': 'FR', 'CANADA': 'CA', 'NETHERLANDS': 'NL'}
    for name, code in countries.items():
        if name in u: return code
    return geo[:8]

text = open(json_path, 'r', encoding='utf-8', errors='replace').read().strip()
if not text: sys.exit(0)
try: data = json.loads(text)
except Exception: sys.exit(0)

if isinstance(data, dict):
    offers = data.get('offers', data.get('rows', data.get('results', [data])))
elif isinstance(data, list): offers = data
else: offers = []

rows = []
for o in offers[:search_limit]:
    if not isinstance(o, dict): continue
    oid = first_str(o, ['id', 'offer_id'])
    model = first_str(o, ['gpu_name', 'gpu', 'model'], 'unknown').replace('_', ' ')[:14]
    num_gpus = first_num(o, ['num_gpus'], 1.0)
    price = first_num(o, ['dph_total', 'dph', 'price', 'hourly_price'], 0.0)
    dlperf = first_num(o, ['dlperf', 'dl_performance', 'dlp'], 0.0)
    dlperf_usd = first_num(o, ['dlperf_usd', 'dlperf_per_dphtotal', 'flops_per_dphtotal', 'score'], 0.0)
    rel = first_num(o, ['reliability', 'reliability2', 'rel', 'r'], 1.0)
    vram = first_num(o, ['gpu_ram', 'gpu_total_ram', 'vram'], 0.0)
    inet_down = first_num(o, ['inet_down'], 0.0)
    inet_down_cost = first_num(o, ['inet_down_cost'], 0.0)
    storage_cost = first_num(o, ['storage_cost'], 0.0)
    disk_space = first_num(o, ['disk_space'], 0.0)
    direct_ports = first_num(o, ['direct_port_count'], 0.0)
    verified = first_str(o, ['verification', 'verified'], 'True')

    country = extract_country(o)
    if country in ('CN', 'CHINA'): continue

    if vram > 200: vram = vram / 1024.0
    if vram < min_vram_gb or rel < min_rel: continue

    initial_load_cost = model_gb * inet_down_cost
    monthly_model_storage = model_gb * storage_cost
    eff_hour = price + (initial_load_cost / max(session_hours, 0.1))

    effective_mbps = max(inet_down * download_efficiency, 0.001)
    model_megabits = model_gb * 1024.0 * 8.0
    est_model_dl_min = model_megabits / effective_mbps / 60.0

    actual_dl_mbps_used = max(inet_down, 1.0)
    speed_overhead_scale = max(ref_dl_mbps / actual_dl_mbps_used, 1.0)
    additional_overhead_min = (ref_total_overhead_min - base_boot_overhead_min) * speed_overhead_scale
    final_boot_overhead = base_boot_overhead_min + additional_overhead_min
    est_ready_min = est_model_dl_min + final_boot_overhead

    rows.append({
        'oid': oid, 'model': model, 'num_gpus': num_gpus, 'price': price,
        'init_load_cost': initial_load_cost, 'eff_hour': eff_hour,
        'monthly_storage': monthly_model_storage, 'dlperf': dlperf,
        'dlperf_usd': dlperf_usd, 'rel': rel, 'vram': vram,
        'inet_down': inet_down, 'disk_space': disk_space,
        'direct_ports': direct_ports, 'verified': verified, 'country': country,
        'est_model_dl_min': est_model_dl_min, 'est_ready_min': est_ready_min,
        'est_model_dl_min_rounded': int(round(est_model_dl_min)),
        'est_ready_min_rounded': int(round(est_ready_min)),
    })

for r in rows:
    print('\t'.join([
        str(r['oid']), str(r['model']), str(int(round(r['num_gpus']))),
        f"{r['price']:.6f}", f"{r['init_load_cost']:.6f}", f"{r['eff_hour']:.6f}",
        f"{r['monthly_storage']:.6f}", f"{r['dlperf']:.6f}", f"{r['dlperf_usd']:.6f}",
        f"{r['rel']:.6f}", f"{r['vram']:.6f}", str(r['country']), f"{r['inet_down']:.6f}",
        f"{r['disk_space']:.6f}", f"{r['direct_ports']:.6f}", f"{r['est_model_dl_min']:.6f}",
        f"{r['est_ready_min']:.6f}", str(r['est_model_dl_min_rounded']), str(r['est_ready_min_rounded']),
        str(r['verified']),
    ]))
PY
  )"

  rm -f "$out_file"

  if [[ -z "$parsed" ]]; then
    echo "[ERR] Keine geeigneten Angebote nach lokalem Filter vorhanden." >&2
    exit 1
  fi

  local -a rows
  mapfile -t rows < <(printf '%s\n' "$parsed")

  local -a scored_rows=()
  local i
  for ((i=0; i<${#rows[@]}; i++)); do
    local oid model numg price tx eff month dl dlu rel vram country inet_down disk_space ports est_dl_min est_ready_min est_dl_min_r est_ready_min_r verified score
    IFS=$'\t' read -r oid model numg price tx eff month dl dlu rel vram country inet_down disk_space ports est_dl_min est_ready_min est_dl_min_r est_ready_min_r verified <<< "${rows[$i]}"
    score="$(score_offer "$eff" "$dl" "$dlu" "$rel" "$vram" "$numg" "$est_ready_min" "$inet_down")"
    scored_rows+=("${score}"$'\t'"${rows[$i]}")
  done

  mapfile -t rows < <(
    printf '%s\n' "${scored_rows[@]}" | sort -t $'\t' -k1,1gr | cut -f2- | head -n "$RESULTS"
  )

  local limit=${#rows[@]}
  if [[ "$limit" -le 0 ]]; then
    echo "[ERR] Keine Rechnerkonfigurationen nach Score-Filterung verblieben." >&2
    exit 1
  fi

  printf '%-3s %-10s %-14s %4s %7s %7s %8s %8s %7s %7s %8s %8s %8s %7s %s\n' \
    "Nr" "Offer_ID" "Model" "GPUx" "$/hr" "Init$" "Eff$/h" "DLMB/s" "DL20m" "Readym" "VRAM" "Ports" "Country" "Score" "Ver"
  printf '%s\n' "------------------------------------------------------------------------------------------------------------------------------------------"

  for ((i=0; i<limit; i++)); do
    local oid model numg price tx eff month dl dlu rel vram country inet_down disk_space ports est_dl_min est_ready_min est_dl_min_r est_ready_min_r verified score line
    IFS=$'\t' read -r oid model numg price tx eff month dl dlu rel vram country inet_down disk_space ports est_dl_min est_ready_min est_dl_min_r est_ready_min_r verified <<< "${rows[$i]}"
    score="$(score_offer "$eff" "$dl" "$dlu" "$rel" "$vram" "$numg" "$est_ready_min" "$inet_down")"
    
    line=$(printf '%-3s %-10s %-14s %4.0f %7.2f %7.2f %8.2f %8.0f %7.0f %7.0f %8.1f %8.0f %8s %7.2f %s' \
      "$((i+1))" "$oid" "$model" "$numg" "$price" "$tx" "$eff" "$inet_down" "$est_dl_min_r" "$est_ready_min_r" "$vram" "$ports" "$country" "$score" "$verified")
    case "$i" in
      0) green "$line" ;;
      1|2) yellow "$line" ;;
      3|4) blue "$line" ;;
      *) printf '%s' "$line" ;;
    esac
    printf '\n'
  done

  # Vorschlags-Zusammenfassung am Ende
  local oid model numg price tx eff month dl dlu rel vram country inet_down disk_space ports est_dl_min est_ready_min est_dl_min_r est_ready_min_r verified
  IFS=$'\t' read -r oid model numg price tx eff month dl dlu rel vram country inet_down disk_space ports est_dl_min est_ready_min est_dl_min_r est_ready_min_r verified <<< "${rows[0]}"

  echo
  echo "Vorschlag: Nummer 1 ($oid / $model / ${country})"
  echo "  - Stundenpreis: $(fmt2 "$price") $/h"
  echo "  - Effektivpreis bei ${SESSION_HOURS}h Sitzung: $(fmt2 "$eff") $/h"
  echo "  - Standort: ${country}"
  echo
}

main "$@"
