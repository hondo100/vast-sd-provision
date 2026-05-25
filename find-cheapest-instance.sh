#!/usr/bin/env bash
set -eEuo pipefail

VERSION="2026-05-25.16"

# ============================================================================ #
# GLOBALE KONFIGURATION / DEFAULTS
# ============================================================================ #

RESULTS=10
SEARCH_LIMIT=120 
QUERY='external=false rentable=true verified=true gpu_ram>=24 disk_space>=40'
SORT='dlperf_usd-'

# Standard-Filter für die Leistungsklasse 3090/4090 und semiprofessionelle/professionelle Äquivalente
GPU_FILTER='RTX (3090|4090|A5000|A6000|5000|6000)'

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
BOOK_INDEX=""
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

========================================================================
ÄNDERUNGSHISTORIE
========================================================================
v2026-05-25.15:
  - FEHLENDE BUCHUNGSLOGIK BEHOBEN: Automatische Instanz-Erstellung via vastai.
v2026-05-25.16 (Aktuelle Version):
  - INTERAKTIVE RECHNERAUSWAHL: --book akzeptiert nun optionale Nummern (--book 3).
    Ohne Nummer wird interaktiv nach der Zeilennummer der Tabelle gefragt.
  - SICHERHEITSABFRAGE: Vor dem Absenden des Buchungsbefehls schützt eine explizite
    Bestätigungsschleife vor Fehlkäufen. Validierung gegen Tabellen-Obergrenze.
========================================================================
SCRIPT_OVERVIEW

usage() {
  cat <<EOF
Usage: $0 [--test] [--dry-run] [--diag] [--debug-json] [--debug-json-limit N]
          [--model-gb N] [--session-hours N] [--results N] [--search-limit N]
          [--book [NUM]] [--template-hash HASH] [--disk N] [--gpu-filter REGEX]
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
      --book) 
        DO_BOOK=1 
        if [[ $# -gt 1 && "$2" =~ ^[0-9]+$ ]]; then
          BOOK_INDEX="$2"
          shift
        fi
        ;;
      --template-hash) shift; TEMPLATE_HASH="${1:?Fehlender Wert fuer --template-hash}" ;;
      --disk) shift; DISK_GB="${1:?Fehlender Wert fuer --disk}" ;;
      --gpu-filter) shift; GPU_FILTER="${1:?Fehlender Wert fuer --gpu-filter}" ;;
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
  echo "[INFO] Aktiver GPU-Modellfilter (Regex): $GPU_FILTER"
  
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
    python3 - "$out_file" "$SEARCH_LIMIT" "$MODEL_GB" "$SESSION_HOURS" "$MIN_VRAM_GB" "$MIN_REL" "$BASE_BOOT_OVERHEAD_MIN" "$DOWNLOAD_EFFICIENCY" "$REF_DL_MBPS" "$REF_TOTAL_OVERHEAD_MIN" "$GPU_FILTER" <<'PY'
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
gpu_filter_regex = sys.argv[11]

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
    
    gpu_name_raw = first_str(o, ['gpu_name', 'gpu', 'model'], 'unknown')
    if not re.search(gpu_filter_regex, gpu_name_raw, re.IGNORECASE):
        continue

    oid = first_str(o, ['id', 'offer_id'])
    model = gpu_name_raw.replace('_', ' ')[:14]
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
    echo "[ERR] Keine geeigneten Angebote nach GPU- und Standort-Filterung vorhanden." >&2
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

  # ==========================================================================
  # INTERAKTIVE ODER DIRECT-INDEX BUCHUNGSLOGIK
  # ==========================================================================
  if [[ "${DO_BOOK}" -eq 1 ]]; then
    # Wenn keine Nummer über das CLI übergeben wurde, fragen wir interaktiv nach
    if [[ -z "${BOOK_INDEX}" ]]; then
      echo
      while true; do
        read -p "Bitte die gewünschte Nummer (Nr 1-$limit) für die Buchung eingeben: " BOOK_INDEX
        if [[ "$BOOK_INDEX" =~ ^[0-9]+$ ]] && [[ "$BOOK_INDEX" -ge 1 ]] && [[ "$BOOK_INDEX" -le "$limit" ]]; then
          break
        fi
        echo "[WARN] Ungültige Auswahl. Bitte eine Zahl zwischen 1 und $limit eingeben."
      done
    else
      # Validierung falls Nummer direkt per Parameter übergeben wurde
      if [[ "$BOOK_INDEX" -lt 1 || "$BOOK_INDEX" -gt "$limit" ]]; then
        echo "[ERR] Übergebene Nummer ($BOOK_INDEX) existiert nicht in der Tabelle (Bereich: 1-$limit)." >&2
        exit 10
      fi
    fi

    # Array-Index verschieben (Tabelle startet bei 1, Bash-Array bei 0)
    local target_idx=$((BOOK_INDEX - 1))

    local oid model numg price tx eff month dl dlu rel vram country inet_down disk_space ports est_dl_min est_ready_min est_dl_min_r est_ready_min_r verified
    IFS=$'\t' read -r oid model numg price tx eff month dl dlu rel vram country inet_down disk_space ports est_dl_min est_ready_min est_dl_min_r est_ready_min_r verified <<< "${rows[$target_idx]}"

    echo
    echo "------------------------------------------------------------------"
    yellow "SICHERHEITSABFRAGE: Instanz-Buchung"
    echo "------------------------------------------------------------------"
    echo "Gewählte Tabellennummer : $BOOK_INDEX"
    echo "Vast Offer ID           : $oid"
    echo "Modell                  : $model ($numg GPU(s))"
    echo "Stundenpreis            : $(fmt2 "$price") $/h"
    echo "Effektivpreis (${SESSION_HOURS}h)   : $(fmt2 "$eff") $/h"
    echo "Standort                : $country"
    echo "Konfiguriertes Template : $TEMPLATE_HASH"
    echo "Zugeordneter Speicher   : ${DISK_GB} GB Disk"
    echo "------------------------------------------------------------------"
    
    local confirm
    read -p "Möchten Sie diese Instanz jetzt kostenpflichtig buchen? [y/N]: " confirm
    case "$confirm" in
      [yY]|[yY][eE][sS])
        echo "[INFO] Starte automatische Instanzbuchung für Offer ID $oid..."
        ;;
      *)
        echo "[INFO] Buchung abgebrochen. Es wurden keine Ressourcen angefordert."
        exit 0
        ;;
    esac

    if [[ -z "${oid:-}" ]]; then
      echo "[ERR] Buchung nicht moeglich: Keine gueltige Offer-ID gefunden." >&2
      exit 10
    fi

    local book_output
    # if ! konsumiert den Exit-Code, set -e bricht hier NICHT unkontrolliert ab
    if ! book_output=$(vast_cmd create instance "$oid" --template_hash "$TEMPLATE_HASH" --disk "$DISK_GB" 2>&1); then
      echo "[ERR] Vast.ai API-Buchungsbefehl fehlgeschlagen!" >&2
      echo "[DETAILS]:" >&2
      echo "$book_output" >&2
      exit 12
    fi

    echo "[OK] Instanz-Erstellung erfolgreich an Vast.ai uebermittelt!"
    echo "------------------------------------------------------------------"
    echo "$book_output"
    echo "------------------------------------------------------------------"
  else
    echo
    echo "[INFO] Suchmodus aktiv. Es wurde keine Buchung vorgenommen (Fuer Buchung '--book [Nr]' verwenden)."
  fi
}

main "$@"
