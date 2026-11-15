#!/bin/bash
# Builds "build/Little Bro.app" (release) and signs it.
# Ad-hoc by default. To keep macOS permission grants (e.g. browser automation) across
# rebuilds, sign with your own identity — the first time macOS asks to allow keychain access:
#   LITTLEBRO_SIGN_IDENTITY="Apple Development" ./scripts/build-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product LittleBro
# Assemble and sign outside the project folder: synced folders (iCloud Desktop & Documents)
# stamp metadata onto files, which breaks the signature.
STAGE="${TMPDIR:-/tmp}/littlebro-build"
APP="$STAGE/Little Bro.app"
mkdir -p "$STAGE"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/LittleBro "$APP/Contents/MacOS/LittleBro"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

IDENTITY="${LITTLEBRO_SIGN_IDENTITY:-}"
if [ -n "$IDENTITY" ] && ! [[ "$IDENTITY" =~ ^[0-9A-Fa-f]{40}$ ]]; then
  # A name can match several certificates (e.g. different teams). Never guess: list them
  # with their team and ask for the exact one (its SHA-1 fingerprint).
  MATCHES=$(security find-identity -v -p codesigning | grep -F "\"$IDENTITY" | awk '{print $2}' | sort -u)
  if [ "$(echo "$MATCHES" | grep -c .)" -gt 1 ]; then
    echo "\"$IDENTITY\" matches more than one certificate:"
    for h in $MATCHES; do
      TEAM=$(security find-certificate -a -Z -c "$IDENTITY" -p 2>/dev/null \
        | awk -v h="$h" '/SHA-1 hash:/{keep=($3==h)} keep && /BEGIN CERT/{p=1} p{print} /END CERT/{if(p){p=0; exit}}' \
        | openssl x509 -noout -subject -nameopt sep_multiline 2>/dev/null \
        | awk -F= '/ O=/{o=$2} / OU=/{ou=$2} END{print o " (team " ou ")"}')
      echo "  $h  $TEAM"
    done
    echo "Pick one: LITTLEBRO_SIGN_IDENTITY=<fingerprint> ./scripts/install.sh"
    exit 1
  fi
fi
# Extended attributes (Finder info, provenance…) on bundle files make the signature fail strict checks.
xattr -cr "$APP"
codesign --force --sign "${IDENTITY:--}" "$APP" >/dev/null
codesign --verify --strict "$APP"
# A convenience copy in build/ (inside a synced folder it may pick up metadata again;
# install.sh installs from the clean staged copy).
mkdir -p build
rm -rf "build/Little Bro.app"
ditto --noextattr --noqtn "$APP" "build/Little Bro.app"
echo "$APP" > build/.staged-app
echo "Built $APP (signed with ${IDENTITY:-ad-hoc})"
