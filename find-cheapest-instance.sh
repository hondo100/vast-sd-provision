


ich möchte auf vastai komfortabel eine gpu mieten, dort automatisch ein template mit sd und forge starten , welches sich dann die von mir gewünschten modelle lädt und mir dann den zugriff über den browser erlaubt. forge soll dabei mit meinen wunsch einstellungen starten. kannst du mir helfen meine vorhandenen scripte zu prüfen.

Du kannst auf Vast.ai sehr komfortabel genau das Setup bauen, was du beschreibst – aber dazu brauche ich deine vorhandenen Skripte bzw. ihre Struktur, am besten als Datei oder als Textblöcke.

Damit ich dir wirklich sinnvoll helfen kann, antworte bitte auf folgende Fragen:

Welche Skripte hast du schon?

Hast du z.B. ein startup.sh, Dockerfile, docker-compose.yml, vastai-template.json, forge-launch.sh oder ähnliches?

Wenn ja, bitte kopiere den Inhalt hier rein (oder teile ihn als Datei, wenn möglich).

Wie startest du Forge aktuell?

Startest du Stable‑Diffusion + Forge per WebUI, als eigenständigen Service, oder als Container‑Setup?

Mit welchen Kommandozeilen‑Parametern wird Forge normalerweise aufgerufen (z.B. Ports, --listen, Model‑Pfade etc.)?

Wie sollen die Modelle geladen werden?

Welche Modelle möchtest du, dass automatisch runtergeladen werden (z.B. modelA.safetensors, modelB.safetensors)?

Gibt es ein Verzeichnis, in das diese sollen (z.B. models/checkpoints/, models/loras/)?

Wie sollen sie heruntergeladen werden (z.B. wget, aria2c, huggingface-cli)?

Wie soll der Browser‑Zugriff funktionieren?

Auf welchen Port soll Forge laufen (z.B. 7860)?

Soll es direkt über den Vast‑ai‑Browser‑Button gehen oder über localhost + Tunnel?

Konkrete Schritte (ohne deine Skripte noch), die du typischerweise brauchst:
Vast.ai Image / Template

Verwende ein Image mit CUDA + Python + git + aria2 + wget (oder erstelle ein eigenes Image mit deinem SD/Forge‑Setup).

In der Vast‑ai‑Template‑Konfiguration stellst du sicher, dass:

Ports öffentlich erreichbar sind (z.B. 7860).

GPU‑RAM und VRAM‑Anforderungen passen.

Start‑Skript auf dem Host (z.B. startup.sh)

Darin:

Repository clonen / Forge installieren.

Modelle automatisch laden (z.B. wget + aria2 + Prüfung ob schon vorhanden).

Forge mit deinen Wunscheinstellungen starten:

bash
python launch.py --listen --port 7860
Das Skript lässt du in den Vast‑ai‑Startup‑Befehl eintragen.

Forge‑Flags / Konfiguration

Du kannst deine Wunscheinstellungen z.B. in eine config.json oder als Flags in startup.sh kodieren:

Standard‑Checkpoint, LoRA, Styles, etc.

Port, --listen, --allow-origins=* (falls nötig), UI‑Theme, etc.

Wenn du mir deine Skripte schickst, kann ich dir:

Sinnvoll kommentiertes startup.sh vorschlagen.

Prüfen, ob dein Forge‑Aufruf korrekt ist.

Vorlage für eine Vast.ai‑Template‑Konfiguration geben (inkl. Ports, Docker‑Befehl etc.).

Sicherstellen, dass die Modelle automatisch geladen und Forge im Browser erreichbar wird.

Bitte antworte als Nächstes mit einem Beispiel deines Skripts (z.B. startup.sh oder Dockerfile) – dann schaue ich deine existierenden Skripte konkret durch und schlage dir Änderungen vor.

Was benutzt du aktuell für das Start‑Skript: ein simples bash‑Script oder ein Docker‑Setup?

hier das readme für das vast template Stable Diffusion WebUI Forge
Create an Instance
What is this template?
This template gives you a complete AI image generation environment with Stable Diffusion WebUI Forge running in a Docker container. Forge is built on top of the popular A1111 WebUI, optimized for faster inference and better resource management.
Think: "The familiar A1111 interface, supercharged with better performance and native support for the latest models like FLUX and SD3!"
Supported Forge Variants
This template supports multiple Forge forks. The default image uses Forge Neo. Select your preferred variant by choosing the appropriate Docker image in the template editor:
VariantDescription
Forge Neo
Community fork with additional features and fixes (default)
Forge
The original by lllyasviel
Forge Reforge
Fork focused on extended model support
Tip: Click "Edit" on the template to change the Docker image and select a different Forge variant.
What can I do with this?
Image Generation
Text-to-image generation with Stable Diffusion 1.5, SDXL, SD3, and FLUX models
Image-to-image transformations for style transfer and editing
Inpainting and outpainting to modify or extend existing images
ControlNet workflows for precise composition control
LoRA and embedding support for custom styles and concepts
Upscaling and enhancement with built-in upscalers
Forge-Specific Features
Optimized memory management for running larger models
Native FLUX support without additional configuration
Faster inference through backend optimizations
SVD video generation support built-in
Automatic memory optimization based on available VRAM
Advanced Workflows
Extension support compatible with most A1111 extensions
Batch processing for generating multiple variations
API integration for automated workflows
Custom scripts and processing pipelines
Who is this for?
This is perfect if you:
Want the familiar A1111 interface with better performance
Need to run FLUX, SD3, or other large models efficiently
Are migrating from A1111 and want compatibility with your existing workflows
Want optimized memory management for limited VRAM
Need a stable, well-tested image generation platform
Are creating AI art, concept art, or design assets
Quick Start Guide
Step 1: Configure Your Setup
Set your preferred configuration via environment variables:
WORKSPACE: Custom workspace directory for your models and outputs
PROVISIONING_SCRIPT: URL to auto-download models on first boot
Template Customization: Want to modify this setup? Click edit, make your changes, and save as your own template. Find it later in "My Templates". Full guide here
Step 2: Launch Instance
Click "Rent" when you've found a suitable GPU instance
Step 3: Wait for Setup
Forge will be ready automatically (initial model downloads may take additional time)
Step 4: Access Your Environment
Easy access: Click the "Open" button for instant access to the Forge interface!
Direct access via mapped ports:
Forge: http://your-instance-ip:7860 (main interface)
HTTPS Option: Want secure connections? Set ENABLE_HTTPS=true in your Vast.ai account settings. You'll need to install the Vast.ai certificate to avoid browser warnings.
Step 5: Start Creating
Load a checkpoint, configure your settings, and start generating!
Key Features
Authentication & Access
MethodUse CaseAccess Point
Web Interface
All Forge operations
Click "Open" or port 7860
SSH Terminal
System administration
SSH access
SSH Tunnel
Bypass authentication
Forward local port to internal port 17860
Finding Your Credentials
Access your authentication details:
# SSH into your instance
echo $OPEN_BUTTON_TOKEN # For web access

