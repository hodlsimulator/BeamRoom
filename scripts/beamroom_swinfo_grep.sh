#!/usr/bin/env bash
set -euo pipefail
IPA="${1:?Usage: beamroom_swinfo_grep.sh /path/to/BeamRoomHost.ipa}"
SW="/Applications/Transporter.app/Contents/Frameworks/ContentDelivery.framework/Resources/swinfo"
OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT
"$SW" -f "$IPA" --platform ios --plistFormat xml --output-spi -temporary "$OUT" -o "$OUT/asset-description.plist" >/dev/null
grep -n -A2 -B2 'RPBroadcastProcessMode' "$OUT/asset-description.plist" || echo "RPBroadcastProcessMode not found"
echo "asset-description: $OUT/asset-description.plist"
