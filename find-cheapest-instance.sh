#!/bin/bash
set -euo pipefail

SCRIPT_VERSION="2026-05-24.6"

if [[ "${1:-}" == "--version" ]]; then
  echo "$SCRIPT_VERSION"
  exit 0
fi

TEMPLATE_HASH="ad0935fab3e1f781fa442c1604ed07e2"
RESULTS=10
DRY_RUN=0
MODE="prod"
CONFIRM=0
MODEL_GB=20.0
MIN_GPU_RAM=16.0
MIN_RELIABILITY=0.95

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
C_CYAN=$'\033[1;36m'
C_DIM=$'\033[2m'

info(){ echo -e "${C_CYAN}[INFO]${C_RESET} $*"; }
ok(){ echo -e "${C_GREEN}[OK]${C_RESET} $*"; }
warn(){ echo -e "${C_YELLOW}[WARN]${C_RESET} $*"; }
err(){ echo -e "${C_RED}[ERR]${C_RESET} $*" >&2; }

echo "Skript-Version: ${SCRIPT_VERSION}"
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

python3 - "$MODE" "$RESULTS" "$DRY_RUN" "$CONFIRM" "$TEMPLATE_HASH" "$RAW_FILE" "$MODEL_GB" "$MIN_GPU_RAM" "$MIN_RELIABILITY" <<'PY'
import sys, json, subprocess

MODE = sys.argv[1]
RESULTS = int(sys.argv[2])
DRY_RUN = sys.argv[3] == '1'
CONFIRM = sys.argv[4] == '1'
TEMPLATE_HASH = sys.argv[5]
RAW_FILE = sys.argv[6]
MODEL_GB = float(sys.argv[7])
MIN_GPU_RAM = float(sys.argv[8])
MIN_RELIABILITY = float(sys.argv[9])

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
        model = str(r.get("gpu_name") or r.get("machine_name") or r.get("model") or "unknown")
        gpu_ram = float(r.get("gpu_ram") or r.get("gpu_total_ram") or 0)
        price = float(r.get("dph_total") or r.get("price") or 0)
        dlperf = float(r.get("dlperf") or 0)
        dlperf_ratio = float(r.get("dlperf_per_dphtotal") or 0)
        if not dlperf_ratio and price > 0:
            dlperf_ratio = dlperf / price
        reliability = float(r.get("reliability") or r.get("expected_reliability") or 0)
        inet_down_cost = float(r.get("inet_down_cost") or 0)
        transfer_cost = MODEL_GB * inet_down_cost
        effective_cost = price + transfer_cost

        vram_factor = 1.0
        if gpu_ram >= 48:
            vram_factor = 1.4
        elif gpu_ram >= 24:
            vram_factor = 1.2
        elif gpu_ram < MIN_GPU_RAM:
            vram_factor = 0.7

        genai_score = (dlperf * vram_factor) / effective_cost if effective_cost > 0 else 0.0
        parsed.append({
            "offer_id": offer_id,
            "model": model,
            "gpu_ram": gpu_ram,
            "price": price,
            "dlperf": dlperf,
            "dlperf_ratio": dlperf_ratio,
            "reliability": reliability,
            "inet_down_cost": inet_down_cost,
            "transfer_cost": transfer_cost,
            "effective_cost": effective_cost,
            "vram_factor": vram_factor,
            "genai_score": genai_score,
            "status": str(r.get("rentable") if r.get("rentable") is not None else r.get("status") or ""),
        })
    except Exception:
        continue

if not parsed:
    print("Keine Angebote konnten geparst werden.")
    sys.exit(1)

best_score = max(parsed, key=lambda r: r["genai_score"])["genai_score"]
best_cost = min(parsed, key=lambda r: r["effective_cost"])["effective_cost"]

for r in parsed:
    if r["reliability"] < MIN_RELIABILITY or r["gpu_ram"] < MIN_GPU_RAM:
        r["color"] = "red"
    elif r["genai_score"] >= best_score:
        r["color"] = "green"
    elif r["effective_cost"] <= best_cost:
        r["color"] = "blue"
    else:
        r["color"] = "yellow"

parsed.sort(key=lambda r: (-r["genai_score"], -r["reliability"], r["effective_cost"]))

colors = {
    "red": "\033[1;31m",
    "green": "\033[1;32m",
    "yellow": "\033[1;33m",
    "blue": "\033[1;34m",
    "dim": "\033[2m",
    "reset": "\033[0m",
}

print(f"Modus: {MODE}")
print(f"{colors['dim']}Legende:{colors['reset']}")
print(f"  {colors['green']}Grün{colors['reset']}  = bester GenAI-Score")
print(f"  {colors['yellow']}Gelb{colors['reset']}  = gute Balance aus Preis und Leistung")
print(f"  {colors['blue']}Blau{colors['reset']}  = günstigste effektive Kosten")
print(f"  {colors['red']}Rot{colors['reset']}   = unter Mindestanforderungen")
print()

print("Nr  Offer_ID    Model               $/hr   20GB Tx   Eff$/h  DLPerf  Score  VRAM  Rel  Status")
print("-" * 104)
for i, r in enumerate(parsed[:RESULTS], 1):
    c = colors[r["color"]]
    reset = colors["reset"]
    tag = "Vorschlag" if i == 1 else ""
    print(
        f"{c}{i:2d}  {r['offer_id']:<10} {r['model']:<18} "
        f"{r['price']:>6.4f}  {r['transfer_cost']:>7.4f}  {r['effective_cost']:>6.4f}  "
        f"{r['dlperf']:>6.1f}  {r['genai_score']:>6.1f}  {r['gpu_ram']:>4.0f}  {r['reliability']:>4.2f}  {r['status']}{reset}"
    )

print()
print(f"Vorschlag: Nummer 1 ({parsed[0]['offer_id']} / {parsed[0]['model']})")
print()

choice = None
while choice is None:
    raw_choice = input(f"Welche Nummer buchen? [1-{min(RESULTS, len(parsed))}] (Enter = 1): ").strip()
    if raw_choice == "":
        choice = 1
        break
    if raw_choice.isdigit():
        n = int(raw_choice)
        if 1 <= n <= min(RESULTS, len(parsed)):
            choice = n
            break
    print("Ungueltige Eingabe. Bitte nur eine gueltige Nummer eingeben.")

pick = parsed[choice - 1]
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
