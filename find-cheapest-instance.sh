#!/bin/bash
set -euo pipefail

MODE="prod"
RESULTS=10
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --test) MODE="test" ;;
    --prod) MODE="prod" ;;
  esac
done

RAW="$(vastai search offers 'gpu_ram>24 reliability>0.98 num_gpus=1 rented=False verified=True' 2>/dev/null || true)"

python3 - "$MODE" "$RESULTS" "$DRY_RUN" <<'PY'
import sys, re, subprocess

MODE = sys.argv[1]
RESULTS = int(sys.argv[2])
DRY_RUN = sys.argv[3] == "1"

text = sys.stdin.read().splitlines()

rows = []
in_offers = False

for line in text:
    if line.strip().startswith("#  ID") or line.strip().startswith("  #  ID"):
        in_offers = True
        continue
    if in_offers and line.strip().startswith("#  country"):
        break
    if not in_offers:
        continue
    if not line.strip():
        continue

    parts = line.split()
    if len(parts) < 24:
        continue

    try:
        idx = parts[0]
        offer_id = parts[1]
        cuda = parts[2]
        model = parts[4]
        price = float(parts[10])
        dlp = float(parts[11])
        score = float(parts[13])
        rel = float(parts[17])
        status = parts[20]
        host_id = parts[21]
        ports = parts[22]
    except Exception:
        continue

    rows.append({
        "offer_id": offer_id,
        "model": model,
        "price": price,
        "dlp": dlp,
        "score": score,
        "rel": rel,
        "status": status,
        "host_id": host_id,
        "ports": ports,
    })

if not rows:
    print("Keine Angebote geparst.")
    sys.exit(1)

rows.sort(key=lambda r: (r["price"], -r["rel"], r["score"]))

for i, r in enumerate(rows[:RESULTS], 1):
    print(f"{i:2d} {r['offer_id']} {r['model']:<18} $/hr={r['price']:.4f} rel={r['rel']:.1f} score={r['score']:.1f} status={r['status']}")

pick = rows[0]
print()
print(f"Befehl: vastai create instance {pick['offer_id']}")

if DRY_RUN:
    sys.exit(0)

subprocess.run(["vastai", "create", "instance", pick["offer_id"]], check=False)
PY <<<"$RAW"
