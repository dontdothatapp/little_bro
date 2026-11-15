#!/bin/bash
# Builds Little Bro, installs it into ~/Applications and (re)starts it.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh
DEST="$HOME/Applications/Little Bro.app"
mkdir -p "$HOME/Applications"
pkill -x LittleBro 2>/dev/null && sleep 0.5 || true
rm -rf "$DEST"
# Install the clean, signed copy without carrying over any extended attributes.
ditto --noextattr --noqtn "$(cat build/.staged-app)" "$DEST"
codesign --verify --strict "$DEST"
open "$DEST"
echo "Installed and launched $DEST"
