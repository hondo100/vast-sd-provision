#!/usr/bin/env python3
# -----------------------------------------------------------------------------
# scoring_engine.py | Version: 2026-06-05.02 (Decoupled Core + CUDA field)
# -----------------------------------------------------------------------------
import json
import sys
import re
import os
import argparse

def load_params(params_path):
    default = {"beta_0": 165.0, "beta_1": 1.38, "beta_2": 52.0, "beta_3": 120.0}
    if os.path.exists(params_path):
        try:
            with open(params_path, 'r') as f:
                return json.load(f)
        except Exception as e:
            sys.stderr.write(f"[WARNUNG] Konnte params.json nicht laden, nutze Defaults. Fehler: {e}\n")
    return default

def main():
    parser = argparse.ArgumentParser(description="Vast.ai Mathematical Scoring Engine")
    parser.add_argument("--gpu_filter", required=True, help="Regex-Filter für GPU-Modelle")
    parser.add_argument("--model_gb", type=float, default=20.0, help="Größe des Modells in Gigabyte")
    parser.add_argument("--session_hours", type=float, default=3.0, help="Geplante Sitzungsdauer")
    parser.add_argument("--params", default="./params.json", help="Pfad zur Parameter-JSON")
    args = parser.parse_args()

    p = load_params(args.params)
    b0 = float(p.get("beta_0", 165.0))
    b1 = float(p.get("beta_1", 1.38))
    b2 = float(p.get("beta_2", 52.0))
    b3 = float(p.get("beta_3", 120.0))

    try:
        raw_data = sys.stdin.read()
        if not raw_data.strip():
            sys.stderr.write("[FEHLER] Keine Daten über stdin empfangen.\n")
            sys.exit(1)

        data = json.loads(raw_data)
        offers = data if isinstance(data, list) else data.get('offers', [])
        rows = []

        for o in offers:
            gpu = str(o.get('gpu_name', 'unk'))
            if not re.search(args.gpu_filter, gpu, re.IGNORECASE):
                continue

            dph = float(o.get('dph_total', 0))
            init = float(o.get('inet_down_cost', 0))
            dl = float(o.get('inet_down', 1))
            vram = float(o.get('gpu_ram', 0))
            if vram > 200:
                vram /= 1024

            dbw = float(o.get('disk_bw', 0))
            rel = float(o.get('reliability', 1.0))
            numg = float(o.get('num_gpus', 1))
            cuda_max_good = float(o.get('cuda_max_good', 0))

            net_download_seconds = (args.model_gb * 8192.0) / max(dl, 0.1)
            estimated_ready_seconds = b0 + b2 + (b1 * net_download_seconds) + (b3 * (1.0 - rel))
            ready = estimated_ready_seconds / 60.0

            score = ((1.0 / max(dph, 0.0001)) * 0.47 + (1.22 if vram > 80 else 0.75) * 0.16 + (rel ** 2) * 0.14) * (1.0 if numg <= 1 else 0.82)
            test_cost = dph * 0.5 + init

            rows.append((
                o.get('id'),
                gpu[:14],
                numg,
                dph,
                init,
                (dph + init / args.session_hours),
                dl,
                ready,
                vram,
                dbw,
                o.get('geolocation', 'US')[:2],
                score,
                test_cost,
                cuda_max_good
            ))

        for r in sorted(rows, key=lambda x: x[11], reverse=True):
            print(f"{r[0]}\t{r[1]}\t{r[2]:.0f}\t{r[3]:.2f}\t{r[4]:.2f}\t{r[5]:.2f}\t{r[6]:.0f}\t{r[7]:.0f}\t{r[8]:.0f}\t{r[9]:.0f}\t{r[10]}\t{r[11]:.2f}\t{r[12]:.2f}\t{r[13]:.1f}")

    except Exception as e:
        sys.stderr.write(f"Python-Inferenz-Fehler: {str(e)}\n")
        sys.exit(1)

if __name__ == "__main__":
    main()
