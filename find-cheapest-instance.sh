#!/bin/bash
# Auto-Fix Windows CRLF -> LF (falls lokal bearbeitet)
sed -i 's/\r//' "$0"

# ==============================================================================
# VAST.AI ANGEBOTS-VERGLEICH - Guenstigstes Gesamtangebot finden
# Berechnet: GPU-Kosten (2h) + Download-Kosten (~18 GB Modelle)
# Normalisiert nach SDXL-Leistung (Bilder/Stunde)
# ==============================================================================

VASTAI_API_KEY="${VASTAI_API_KEY:-}"
SESSION_HOURS=2
MODEL_DOWNLOAD_GB=18
MIN_VRAM_MB=16000
MIN_RELIABILITY=0.98
RESULTS=20

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

python3 << PYEOF
import json, sys, urllib.request

VASTAI_API_KEY  = "${VASTAI_API_KEY}"
SESSION_H       = ${SESSION_HOURS}
DOWNLOAD_GB     = ${MODEL_DOWNLOAD_GB}
TOP_N           = ${RESULTS}
RESPONSE        = """${RESPONSE}"""

# ==============================================================================
# SDXL Benchmark-Tabelle (Bilder/Stunde @ 1024x1024, 20 Steps)
# Quellen: SaladCloud SDXL Benchmark, Tom's Hardware, promptingpixels.com
# Fehlende GPUs werden via dlperf interpoliert
# ==============================================================================
SDXL_IMG_PER_H = {
    # RTX 50xx Serie
    "RTX 5090":       1200,
    "RTX 5080":        850,
    "RTX 5070 Ti":     700,
    "RTX 5070":        580,
    "RTX 5060 Ti":     420,
    # RTX 40xx Serie
    "RTX 4090":        900,
    "RTX 4080 Super":  680,
    "RTX 4080":        640,
    "RTX 4070 Ti Super": 520,
    "RTX 4070S Ti":    520,
    "RTX 4070 Ti":     490,
    "RTX 4070 Super":  420,
    "RTX 4070S":       420,
    "RTX 4070":        370,
    "RTX 4060 Ti":     290,
    "RTX 4060":        240,
    # RTX 30xx Serie
    "RTX 3090 Ti":     490,
    "RTX 3090":        450,
    "RTX 3080 Ti":     400,
    "RTX 3080":        350,
    "RTX 3070 Ti":     280,
    "RTX 3070":        260,
    # RTX 20xx Serie
    "RTX 2080 Ti":     220,
    "RTX 2080 Super":  190,
    "RTX 2080":        180,
    "RTX 2070 Super":  160,
    # Titan
    "Titan RTX":       300,
    "Titan V":         250,
    # Tesla / Datacenter
    "A100 SXM4":       920,
    "A100 SXM":        920,
    "A100 PCIe":       880,
    "A100":            880,
    "A40":             600,
    "A30":             420,
    "A10":             380,
    "A10G":            380,
    "A6000":           520,
    "RTX A6000":       520,
    "RTX A5000":       430,
    "RTX A4500":       360,
    "RTX A4000":       300,
    "RTX A3000":       240,
    "Tesla V100":      280,
    "Tesla V100 SXM2": 320,
    "Tesla T4":        180,
    "L40S":            780,
    "L40":             700,
    "L4":              360,
    "H100 SXM":       1400,
    "H100 PCIe":      1200,
    "H100":           1200,
}

def get_sdxl_perf(gpu_name, dlperf):
    """Gibt SDXL Bilder/Stunde zurueck – exakt wenn bekannt, sonst via dlperf interpoliert."""
    # Exakter Match
    for key, val in SDXL_IMG_PER_H.items():
        if key.lower() in gpu_name.lower():
            return val, "benchmark"
    # Fallback: dlperf-basierte Interpolation
    # Referenz: RTX 3090 ~ dlperf 45 ~ 450 img/h => Faktor ~10
    if dlperf and dlperf > 0:
        estimated = round(dlperf * 10)
        return estimated, "geschaetzt"
    return 200, "unbekannt"

try:
    data = json.loads(RESPONSE)
except Exception as e:
    print(f"Ungueltige API-Antwort: {e}")
    sys.exit(1)

offers = data.get("offers", [])
if not offers:
    print("Keine Angebote gefunden.")
    print(f"API-Antwort: {str(data)[:300]}")
    sys.exit(1)

print(f"Gefunden: {len(offers)} Angebote - berechne Gesamtkosten + GPU-Leistung...")
print("")

