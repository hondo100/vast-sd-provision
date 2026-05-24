#!/usr/bin/env bash
set -euo pipefail

VERSION="2026-05-24.20"

: <<'SCRIPT_NOTES'
Erkenntnisse / Lessons Learned / Bitte bei Neuauflagen beibehalten und erweitern

======================================================================
A) WAS NICHT ZUVERLÄSSIG FUNKTIONIERT HAT
======================================================================

1) Direkte REST-Aufrufe gegen die Vast-API per curl
- Mehrere Varianten gegen:
    https://console.vast.ai/api/v0/bundles
  haben wiederholt HTTP 400 erzeugt.
- Getestete Fehlwege:
  a) JSON-artige Query direkt in der URL
     /bundles?q={"verified":{"eq":true}}&limit=200...
     -> Problem: curl/globbing/nested brace + API 400
  b) JSON-Body gegen /bundles/
     -> API-Format war nicht stabil bzw. nicht passend zur erwarteten Search-Syntax
  c) URL-encoded q=... auf /bundles/
     -> weiterhin 400
- Fazit:
  Nicht erneut auf rohe curl-/bundles-Varianten zurückfallen, solange CLI/--raw verfügbar ist.

2) Parsen der menschenlesbaren CLI-Tabelle
- Aufrufe wie:
    vastai search offers '...'
  liefern eine gut lesbare Tabelle für Menschen, aber kein robustes Skriptformat.
- Mehrere Parser-Ansätze (awk, Regex, Python auf Texttabelle) waren brüchig.
- Grund:
  Tabellenlayout kann je nach CLI-Version, Terminal, Spaltenbreite oder Formatierung variieren.

3) awk-basierte Parser
- Mindestens eine Version scheiterte direkt mit awk-Syntaxfehler.
- Schlussfolgerung:
  Für dieses Skript lieber Python-Parsing statt komplexer awk-Logik.

======================================================================
B) WAS BESSER FUNKTIONIERT / BEVORZUGTER PFAD
======================================================================

1) Vast CLI statt rohe REST-API
- Bevorzugt:
    vastai search offers ...
- Laut Vast-Dokumentation ist search offers die vorgesehene Suchschnittstelle.
- Die CLI unterstützt dieselben Filter-/Sortierfelder wie die Website.

2) Maschinenlesbare Ausgabe bevorzugen
- Bevorzugt:
    vastai search offers --raw 'QUERY' -o 'SORT'
- --raw ist laut CLI-Doku für maschinenlesbare JSON-Ausgabe gedacht.
- Für Skripte ist JSON deutlich stabiler als Tabellen-Text.

3) Standard-Query
- Dokumentationsnah und sinnvoll:
    external=false rentable=true verified=true
- Sortierung:
    -o 'dlperf_usd-'

======================================================================
C) BISHERIGE KONKRETE VERSIONEN / ERKENNTNISSE
======================================================================

v2026-05-24.9 bis v2026-05-24.12
- Diverse curl/API-Varianten
- Ergebnis:
  wiederholt HTTP 400

v2026-05-24.13
- Umstieg auf CLI
- Ergebnis:
  CLI lief grundsätzlich, aber noch ohne echtes Output-Parsing

v2026-05-24.14
- awk-Parser auf Tabellen-Output
- Ergebnis:
  awk-Syntaxfehler

v2026-05-24.15 / v2026-05-24.16
- Python-Parser auf Tabellen-Output
- Ergebnis:
  "Keine Angebote gefunden oder Parser passt nicht zum CLI-Output."
- Schluss:
  Tabellen-Parsing zu fragil

v2026-05-24.16b
- Umstieg auf:
    vastai search offers --raw 'external=false rentable=true verified=true' -o 'dlperf_usd-'
- Neues Log-Ergebnis:
  Das Skript lief bis zum Suchschritt und beendete sich danach OHNE Ausgabe und OHNE Fehlermeldung.
- Wichtige neue Erkenntnis:
  Nicht nur das Parserformat ist unsicher; offenbar kann auch die --raw-Ausgabe in der lokalen CLI-Umgebung leer sein
  oder anders zurückkommen als erwartet.
- Das muss künftig als eigener Problemfall behandelt werden.

v2026-05-24.18
- stdout/stderr der CLI-Suche werden zuerst getrennt in Dateien geschrieben und byteweise geprüft.
- Ergebnis:
  Leerfall, stderr-only-Fall und "kein JSON"-Fall lassen sich nun sauber unterscheiden.
- Schluss:
  Vor Parser- oder Ranking-Änderungen immer erst die Rohausgabe verifizieren.

v2026-05-24.19
- Wirtschaftlichkeitslogik erweitert um initiale Downloadkosten (20GB) und Storage-Kosten.
- Ergebnis:
  Bewertung ist näher an realen Betriebskosten als reine dph/dlperf-Sicht.
- Schluss:
  Für Modell-Hosting nicht nur Rechenpreis, sondern auch Daten-/Storage-Kosten berücksichtigen.

