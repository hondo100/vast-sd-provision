#!/usr/bin/env bash
set -euo pipefail

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

VERSION="2026-05-24.17"
RESULTS=10
MIN_VRAM_GB=24.0
MIN_REL=0.95
QUERY='external=false rentable=true verified=true'
SORT='dlperf_usd-'

usage() {
  echo "Usage: $0 [--test] [--dry-run]"
}

color_supported() {
  [[ -t 1 ]]
}

c() {
  local code="$1"; shift
  local text="$1"
  if color_supported; then printf '\033[%sm%s\033[0m' "$code" "$text"; else printf '%s' "$text"; fi
}

green(){ c 32 "$1"; }
yellow(){ c 33 "$1"; }
blue(){ c 34 "$1"; }
red(){ c 31 "$1"; }

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
  local price="$1" dl="$2" rel="$3" vram="$4"
  awk -v price="$price" -v dl="$dl" -v rel="$rel" -v vram="$vram" -v minv="$MIN_VRAM_GB" -v minr="$MIN_REL" '
    BEGIN {
      if (vram < minv || rel < minr) { print -1; exit }
      price_score = 1.0 / (price > 0.0001 ? price : 0.0001)
      vram_bonus = vram / 24.0
      if (vram_bonus > 2.0) vram_bonus = 2.0
      dl_bonus = dl / 100.0
      print (price_score * 0.45) + (dl_bonus * 0.35) + (vram_bonus * 0.15) + (rel * 0.05)
    }'
}

main() {
  local test=0 dry=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --test) test=1 ;;
      --dry-run) dry=1 ;;
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
  echo "[INFO] Suche Angebote..."
  if [[ $test -eq 1 ]]; then echo "Modus: test"; else echo "Modus: live"; fi
  echo "Legende:"
  echo "  Grün  = bester GenAI-Score"
  echo "  Gelb  = gute Balance aus Preis und Leistung"
  echo "  Blau  = günstigste effektive Kosten"
  echo "  Rot   = unter Mindestanforderungen"
  echo

  raw="$(vast_cmd search offers --raw "$QUERY" -o "$SORT" 2>/dev/null || true)"

  if [[ -z "$raw" ]]; then
    echo "[ERR] Keine --raw-Ausgabe erhalten." >&2
    echo "Diagnose 1: vastai show user" >&2
    echo "Diagnose 2: vastai search offers --raw '$QUERY' -o '$SORT' | head -c 1200" >&2
    echo "Diagnose 3: vastai search offers --raw '$QUERY' -o '$SORT' > /tmp/vast_raw.out 2> /tmp/vast_raw.err" >&2
    exit 1
  fi

  parsed="$(
    RAW_JSON="$raw" python3 - "$RESULTS" <<'PY'
import json
import os
import sys

results = int(sys.argv[1])
text = os.environ.get("RAW_JSON", "").strip()

if not text:
    sys.exit(0)

try:
    data = json.loads(text)
except Exception:
    sys.exit(0)

if isinstance(data, dict):
    if isinstance(data.get("offers"), list):
        offers = data["offers"]
    elif isinstance(data.get("rows"), list):
        offers = data["rows"]
    elif isinstance(data.get("results"), list):
        offers = data["results"]
    else:
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

    price = first_num(o, ["dph_total", "price", "hourly_price", "dph"], 0.0)
    dlp = first_num(o, ["dlperf", "dl_performance", "dlp"], 0.0)
    rel = first_num(o, ["reliability", "reliability2", "rel", "r"], 1.0)
    vram = first_num(o, ["gpu_ram", "gpu_total_ram", "vram"], 0.0)
    score = first_num(o, ["score"], 0.0)

    if vram > 200:
        vram = vram / 1024.0

    status = first_str(o, ["verified", "status"], "True")
    if status.lower() in ("true", "verified", "1"):
        status = "True"

    tx = 0.0
    eff = price

    if oid:
        rows.append((oid, model, price, tx, eff, dlp, rel, vram, status, score))

rows = rows[:results]

for r in rows:
    print("\t".join(map(str, r)))
PY
  )"

  if [[ -z "$parsed" ]]; then
    echo "[ERR] --raw wurde empfangen, aber das JSON-Format passte nicht zum Parser." >&2
    echo "Bitte diese Diagnose ausführen:" >&2
    echo "vastai search offers --raw '$QUERY' -o '$SORT' | head -c 1200" >&2
    exit 1
  fi

  mapfile -t rows < <(printf '%s\n' "$parsed")

  printf '%-3s %-10s %-18s %7s %8s %8s %8s %7s %8s %5s %6s\n' "Nr" "Offer_ID" "Model" "\$/hr" "20GB Tx" "Eff$/h" "DLPerf" "Score" "VRAM GB" "Rel" "Status"
  printf '%s\n' "--------------------------------------------------------------------------------------------------------"

  limit=$(( RESULTS < ${#rows[@]} ? RESULTS : ${#rows[@]} ))
  for ((i=0; i<limit; i++)); do
    IFS=$'\t' read -r oid model price tx eff dl rel vram status score <<< "${rows[$i]}"
    score2="$(score_offer "$price" "$dl" "$rel" "$vram")"
    [[ "$score" == "0" || "$score" == "0.0" ]] && score="$score2"
    line=$(printf '%-3s %-10s %-18s %7.4f %8.4f %8.4f %8.1f %7.1f %8.1f %5.2f %6s' \
      "$((i+1))" "$oid" "$model" "$price" "$tx" "$eff" "$dl" "$score" "$vram" "$rel" "$status")
    case "$i" in
      0) green "$line" ;;
      1|2) yellow "$line" ;;
      3|4) blue "$line" ;;
      *) printf '%s' "$line" ;;
    esac
    printf '\n'
  done

  IFS=$'\t' read -r oid model price tx eff dl rel vram status score <<< "${rows[0]}"
  echo
  echo "Vorschlag: Nummer 1 ($oid / $model)"

  if [[ $dry -eq 1 ]]; then
    exit 0
  fi

  choice=""
  while [[ -z "$choice" ]]; do
    read -r -p "Welche Nummer buchen? [1-$limit] (Enter = 1): " raw
    if [[ -z "$raw" ]]; then
      choice=1
    elif [[ "$raw" =~ ^[0-9]+$ ]] && (( raw >= 1 && raw <= limit )); then
      choice="$raw"
    else
      echo "Ungueltige Eingabe. Bitte nur eine gueltige Nummer eingeben."
    fi
  done

  IFS=$'\t' read -r oid model price tx eff dl rel vram status score <<< "${rows[$((choice-1))]}"
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
}

main "$@"