Use https:// instead of http:// if you've enabled HTTPS in your account settings.
Port Reference
ServiceExternal PortInternal Port
Instance Portal
1111
11111
Forge
7860
17860
Jupyter
8080
8080
Instance Portal (Application Manager)
Service monitoring with real-time status updates
Resource usage tracking for GPU and memory
Log aggregation for debugging issues
One-click service restarts when needed
Advanced Features
Dynamic Provisioning
Set PROVISIONING_SCRIPT environment variable to auto-download models and extensions from any public URL (GitHub, Gist, etc.)
Multiple Access Methods
MethodBest ForAccess Point
Web Interface
Image generation and configuration
Port 7860
Jupyter Notebook
Custom scripts and model management
/jupyter endpoint
SSH Terminal
File management and debugging
SSH connection
SSH Tunnel
Auth-free local access
Forward to port 17860
Service Management
# Check service status
supervisorctl status

# Restart Forge
supervisorctl restart forge

# View service logs
supervisorctl tail -f forge

Model Organization
Forge organizes models in the following directories:
/workspace/stable-diffusion-webui-forge/models/
├── Stable-diffusion/ # Main checkpoint files
├── Lora/ # LoRA files
├── VAE/ # VAE models
├── ControlNet/ # ControlNet models
├── ESRGAN/ # Upscaling models
└── embeddings/ # Textual embeddings

Environment Variables Reference
VariableDefaultDescription
WORKSPACE
/workspace
Forge workspace directory
FORGE_ARGS
--port 17860
Forge startup arguments
PROVISIONING_SCRIPT
(none)
Auto-setup script URL
ENABLE_HTTPS
false
Enable HTTPS connections (set in Vast.ai account settings)
Recommended GPU Memory
Use CaseMinimum VRAMRecommended VRAM
SD 1.5
4 GB
8 GB
SDXL
8 GB
12 GB
FLUX.1 Dev
12 GB
24 GB
SD3 Medium
12 GB
16 GB
CUDA Forward Compatibility
Images tagged cu130 or above automatically enable CUDA forward compatibility. This allows them to run on datacenter GPUs (e.g., H100, A100, L40S, RTX Pro series) with older driver versions. Consumer GPUs (e.g., RTX 4090, RTX 5090) do not support forward compatibility and require a driver version that natively supports CUDA 13.0 or above.
Licenses
This template ships vendor application(s) under the following license(s):
SD WebUI Forge — AGPL-3.0 (upstream)
PyTorch — BSD-3-Clause (upstream)
See /LICENSES.md in the image for license details and file locations.
Need More Help?
Documentation & Resources
Forge Documentation: Official Repository
A1111 Wiki: Features and Usage
Base Image Features: GitHub Repository
Instance Portal Guide: Vast.ai Instance Portal Documentation
Community & Support
Forge GitHub: Issues & Discussions
Vast.ai Support: Use the messaging icon in the console
Getting Started Resources
Model Downloads: CivitAI and Hugging Face
LoRA Training: Community guides available on CivitAI
Extensions: Compatible with most A1111 extensions
updated 2026-05-07 14:31

Ja — das README ist schon sehr hilfreich, weil es die relevanten Stellschrauben klar benennt: PROVISIONING_SCRIPT für dein Auto‑Setup, FORGE_ARGS für den Start von Forge und die Modellpfade unter /workspace/stable-diffusion-webui-forge/models/....

Damit lässt sich eine saubere Lösung bauen, bei der du auf Vast.ai nur die Instance startest und der Rest automatisch passiert.

Zielbild
Dein sinnvollster Weg ist: eigenes Vast‑Template auf Basis dieses Forge‑Templates, dazu ein öffentlich erreichbares Shell‑Script als PROVISIONING_SCRIPT, und deine gewünschten Startparameter direkt über FORGE_ARGS oder ergänzend per Wrapper‑Script.