results = []
for o in offers:
    gpu_name       = o.get("gpu_name", "?")
    vram_gb        = round(o.get("gpu_ram", 0) / 1024, 1)
    dph            = o.get("dph_total", 0)
    inet_down_cost = o.get("inet_down_cost", 0)
    inet_down_mbs  = o.get("inet_down", 0)
    reliability    = o.get("reliability", 0)
    geolocation    = o.get("geolocation", "?")
    offer_id       = o.get("id", "?")
    dlperf         = o.get("dlperf", 0)

    gpu_cost      = dph * SESSION_H
    download_cost = inet_down_cost * DOWNLOAD_GB
    total_cost    = gpu_cost + download_cost

    try:
        spd = float(inet_down_mbs) if inet_down_mbs else 0
        download_min = round((DOWNLOAD_GB * 1024) / spd / 60, 1) if spd > 0 else None
    except:
        download_min = None

    sdxl_img_h, perf_src = get_sdxl_perf(gpu_name, dlperf)

    # Kosten pro 100 SDXL-Bilder (normalisierter Vergleich)
    imgs_per_session  = sdxl_img_h * SESSION_H
    cost_per_100_imgs = (total_cost / imgs_per_session * 100) if imgs_per_session > 0 else 999

    results.append({
        "id":               offer_id,
        "gpu":              gpu_name,
        "vram_gb":          vram_gb,
        "dph":              dph,
        "gpu_cost":         gpu_cost,
        "dl_cost":          download_cost,
        "total":            total_cost,
        "inet_down_mbs":    inet_down_mbs if inet_down_mbs else 0,
        "dl_min":           download_min,
        "reliability":      reliability,
        "location":         geolocation,
        "sdxl_img_h":       sdxl_img_h,
        "perf_src":         perf_src,
        "cost_per_100":     cost_per_100_imgs,
        "imgs_per_session": imgs_per_session,
    })

# Sortierung nach Kosten pro 100 Bilder (normalisiert)
results.sort(key=lambda x: x["cost_per_100"])

print(f"{'Rang':<5} {'GPU':<22} {'VRAM':>6} {'$/h':>6} {'Gesamt':>7} {'img/h':>6} {'$/100img':>9} {'DL-Speed':>10} {'DL-Zeit':>8} {'Reliab.':>8} {'Quelle':<12} {'Ort':<18} {'ID'}")
print("-" * 155)
for i, r in enumerate(results[:TOP_N], 1):
    dl_min_str = f"{r['dl_min']}min" if r['dl_min'] is not None else "?"
    inet_str   = f"{r['inet_down_mbs']:.0f} MB/s" if r['inet_down_mbs'] and r['inet_down_mbs'] > 0 else "?"
    print(
        f"{i:<5} {r['gpu']:<22} {r['vram_gb']:>5.1f}G "
        f"\${r['dph']:>5.3f} \${r['total']:>6.4f} "
        f"{r['sdxl_img_h']:>6} \${r['cost_per_100']:>8.4f} "
        f"{inet_str:>10} {dl_min_str:>8} "
        f"{r['reliability']:>7.3f} {r['perf_src']:<12} "
        f"{r['location']:<18} {r['id']}"
    )

print("")
best = results[0]
print(f"Bestes Preis-Leistungs-Angebot: {best['gpu']} ({best['vram_gb']}G VRAM)")
print(f"  SDXL Leistung:          {best['sdxl_img_h']} Bilder/Stunde ({best['perf_src']})")
print(f"  Bilder in {SESSION_H}h Session:  ~{best['imgs_per_session']} Bilder")
print(f"  GPU-Kosten ({SESSION_H}h):        \${best['gpu_cost']:.4f}")
print(f"  Download-Kosten ({DOWNLOAD_GB} GB): \${best['dl_cost']:.4f}")
print(f"  ---------------------------------")
print(f"  Gesamtkosten:           \${best['total']:.4f}")
print(f"  Kosten pro 100 Bilder:  \${best['cost_per_100']:.4f}")
print(f"  Offer-ID:               {best['id']}")
print(f"  Standort:               {best['location']}")
if best['dl_min'] is not None:
    print(f"  Download-Speed:         {best['inet_down_mbs']:.0f} MB/s (~{best['dl_min']} Min fuer {DOWNLOAD_GB} GB)")

# Template ermitteln
print("")
print("Suche passendes Forge-Template...")
req = urllib.request.Request(
    "https://console.vast.ai/api/v0/template/",
    headers={"Authorization": f"Bearer {VASTAI_API_KEY}"}
)
try:
    with urllib.request.urlopen(req) as resp:
        tdata = json.loads(resp.read())
    templates = tdata.get("templates", [])
    forge_templates = [t for t in templates if "forge" in t.get("name", "").lower()]

    if len(forge_templates) == 1:
        tmpl = forge_templates[0]
        print(f"  Template gefunden: {tmpl.get('name')} (ID: {tmpl.get('id')})")
        print("")
        print(f"Zum Starten:")
        print(f"  vastai create instance {best['id']} --template_hash {tmpl.get('id')} --disk 50")
    elif len(forge_templates) > 1:
        print(f"  Mehrere Forge-Templates gefunden:")
        for t in forge_templates:
            print(f"  ID: {t['id']}  Name: {t.get('name','?')}")
        print("")
        print(f"Zum Starten (Template-ID einsetzen):")
        print(f"  vastai create instance {best['id']} --template_hash TEMPLATE_ID --disk 50")
    else:
        print(f"  Kein Forge-Template gefunden.")
        print("")
        print(f"Zum Starten (ohne Template):")
        print(f"  vastai create instance {best['id']} --image vastai/sd-forge:neo --disk 50")
except Exception as e:
    print(f"  Template-Abfrage fehlgeschlagen: {e}")
    print("")
    print(f"Zum Starten (ohne Template):")
    print(f"  vastai create instance {best['id']} --image vastai/sd-forge:neo --disk 50")
PYEOF
