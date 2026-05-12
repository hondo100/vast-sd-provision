#!/bin/bash
sed -i 's/\r//' "$0"

# ==============================================================================
# VAST.AI ANGEBOTS-VERGLEICH - Bestes Preis/Leistungs-Angebot finden
# Berechnet: GPU-Kosten (2h) + Download-Kosten (~18 GB), normalisiert nach SDXL
# ==============================================================================

VASTAI_API_KEY="${VASTAI_API_KEY:-}"
SESSION_HOURS=2
MODEL_DOWNLOAD_GB=18
MIN_VRAM_MB=16000
MIN_RELIABILITY=0.98
RESULTS=20
FORGE_TEMPLATE_HASH="617186aaa06dfb7676d626f5655b23c6"
FORGE_DISK=50

if [ -z "$VASTAI_API_KEY" ]; then
    echo "VASTAI_API_KEY nicht gesetzt."
    echo "Aufruf: VASTAI_API_KEY=dein_key $(basename $0)"
    echo "Oder:   export VASTAI_API_KEY=dein_key"
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

VASTAI_API_KEY  = "${VASTAI_API_KEY}"
SESSION_H       = ${SESSION_HOURS}
DOWNLOAD_GB     = ${MODEL_DOWNLOAD_GB}
TOP_N           = ${RESULTS}
RESPONSE        = """${RESPONSE}"""

SDXL_IMG_PER_H = {
    # RTX 50xx
    "RTX 5090":              1200,
    "RTX 5080":               850,
    "RTX 5070 Ti":            700,
    "RTX 5070":               580,
    "RTX 5060 Ti":            420,
    # RTX 40xx
    "RTX 4090":               900,
    "RTX 4080 Super":         680,
    "RTX 4080S":              680,
    "RTX 4080":               640,
    "RTX 4070 Ti Super":      520,
    "RTX 4070S Ti":           520,
    "RTX 4070 Ti":            490,
    "RTX 4070 Super":         420,
    "RTX 4070S":              420,
    "RTX 4070":               370,
    "RTX 4060 Ti":            290,
    "RTX 4060":               240,
    # RTX 30xx
    "RTX 3090 Ti":            490,
    "RTX 3090":               450,
    "RTX 3080 Ti":            400,
    "RTX 3080":               350,
    "RTX 3070 Ti":            280,
    "RTX 3070":               260,
    # RTX 20xx
    "RTX 2080 Ti":            220,
    "RTX 2080 Super":         190,
    "RTX 2080":               180,
    "RTX 2070 Super":         160,
    # Titan
    "Titan RTX":              300,
    "Titan V":                250,
    # Datacenter
    "H100 SXM":              1400,
    "H100 PCIe":             1200,
    "H100":                  1200,
    "A100 SXM4":              920,
    "A100 SXM":               920,
    "A100 PCIe":              880,
    "A100":                   880,
    "L40S":                   780,
    "L40":                    700,
    "A40":                    600,
    "RTX A6000":              520,
    "A6000":                  520,
    "RTX A5000":              430,
    "A30":                    420,
    "L4":                     360,
    "RTX A4500":              360,
    "A10":                    380,
    "A10G":                   380,
    "RTX A4000":              300,
    "RTX A3000":              240,
    "Tesla V100 SXM2":        320,
    "Tesla V100":             280,
    "Tesla T4":               180,
}

def get_sdxl_perf(gpu_name, dlperf):
    for key, val in SDXL_IMG_PER_H.items():
        if key.lower() in gpu_name.lower():
            return val, "benchmark"
    if dlperf and dlperf > 0:
        return round(dlperf * 10), "geschaetzt"
    return 200, "unbekannt"

try:
    data = json.loads(RESPONSE)
except Exception as e:
    print(f"Ungueltige API-Antwort: {e}", file=sys.stderr)
    sys.exit(1)

offers = data.get("offers", [])
if not offers:
    print(f"Keine Angebote gefunden. API: {str(data)[:300]}", file=sys.stderr)
    sys.exit(1)

print(f"Gefunden: {len(offers)} Angebote - berechne Gesamtkosten + SDXL-Leistung...\n", file=sys.stderr)

