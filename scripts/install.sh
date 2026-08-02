#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

DERIVED="$HOME/Library/Developer/Xcode/DerivedData/Magneto"

xcodegen generate
xcodebuild -project Magneto.xcodeproj -scheme Magneto -configuration Release -derivedDataPath "$DERIVED" build

osascript -e 'quit app "Magneto"' 2>/dev/null || true
sleep 1
rm -rf /Applications/Magneto.app
ditto "$DERIVED/Build/Products/Release/Magneto.app" /Applications/Magneto.app

# Spotlight indexes every .app it finds, so the build copy is removed once
# installed: searching "Magneto" in Finder must return exactly one icon.
# Object files stay in DerivedData, so the next build is still incremental.
rm -rf "$DERIVED/Build/Products/Release/Magneto.app" "$DERIVED/Build/Products/Release/Magneto.app.dSYM"

open /Applications/Magneto.app
echo "Magneto installé dans /Applications et lancé."