Das Template selbst nennt dafür genau die Variablen WORKSPACE, PROVISIONING_SCRIPT und FORGE_ARGS, und Forge läuft dabei standardmäßig auf internem Port 17860, der nach außen auf 7860 gemappt wird.

Was das README bestätigt
Die Modelle sollen in diesem Template nach /workspace/stable-diffusion-webui-forge/models/ organisiert werden, mit Unterordnern wie Stable-diffusion, Lora, VAE, ControlNet, ESRGAN und embeddings.

Für den Browserzugriff ist laut Vast‑Dokumentation und Template‑Beschreibung die Forge‑Weboberfläche über den Open‑Button oder per Tunnel/Port verfügbar; im Portal wird oft direkt ein Tunnel auf localhost:7860 angelegt, intern arbeitet der Dienst aber auf 17860.

Empfohlene Architektur
Ich würde deine Automatisierung in drei Ebenen aufteilen:

PROVISIONING_SCRIPT: legt Verzeichnisse an, lädt Modelle/VAEs/LoRAs herunter, installiert optionale Extensions, schreibt Logdateien.

FORGE_ARGS: enthält deine stabilen Forge‑Startflags wie --listen 0.0.0.0 --port 17860 --api, damit du nicht unnötig an Supervisor oder Container‑Interna herumfassen musst.

Optionales Wrapper‑Script nur dann, wenn du Logik brauchst, die mit reinem FORGE_ARGS nicht sauber abbildbar ist, etwa bedingte Parameter je nach VRAM oder ein Vorab‑Check, ob Dateien vollständig vorhanden sind.

Wichtige Hinweise
Wenn du das empfohlene Template anpasst, solltest du es als eigenes Template speichern; Vast beschreibt genau diesen Weg für angepasste Recommended Templates.

Für Betrieb und Debugging sind supervisorctl status, supervisorctl restart forge und supervisorctl tail -f forge die vorgesehenen Verwaltungsbefehle, was wichtig ist, falls deine Skripte derzeit selbst Prozesse im Hintergrund starten und damit Supervisor umgehen.

Was ich jetzt prüfen kann
Als Nächstes brauche ich von dir am besten genau diese Inhalte als Text:

dein bisheriges PROVISIONING_SCRIPT,

deine gesetzten FORGE_ARGS,

und falls vorhanden dein eigenes Start‑ oder Wrapper‑Script.

Dann prüfe ich dir konkret:

ob die Pfade zum Template passen,

ob du Modelle in die richtigen Ordner lädst,

ob deine Forge‑Parameter zum Port‑Mapping passen,

und ob dein Ansatz mit Supervisor/Vast sauber zusammenspielt.

Schick zuerst am besten einfach dein aktuelles PROVISIONING_SCRIPT hier rein.

nun meine konfiguration des templates. es holt sich von github das steuerungsscript

2 Anhänge
2 Schritte abgeschlossen
Ja — die Richtung ist grundsätzlich richtig, aber in deiner gezeigten Konfiguration sehe ich ein paar Punkte, die ich sofort härten bzw. vereinfachen würde. Der wichtigste Punkt ist: Du nutzt bereits den vorgesehenen Mechanismus mit PROVISIONING_SCRIPT und FORGE_ARGS, genau dafür ist das Template gedacht.

Was gut aussieht
Du hast PROVISIONING_SCRIPT gesetzt und lädst damit dein Steuerungsskript von raw.githubusercontent.com; das passt zum vorgesehenen Vast‑Ansatz für automatisches Provisioning per öffentlicher URL.

Auch FORGE_ARGS ist der richtige Ort für Forge‑Startparameter wie --api und --port 17860, weil das Template diese Variable ausdrücklich für den Forge‑Start vorsieht.

Was ich anpassen würde
Dein FORGE_ARGS enthält auf dem Screenshot ungefähr --xformers --api --cuda-malloc --cuda-stream --port 17860 --sk...; den Port 17860 finde ich konsistent zum Template, aber die abgeschnittene Option am Ende sollten wir genau prüfen, weil schon ein falsches oder veraltetes Flag den Start brechen kann.

Zusätzlich würde ich nicht gleichzeitig unnötig viele Zugangspfade offenhalten, wenn du sie nicht brauchst: In deinem Screenshot sind mehrere Ports veröffentlicht, darunter 1111, 8080, 8384, 72299 und 7860; für einen stabilen Forge‑Betrieb reichen oft deutlich weniger offene Ports.

Konkrete Bewertung deiner Felder
PROVISIONING_SCRIPT: gut, sofern die URL direkt auf das rohe Shell‑Script zeigt und das Script mit Shebang startet, also z.B. #!/usr/bin/env bash, und ohne interaktive Eingaben läuft.

FORGE_ARGS: gut als Konzept, aber ich würde nur bestätigte Flags verwenden und alles Überflüssige rausnehmen, bis der Basisstart stabil ist.

On-start Script = entrypoint.sh: Das ist der Punkt, bei dem ich vorsichtig wäre, denn wenn das Template intern selbst mit Supervisor/Entrypoint arbeitet, kann ein zusätzlicher On‑Start‑Mechanismus unbeabsichtigt in den Standardablauf eingreifen oder ihn doppelt triggern.

PORTAL_CONFIG: Das wirkt grundsätzlich passend zum Vast‑Portal‑Prinzip, aber der Screenshot ist abgeschnitten; wichtig ist, dass dort Forge intern korrekt auf 17860 referenziert wird und extern konsistent erreichbar bleibt.