v2026-05-24.20
- Versionsnummer direkt an den Skriptanfang verschoben.
- Here-Docs und Funktionsblöcke sauber geschlossen, um EOF-Syntaxfehler zu vermeiden.
- Schluss:
  Syntax bleibt leichter prüfbar, und die Version ist sofort sichtbar.

======================================================================
D) NEUER PROBLEM-FALL AB v16b
======================================================================

Beobachtung:
- Log:
    Skript-Version: 2026-05-24.16b
    [INFO] Suche Angebote...
    Modus: test
    ...
  danach direkte Rückkehr zum Prompt, ohne Tabelle, ohne Fehler.

Mögliche Ursachen:
1) vastai search offers --raw liefert leeres stdout
2) vastai search offers --raw liefert etwas, das weder gültiges JSON noch erwartetes JSON ist
3) die lokale CLI-Version verhält sich bei --raw anders als dokumentiert
4) der Befehl schreibt evtl. relevante Infos nach stderr statt stdout
5) ein nicht abgefangener Leerfall im Shell-/Python-Pfad

Konsequenz:
- Vor weiteren funktionalen Umbauten IMMER zuerst Rohdiagnose machen.
- Nicht erneut an Ranking-/Farblogik arbeiten, solange die Rohdaten nicht verifiziert sind.

======================================================================
E) VERPFLICHTENDE DIAGNOSE VOR DER NÄCHSTEN NEUAUFLAGE
======================================================================

Diese Befehle zuerst manuell ausführen und die Ausgaben sichern:

1) Prüfen, ob CLI grundsätzlich korrekt authentifiziert ist
    vastai show user

2) Prüfen, ob --raw überhaupt Daten liefert
    vastai search offers --raw 'external=false rentable=true verified=true' -o 'dlperf_usd-' | head -c 1200

3) Prüfen, ob evtl. stderr genutzt wird
    vastai search offers --raw 'external=false rentable=true verified=true' -o 'dlperf_usd-' > /tmp/vast_raw.out 2> /tmp/vast_raw.err
    wc -c /tmp/vast_raw.out /tmp/vast_raw.err
    head -c 1200 /tmp/vast_raw.out
    head -c 1200 /tmp/vast_raw.err

4) CLI-Hilfe gegen lokale Version prüfen
    vastai search offers --help

Wenn /tmp/vast_raw.out leer ist:
- Problem liegt NICHT am Parser, sondern an CLI/Version/Auth/Flag-Verhalten.

Wenn /tmp/vast_raw.out Daten enthält, aber kein JSON:
- Problem liegt an lokalem --raw-Verhalten oder einer abweichenden CLI-Version.

Wenn /tmp/vast_raw.out JSON enthält:
- Dann erst Parser gegen genau dieses JSON anpassen.

======================================================================
F) BITTE BEI KÜNFTIGEN ÄNDERUNGEN BEACHTEN
======================================================================

- Diesen Kommentarblock NICHT entfernen.
- Nur erweitern, nicht ersetzen.
- Jede neue Version soll hier kurz dokumentieren:
  1) Was ausprobiert wurde
  2) Was passiert ist
  3) Welche Schlussfolgerung daraus folgt
- Nicht erneut zu curl + /api/v0/bundles zurückkehren, solange CLI + --raw möglich ist.
- Nicht wieder Texttabellen parsen, wenn --raw oder SDK verfügbar ist.

Kurzfazit:
BEVORZUGTER STABILER PFAD:
  Vast CLI -> search offers --raw -> Rohausgabe prüfen -> JSON mit python3 parsen -> Bash-Ausgabe erzeugen
SCRIPT_NOTES

RESULTS=10
MODEL_GB=20
MIN_VRAM_GB=24.0
MIN_REL=0.95
MIN_DISK_GB=40
QUERY='external=false rentable=true verified=true gpu_ram>=24 disk_space>=40'
SORT='dlperf_usd-'

usage() {
  cat <<EOF
Usage: $0 [--test] [--dry-run] [--diag] [--model-gb N] [--results N]

Optionen:
  --test         keine Buchung ausführen
  --dry-run      nur anzeigen, keine Auswahl/Buchung
  --diag         nur Diagnose der Roh-CLI-Ausgabe
  --model-gb N   Modellgröße in GB (default: $MODEL_GB)
  --results N    Anzahl anzuzeigender Treffer (default: $RESULTS)
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

score_offer() {
  local eff_hour="$1"
  local dl="$2"
  local rel="$3"
  local vram="$4"

  python3 - "$eff_hour" "$dl" "$rel" "$vram" "$MIN_VRAM_GB" "$MIN_REL" <<'PY'
import sys

eff  = float(sys.argv[1])
dl   = float(sys.argv[2])
rel  = float(sys.argv[3])
vram = float(sys.argv[4])
minv = float(sys.argv[5])
minr = float(sys.argv[6])

if vram < minv or rel < minr:
    print(-1.0)
    raise SystemExit(0)

eff = max(eff, 0.0001)
price_score = 1.0 / eff
vram_bonus = min(vram / 24.0, 2.0)
dl_bonus = dl / 100.0

score = (price_score * 0.50) + (dl_bonus * 0.30) + (vram_bonus * 0.15) + (rel * 0.05)
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
      --model-gb)
        shift
        MODEL_GB="${1:?Fehlender Wert fuer --model-gb}"
        ;;
      --results)
        shift
        RESULTS="${1:?Fehlender Wert fuer --results}"
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
  echo "[INFO] Sortierung: $SORT"
  echo "[INFO] Modellgroesse fuer initiale Beladung: ${MODEL_GB} GB"
  if [[ $test -eq 1 ]]; then
    echo "Modus: test"
  else
    echo "Modus: live"
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
  rm -f "$out_file" "$err_file"

  parsed="$(
    RAW_JSON="$raw" python3 - "$RESULTS" "$MODEL_GB" <<'PY'
