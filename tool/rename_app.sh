#!/usr/bin/env bash
# Renames the app id and the visible app name.
# Usage (from the project root):  bash tool/rename_app.sh bd.medivo.app
# Use your own reverse-domain id. It must be unique on the stores.
set -euo pipefail

NEW_ID="${1:-}"
if [[ -z "$NEW_ID" ]]; then
  echo "Usage: bash tool/rename_app.sh <new.app.id>   (for example bd.medivo.app)"
  exit 1
fi
if [[ ! "$NEW_ID" =~ ^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$ ]]; then
  echo "The id must use lower case letters, digits, underscores and dots, for example bd.medivo.app"
  exit 1
fi

GRADLE="android/app/build.gradle.kts"
if [[ ! -f "$GRADLE" ]]; then
  echo "Run this from the project root (the folder that contains android/ and ios/)."
  exit 1
fi

OLD_ID="$(grep -E 'applicationId *= *"' "$GRADLE" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
if [[ -z "$OLD_ID" ]]; then
  echo "Could not find the current applicationId in $GRADLE"
  exit 1
fi
if [[ "$OLD_ID" == "$NEW_ID" ]]; then
  echo "The app id is already $NEW_ID. Nothing to change."
  exit 0
fi

echo "Changing $OLD_ID to $NEW_ID"

# 1. The id inside every platform file that holds it.
FILES="$(grep -rIl --exclude-dir=build --exclude-dir=.dart_tool --exclude-dir=Pods \
  --exclude-dir=.gradle -F "$OLD_ID" android ios macos linux windows 2>/dev/null || true)"
for f in $FILES; do
  perl -pi -e "s/\Q$OLD_ID\E/$NEW_ID/g" "$f"
  echo "  updated $f"
done

# 2. Move the Kotlin file to the matching folder.
OLD_DIR="android/app/src/main/kotlin/${OLD_ID//./\/}"
NEW_DIR="android/app/src/main/kotlin/${NEW_ID//./\/}"
if [[ -d "$OLD_DIR" ]]; then
  mkdir -p "$NEW_DIR"
  mv "$OLD_DIR"/*.kt "$NEW_DIR"/
  find android/app/src/main/kotlin -type d -empty -delete
  echo "  moved MainActivity to $NEW_DIR"
fi

# 3. The name people see.
if [[ -f android/app/src/main/AndroidManifest.xml ]]; then
  perl -pi -e 's/android:label="[^"]*"/android:label="MEDIVO"/' android/app/src/main/AndroidManifest.xml
fi
if [[ -f ios/Runner/Info.plist ]]; then
  perl -0pi -e 's|(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)|${1}MEDIVO${2}|' ios/Runner/Info.plist
  perl -0pi -e 's|(<key>CFBundleName</key>\s*<string>)[^<]*(</string>)|${1}MEDIVO${2}|' ios/Runner/Info.plist
fi
if [[ -f web/index.html ]]; then
  perl -pi -e 's|<title>[^<]*</title>|<title>MEDIVO</title>|; s|(apple-mobile-web-app-title" content=")[^"]*"|${1}MEDIVO"|' web/index.html
fi
if [[ -f web/manifest.json ]]; then
  perl -pi -e 's|("name": )"[^"]*"|${1}"MEDIVO"|; s|("short_name": )"[^"]*"|${1}"MEDIVO"|' web/manifest.json
fi

echo
echo "Done. Now run:"
echo "  flutter clean && flutter pub get"
echo "  flutter analyze && flutter test"
echo "  git diff --stat    # check what changed before you commit"
echo
echo "Note: this is a new app identity. Remove the old app from your phone or simulator first."