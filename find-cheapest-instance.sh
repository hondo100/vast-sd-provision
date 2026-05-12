#!/bin/bash
sed -i 's/\r//' "$0"

VASTAI_API_KEY="${VASTAI_API_KEY:-}"
MIN_VRAM_MB=24000
MIN_RELIABILITY=0.98
RESULTS=10
FORGE_TEMPLATE_HASH="617186aaa06dfb7676d626f5655b23c6"
FORGE_DISK=50
SESSION_HOURS_PROD=2
SESSION_MIN_TEST=15
MODEL_DOWNLOAD_GB=20
DRY_RUN=0
MODE="prod"

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --test) MODE="test" ;;
        --prod) MODE="prod" ;;
    esac
done

if [ -z "$VASTAI_API_KEY" ]; then
    if command -v pass >/dev/null 2>&1; then
        VASTAI_API_KEY="$(pass show vastai/api_key 2>/dev/null | head -n1)"
    fi
fi

if [ -z "$VASTAI_API_KEY" ]; then
    echo "VASTAI_API_KEY nicht gesetzt."
    exit 1
fi

echo ""
echo "Suche verfuegbare GPU-Instanzen bei Vast.ai..."
echo "Mindest-VRAM: ${MIN_VRAM_MB} MB | Reliability: >= ${MIN_RELIABILITY}"
echo ""

curl -sL --request POST \
    --url "https://console.vast.ai/api/v0/bundles/" \
    --header "Authorization: Bearer ${VASTAI_API_KEY}" \
    --header "Content-Type: application/json" \
    --data "{\"limit\":200,\"type\":\"on-demand\",\"verified\":{\"eq\":true},\"rentable\":{\"eq\":true},\"rented\":{\"eq\":false},\"gpu_ram\":{\"gte\":${MIN_VRAM_MB}},\"reliability\":{\"gte\":${MIN_RELIABILITY}},\"num_gpus\":{\"eq\":1},\"order\":[[\"dph_total\",\"asc\"]]}" | \
MODE="$MODE" SESSION_HOURS_PROD="$SESSION_HOURS_PROD" SESSION_MIN_TEST="$SESSION_MIN_TEST" MODEL_DOWNLOAD_GB="$MODEL_DOWNLOAD_GB" RESULTS="$RESULTS" FORGE_TEMPLATE_HASH="$FORGE_TEMPLATE_HASH" FORGE_DISK="$FORGE_DISK" DRY_RUN="$DRY_RUN" python3 - <<'PYEOF'
import json, os, sys, subprocess

MODE = os.environ.get("MODE", "prod")
SESSION_HOURS_PROD = float(os.environ.get("SESSION_HOURS_PROD", "2"))
SESSION_MIN_TEST = float(os.environ.get("SESSION_MIN_TEST", "15"))
DOWNLOAD_GB = float(os.environ.get("MODEL_DOWNLOAD_GB", "20"))
RESULTS = int(os.environ.get("RESULTS", "10"))
FORGE_TEMPLATE_HASH = os.environ.get("FORGE_TEMPLATE_HASH", "")
FORGE_DISK = os.environ.get("FORGE_DISK", "50")
DRY_RUN = os.environ.get("DRY_RUN", "0") == "1"

SDXL_IMG_PER_H = {
    "RTX 5090":1200, "RTX 5080":850, "RTX 5070 Ti":700, "RTX 5070":580, "RTX 5060 Ti":420,
    "RTX 4090":900, "RTX 4080 Super":680, "RTX 4080S":680, "RTX 4080":640, "RTX 4070 Ti Super":520,
    "RTX 4070S Ti":520, "RTX 4070 Ti":490, "RTX 4070 Super":420, "RTX 4070S":420, "RTX 4070":370,
    "RTX 4060 Ti":290, "RTX 4060":240,
    "RTX 3090 Ti":490, "RTX 3090":450, "RTX 3080 Ti":400, "RTX 3080":350, "RTX 3070 Ti":280, "RTX 3070":260,
    "RTX 2080 Ti":220, "RTX 2080 Super":190, "RTX 2080":180, "RTX 2070 Super":160,
    "Titan RTX":300, "Titan V":250,
    "H100 SXM":1400, "H100 PCIe":1200, "H100":1200, "A100 SXM4":920, "A100 SXM":920, "A100 PCIe":880, "A100":880,
    "L40S":780, "L40":700, "A40":600, "RTX A6000":520, "A6000":520, "RTX A5000":430, "A30":420, "L4":360,
    "RTX A4500":360, "A10":380, "A10G":380, "RTX A4000":300, "RTX A3000":240, "Tesla V100 SXM2":320,
    "Tesla V100":280, "Tesla T4":180
}

GREEN_BG = "\033[42m"
YELLOW_BG = "\033[43m"
RESET = "\033[0m"

