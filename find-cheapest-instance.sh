#!/bin/bash
sed -i 's/\r//' "$0"

VASTAI_API_KEY="${VASTAI_API_KEY:-}"
SESSION_HOURS=2
SESSION_MIN_TEST=15
MODEL_DOWNLOAD_GB=20
MIN_VRAM_MB=24000
MIN_RELIABILITY=0.98
RESULTS=10
FORGE_TEMPLATE_HASH="617186aaa06dfb7676d626f5655b23c6"
FORGE_DISK=50
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

RESPONSE=$(curl -sL --request POST \
    --url "https://console.vast.ai/api/v0/bundles/" \
    --header "Authorization: Bearer ${VASTAI_API_KEY}" \
    --header "Content-Type: application/json" \
    --data "{\"limit\":200,\"type\":\"on-demand\",\"verified\":{\"eq\":true},\"rentable\":{\"eq\":true},\"rented\":{\"eq\":false},\"gpu_ram\":{\"gte\":${MIN_VRAM_MB}},\"reliability\":{\"gte\":${MIN_RELIABILITY}},\"num_gpus\":{\"eq\":1},\"order\":[[\"dph_total\",\"asc\"]]}")

BEST_ID=$(python3 << PYEOF
import json, sys

RESPONSE = """${RESPONSE}"""
SESSION_H = ${SESSION_HOURS}
SESSION_MIN_TEST = ${SESSION_MIN_TEST}
DOWNLOAD_GB = ${MODEL_DOWNLOAD_GB}
TOP_N = ${RESULTS}

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

def short_gpu(name, width=14):
    return name if len(name) <= width else name[:width-1] + "…"

def get_perf(name, dlperf):
    for k, v in SDXL_IMG_PER_H.items():
        if k.lower() in name.lower():
            return v, "benchmark"
    return (round(dlperf * 10), "geschaetzt") if dlperf and dlperf > 0 else (200, "unbekannt")

def estimate_download_sec(size_gb, speed_mbps, files=60):
    if speed_mbps <= 0:
        return None
    base = (size_gb * 1024) / speed_mbps
    return base * 1.4 + files * 0.08 + 8

data = json.loads(RESPONSE)
offers = data.get("offers", [])
results = []

for o in offers:
    raw = o.get("gpu_name", "?")
    gpu = short_gpu(raw)
    vram_gb = round(o.get("gpu_ram", 0) / 1024, 1)
    dph = o.get("dph_total", 0)

    dlspd = o.get("inet_down", 0) or 0
    dlsec = estimate_download_sec(DOWNLOAD_GB, float(dlspd)) if dlspd else None
    dl_cost = o.get("inet_down_cost", 0) * DOWNLOAD_GB

    prod_session_h = SESSION_H
    test_session_h = SESSION_MIN_TEST / 60.0
    total_prod = dph * prod_session_h + dl_cost
    total_test = dph * test_session_h + dl_cost

    img_h, src = get_perf(raw, o.get("dlperf", 0))
    prod_score = (total_prod / (img_h * SESSION_H) * 100) if img_h > 0 else 999
    test_score = total_test + (dlsec / 60.0 if dlsec else 999)
    score = prod_score if "${MODE}" == "prod" else test_score

    if dlsec is None:
        dltxt = "?"
    elif dlsec < 60:
        dltxt = f"{int(round(dlsec))}s"
    else:
        dltxt = f"{round(dlsec/60,1)}m"

    results.append({
        "id": o.get("id", "?"),
        "gpu": gpu,
        "vram": vram_gb,
        "dph": dph,
        "total": total_prod if "${MODE}" == "prod" else total_test,
        "img_h": img_h,
        "score": score,
        "dlspd": dlspd,
        "dltxt": dltxt,
        "rel": o.get("reliability", 0),
        "loc": o.get("geolocation", "?"),
        "src": src,
        "dlsec": dlsec,
    })

results.sort(key=lambda x: x["score"])
results = results[:TOP_N]

fmt_header = "{:<3} {:<14} {:>6} {:>6} {:>7} {:>5} {:>8} {:>10} {:>6} {:>5} {:<16} {}".format(
    "Nr", "GPU", "VRAM", "$/h", "Gesamt", "img/h", "Score", "DL", "Zeit", "Rel", "Ort", "ID"
)
print(fmt_header)
print("-" * 132)

for i, r in enumerate(results, 1):
    line = "{:<3} {:<14} {:>6} {:>6.3f} {:>7.4f} {:>5} {:>8.4f} {:>10} {:>6} {:>5.3f} {:<16} {}".format(
        i, r["gpu"], f'{r["vram"]:.1f}G', r["dph"], r["total"], r["img_h"], r["score"],
        f'{int(r["dlspd"])} MB/s' if r["dlspd"] else "?", r["dltxt"], r["rel"], r["loc"], r["id"]
    )
    if i == 1:
        print(f"{GREEN_BG}{line}{RESET}" if "${MODE}" == "prod" else f"{YELLOW_BG}{line}{RESET}")
    else:
        print(line)

print("")
best = results[0]["id"] if results else ""
print(best)
PYEOF
)

if [ -z "$BEST_ID" ]; then
    echo "Keine passenden Angebote gefunden."
    exit 1
fi

echo ""
echo "Top 10 berechnet."
echo "Beste Instanz-ID: $BEST_ID"
echo "Befehl:"
echo "  vastai create instance $BEST_ID --template_hash $FORGE_TEMPLATE_HASH --disk $FORGE_DISK"

if [ "$DRY_RUN" -eq 1 ]; then
    echo ""
    echo "Dry-run aktiv: es wird nichts gestartet."
    exit 0
fi

read -p "Jetzt starten? [j/N] " CONFIRM
if [[ "$CONFIRM" =~ ^[jJ]$ ]]; then
    vastai create instance "$BEST_ID" --template_hash "$FORGE_TEMPLATE_HASH" --disk "$FORGE_DISK"
else
    echo "Abgebrochen."
fi
