#!/bin/bash
# Auto-Fix Windows CRLF → LF (falls lokal bearbeitet)
sed -i 's/\r//' "$0"

# ==============================================================================
# 💰 VAST.AI ANGEBOTS-VERGLEICH – Günstigstes Gesamtangebot finden
# Berechnet: GPU-Kosten (2h) + Download-Kosten (~18 GB Modelle)
# ==============================================================================

# ── Konfiguration (hier anpassbar) ────────────────────────────────────────
VASTAI_API_KEY="${VASTAI_API_KEY:-}"
SESSION_HOURS=2
MODEL_DOWNLOAD_GB=18
MIN_VRAM_MB=16000
MIN_RELIABILITY=0.98
RESULTS=20

if [ -z "$VASTAI_API_KEY" ]; then
    echo "❌ VASTAI_API_KEY nicht gesetzt."
    echo "   Aufruf: VASTAI_API_KEY=dein_key $(basename $0)"
    echo "   Oder: export VASTAI_API_KEY=dein_key"
    exit 1
fi

# ── API-Abfrage ────────────────────────────────────────────────────────────
echo ""
echo "🔍 Suche verfügbare GPU-Instanzen bei Vast.ai..."
echo "   Mindest-VRAM: ${MIN_VRAM_MB} MB | Reliability: >= ${MIN_RELIABILITY}"
echo ""

RESPONSE=$(curl -sL --request POST \
    --url "https://console.vast.ai/api/v0/bundles/" \
    --header "Authorization: Bearer ${VASTAI_API_KEY}" \
    --header "Content-Type: application/json" \
    --data "{\"limit\":200,\"type\":\"on-demand\",\"verified\":{\"eq\":true},\"rentable\":{\"eq\":true},\"rented\":{\"eq\":false},\"gpu_ram\":{\"gte\":${MIN_VRAM_MB}},\"reliability\":{\"gte\":${MIN_RELIABILITY}},\"num_gpus\":{\"eq\":1},\"order\":[[\"dph_total\",\"asc\"]]}")

# ── Auswertung via Python ──────────────────────────────────────────────────
python3 << PYEOF
import json, sys, urllib.request

VASTAI_API_KEY  = "${VASTAI_API_KEY}"
SESSION_H       = ${SESSION_HOURS}
DOWNLOAD_GB     = ${MODEL_DOWNLOAD_GB}
TOP_N           = ${RESULTS}
RESPONSE        = """${RESPONSE}"""

try:
    data = json.loads(RESPONSE)
except Exception as e:
    print(f"Ungueltige API-Antwort: {e}")
    print(f"Antwort (ersten 300 Zeichen): {RESPONSE[:300]}")
    sys.exit(1)

offers = data.get("offers", [])
if not offers:
    print("Keine Angebote gefunden.")
    print(f"API-Antwort: {str(data)[:300]}")
    sys.exit(1)

print(f"Gefunden: {len(offers)} Angebote – berechne Gesamtkosten...")
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
    gpu_cost       = dph * SESSION_H
    download_cost  = inet_down_cost * DOWNLOAD_GB
    total_cost     = gpu_cost + download_cost
    download_min   = round((DOWNLOAD_GB * 1024) / inet_down_mbs / 60, 1) if inet_down_mbs > 0 else None
    results.append({
        "id":            offer_id,
        "gpu":           gpu_name,
        "vram_gb":       vram_gb,
        "dph":           dph,
        "gpu_cost":      gpu_cost,
        "dl_cost":       download_cost,
        "total":         total_cost,
        "inet_down_mbs": inet_down_mbs,
        "dl_min":        download_min,
        "reliability":   reliability,
        "location":      geolocation,
    })

results.sort(key=lambda x: x["total"])

print(f"{'Rang':<5} {'GPU':<22} {'VRAM':>6} {'$/h':>6} {'GPU 2h':>7} {'DL-Kosten':>10} {'GESAMT':>8} {'DL-Speed':>10} {'DL-Zeit':>8} {'Reliab.':>8} {'Ort':<15} {'ID'}")
print("-" * 135)
for i, r in enumerate(results[:TOP_N], 1):
    dl_min_str = f"{r['dl_min']}min" if r['dl_min'] else "?"
    inet_str   = f"{r['inet_down_mbs']:.0f} MB/s" if r['inet_down_mbs'] else "?"
    print(
        f"{i:<5} {r['gpu']:<22} {r['vram_gb']:>5.1f}G "
        f"\${r['dph']:>5.3f} \${r['gpu_cost']:>6.3f} \${r['dl_cost']:>9.4f} \${r['total']:>7.4f} "
        f"{inet_str:>10} {dl_min_str:>8} {r['reliability']:>7.3f} {r['location']:<15} {r['id']}"
    )

print("")
best = results[0]
print(f"Guenstigstes Angebot: {best['gpu']} ({best['vram_gb']}G VRAM)")
print(f"  GPU-Kosten ({SESSION_H}h):        \${best['gpu_cost']:.4f}")
print(f"  Download-Kosten ({DOWNLOAD_GB} GB): \${best['dl_cost']:.4f}")
print(f"  ---------------------------------")
print(f"  Gesamtkosten:           \${best['total']:.4f}")
print(f"  Offer-ID:               {best['id']}")
print(f"  Standort:               {best['location']}")
if best['dl_min']:
    print(f"  Download-Speed:         {best['inet_down_mbs']:.0f} MB/s (~{best['dl_min']} Min fuer {DOWNLOAD_GB} GB)")

# Template ermitteln
print("")
print("Suche passendes Forge-Template...")
req = urllib.request.Request(
    "https://console.vast.ai/api/v0/templates/",
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