Meine Empfehlung für die Zielkonfiguration
Für einen robusten ersten Wurf würde ich die Startkonfiguration auf das Nötigste reduzieren:

PROVISIONING_SCRIPT setzen.

FORGE_ARGS="--listen 0.0.0.0 --port 17860 --api" als Basis nehmen; --xformers nur lassen, wenn dein Image und deine GPU damit wirklich sauber laufen.

On-start Script zunächst leer lassen, solange dein Provisioning‑Script alles Nötige vorbereitet.

Nur die Ports offen lassen, die du wirklich brauchst, typischerweise Forge und optional Jupyter/Portal.

Was ich als Nächstes brauche
Jetzt ist der richtige nächste Schritt nicht mehr der Screenshot, sondern der tatsächliche Inhalt deiner GitHub‑Datei hinter PROVISIONING_SCRIPT.

Bitte poste hier als Nächstes:

die komplette Raw‑URL,

den Inhalt des Skripts,

und den vollständigen Wert von FORGE_ARGS.

Dann prüfe ich dir konkret: Syntaxfehler, Pfade, Modell‑Downloads, Startreihenfolge, idempotentes Verhalten beim Neustart und ob Forge mit deinen Wunschparametern sauber hochkommt.

curl -I https://raw.githubusercontent.com/hondo100/public-bootstrap/main/bootstrap.sh gibt output. was nun beim test

Jetzt prüfst du nicht mehr die URL, sondern den Inhalt und Ablauf des Bootstrap-Skripts. Der nächste saubere Test ist: bootstrap.sh lokal herunterladen, ansehen, Syntax prüfen und erst dann ausführen. Vast.ai selbst empfiehlt für PROVISIONING_SCRIPT eine URL zu einem Shell-Skript, also ist dieser lokale Trockenlauf genau der richtige Vorabtest.

1) Bootstrap lokal laden
bash
curl -fsSL https://raw.githubusercontent.com/hondo100/public-bootstrap/main/bootstrap.sh -o /tmp/bootstrap.sh
2) Syntax prüfen
bash
bash -n /tmp/bootstrap.sh
Wenn dabei keine Ausgabe kommt, ist die Shell-Syntax okay.

3) Vorher ansehen
bash
less /tmp/bootstrap.sh
So prüfst du, ob das Skript wirklich nur das tut, was du erwartest, bevor du es ausführst. Das ist sinnvoll, weil curl | bash bequem ist, aber ohne Sichtprüfung unnötig riskant sein kann. 

4) Mit Test-Variablen ausführen
Wenn du danach testen willst, setze die Variablen für dein privates Repo in der Shell:

bash
export GITHUB_PAT="dein_token"
export PRIVATE_REPO_OWNER="hondo100"
export PRIVATE_REPO_NAME="private-repo-vast"
export PRIVATE_REPO_REF="main"
Dann kannst du das Skript ausführen:

bash
bash /tmp/bootstrap.sh
GitHub dokumentiert den Zugriff auf private Repo-Inhalte über den Contents-Endpunkt; der Token gehört dabei in den Header und nicht in eine öffentliche Raw-URL.

5) Was du danach sehen solltest
Wenn alles stimmt, sollte das Bootstrap-Skript:

die privaten Dateien holen,

sie unter /workspace ablegen,

und dann das Provisioning starten.

6) Wenn es scheitert
Dann ist der Fehler jetzt wahrscheinlich einer von drei Punkten:

falscher Repo-Name,

fehlender Token,

falscher ref/Branch.

Mein Vorschlag für den nächsten Schritt
Führe jetzt diese drei Befehle aus:

bash
curl -fsSL https://raw.githubusercontent.com/hondo100/public-bootstrap/main/bootstrap.sh -o /tmp/bootstrap.sh
bash -n /tmp/bootstrap.sh
less /tmp/bootstrap.sh
Wenn du den Inhalt geprüft hast, starten wir den eigentlichen Lauf mit den passenden Variablen.

werner@AZexone:~$ bash <(curl -fsSL https://raw.githubusercontent.com/hondo100/public-bootstrap/main/bootstrap.sh)
[BOOTSTRAP] 20:05:27 START
[BOOTSTRAP] 20:05:27 WORKSPACE=/home/werner/vast-workspace-test
[BOOTSTRAP] 20:05:27 PRIVATE_REPO_OWNER=hondo100
[BOOTSTRAP] 20:05:27 PRIVATE_REPO_NAME=private-repo-vast
[BOOTSTRAP] 20:05:27 PRIVATE_REPO_REF=main
[BOOTSTRAP] 20:05:27 Hole provisioning.sh
[BOOTSTRAP] 20:05:27 Hole model-list.sh
[BOOTSTRAP] 20:05:27 Hole configs/config.json
curl: (22) The requested URL returned error: 404
[BOOTSTRAP][ERROR] 20:05:28 Abbruch in Zeile 26: curl -fsSL -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" "${API_BASE}/${repo_path}?ref=${PRIVATE_REPO_REF}" -o "$dest"

Ja — das ist jetzt sehr wahrscheinlich kein Workspace-Problem mehr, sondern ein GitHub-Zugriffs- oder Pfadproblem beim privaten Repo. GitHub dokumentiert, dass ein 404 bei privaten Ressourcen auch dann erscheinen kann, wenn Authentifizierung oder Berechtigung nicht passt, also nicht nur wenn die Datei wirklich fehlt.

Was die Meldung bedeutet
Dein Bootstrap kommt bis provisioning.sh und model-list.sh, scheitert aber bei configs/config.json. Das heißt:

das private Repo wird grundsätzlich erreicht,

dein Token wird zumindest teilweise akzeptiert,

aber die Datei oder der Pfad configs/config.json ist aus GitHub-Sicht nicht abrufbar.

Häufigste Ursachen
Die Datei liegt nicht exakt unter configs/config.json.

Der Branch/Ref main ist falsch.

Der Token hat nicht die nötigen Rechte für private Inhalte. GitHub weist ausdrücklich darauf hin, dass private Ressourcen bei fehlender Authentifizierung oft als 404 erscheinen.

Das Repo ist leer oder der Commit ist noch nicht auf dem erwarteten Ref.

Was du jetzt prüfen solltest
1) Repo-Struktur prüfen
In deinem privaten Repo muss wirklich das hier liegen:

