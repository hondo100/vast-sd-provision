#!/bin/bash
set -euo pipefail

SESSION_HOURS=2
SESSION_MIN_TEST=15
MODEL_DOWNLOAD_GB=20
MIN_VRAM_GB=24
MIN_RELIABILITY=0.98
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

OUT="$(vastai search offers 'gpu_ram>24 reliability>0.98 num_gpus=1 rented=False verified=True' 2>/dev/null || true)"

python3 - "$MODE" "$SESSION_HOURS" "$SESSION_MIN_TEST" "$MODEL_DOWNLOAD_GB" "$RESULTS" "$DRY_RUN" <<'PY'
import sys, re, subprocess

MODE = sys.argv[1]
SESSION_HOURS = float(sys.argv[2])
SESSION_MIN_TEST = float(sys.argv[3])
DOWNLOAD_GB = float(sys.argv[4])
RESULTS = int(sys.argv[5])
DRY_RUN = sys.argv[6] == "1"

text = sys.stdin.read()
lines = [l.rstrip() for l in text.splitlines() if l.strip()]

rows = []
in_table = False
for line in lines:
    if line.startswith("  #  ID") or line.startswith("#  ID"):
        in_table = True
        continue
    if in_table and line.startswith("  #  country"):
        break
    if not in_table:
        continue
    m = re.match(r"\s*(\d+)\s+(\d+)\s+([0-9.]+)\s+1x\s+(\S+)\s+(.+?)\s+([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)\s+(\d+)\s+([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)\s+(\S+)\s+([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)\s+(\d+)\s+(\S+)\s+(\d+)\s+(\S+)$", line)
    if not m:
        continue
    idx, offer_id, cuda, model, pcie, cpu_ghz, vcpu, ram, vram, disk, price, dlp, dlpd, score, driver, net_up, net_down, rel, max_days, mach_id, status, host_id, ports = m.groups()
    rows.append({
        "offer_id": offer_id,
        "model": model,
        "vram": float(vram),
        "price": float(price),
        "dlp": float(dlp),
        "score": float(score),
        "rel": float(rel),
        "status": status,
        "ports": ports
    })

if not rows:
    print("Keine Angebote geparst.")
    sys.exit(1)

rows.sort(key=lambda x: (x["price"], -x["rel"], x["score"]))
for i, r in enumerate(rows[:RESULTS], 1):
    print(f"{i:2d} {r['offer_id']} {r['model']:<18} VRAM={r['vram']:.1f}GB $/h={r['price']:.4f} rel={r['rel']:.1f} score={r['score']:.1f}")

pick = rows[0]
print()
print(f"Befehl: vastai create instance {pick['offer_id']}")

if DRY_RUN:
    sys.exit(0)

subprocess.run(["vastai", "create", "instance", pick["offer_id"]], check=False)
PY
