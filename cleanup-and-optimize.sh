#!/usr/bin/env bash
# cleanup-and-optimize.sh
set -euo pipefail

INSTANCE_ID="1234567" # Dynamisch aus deinem Workflow übergeben

echo "Hole Telemetriedaten von Instanz $INSTANCE_ID vor dem Destroy..."

# 1. Sicherer Pull über das Vast.ai API Gateway
vastai copy-from "$INSTANCE_ID":/workspace/provisioning_telemetry.json ./latest_telemetry.json

# 2. Instanz zerstören (Daten sind nun lokal gesichert)
vastai destroy "$INSTANCE_ID"

# 3. Parameter-Optimierung lokal ausführen
python3 ./optimizer.py --telemetry ./latest_telemetry.json --params ./params.json --alpha 0.25

rm ./latest_telemetry.json
