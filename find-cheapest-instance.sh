#!/usr/bin/env bash
# =============================================================================
# find-cheapest-instance.sh | Version: 2026-06-04.11
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
# Diese Version haertet insbesondere den Buchungsfluss gegen Fehlkonfigurationen
# beim Einsatz von Vast-Templates:
#
# - Template-Hash wird vor der Buchung optional validiert.
# - Es gibt keinen impliziten Disk-Override.
# - Ein explizites DISK_GB wird vorab gegen Sicherheitsgrenzen geprueft.
# - Nach der Buchung wird die reale Instanz optional nachgeprueft.
# - Falls die erzeugte Storage-Groesse kleiner als erwartet ist, kann die
#   Instanz automatisch sofort wieder zerstoert werden.
#
# HINTERGRUND
# -----------
# Vast-Templates liefern Standardwerte fuer die Instanzerstellung, koennen aber
# durch explizit uebergebene Request-Werte ueberschrieben werden.
# Genau deshalb wird --disk nur dann uebergeben, wenn DISK_GB explizit gesetzt
# ist. Dadurch bleibt der Template-Default aktiv, solange kein Override
# gewuenscht ist.
#
# FUNKTIONSUEBERSICHT
# ------------------
# 1. Vast.ai CLI und lokale Dateien pruefen.
# 2. Angebote per Vast.ai laden.
# 3. Angebote mit scoring_engine.py bewerten.
# 4. Ergebnisse filtern und tabellarisch darstellen.
# 5. Optional ein Angebot auswaehlen und buchen.
# 6. Template-Hash vorab validieren.
# 7. Gebuchte Instanz-ID extrahieren und speichern.
# 8. Storage der real erzeugten Instanz nachpruefen.
# 9. Bei zu kleiner Storage-Groesse optional automatisch zerstoeren.
#
# BENOETIGTE DATEIEN
# ------------------
# - ./scoring_engine.py
#   Bewertet die Vast-Angebote und erzeugt tab-separierte Ergebniszeilen.
#
# - ./params.json
#   Eingabeparameter fuer scoring_engine.py.
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
#   Regex/Filter fuer erlaubte GPU-Modelle innerhalb der Scoring-Logik.
#
# - RESULTS
#   Maximale Anzahl an Ergebnissen, die angezeigt werden.
#
# - TEMPLATE_HASH
#   Hash-ID des Vast-Templates, das fuer `create instance` verwendet wird.
#
# - VALIDATE_TEMPLATE_HASH
#   1 = Template-Hash vor Buchung pruefen
#   0 = keine Vorab-Pruefung
#
# - STRICT_TEMPLATE_VALIDATION
#   1 = Abbruch, wenn Template nicht bestaetigt werden kann
#   0 = Warnung, aber Fortsetzung
#
# - DISK_GB
#   Expliziter Disk-Override in GB. Leer = kein `--disk`, Template-Default
#   bleibt aktiv.
#
# - EXPECTED_TEMPLATE_DISK_GB
#   Erwartete Mindestgroesse der Storage, die nach Buchung erreicht sein soll.
#
# - MIN_DISK_GB
#   Sicherheitsgrenze fuer explizit gesetztes DISK_GB.
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
#   1 = vor Buchung interaktive Bestaetigung erzwingen
#   0 = ohne diese Zusatzbestaetigung fortfahren
#
# - STATE_FILE
#   Datei, in die die erzeugte Instanz-ID geschrieben wird.
#
# PROGRAMMABLAUF BEI BUCHUNG
# --------------------------
# Wenn --book verwendet wird, passiert in dieser Reihenfolge:
#
# 1. Template wird optional validiert.
# 2. Nutzer bestaetigt Offer, Modell und Template.
# 3. Instanz wird mit `create instance` erstellt.
# 4. Rueckgabe wird auf neue Contract-/Instanz-ID geparst.
# 5. Instanz-ID wird in STATE_FILE gespeichert.
# 6. Erzeugte Instanz wird auf Storage-Groesse geprueft.
# 7. Bei Untergroesse kann die Instanz automatisch zerstoert werden.
#
# AUSGABEN
# --------
# Das Script erzeugt:
#
# - eine tabellarische Uebersicht der bestbewerteten Vast-Angebote;
# - farbliche Kennzeichnung fuer Top Score und Best Test;
# - Logging fuer Validierung, Buchung und Post-Check;
# - optional einen gespeicherten Zustand in STATE_FILE.
#
# EXIT-VERHALTEN
# --------------
# - Exit 0: Erfolg oder bewusst abgebrochene interaktive Auswahl.
# - Exit 1: Fehler bei Validierung, Buchung oder Sicherheitspruefung.
# - Exit 2: Keine passenden Angebote nach Filterung vorhanden.
#
# BEISPIELE
# ---------
# Nur Angebote anzeigen:
#   bash find-cheapest-instance.sh
#
# Testmodus:
#   bash find-cheapest-instance.sh --test
#
# Dry-Run fuer Buchung:
#   bash find-cheapest-instance.sh --book 1 --dry-run
#
# Angebot Nr. 2 wirklich buchen:
#   bash find-cheapest-instance.sh --book 2
#
# Buchung mit explizitem Disk-Override:
#   DISK_GB=100 bash find-cheapest-instance.sh --book 1
#
# Nur warnen, wenn Template-Suche fehlschlaegt:
#   STRICT_TEMPLATE_VALIDATION=0 bash find-cheapest-instance.sh --book 1
#
# WARTUNGSHINWEIS
# ---------------
# Bei Aenderungen an Vast.ai CLI-Ausgaben oder JSON-Strukturen sollten vor allem
# folgende Bereiche erneut geprueft werden:
# - validate_template_hash
# - extract_new_contract_id
# - postcheck_instance_storage
# - extract_storage_from_json
#
# DOKUMENTATIONSSTANDARD
# ---------------------
# Dieses Script verwendet bewusst einen ausfuehrlichen Datei-Header, damit
# Zweck, Risiken, Eingaben und Sicherheitsmechanismen direkt am Dateianfang
# sichtbar sind.
#
# =============================================================================
