#!/usr/bin/env bash
# Wraps an already assembled packaging/Pesty.app into a distributable DMG.
#
# Unlike sign_notarize.sh this does no Developer ID work, so it runs anywhere -
# including a CI runner with no certificates - and is what the GitHub Actions
# release job falls back to when the signing secrets are not configured. The
# app is left with whatever signature build_app.sh gave it (ad-hoc), which is
# enough to run locally but is not notarized, so downloaders have to clear the
# quarantine flag themselves.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
APP="packaging/Pesty.app"
DMG="packaging/Pesty-$VERSION.dmg"

[ -d "$APP" ] || { echo "Missing $APP - run build_app.sh first" >&2; exit 1; }

echo "==> Staging $APP"
rm -f "$DMG"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
# ditto keeps the resource forks, extended attributes and code signature intact;
# cp -R is enough for the bundle itself but not for the signature's xattrs.
/usr/bin/ditto "$APP" "$STAGE/Pesty.app"
ln -s /Applications "$STAGE/Applications"

echo "==> Building $DMG"
hdiutil create -volname "Pesty" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
hdiutil verify "$DMG"

echo "==> Signature carried into the DMG"
codesign --verify --strict --verbose=2 "$STAGE/Pesty.app" 2>&1 | sed 's/^/    /'

shasum -a 256 "$DMG"
echo "==> Done: $DMG"
