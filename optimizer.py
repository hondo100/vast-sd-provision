#!/usr/bin/env python3
# -----------------------------------------------------------------------------
# optimizer.py | Version: 2026-05-30.01 (Closed-Loop Parameter Alignment)
# -----------------------------------------------------------------------------
import json
import os
import sys
import argparse

def load_json(path):
    with open(path, 'r') as f:
        return json.load(f)

def save_json(data, path):
    with open(path, 'w') as f:
        json.dump(data, f, indent=2)

def main():
    parser = argparse.ArgumentParser(description="Adaptive Parameter Calibration Engine")
    parser.add_argument("--telemetry", required=True, help="Pfad zur gepullten provisioning_telemetry.json")
    parser.add_argument("--params", default="./params.json", help="Pfad zur lokalen params.json")
    parser.add_argument("--alpha", type=float, default=0.25, help="Lernrate / Glättungsfaktor (0 < alpha <= 1)")
    parser.add_argument("--model_gb", type=float, default=20.0, help="Genutzte Modellgröße in GB für die Validierung")
    args = parser.parse_args()

    if not os.path.exists(args.telemetry):
        sys.stderr.write(f"[FEHLER] Telemetriedatei nicht gefunden: {args.telemetry}\n")
        sys.exit(1)
        
    if not os.path.exists(args.params):
        sys.stderr.write(f"[FEHLER] Parameterdatei nicht gefunden: {args.params}\n")
        sys.exit(1)

    # Daten einlesen
    telemetry = load_json(args.telemetry)
    params = load_json(args.params)

    # Extraktion der gemessenen Zeiten (Phasen-Ebene)
    metrics = telemetry.get("metrics_seconds", {})
    infra = telemetry.get("infrastructure_parameters", {})

    t_configs = float(metrics.get("phase_3a_config_merge", 0))
    t_downloads = float(metrics.get("phase_4_asset_downloads", 0))
    t_extensions = float(metrics.get("phase_5_extensions_clone", 0))
    t_deps = float(metrics.get("phase_3b_python_dependencies", 0))
    t_restart = float(metrics.get("phase_6_forge_restart_boot", 0))
    
    actual_bps = float(infra.get("effective_network_download_speed_bps", 0))

    # Validierung des Status
    if telemetry.get("status") != "success":
        sys.stderr.write("[INFO] Instanz-Status war nicht erfolgreich. Optimiere nur Setup-Baselines.\n")

    # 1. Berechnung des realen Setup-Overheads (alle Phasen außer Download)
    # Entspricht im Modell der Summe aus beta_0 + beta_2
    actual_setup_overhead = t_configs + t_extensions + t_deps + t_restart
    
    # Da beta_2 (52.0) als statischer Fixwert für vdisk-Aktionen dient,
    # isolieren wir den systematischen Fehler direkt auf beta_0.
    current_b0 = float(params.get("beta_0", 165.0))
    current_b2 = float(params.get("beta_2", 52.0))
    target_b0 = max(10.0, actual_setup_overhead - current_b2)

    # 2. Berechnung des Download-Skalierungsfaktors (beta_1)
    current_b1 = float(params.get("beta_1", 1.38))
    new_b1 = current_b1
    
    if actual_bps > 0 and t_downloads > 0:
        actual_dl_mbps = actual_bps / 1_000_000.0
        # Theoretische Mindestzeit laut Formel der Scoring-Engine
        theoretical_download_seconds = (args.model_gb * 8192.0) / actual_dl_mbps
        if theoretical_download_seconds > 0:
            target_b1 = t_downloads / theoretical_download_seconds
            # Sicherheits-Bounds für beta_1 (Verhindert absurde Sprünge bei Netzwerk-Glitches)
            target_b1 = max(0.5, min(target_b1, 3.5))
            new_b1 = (1.0 - args.alpha) * current_b1 + args.alpha * target_b1

    # EMA-Update für beta_0
    new_b0 = (1.0 - args.alpha) * current_b0 + args.alpha * target_b0

    # Werte aktualisieren
    old_params = params.copy()
    params["beta_0"] = round(new_b0, 2)
    params["beta_1"] = round(new_b1, 2)

    # Speichern der kalibrierten Parameter
    save_json(params, args.params)

    # Protokollierung der Feedback-Schleife
    print("=========================================================================")
    print(" CLOSED-LOOP PARAMETER OPTIMIZATION REPORT")
    print("=========================================================================")
    print(f"Gemessene Setup-Zeit:  {actual_setup_overhead:.1f}s (Target beta_0: {target_b0:.1f}s)")
    print(f"Gemessene Downloadzeit:{t_downloads:.1f}s bei {actual_bps/1e6:.2f} Mbps")
    print("-------------------------------------------------------------------------")
    print(f"Parameter  |  Alt    -->  Neu")
    print(f"beta_0     |  {old_params['beta_0']:-7.2f} --> {params['beta_0']:-7.2f} (Basis-Overhead)")
    print(f"beta_1     |  {old_params['beta_1']:-7.2f} --> {params['beta_1']:-7.2f} (Netzwerk-Faktor)")
    print("=========================================================================")

if __name__ == "__main__":
    main()
