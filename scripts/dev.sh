#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

DERIVED="$HOME/Library/Developer/Xcode/DerivedData/Magneto"

xcodegen generate
xcodebuild -project Magneto.xcodeproj -scheme Magneto -configuration Debug -derivedDataPath "$DERIVED" build

osascript -e 'quit app "Magneto"' 2>/dev/null || true
sleep 1
rm -rf /Applications/Magneto.app
ditto "$DERIVED/Build/Products/Debug/Magneto.app" /Applications/Magneto.app

# Same reason as install.sh: never leave a second .app on disk for Spotlight.
rm -rf "$DERIVED/Build/Products/Debug/Magneto.app" "$DERIVED/Build/Products/Debug/Magneto.app.dSYM"

open /Applications/Magneto.app
echo "Magneto (build Debug) installé dans /Applications et lancé."
