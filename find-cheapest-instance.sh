#!/bin/bash
set -euo pipefail

RAW="$(vastai search offers 'gpu_ram>24 reliability>0.98 num_gpus=1 rented=False verified=True' 2>/dev/null || true)"

python3 - "$RAW" <<'PY'
import sys, re, subprocess

text = sys.argv[1].splitlines()
rows = []
in_offers = False

for line in text:
    s = line.strip()
    if s.startswith("#  ID") or s.startswith("# ID"):
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
        score = float(parts[13])
        rel = float(parts[17])
        status = parts[20]
    except Exception:
        continue

    rows.append({"offer_id": offer_id, "model": model, "price": price, "score": score, "rel": rel, "status": status})

if not rows:
    print("Keine Angebote geparst.")
    sys.exit(1)

rows.sort(key=lambda r: (r["price"], -r["rel"], r["score"]))
for i, r in enumerate(rows[:10], 1):
    print(f"{i:2d} {r['offer_id']} {r['model']:<18} $/hr={r['price']:.4f} rel={r['rel']:.1f} score={r['score']:.1f} status={r['status']}")

print()
print(f"Befehl: vastai create instance {rows[0]['offer_id']}")
PY
