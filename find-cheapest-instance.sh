#!/usr/bin/env python3
# find-cheapest-instance.sh
# Version: 2026-05-24.7

import os
import sys
import json
import argparse
import subprocess
import time

try:
    import requests
except ImportError:
    print("[ERR] requests fehlt. Bitte installieren: pip install requests", file=sys.stderr)
    sys.exit(1)

VERSION = "2026-05-24.7"
RESULTS = 10
TX_GB = 20.0
MIN_VRAM_GB = 24.0
MIN_REL = 0.95
MIN_DL_PERF = 0.0
VAST_URL = "https://console.vast.ai/api/v0/bundles"

def c(text, code):
    return f"\033[{code}m{text}\033[0m"

def green(text): return c(text, "32")
def yellow(text): return c(text, "33")
def blue(text): return c(text, "34")
def red(text): return c(text, "31")
def bold(text): return c(text, "1")

def fmt_num(x, width=7, prec=1):
    return f"{x:>{width}.{prec}f}"

def get_auth():
    env = os.getenv("VAST_AUTH", "").strip()
    if env:
        return env
    try:
        out = subprocess.check_output(["vast", "show", "auth"], text=True).strip()
        return out
    except Exception:
        return ""

def fetch_offers():
    params = {
        "q": json.dumps({
            "verified": {"eq": True}
        }),
        "limit": 200,
        "order": "-gpu_total_ram"
    }
    headers = {"Authorization": f"Bearer {AUTH}"}
    r = requests.get(VAST_URL, params=params, headers=headers, timeout=30)
    r.raise_for_status()
    data = r.json()
    if isinstance(data, dict) and "offers" in data:
        return data["offers"]
    if isinstance(data, dict) and "results" in data:
        return data["results"]
    if isinstance(data, list):
        return data
    return []

def get_value(d, *keys, default=0):
    for k in keys:
        if k in d and d[k] is not None:
            return d[k]
    return default

def as_float(v, default=0.0):
    try:
        return float(v)
    except Exception:
        return default

def score_offer(r):
    price = as_float(get_value(r, "dph_total", "price", "hourly_price", default=0))
    eff = as_float(r.get("effective_hourly", price))
    dl = as_float(get_value(r, "dlperf", "dl_performance", default=0))
    rel = as_float(get_value(r, "reliability", "rel", default=1))
    vram = as_float(get_value(r, "gpu_ram", "gpu_total_ram", "vram", default=0)) / 1024.0

    if vram < MIN_VRAM_GB or rel < MIN_REL:
        return -1

    price_score = 1.0 / max(eff, 0.0001)
    vram_bonus = min(vram / 24.0, 2.0)
    rel_bonus = rel
    dl_bonus = dl / 100.0
    return price_score * 0.45 + dl_bonus * 0.35 + vram_bonus * 0.15 + rel_bonus * 0.05

def classify(i):
    if i == 0:
        return green
    if i in (1, 2):
        return yellow
    if i in (3, 4):
        return blue
    return lambda x: x

def main():
    global AUTH
    parser = argparse.ArgumentParser()
    parser.add_argument("--test", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    print(f"Skript-Version: {VERSION}")
    print("Pruefe Vast.ai Auth...")
    AUTH = get_auth()
    if not AUTH:
        print("[ERR] Kein Vast.ai Auth-Token gefunden", file=sys.stderr)
        sys.exit(2)
    print("[OK] VAST_AUTH_OK")
    print()
    print("[INFO] Suche Angebote...")
    print(f"Modus: {'test' if args.test else 'live'}")
    print("Legende:")
    print("  Grün  = bester GenAI-Score")
    print("  Gelb  = gute Balance aus Preis und Leistung")
    print("  Blau  = günstigste effektive Kosten")
    print("  Rot   = unter Mindestanforderungen")
    print()

    offers = fetch_offers()

    parsed = []
    for r in offers:
        price = as_float(get_value(r, "dph_total", "price", "hourly_price", default=0))
        tx = as_float(r.get("tx_cost_20gb", 0))
        eff = price + tx
        dl = as_float(get_value(r, "dlperf", "dl_performance", default=0))
        rel = as_float(get_value(r, "reliability", "rel", default=1))
        vram_gb = as_float(get_value(r, "gpu_ram", "gpu_total_ram", "vram", default=0)) / 1024.0
        status = bool(get_value(r, "verified", "status", default=True))
        model = str(get_value(r, "gpu_name", "model", "gpu", default="unknown"))
        offer_id = str(get_value(r, "id", "offer_id", default=""))
        parsed.append({
            "offer_id": offer_id,
            "model": model,
            "price": price,
            "tx": tx,
            "eff": eff,
            "dl": dl,
            "rel": rel,
            "vram_gb": vram_gb,
            "status": status,
            "score": score_offer(r),
        })

    parsed = sorted(parsed, key=lambda x: (-x["score"], x["eff"], -x["dl"]))

    print(f"{'Nr':<3} {'Offer_ID':<10} {'Model':<18} {'$/hr':>7} {'20GB Tx':>8} {'Eff$/h':>8} {'DLPerf':>8} {'Score':>7} {'VRAM GB':>8} {'Rel':>5} {'Status':>6}")
    print("-" * 96)

    shown = parsed[:RESULTS]
    for idx, r in enumerate(shown, start=1):
        color = classify(idx - 1)
        line = (
            f"{idx:<3} {r['offer_id']:<10} {r['model']:<18} "
            f"{r['price']:>7.4f} {r['tx']:>8.4f} {r['eff']:>8.4f} "
            f"{r['dl']:>8.1f} {r['score']:>7.1f} {r['vram_gb']:>8.1f} "
            f"{r['rel']:>5.2f} {str(r['status']):>6}"
        )
        if r["score"] < 0:
            line = red(line)
        else:
            line = color(line)
        print(line)

    print()
    if shown:
        print(f"Vorschlag: Nummer 1 ({shown[0]['offer_id']} / {shown[0]['model']})")
    else:
        print("Vorschlag: keine passenden Angebote gefunden")
        sys.exit(1)

    if args.dry_run:
        sys.exit(0)

    choice = None
    limit = min(RESULTS, len(shown))
    while choice is None:
        raw_choice = input(f"Welche Nummer buchen? [1-{limit}] (Enter = 1): ").strip()
        if raw_choice == "":
            choice = 1
            break
        if raw_choice.isdigit():
            n = int(raw_choice)
            if 1 <= n <= limit:
                choice = n
                break
        print("Ungueltige Eingabe. Bitte nur eine gueltige Nummer eingeben.")

    selected = shown[choice - 1]
    print()
    print(f"Gewählt: {choice} -> {selected['offer_id']} / {selected['model']}")
    if args.test:
        print("[TEST] Kein Booking ausgeführt.")
        sys.exit(0)

    confirm = input("Buchung wirklich ausführen? [j/N]: ").strip().lower()
    if confirm != "j":
        print("Abgebrochen.")
        sys.exit(0)

    print("[INFO] Booking würde hier ausgeführt werden.")
    # hier deine echte Booking-Logik einfügen

if __name__ == "__main__":
    main()