text
private-repo-vast/
├── provisioning.sh
├── model-list.sh
└── configs/
    ├── config.json
    └── ui-config.json
2) Direkt testen
Teste die Datei einzeln mit der GitHub API:

bash
curl -fsSL \
  -H "Authorization: token $GITHUB_PAT" \
  -H "Accept: application/vnd.github.raw+json" \
  "https://api.github.com/repos/hondo100/private-repo-vast/contents/configs/config.json?ref=main"
Wenn das 404 liefert, stimmt entweder der Pfad, der Ref oder die Berechtigung nicht.

3) Token-Rechte prüfen
Wenn du einen fine-grained Token nutzt, muss er Zugriff auf genau dieses Repo haben und mindestens Leserechte auf Inhalte besitzen. GitHub weist darauf hin, dass fehlende Berechtigungen bei privaten Ressourcen als 404 erscheinen können.

Mein Verdacht
Am wahrscheinlichsten ist im Moment entweder:

die Datei config.json liegt nicht genau dort, wo bootstrap.sh sie erwartet, oder

dein GITHUB_PAT hat nicht die nötigen Repo-Rechte.

Sofortlösung
Wenn du es schnell eingrenzen willst, ändere dein Bootstrap testweise so, dass es config.json und ui-config.json überspringt, und prüfe, ob der Rest sauber durchläuft. Dann weißt du sofort, ob nur diese beiden Dateien das Problem sind.

Wenn du willst, gebe ich dir jetzt die konkrete Debug-Version des Bootstrap-Skripts, die genau sagt, ob config.json fehlt, der Ref falsch ist oder der Token nicht reicht.

ja bitte

Ja — hier ist die minimal korrigierte Version ohne score, mit sauberem JSON-Parsing und ohne die fehleranfällige Here-String-Konstruktion. search offers ist laut Doku genau der richtige Befehl für die Angebotsauswahl; dlperf_usd ist ein dokumentierter Sortierwert, und create instance nutzt anschließend die Offer-ID.

bash
#!/bin/bash
set -euo pipefail

TEMPLATE_HASH="ad0935fab3e1f781fa442c1604ed07e2"
RESULTS=10
DRY_RUN=0
MODE="prod"
CONFIRM=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --test) MODE="test" ;;
    --prod) MODE="prod" ;;
    --yes) CONFIRM=1 ;;
    *)
      echo "Ungueltiger Parameter: $arg"
      exit 1
      ;;
  esac
done

C_RESET=$'\033[0m'
C_RED=$'\033[1;31m'
C_GREEN=$'\033[1;32m'
C_YELLOW=$'\033[1;33m'
C_BLUE=$'\033[1;34m'

info(){ echo -e "${C_BLUE}[INFO]${C_RESET} $*"; }
ok(){ echo -e "${C_GREEN}[OK]${C_RESET} $*"; }
warn(){ echo -e "${C_YELLOW}[WARN]${C_RESET} $*"; }
err(){ echo -e "${C_RED}[ERR]${C_RESET} $*" >&2; }

echo "Pruefe Vast.ai Auth..."
if ! vastai show api-keys >/dev/null 2>&1; then
  err "VAST_KEY_FAIL"
  exit 1
fi

ok "VAST_AUTH_OK"
echo

case "$MODE" in
  prod)
    QUERY="gpu_ram>24 reliability>0.98 num_gpus=1 rented=False verified=True rentable=true direct_port_count>=1"
    ;;
  test)
    QUERY="gpu_ram>16 reliability>0.95 num_gpus=1 rented=False verified=True rentable=true direct_port_count>=1"
    ;;
  *)
    err "Ungueltiger Modus: $MODE"
    exit 1
    ;;
esac

info "Suche Angebote..."
RAW="$(vastai search offers "$QUERY" --raw -o 'dlperf_usd-')"

printf '%s' "$RAW" | python3 - "$MODE" "$RESULTS" "$DRY_RUN" "$CONFIRM" "$TEMPLATE_HASH" <<'PY'
import sys, json, subprocess

MODE = sys.argv[1]
RESULTS = int(sys.argv[2])
DRY_RUN = sys.argv[3] == '1'
CONFIRM = sys.argv[4] == '1'
TEMPLATE_HASH = sys.argv[5]

raw = sys.stdin.read().strip()
if not raw:
    print("Keine Daten empfangen.")
    sys.exit(1)

try:
    data = json.loads(raw)
except Exception as e:
    print(f"JSON-Parse-Fehler: {e}")
    sys.exit(1)

def extract_rows(obj):
    if isinstance(obj, list):
        return obj
    if isinstance(obj, dict):
        for key in ("offers", "results", "data"):
            val = obj.get(key)
            if isinstance(val, list):
                return val
    return []

