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

VERSION="2026-05-24.19"
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

color_supported() { [[ -t 1 ]]; }

c() {
  local code="$1"; shift
  local text="$1"
  if color_supported; then
    printf '\033[%sm%s\033[0m' "$code" "$text"
  else
    printf '%s' "$text"
  fi
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
  local eff_hour="$1" dl="$2" rel="$3" vram="$4"
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
  vast_cmd search offers --raw "$QUERY" -o "$SORT" >"$out_file" 2>"$err_file"
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
import json, sys
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
  local test=0 dry=0 diag=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --test) test=1 ;;
      --dry-run) dry=1 ;;
      --diag) diag=1 ;;
      --model-gb)
        shift
        MODEL_GB="${1:?Fehlender Wert fuer --model-gb}"
        ;;
      --results)
        shift
        RESULTS="${1:?Fehlender Wert fuer --results}"
        ;;
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
  echo "[INFO] Suchquery: $QUERY"
  echo "[INFO] Sortierung: $SORT"
  echo "[INFO] Modellgroesse fuer initiale Beladung: ${MODEL_GB} GB"
  if [[ $test -eq 1 ]]; then echo "Modus: test"; else echo "Modus: live"; fi
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
  vast_cmd search offers --raw "$QUERY" 
