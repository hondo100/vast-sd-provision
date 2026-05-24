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
