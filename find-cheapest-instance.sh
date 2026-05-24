#!/usr/bin/env bash
set -euo pipefail

VERSION="2026-05-24.26"

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

12) Grosse JSON-Daten nicht ueber Environment-Variablen weiterreichen
- Umfangreiche --raw-Antworten koennen bei Uebergabe ueber
  RAW_JSON=... an python3 zu "Argument list too long" fuehren.
- Grosse Rohdaten deshalb immer ueber Datei oder stdin an Python
  uebergeben, nicht ueber Umgebungsvariablen.

Kurzfazit
- Nicht Tabellen parsen.
- Nicht rohe Bundles-API priorisieren.
- Erst Rohdaten pruefen, dann Parser anpassen.
- Mehr Rohangebote laden, lokal ungeeignete eliminieren.
- Grosse JSON-Daten ueber Datei/stdin statt Environment-Variable.
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

color_supported() { [[ -t 1 ]]; }

c() {
  local code="$1"
  shift
  local text="$1"
  if color_supported; then
    printf '\0
