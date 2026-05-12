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
if ! vastai show api-keys >/tmp/vast_keys.out 2>/tmp/vast_keys.err; then
  echo "VAST_KEY_FAIL"
  cat /tmp/vast_keys.err
  exit 1
fi

if ! vastai show user >/tmp/vast_user.out 2>/tmp/vast_user.err; then
  echo "VAST_USER_FAIL"
  cat /tmp/vast_user.err
  exit 1
fi

echo "VAST_AUTH_OK"
echo

RAW="$(vastai search offers 'gpu_ram>24 reliability>0.98 num_gpus=1 rented=False verified=True' 2>/dev/null || true)"

python3 - "$MODE" "$SESSION_HOURS" "$SESSION_MIN_TEST" "$MODEL_DOWNLOAD_GB" "$RESULTS" "$DRY_RUN" <<'PY'
import sys, subprocess

MODE = sys.argv[1]
SESSION_HOURS = float(sys.argv[2])
SESSION_MIN_TEST = float(sys.argv[3])
DOWNLOAD_GB = float(sys.argv[4])
RESULTS = int(sys.argv[5])
DRY_RUN = sys.argv[6] == "1"

text = sys.stdin.read().splitlines()
rows = []
in_offers = False

for line in text:
    s = line.strip()
    if s.startswith("#  ID") or s.startswith("ID") or s.startswith("  #  ID"):
        in_offers = True
        continue
    if in_offers and s.startswith("#  country"):
        break
    if not in_offers or not s:
        continue

    parts = s.split()
    if len(parts) < 23:
        continue

    try:
        offer_id = parts[1]
        model = parts[4]
        price = float(parts[10])
        dlp = float(parts[11])
        dlp_usd = float(parts[12])
        score = float(parts[13])
        rel = float(parts[17])
        status = parts[20]
        host_id = parts[21]
        ports = parts[22]
        rows.append({
            "offer_id": offer_id,
            "model": model,
            "price": price,
            "dlp": dlp,
            "dlp_usd": dlp_usd,
            "score": score,
            "rel": rel,
            "status": status,
            "host_id": host_id,
            "ports": ports,
        })
    except Exception:
        continue

if not rows:
    print("Keine Angebote geparst.")
    sys.exit(1)

rows.sort(key=lambda r: (r["price"], -r["rel"], r["score"]))

print("Nr  Offer_ID    Model               $/hr     DLP    DLP/$   Score   Rel    Status")
print("-" * 80)
for i, r in enumerate(rows[:RESULTS], 1):
    print(f"{i:2d}  {r['offer_id']:<10} {r['model']:<18} {r['price']:>6.4f}  {r['dlp']:>6.1f}  {r['dlp_usd']:>6.2f}  {r['score']:>6.1f}  {r['rel']:>5.1f}  {r['status']}")

pick = rows[0]
print()
print(f"Auswahl: {pick['offer_id']} ({pick['model']})")
print(f"Befehl: vastai create instance {pick['offer_id']}")

if DRY_RUN:
    sys.exit(0)

subprocess.run(["vastai", "create", "instance", pick["offer_id"]], check=False)
PY <<<"$RAW"
