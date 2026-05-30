# Vast.ai Closed-Loop Spot Instance Optimizer

Dieses Repository enthält ein modulares, dreiteiliges System zur automatisierten Suche, Bewertung und kontinuierlichen Parameter-Kalibrierung von GPU-Instanzen auf dem Vast.ai-Marktplatz. Ziel des Systems ist es, die Bereitstellungslatenz (Time-to-Ready) von volatilen Spot-Instanzen mathematisch vorherzusagen und die Bewertungsmatrix durch echte Telemetriedaten nach jeder Nutzung im geschlossenen Regelkreis (*Closed-Loop*) zu optimieren.

---
## 1. Sinn und Zweck

Bei der Nutzung von Cloud-GPU-Anbietern wie Vast.ai hängen die realen Kosten nicht nur vom reinen Stundenpreis ab, sondern massiv von der **Setup- und Download-Latenz**. Eine vermeintlich günstige Instanz mit langsamer Netzanbindung oder hohem Overhead kann durch lange Bereitstellungszeiten in der Gesamtrechnung teurer werden als eine Instanz mit höherem Stundenpreis, die jedoch sofort einsatzbereit ist.

Dieses System:
* **Automatisiert** die Abfrage und Filterung des Vast.ai-Marktplatzes.
* **Berechnet** einen multivariaten Score für jede Instanz anhand von Preis, VRAM, Netzwerkspeed und Zuverlässigkeit.
* **Prognostiziert** die exakte Bereitstellungszeit in Minuten.
* **Kalibriert** sich nach jeder Instanz-Nutzung selbst, indem es die reale Phasen-Telemetrie per Pull-Verfahren abgreift und die Vorhersage-Parameter adaptiv anpasst
---

## 2. Komponenten und Funktionsweise
Das System teilt die Verantwortlichkeiten strikt nach dem Prinzip der *Separation of Concerns* auf:
```
[vastai API] -> (find-cheapest-instance.sh) -> [Pipe] -> (scoring_engine.py) <- [params.json]
                                                                |
                                                         [Ausgabe Tabelle]
                                                                |
[Instanz terminiert] -> (cleanup-and-optimize.sh) -> [Pull] -> (optimizer.py) ---> [params.json aktualisiert]
```

* **`find-cheapest-instance.sh` (Der Orchestrator):**
    Ein POSIX-konformes Bash-Skript. Es kommuniziert mit der `vastai` CLI, ruft rohe JSON-Daten ab und reicht diese zustandslos über eine Unix-Pipe an die Scoring Engine weiter. Es übernimmt zudem das UI-Rendering und die interaktive Buchungsschleife.
* **`scoring_engine.py` (Das mathematische Herzstück):**
    Ein eigenständiges Python-Skript, das die Rohdaten über `stdin` liest. Es filtert nach den gewünschten GPU-Typen und berechnet das mathematische Latenzmodell unter Einbeziehung der externen Konfiguration.
* **`params.json` (Die Konfigurations-Schnittstelle):**
    Die *Single Source of Truth* für die empirischen Regressionsparameter (Beta-Werte). Sie entkoppelt die mathematischen Koeffizienten vollständig vom ausführbaren Code.
* **`optimizer.py` (Der Feedback-Kanal):**
    Dieses Skript realisiert den geschlossenen Regelkreis. Es liest die von der zerstörten Instanz gesicherte `provisioning_telemetry.json` aus, zerlegt die gemessenen Zeiten in ihre atomaren Phasen und kalibriert die Beta-Werte für den nächsten Suchlauf.
---

## 3. Mathematische Grundlagen

### Latenzprognose (Scoring Engine)
Die prognostizierte Bereitstellungszeit T_ready in Minuten wird über folgende multivariate lineare Gleichung geschätzt:
T_ready = (beta_0 + beta_2 + (beta_1 * (Modell-Größe in MB / Download-Speed in MB/s)) + beta_3 * (1 - Reliability)) / 60.0

### Parameter-Anpassung (Optimizer)
Die Anpassung erfolgt über einen exponentiellen gleitenden Durchschnitt (*Exponential Moving Average*, EMA). Dadurch lernt das System systematische Verschiebungen (z.B. veränderte Docker-Images oder geänderte Paketquellen), ignoriert jedoch temporäre Netzwerk-Ausreißer einzelner Hoster:

beta_0_neu = (1 - alpha) * beta_0_alt + alpha * (T_setup_gemessen - beta_2)

Dabei steuert alpha die Lernrate (Standard: 0.25).
---

## 4. Voraussetzungen & Installation

### System-Abhängigkeiten
Stelle sicher, dass folgende Werkzeuge auf dem lokalen Host-System installiert und im `PATH` verfügbar sind:
* Python 3.10 oder neuer
* `vastai` CLI (ordnungsgemäß authentifiziert via `vastai set api-key`)
* `bc` (für mathematische Vergleiche in Bash)

### Installation
Kopiere alle Dateien in dasselbe lokale Arbeitsverzeichnis und vergebe die erforderlichen Ausführungsrechte:

```bash
chmod +x find-cheapest-instance.sh
chmod +x scoring_engine.py
chmod +x optimizer.py
```

Stelle sicher, dass die initiale `params.json` im selben Verzeichnis liegt.
---

## 5. Bedienung und Workflow

### Schritt 1: Instanz suchen und buchen
Starte die interaktive Suche und Bewertung über das Hauptskript:

```bash
./find-cheapest-instance.sh --book
```

* **Farbkodierung der Konsolenausgabe:**
    * **Grün (Top Score):** Das mathematisch beste Verhältnis aus Kosten, Leistung und Zuverlässigkeit für Langzeitsitzungen.
    * **Gelb (Best Test):** Die absolut günstigste Option für kurze Test-Sitzungen (unter Einbeziehung der Initialisierungskosten).
    * **Cyan (Top & Best Test):** Die mathematisch perfekte Instanz, die beide Kriterien gleichzeitig erfüllt.

### Schritt 2: Telemetrie sichern und optimieren
Da Vast.ai-Instanzen hinter einem NAT/Firewall liegen, ist ein Pull-Verfahren notwendig. Nach Beendigung der Workload darf die Instanz nicht direkt verworfen werden. Sichere die Daten und stoße die Optimierung wie folgt an:

```bash
# 1. Telemetrie über das Vast.ai API-Gateway lokal sichern
vastai copy-from "<INSTANCE_ID>":/workspace/provisioning_telemetry.json ./latest_telemetry.json

# 2. Instanz zerstören
vastai destroy "<INSTANCE_ID>"

# 3. Parameter adaptiv anpassen (überschreibt params.json)
python3 ./optimizer.py --telemetry ./latest_telemetry.json --params ./params.json --alpha 0.25

# 4. Temporäre Datei bereinigen
rm ./latest_telemetry.json
```
---

## Fazit

Durch die konsequente Modularisierung und die zustandslose Kopplung über native Unix-Standardströme bietet diese Architektur maximale Ausfallsicherheit und Wartbarkeit. Die mathematische Scoring-Engine operiert vollständig entkoppelt von der Infrastruktur-Ebene der Vast.ai-API. Durch den geschlossenen Regelkreis optimiert sich das System mit jeder genutzten Instanz selbstständig, wodurch Fehlprognosen bei der Instanzauswahl kontinuierlich minimiert werden.

*(Quellen: POSIX.1-2008 Standard Guidelines, Separation of Concerns Paradigm, Exponential Moving Average Convergence Models in Time-Series Calibration)*