rows = extract_rows(data)
if not rows:
    print("Keine Angebote gefunden.")
    sys.exit(1)

parsed = []
for r in rows:
    try:
        offer_id = str(r.get("id") or r.get("offer_id") or "")
        if not offer_id:
            continue
        model = str(r.get("machine_name") or r.get("gpu_name") or r.get("model") or "unknown")
        price = float(r.get("dph_total") or r.get("price") or 9999)
        dlp = float(r.get("dlperf") or r.get("dlp") or 0)
        dlp_usd = float(r.get("dlperf_usd") or r.get("dlp_usd") or 0)
        rel = float(r.get("reliability") or r.get("rel") or 0)
        status = str(r.get("status") or "")
        parsed.append({
            "offer_id": offer_id,
            "model": model,
            "price": price,
            "dlp": dlp,
            "dlp_usd": dlp_usd,
            "rel": rel,
            "status": status,
        })
    except Exception:
        continue

if not parsed:
    print("Keine Angebote konnten geparst werden.")
    sys.exit(1)

parsed.sort(key=lambda r: (-r["dlp_usd"], -r["rel"], r["price"]))

print(f"Modus: {MODE}")
print("Nr  Offer_ID    Model               $/hr     DLP    DLP/$   Rel    Status")
print("-" * 74)
for i, r in enumerate(parsed[:RESULTS], 1):
    mark = ">>" if i == 1 else "  "
    print(f"{mark} {i:2d}  {r['offer_id']:<10} {r['model']:<18} {r['price']:>6.4f}  {r['dlp']:>6.1f}  {r['dlp_usd']:>6.2f}  {r['rel']:>5.2f}  {r['status']}")

pick = parsed[0]
print()
print(f"Auswahl: {pick['offer_id']} ({pick['model']})")
print(f"Befehl: vastai create instance {pick['offer_id']} --template_hash {TEMPLATE_HASH}")

if DRY_RUN:
    sys.exit(0)

if not CONFIRM:
    answer = input("Instanz wirklich mieten? [y/N] ").strip().lower()
    if answer not in ("y", "yes"):
        print("Abgebrochen.")
        sys.exit(1)

subprocess.run([
    "vastai", "create", "instance", pick["offer_id"],
    "--template_hash", TEMPLATE_HASH
], check=True)
PY
Danach testen
bash
bash -n find-cheapest-instance.sh
bash find-cheapest-instance.sh --test --dry-run
Warum das helfen sollte
score ist komplett entfernt, damit die Warnung weg ist.

Der Python-Teil liest jetzt wirklich nur noch JSON aus stdin.

Die Sortierung läuft über dlperf_usd und reliability, was mit der Vast-CLI-Doku konsistent ist.

Wenn du willst, passe ich dir im nächsten Schritt noch die Query auf RTX 3090 / 4090 an, damit du direkt auf deinen bevorzugten GPU-Typ filterst.

werner@AZexone:~/github-scripts$ bash find-cheapest-instance.sh --test --dry-run
Pruefe Vast.ai Auth...
VAST_AUTH_OK

Warning: Unrecognized field: score, see list of recognized fields.
Traceback (most recent call last):
File "<stdin>", line 8, in <module>
NameError: name 'null' is not defined
werner@AZexone:~/github-scripts$

Ja — der Fehler kommt von der aktuellen Mischform aus Pipe und Here-Doc. Am stabilsten ist jetzt: JSON in eine Datei schreiben und dann in Python einlesen; damit verschwindet auch der null-Konflikt. In Bash ist das der verlässlichste Weg, wenn ein Programm bereits selbst per stdin arbeitet oder du Parsing sauber trennen willst.

Korrigierte Datei
Ersetze dein Skript vollständig durch dieses:

bash
#!/bin/bash
set -euo pipefail

TEMPLATE_HASH="ad0935fab3e1f781fa442c1604ed07e2"
RESULTS=10
DRY_RUN=0
MODE="prod"
CONFIRM=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --test) MODE="test" ;;
    --prod) MODE="prod" ;;
    --yes) CONFIRM=1 ;;
    *)
      echo "Ungueltiger Parameter: $arg"
      exit 1
      ;;
  esac
done

C_RESET=$'\033[0m'
C_RED=$'\033[1;31m'
C_GREEN=$'\033[1;32m'
C_YELLOW=$'\033[1;33m'
C_BLUE=$'\033[1;34m'

info(){ echo -e "${C_BLUE}[INFO]${C_RESET} $*"; }
ok(){ echo -e "${C_GREEN}[OK]${C_RESET} $*"; }
warn(){ echo -e "${C_YELLOW}[WARN]${C_RESET} $*"; }
err(){ echo -e "${C_RED}[ERR]${C_RESET} $*" >&2; }

echo "Pruefe Vast.ai Auth..."
if ! vastai show api-keys >/dev/null 2>&1; then
  err "VAST_KEY_FAIL"
  exit 1
fi

ok "VAST_AUTH_OK"
echo

case "$MODE" in
  prod)
    QUERY="gpu_ram>24 reliability>0.98 num_gpus=1 rented=False verified=True rentable=true direct_port_count>=1"
    ;;
  test)
    QUERY="gpu_ram>16 reliability>0.95 num_gpus=1 rented=False verified=True rentable=true direct_port_count>=1"
    ;;
  *)
    err "Ungueltiger Modus: $MODE"
    exit 1
    ;;
esac

