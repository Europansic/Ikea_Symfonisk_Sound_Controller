#!/bin/bash
# IKEA SYMFONISK + Sonos – SmartThings Rules API Setup
# Uploads 4 rules that connect the SYMFONISK Sound Controller to a Sonos speaker.
# All rules run locally on the SmartThings Hub.
#
# Requirements:
#   - curl
#   - python3
#   - A SmartThings Personal Access Token (https://account.smartthings.com/tokens)
#     with scopes: Devices (read/control), Rules (read/write/execute), Locations (read)

set -e
cd "$(dirname "$0")"

echo "========================================"
echo "  SYMFONISK x Sonos – Rules API Setup"
echo "========================================"
echo ""
echo "You need a Personal Access Token from:"
echo "  https://account.smartthings.com/tokens"
echo "Required scopes: Devices, Rules, Locations"
echo ""

# ── Collect input ──────────────────────────────────────────────────────────
read -rp "Personal Access Token : " TOKEN
echo ""

echo "Fetching your locations..."
curl -s "https://api.smartthings.com/locations" \
  -H "Authorization: Bearer ${TOKEN}" \
  | python3 -c "
import json, sys
data = json.load(sys.stdin)
for loc in data.get('items', []):
    print(f\"  {loc['name']:40s}  {loc['locationId']}\")
" 2>/dev/null || echo "  (could not fetch locations – check your token)"
echo ""
read -rp "Location ID           : " LOCATION_ID
echo ""

echo "Fetching your devices..."
curl -s "https://api.smartthings.com/devices" \
  -H "Authorization: Bearer ${TOKEN}" \
  | python3 -c "
import json, sys
data = json.load(sys.stdin)
for d in data.get('items', []):
    print(f\"  {d.get('label','?'):40s}  {d['deviceId']}\")
" 2>/dev/null || echo "  (could not fetch devices – check your token)"
echo ""
read -rp "SYMFONISK Device ID   : " SYMFONISK_ID
read -rp "Sonos Device ID       : " SONOS_ID
echo ""

# ── Substitute IDs ────────────────────────────────────────────────────────
echo "Uploading rules..."
echo ""

for f in 01_play_pause.json 02_next_track.json 03_previous_track.json 04_volume_sync.json; do
  echo "--- ${f} ---"

  # Replace placeholders in a temp file
  sed \
    -e "s/YOUR_SYMFONISK_DEVICE_ID/${SYMFONISK_ID}/g" \
    -e "s/YOUR_SONOS_DEVICE_ID/${SONOS_ID}/g" \
    "${f}" > "/tmp/st_rule_${f}"

  RESPONSE=$(curl -s -X POST \
    "https://api.smartthings.com/rules?locationId=${LOCATION_ID}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d @"/tmp/st_rule_${f}")

  # Pretty-print or show raw on failure
  echo "${RESPONSE}" | python3 -m json.tool 2>/dev/null || echo "${RESPONSE}"
  echo ""
done

# ── Summary ───────────────────────────────────────────────────────────────
echo "========================================"
echo "  Done! Active rules in your location:"
echo "========================================"
curl -s "https://api.smartthings.com/rules?locationId=${LOCATION_ID}" \
  -H "Authorization: Bearer ${TOKEN}" \
  | python3 -c "
import json, sys
data = json.load(sys.stdin)
for r in data.get('items', []):
    status = r.get('status','?')
    print(f\"  [{status:8s}] {r['name']}\")
" 2>/dev/null

echo ""
echo "Test it: press the SYMFONISK button → Sonos should play/pause!"