def short(s, n):
    s = str(s)
    return s if len(s) <= n else s[:n-1] + "…"

def perf(name, dlperf):
    for k, v in SDXL_IMG_PER_H.items():
        if k.lower() in name.lower():
            return v, "bench"
    return (round(dlperf * 10), "est") if dlperf and dlperf > 0 else (200, "unk")

def download_sec(gb, speed):
    if speed <= 0:
        return None
    base = (gb * 1024) / speed
    return base * 1.4 + 8

text = sys.stdin.read().strip()
try:
    data = json.loads(text) if text else {}
except Exception:
    data = {}
offers = data.get("offers", []) or []
rows = []

for o in offers:
    raw = o.get("gpu_name", "?")
    gpu = short(raw, 14)
    vram = round(o.get("gpu_ram", 0) / 1024, 1)
    dph = float(o.get("dph_total", 0) or 0)
    dlspd = float(o.get("inet_down", 0) or 0)
    dsec = download_sec(DOWNLOAD_GB, dlspd)
    img_h, _ = perf(raw, o.get("dlperf", 0))
    session_h = SESSION_HOURS_PROD if MODE == "prod" else (SESSION_MIN_TEST / 60.0)
    total = dph * session_h + float(o.get("inet_down_cost", 0) or 0) * DOWNLOAD_GB
    score = (total / (img_h * SESSION_HOURS_PROD) * 100) if MODE == "prod" else total

    if dsec is None:
        dltxt = "?"
    elif dsec < 60:
        dltxt = f"{int(round(dsec))}s"
    else:
        dltxt = f"{round(dsec/60,1)}m"

    rows.append({
        "id": str(o.get("id", "?")),
        "gpu": gpu,
        "vram": vram,
        "dph": dph,
        "total": total,
        "img_h": img_h,
        "score": score,
        "dlspd": dlspd,
        "dltxt": dltxt,
        "rel": float(o.get("reliability", 0) or 0),
        "loc": short(o.get("geolocation", "?"), 16),
    })

rows.sort(key=lambda x: x["score"])
rows = rows[:RESULTS]

header = "{:<3} {:<14} {:>6} {:>6} {:>7} {:>5} {:>8} {:>10} {:>6} {:>5} {:<16} {}".format(
    "Nr", "GPU", "VRAM", "$/h", "Gesamt", "img/h", "Score", "DL", "Zeit", "Rel", "Ort", "ID"
)
print(header)
print("-" * len(header))

for i, r in enumerate(rows, 1):
    line = "{:<3} {:<14} {:>6} {:>6.3f} {:>7.4f} {:>5} {:>8.4f} {:>10} {:>6} {:>5.3f} {:<16} {}".format(
        i, r["gpu"], f'{r["vram"]:.1f}G', r["dph"], r["total"], r["img_h"], r["score"],
        f'{int(r["dlspd"])} MB/s' if r["dlspd"] else "?", r["dltxt"], r["rel"], r["loc"], r["id"]
    )
    if i == 1:
        bg = GREEN_BG if MODE == "prod" else YELLOW_BG
        print(f"{bg}{line}{RESET}")
    else:
        print(line)

print("")
try:
    choice = input("Gewuenschte Nummer [1]: ").strip()
except EOFError:
    choice = ""
choice = choice or "1"

picked = None
for idx, r in enumerate(rows, 1):
    if str(idx) == choice:
        picked = r
        break

if picked is None:
    print("Ungueltige Nummer. Abgebrochen.")
    sys.exit(1)

print("")
print(f"Ausgewaehlt: Nr {choice} - {picked['gpu']} - {picked['loc']} - ID {picked['id']}")
print("Befehl:")
print(f"  vastai create instance {picked['id']} --template_hash {FORGE_TEMPLATE_HASH} --disk {FORGE_DISK}")

try:
    mode_in = input(f"Mode [p=Prod, t=Test] (Default: {MODE}): ").strip().lower()
except EOFError:
    mode_in = ""
mode_in = mode_in or MODE

if mode_in == "t":
    print("Kurztest gewaehlt: 10-15 Minuten, Downloadkosten dominieren.")
else:
    print("Produktionsmodus gewaehlt: Bewertung nach Kosten pro Bild.")

if DRY_RUN:
    print("")
    print("Dry-run aktiv: es wird nichts gestartet.")
    sys.exit(0)

try:
    confirm = input("Jetzt starten? [j/N] ").strip().lower()
except EOFError:
    confirm = ""
if confirm == "j":
    subprocess.run([
        "vastai", "create", "instance", picked["id"],
        "--template_hash", FORGE_TEMPLATE_HASH,
        "--disk", str(FORGE_DISK)
    ], check=False)
else:
    print("Abgebrochen.")
PYEOF