info "Suche Angebote..."
RAW_FILE="$(mktemp)"
trap 'rm -f "$RAW_FILE"' EXIT

vastai search offers "$QUERY" --raw -o 'dlperf_usd-' > "$RAW_FILE"

python3 - "$MODE" "$RESULTS" "$DRY_RUN" "$CONFIRM" "$TEMPLATE_HASH" "$RAW_FILE" <<'PY'
import sys, json, subprocess

MODE = sys.argv[1]
RESULTS = int(sys.argv[2])
DRY_RUN = sys.argv[3] == '1'
CONFIRM = sys.argv[4] == '1'
TEMPLATE_HASH = sys.argv[5]
RAW_FILE = sys.argv[6]

with open(RAW_FILE, 'r', encoding='utf-8') as f:
    raw = f.read().strip()

if not raw:
    print("Keine Daten empfangen.")
    sys.exit(1)

try:
    data = json.loads(raw)
except Exception as e:
    print(f"JSON-Parse-Fehler: {e}")
    print(raw[:1000])
    sys.exit(1)

def extract_rows(obj):
    if isinstance(obj, list):
        return obj
    if isinstance(obj, dict):
        for key in ("offers", "results", "data"):
            val = obj.get(key)
            if isinstance(val, list):
                return val
    return []

rows = extract_rows(data)
if not rows:
    print("Keine Angebote gefunden.")
    sys.exit(1)

parsed = []
for r in rows:
    try:
        offer_id = str(r.get("id") or r.get("offer_id") or "")
        if not offer_id:
            continue
        model = str(r.get("machine_name") or r.get("gpu_name") or r.get("model") or "unknown")
        price = float(r.get("dph_total") or r.get("price") or 9999)
        dlp = float(r.get("dlperf") or r.get("dlp") or 0)
        dlp_usd = float(r.get("dlperf_usd") or r.get("dlp_usd") or 0)
        rel = float(r.get("reliability") or r.get("rel") or 0)
        status = str(r.get("status") or "")
        parsed.append({
            "offer_id": offer_id,
            "model": model,
            "price": price,
            "dlp": dlp,
            "dlp_usd": dlp_usd,
            "rel": rel,
            "status": status,
        })
    except Exception:
        continue

if not parsed:
    print("Keine Angebote konnten geparst werden.")
    sys.exit(1)

parsed.sort(key=lambda r: (-r["dlp_usd"], -r["rel"], r["price"]))

print(f"Modus: {MODE}")
print("Nr  Offer_ID    Model               $/hr     DLP    DLP/$   Rel    Status")
print("-" * 74)
for i, r in enumerate(parsed[:RESULTS], 1):
    mark = ">>" if i == 1 else "  "
    print(f"{mark} {i:2d}  {r['offer_id']:<10} {r['model']:<18} {r['price']:>6.4f}  {r['dlp']:>6.1f}  {r['dlp_usd']:>6.2f}  {r['rel']:>5.2f}  {r['status']}")

pick = parsed[0]
print()
print(f"Auswahl: {pick['offer_id']} ({pick['model']})")
print(f"Befehl: vastai create instance {pick['offer_id']} --template_hash {TEMPLATE_HASH}")

if DRY_RUN:
    sys.exit(0)

if not CONFIRM:
    answer = input("Instanz wirklich mieten? [y/N] ").strip().lower()
    if answer not in ("y", "yes"):
        print("Abgebrochen.")
        sys.exit(1)

subprocess.run([
    "vastai", "create", "instance", pick["offer_id"],
    "--template_hash", TEMPLATE_HASH
], check=True)
PY
Danach testen
bash
bash -n find-cheapest-instance.sh
bash find-cheapest-instance.sh --test --dry-run
Warum das jetzt stabiler ist
Kein stdin-Konflikt mehr zwischen Bash und Python.

Kein score mehr im Parser.

JSON wird über eine Datei übergeben, nicht über eine riskante Here-Doc/Pipe-Kombination.

Wenn du möchtest, kann ich dir als Nächstes noch die minimalen 2 Zeilen zum Überschreiben deiner vorhandenen Datei geben.

werner@AZexone:~/github-scripts$ bash find-cheapest-instance.sh --test --dry-run
Pruefe Vast.ai Auth...
VAST_AUTH_OK

Warning: Unrecognized field: score, see list of recognized fields.
Traceback (most recent call last):
File "<stdin>", line 8, in <module>
NameError: name 'null' is not defined
werner@AZexone:~/github-scripts$

Der Fehler zeigt, dass deine lokale Datei noch die alte, kaputte Version ist. In der aktuellen Fassung müssen wir den gesamten Parser-Teil ersetzen; besonders wichtig ist, dass score komplett raus ist und der Python-Block kein null mehr aus einem falsch zusammengesetzten Input bekommt.

Was du jetzt tun solltest
Öffne die Datei lokal und ersetze den kompletten Inhalt durch diese bereinigte Version:

bash
#!/bin/bash
set -euo pipefail

TEMPLATE_HASH="ad0935fab3e1f781fa442c1604ed07e2"
RESULTS=10
DRY_RUN=0
MODE="prod"
CONFIRM=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --test) MODE="test" ;;
    --prod) MODE="prod" ;;
    --yes) CONFIRM=1 ;;
    *)
      echo "Ungueltiger Parameter: $arg"
      exit 1
      ;;
  esac
done

C_RESET=$'\033[0m'
C_RED=$'\033[1;31m'
C_GREEN=$'\033[1;32m'
C_YELLOW=$'\033[1;33m'
C_BLUE=$'\033[1;34m'