import json
import os
import sys

results = int(sys.argv[1])
model_gb = float(sys.argv[2])
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

rows = []
for o in offers:
    if not isinstance(o, dict):
        continue

    oid = first_str(o, ["id", "offer_id"])
    model = first_str(o, ["gpu_name", "gpu", "model"], "unknown").replace("_", " ")
    num_gpus = first_num(o, ["num_gpus"], 1.0)

    price = first_num(o, ["dph_total", "dph", "price", "hourly_price"], 0.0)
    dlperf = first_num(o, ["dlperf", "dl_performance", "dlp"], 0.0)
    dlperf_usd = first_num(o, ["dlperf_usd"], 0.0)
    rel = first_num(o, ["reliability", "reliability2", "rel", "r"], 1.0)
    vram = first_num(o, ["gpu_ram", "gpu_total_ram", "vram"], 0.0)
    inet_down = first_num(o, ["inet_down"], 0.0)
    inet_down_cost = first_num(o, ["inet_down_cost"], 0.0)
    storage_cost = first_num(o, ["storage_cost"], 0.0)
    disk_space = first_num(o, ["disk_space"], 0.0)
    direct_ports = first_num(o, ["direct_port_count"], 0.0)
    verified = first_str(o, ["verified"], "True")

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

  printf '%-3s %-10s %-16s %4s %7s %8s %8s %8s %7s %8s %6s %7s %6s\n' \
    "Nr" "Offer_ID" "Model" "GPUx" "$/hr" "20GB Tx" "Eff$/h" "DLPerf" "DLP/\$" "VRAMGB" "Rel" "Ports" "Score"
  printf '%s\n' "-------------------------------------------------------------------------------------------------------------"

  local limit
  limit=$(( RESULTS < ${#rows[@]} ? RESULTS : ${#rows[@]} ))

  if [[ "$limit" -le 0 ]]; then
    echo "[ERR] Keine Angebote nach dem Parsen vorhanden."
    exit 1
  fi

  local best_idx=0
  local best_score="-999999"

  local i
  for ((i=0; i<limit; i++)); do
    IFS=$'\t' read -r oid model numg price tx eff month dl dlu rel vram inet_down inet_cost disk ports verified <<< "${rows[$i]}"

    score="$(score_offer "$eff" "$dl" "$rel" "$vram")"

    if python3 - "$score" "$best_score" <<'PY'
import sys
sys.exit(0 if float(sys.argv[1]) > float(sys.argv[2]) else 1)
PY
    then
      best_score="$score"
      best_idx="$i"
    fi

    line=$(printf '%-3s %-10s %-16s %4.0f %7.4f %8.4f %8.4f %8.1f %7.1f %8.1f %6.2f %7.0f %6.2f' \
      "$((i+1))" "$oid" "$model" "$numg" "$price" "$tx" "$eff" "$dl" "$dlu" "$vram" "$rel" "$ports" "$score")

    if python3 - "$score" <<'PY'
import sys
sys.exit(0 if float(sys.argv[1]) < 0 else 1)
PY
    then
      red "$line"
    else
      if [[ "$i" -eq "$best_idx" ]]; then
        green "$line"
      elif [[ "$i" -le 2 ]]; then
        yellow "$line"
      elif [[ "$i" -le 4 ]]; then
        blue "$line"
      else
        printf '%s' "$line"
      fi
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

  if [[ $test -eq 1 ]]; then
    echo "[TEST] Kein Booking ausgeführt."
    exit 0
  fi

  read -r -p "Buchung wirklich ausführen? [j/N]: " confirm
  if [[ "${confirm,,}" != "j" ]]; then
    echo "Abgebrochen."
    exit 0
  fi

  echo "[INFO] Booking würde hier ausgeführt werden."
  echo "[INFO] Beispielkommando (Image/Disk/Flags bei Bedarf anpassen):"
  echo "vastai create instance $oid --image pytorch/pytorch:2.4.0-cuda12.4-cudnn9-runtime --disk 40 --onstart-cmd \"echo hello && nvidia-smi\" --ssh --direct"
}

main "$@"
