#!/bin/bash
set -euo pipefail

TEMPLATE_HASH="ad0935fab3e1f781fa442c1604ed07e2"
RESULTS=10
DRY_RUN=0
MODE="prod"

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --test) MODE="test" ;;
    --prod) MODE="prod" ;;
    *)
      echo "Ungueltiger Parameter: $arg"
      exit 1
      ;;
  esac
done

echo "Pruefe Vast.ai Auth..."
if ! vastai show user >/dev/null 2>&1; then
  echo "VAST_USER_FAIL"
  exit 1
fi
if ! vastai show api-keys >/dev/null 2>&1; then
  echo "VAST_KEY_FAIL"
  exit 1
fi

echo "VAST_AUTH_OK"
echo

case "$MODE" in
  prod)
    QUERY='gpu_ram>24 reliability>0.98 num_gpus=1 rented=False verified=True rentable=true direct_port_count>=1'
    ;;
  test)
    QUERY='gpu_ram>16 reliability>0.95 num_gpus=1 rented=False verified=True rentable=true direct_port_count>=1'
    ;;
  *)
    echo "Ungueltiger Modus: $MODE"
    exit 1
    ;;
esac

RAW="$(vastai search offers "$QUERY" --raw -o 'dlperf_usd-')"

python3 - "$MODE" "$RESULTS" "$DRY_RUN" "$TEMPLATE_HASH" <<'PY' <<<"$RAW"
import sys, json, subprocess

MODE = sys.argv[1]
RESULTS = int(sys.argv[2])
DRY_RUN = sys.argv[3] == '1'
TEMPLATE_HASH = sys.argv[4]
raw = sys.stdin.read().strip()

if not raw:
    print('Keine Daten empfangen.')
    sys.exit(1)

def parse_rows(payload):
    try:
        data = json.loads(payload)
        if isinstance(data, list):
            return data
        if isinstance(data, dict):
            for key in ('offers', 'results', 'data'):
                if key in data and isinstance(data[key], list):
                    return data[key]
    except Exception:
        pass

    rows = []
    lines = payload.splitlines()
    header_idx = None
    for i, line in enumerate(lines):
        s = line.strip()
        if s.startswith('#  ID') or s.startswith('ID') or s.startswith('# ID'):
            header_idx = i
            break
    if header_idx is None:
        return rows

    for line in lines[header_idx + 1:]:
        s = line.strip()
        if not s:
            continue
        if s.startswith('#  country') or s.startswith('# country'):
            break
        parts = s.split()
        if len(parts) < 10:
            continue
        rows.append({'_parts': parts})
    return rows

rows = parse_rows(raw)
if not rows:
    print('Keine Angebote gefunden.')
    sys.exit(1)

parsed = []
for r in rows:
    try:
        if '_parts' in r:
            p = r['_parts']
            offer_id = p[1]
            model = p[4]
            price = float(p[10])
            dlp = float(p[11])
            dlp_usd = float(p[12])
            score = float(p[13])
            rel = float(p[17])
            status = p[20]
            host_id = p[21]
            ports = p[22]
        else:
            offer_id = str(r.get('id') or r.get('offer_id') or '')
            model = str(r.get('machine_name') or r.get('gpu_name') or r.get('model') or 'unknown')
            price = float(r.get('dph_total') or r.get('price') or 9999)
            dlp = float(r.get('dlperf') or r.get('dlp') or 0)
            dlp_usd = float(r.get('dlperf_usd') or r.get('dlp_usd') or 0)
            score = float(r.get('score') or 0)
            rel = float(r.get('reliability') or r.get('rel') or 0)
            status = str(r.get('status') or '')
            host_id = str(r.get('host_id') or '')
            ports = str(r.get('direct_port_count') or r.get('ports') or '')
        parsed.append({
            'offer_id': offer_id,
            'model': model,
            'price': price,
            'dlp': dlp,
            'dlp_usd': dlp_usd,
            'score': score,
            'rel': rel,
            'status': status,
            'host_id': host_id,
            'ports': ports,
        })
    except Exception:
        continue

if not parsed:
    print('Keine Angebote konnten geparst werden.')
    sys.exit(1)

parsed.sort(key=lambda r: (-r['dlp_usd'], -r['rel'], r['price']))

print(f'Modus: {MODE}')
print('Nr  Offer_ID    Model               $/hr     DLP    DLP/$   Score   Rel    Status')
print('-' * 80)
for i, r in enumerate(parsed[:RESULTS], 1):
    print(f"{i:2d}  {r['offer_id']:<10} {r['model']:<18} {r['price']:>6.4f}  {r['dlp']:>6.1f}  {r['dlp_usd']:>6.2f}  {r['score']:>6.1f}  {r['rel']:>5.2f}  {r['status']}")

pick = parsed[0]
print()
print(f"Auswahl: {pick['offer_id']} ({pick['model']})")
print(f"Befehl: vastai create instance {pick['offer_id']} --template_hash {TEMPLATE_HASH}")

if DRY_RUN:
    sys.exit(0)

subprocess.run(['vastai', 'create', 'instance', pick['offer_id'], '--template_hash', TEMPLATE_HASH], check=True)
PY