info(){ echo -e "${C_BLUE}[INFO]${C_RESET} $*"; }
ok(){ echo -e "${C_GREEN}[OK]${C_RESET} $*"; }
warn(){ echo -e "${C_YELLOW}[WARN]${C_RESET} $*"; }
err(){ echo -e "${C_RED}[ERR]${C_RESET} $*" >&2; }

echo "Pruefe Vast.ai Auth..."
if ! vastai show api-keys >/dev/null 2>&1; then
  err "VAST_KEY_FAIL"
  exit 1
fi

ok "VAST_AUTH_OK"
echo

case "$MODE" in
  prod)
    QUERY="gpu_ram>24 reliability>0.98 num_gpus=1 rented=False verified=True rentable=true direct_port_count>=1"
    ;;
  test)
    QUERY="gpu_ram>16 reliability>0.95 num_gpus=1 rented=False verified=True rentable=true direct_port_count>=1"
    ;;
  *)
    err "Ungueltiger Modus: $MODE"
    exit 1
    ;;
esac

info "Suche Angebote..."
RAW_FILE="$(mktemp)"
trap 'rm -f "$RAW_FILE"' EXIT

vastai search offers "$QUERY" --raw -o 'dlperf_usd-' > "$RAW_FILE"

python3 - "$MODE" "$RESULTS" "$DRY_RUN" "$CONFIRM" "$TEMPLATE_HASH" "$RAW_FILE" <<'PY'
import sys, json, subprocess

MODE = sys.argv[1]
RESULTS = int(sys.argv[2])
DRY_RUN = sys.argv[3] == '1'
CONFIRM = sys.argv[4] == '1'
TEMPLATE_HASH = sys.argv[5]
RAW_FILE = sys.argv[6]

with open(RAW_FILE, 'r', encoding='utf-8') as f:
    raw = f.read().strip()

if not raw:
    print("Keine Daten empfangen.")
    sys.exit(1)

try:
    data = json.loads(raw)
except Exception as e:
    print(f"JSON-Parse-Fehler: {e}")
    print(raw[:1000])
    sys.exit(1)

def extract_rows(obj):
    if isinstance(obj, list):
        return obj
    if isinstance(obj, dict):
        for key in ("offers", "results", "data"):
            val = obj.get(key)
            if isinstance(val, list):
                return val
    return []

rows = extract_rows(data)
if not rows:
    print("Keine Angebote gefunden.")
    sys.exit(1)

parsed = []
for r in rows:
    try:
        offer_id = str(r.get("id") or r.get("offer_id") or "")
        if not offer_id:
            continue
        model = str(r.get("machine_name") or r.get("gpu_name") or r.get("model") or "unknown")
        price = float(r.get("dph_total") or r.get("price") or 9999)
        dlp = float(r.get("dlperf") or r.get("dlp") or 0)
        dlp_usd = float(r.get("dlperf_usd") or r.get("dlp_usd") or 0)
        rel = float(r.get("reliability") or r.get("rel") or 0)
        status = str(r.get("status") or "")
        parsed.append({
            "offer_id": offer_id,
            "model": model,
            "price": price,
            "dlp": dlp,
            "dlperf_usd": dlp_usd,
            "rel": rel,
            "status": status,
        })
    except Exception:
        continue

if not parsed:
    print("Keine Angebote konnten geparst werden.")
    sys.exit(1)

parsed.sort(key=lambda r: (-r["dlperf_usd"], -r["rel"], r["price"]))

print(f"Modus: {MODE}")
print("Nr  Offer_ID    Model               $/hr     DLP    DLP/$   Rel    Status")
print("-" * 74)
for i, r in enumerate(parsed[:RESULTS], 1):
    mark = ">>" if i == 1 else "  "
    print(f"{mark} {i:2d}  {r['offer_id']:<10} {r['model']:<18} {r['price']:>6.4f}  {r['dlp']:>6.1f}  {r['dlperf_usd']:>6.2f}  {r['rel']:>5.2f}  {r['status']}")

pick = parsed[0]
print()
print(f"Auswahl: {pick['offer_id']} ({pick['model']})")
print(f"Befehl: vastai create instance {pick['offer_id']} --template_hash {TEMPLATE_HASH}")

if DRY_RUN:\n    sys.exit(0)\n\nif not CONFIRM:\n    answer = input(\"Instanz wirklich mieten? [y/N] \").strip().lower()\n    if answer not in (\"y\", \"yes\"):\n        print(\"Abgebrochen.\")\n        sys.exit(1)\n\nsubprocess.run([\n    \"vastai\", \"create\", \"instance\", pick[\"offer_id\"],\n    \"--template_hash\", TEMPLATE_HASH\n], check=True)\nPY\n```\n\n## Danach ausführen\n\n```bash\nbash -n find-cheapest-instance.sh\nbash find-cheapest-instance.sh --test --dry-run\n```\n\n## Warum es gerade noch scheitert\n\nDie Meldung `Unrecognized field: score` kommt von der Vast-CLI-Suche, also ist noch irgendwo die alte Version aktiv. Der `null`-Fehler entsteht zusätzlich, wenn ein falsch zusammengesetzter JSON-/Shell-Input in Python als Code landet. [1][3][2]\n\nWenn du willst, gebe ich dir als Nächstes die **eine exakte Copy-Paste-Sequenz**, mit der du die Datei sauber überschreibst, ohne manuell zu editieren.
