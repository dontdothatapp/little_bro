#!/bin/bash
# Builds Little Bro, installs it into ~/Applications and (re)starts it.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh
DEST="$HOME/Applications/Little Bro.app"
mkdir -p "$HOME/Applications"
pkill -x LittleBro 2>/dev/null && sleep 0.5 || true
rm -rf "$DEST"
cp -R "build/Little Bro.app" "$DEST"
open "$DEST"
echo "Installed and launched $DEST"
