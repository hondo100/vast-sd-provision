#!/bin/bash
set -euo pipefail

SESSION_HOURS=2
SESSION_MIN_TEST=15
MODEL_DOWNLOAD_GB=20
RESULTS=10
DRY_RUN=0
MODE="prod"

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --test) MODE="test" ;;
    --prod) MODE="prod" ;;
  esac
done

echo "Pruefe Vast.ai Auth..."
vastai show api-keys >/dev/null
vastai show user >/dev/null
echo "VAST_AUTH_OK"
echo

RAW="$(vastai search offers 'gpu_ram > 24 reliability > 0.98 num_gpus == 1 rented == False verified == True' --raw)"

python3 - "$MODE" "$SESSION_HOURS" "$SESSION_MIN_TEST" "$MODEL_DOWNLOAD_GB" "$RESULTS" "$DRY_RUN" <<'PY'
import sys, json, subprocess

MODE = sys.argv[1]
SESSION_HOURS = float(sys.argv[2])
SESSION_MIN_TEST = float(sys.argv[3])
DOWNLOAD_GB = float(sys.argv[4])
RESULTS = int(sys.argv[5])
DRY_RUN = sys.argv[6] == "1"

raw = sys.stdin.read().strip()
if not raw:
    print("Keine Daten empfangen.")
    sys.exit(1)

data = json.loads(raw)
rows = data if isinstance(data, list) else data.get("offers", data.get("results", []))

if not rows:
    print("Keine Angebote gefunden.")
    sys.exit(1)

def get(r, *keys, default=None):
    for k in keys:
        if k in r:
            return r[k]
    return default

parsed = []
for r in rows:
    try:
        parsed.append({
            "offer_id": str(get(r, "id", "offer_id")),
            "model": str(get(r, "machine_name", "model", "gpu_name", default="unknown")),
            "price": float(get(r, "dph_total", "price", default=9999)),
            "dlp": float(get(r, "dlperf", "dlp", default=0)),
            "dlp_usd": float(get(r, "dlperf_usd", "dlp_usd", default=0)),
            "score": float(get(r, "score", default=0)),
            "rel": float(get(r, "reliability", "rel", default=0)),
            "status": str(get(r, "status", default="")),
            "host_id": str(get(r, "host_id", default="")),
            "ports": str(get(r, "direct_port_count", "ports", default="")),
        })
    except Exception:
        continue

if not parsed:
    print("Keine Angebote konnten geparst werden.")
    sys.exit(1)

parsed.sort(key=lambda r: (r["price"], -r["rel"], r["score"]))

print("Nr  Offer_ID    Model               $/hr     DLP    DLP/$   Score   Rel    Status")
print("-" * 80)
for i, r in enumerate(parsed[:RESULTS], 1):
    print(f"{i:2d}  {r['offer_id']:<10} {r['model']:<18} {r['price']:>6.4f}  {r['dlp']:>6.1f}  {r['dlp_usd']:>6.2f}  {r['score']:>6.1f}  {r['rel']:>5.2f}  {r['status']}")

pick = parsed[0]
print()
print(f"Auswahl: {pick['offer_id']} ({pick['model']})")
print(f"Befehl: vastai create instance {pick['offer_id']}")

if DRY_RUN:
    sys.exit(0)

subprocess.run(["vastai", "create", "instance", pick["offer_id"]], check=True)
PY <<<"$RAW"
