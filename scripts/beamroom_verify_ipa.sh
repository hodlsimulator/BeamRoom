#!/usr/bin/env bash
set -euo pipefail
IPA="${1:?Usage: beamroom_verify_ipa.sh /path/to/BeamRoomHost.ipa}"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
unzip -q "$IPA" -d "$TMP" >/dev/null

APPEX_DIR="$(find "$TMP/Payload/BeamRoomHost.app/PlugIns" -maxdepth 1 -type d -name '*.appex' -print -quit)"
[ -n "${APPEX_DIR:-}" ] || { echo "❌ No .appex found"; exit 2; }

AP="$APPEX_DIR/Info.plist"
echo "AppeX: $APPEX_DIR"
plutil -lint "$AP" >/dev/null && echo "✅ AppeX Info.plist parses"
echo -n "PointIdentifier: "; /usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "$AP"
echo -n "ProcessMode:     "; /usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionAttributes:RPBroadcastProcessMode' "$AP"