results = []
for o in offers:
    gpu_name       = o.get("gpu_name", "?")
    vram_gb        = round(o.get("gpu_ram", 0) / 1024, 1)
    dph            = o.get("dph_total", 0)
    inet_down_cost = o.get("inet_down_cost", 0)
    inet_down_mbs  = o.get("inet_down", 0) or 0
    reliability    = o.get("reliability", 0)
    geolocation    = o.get("geolocation", "?")
    offer_id       = o.get("id", "?")
    dlperf         = o.get("dlperf", 0)

    gpu_cost      = dph * SESSION_H
    download_cost = inet_down_cost * DOWNLOAD_GB
    total_cost    = gpu_cost + download_cost

    try:
        spd = float(inet_down_mbs)
        download_min = round((DOWNLOAD_GB * 1024) / spd / 60, 1) if spd > 0 else None
    except:
        download_min = None

    sdxl_img_h, perf_src  = get_sdxl_perf(gpu_name, dlperf)
    imgs_per_session       = sdxl_img_h * SESSION_H
    cost_per_100_imgs      = (total_cost / imgs_per_session * 100) if imgs_per_session > 0 else 999

    results.append({
        "id":               offer_id,
        "gpu":              gpu_name,
        "vram_gb":          vram_gb,
        "dph":              dph,
        "gpu_cost":         gpu_cost,
        "dl_cost":          download_cost,
        "total":            total_cost,
        "inet_down_mbs":    inet_down_mbs,
        "dl_min":           download_min,
        "reliability":      reliability,
        "location":         geolocation,
        "sdxl_img_h":       sdxl_img_h,
        "perf_src":         perf_src,
        "cost_per_100":     cost_per_100_imgs,
        "imgs_per_session": imgs_per_session,
    })

results.sort(key=lambda x: x["cost_per_100"])

# Tabelle auf stderr (sichtbar im Terminal)
header = f"{'Rang':<5} {'GPU':<22} {'VRAM':>6} {'$/h':>6} {'Gesamt':>7} {'img/h':>6} {'$/100img':>9} {'DL-Speed':>10} {'DL-Zeit':>8} {'Reliab.':>8} {'Quelle':<12} {'Ort':<18} {'ID'}"
print(header, file=sys.stderr)
print("-" * 155, file=sys.stderr)
for i, r in enumerate(results[:TOP_N], 1):
    dl_min_str = f"{r['dl_min']}min" if r['dl_min'] is not None else "?"
    inet_str   = f"{r['inet_down_mbs']:.0f} MB/s" if r['inet_down_mbs'] > 0 else "?"
    print(
        f"{i:<5} {r['gpu']:<22} {r['vram_gb']:>5.1f}G "
        f"\${r['dph']:>5.3f} \${r['total']:>6.4f} "
        f"{r['sdxl_img_h']:>6} \${r['cost_per_100']:>8.4f} "
        f"{inet_str:>10} {dl_min_str:>8} "
        f"{r['reliability']:>7.3f} {r['perf_src']:<12} "
        f"{r['location']:<18} {r['id']}",
        file=sys.stderr
    )

best = results[0]
print(f"""
Bestes Preis-Leistungs-Angebot: {best['gpu']} ({best['vram_gb']}G VRAM)
  SDXL Leistung:           {best['sdxl_img_h']} Bilder/Stunde ({best['perf_src']})
  Bilder in {SESSION_H}h Session:   ~{best['imgs_per_session']} Bilder
  GPU-Kosten ({SESSION_H}h):         \${best['gpu_cost']:.4f}
  Download-Kosten ({DOWNLOAD_GB} GB):  \${best['dl_cost']:.4f}
  ---------------------------------
  Gesamtkosten:            \${best['total']:.4f}
  Kosten pro 100 Bilder:   \${best['cost_per_100']:.4f}
  Standort:                {best['location']}
  Download-Speed:          {best['inet_down_mbs']:.0f} MB/s""", file=sys.stderr)

# Nur die ID auf stdout – sauber für bash-Variable
print(best['id'])
PYEOF
)

# Abbruch wenn Python fehlschlug
if [ -z "$BEST_ID" ]; then
    echo "Fehler: Keine best_id ermittelt." >&2
    exit 1
fi

echo ""
echo "Zum Starten der Instanz:"
echo ""
echo "  vastai create instance $BEST_ID --template_hash $FORGE_TEMPLATE_HASH --disk $FORGE_DISK"
echo ""
read -p "Jetzt starten? [j/N] " CONFIRM
if [[ "$CONFIRM" =~ ^[jJ]$ ]]; then
    echo "Starte Instanz $BEST_ID ..."
    vastai create instance "$BEST_ID" --template_hash "$FORGE_TEMPLATE_HASH" --disk "$FORGE_DISK"
else
    echo "Abgebrochen."
fi
