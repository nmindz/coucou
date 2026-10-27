#!/usr/bin/env bash
# Builds Coucou the way it runs every day (DebugCloud: signed with the Apple Development
# certificate, iPhone link on) and makes it the only Coucou: installed in /Applications,
# the copies left by earlier builds removed.
#
# Why: macOS gives its permissions (Accessibility, Screen Recording, microphone...) to one
# app signed one way. An unsigned Debug build looks like a new app after every build, and
# each copy of Coucou.app is one more entry to allow. One signed app at one place keeps
# its permissions from one build to the next.
#
#   ./scripts/dev-install.sh
#
# Use it instead of xcodebuild by hand or ▶ in Xcode (which leave copies in DerivedData).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_ID="fr.louisraille.NotchBuddy"
DERIVED="${HOME}/Library/Developer/Xcode/DerivedData/CoucouDev"
BUILT="${DERIVED}/Build/Products/DebugCloud/Coucou.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

# The App Store Coucou (fr.louisraille.Coucou) has the same file name: never overwrite it.
TARGET="/Applications/Coucou.app"
if [ -d "${TARGET}" ]; then
  EXISTING=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "${TARGET}/Contents/Info.plist" 2>/dev/null || echo "")
  if [ "${EXISTING}" != "${BUNDLE_ID}" ]; then
    mkdir -p "${HOME}/Applications"
    TARGET="${HOME}/Applications/Coucou.app"
    echo "/Applications/Coucou.app is another Coucou (${EXISTING}): installing in ~/Applications instead."
  fi
fi

cd "${REPO_ROOT}/NotchBuddy"
xcodegen >/dev/null

# Plain Debug has no iCloud entitlements, so any Apple Development certificate can sign it.
TEAM="256AUJ9555"
if security find-identity -p codesigning -v | grep -q "(${TEAM})"; then
  echo "Building (DebugCloud)..."
  xcodebuild -scheme NotchBuddyCloud -configuration DebugCloud -allowProvisioningUpdates \
    -derivedDataPath "${DERIVED}" -quiet build
else
  IDENTITY="${COUCOU_SIGN_IDENTITY:-$(security find-identity -p codesigning -v \
    | sed -nE 's/.*"(Apple Development: [^"]+)".*/\1/p' | head -1)}"
  if [ -z "${IDENTITY}" ]; then
    echo "No ${TEAM} or Apple Development certificate in the keychain; set COUCOU_SIGN_IDENTITY." >&2
    exit 1
  fi
  OWN_TEAM="$(security find-certificate -c "${IDENTITY}" -p | openssl x509 -noout -subject \
    | sed -nE 's/.*OU ?= ?([A-Z0-9]{10}).*/\1/p')"
  echo "Building (Debug, signed by ${IDENTITY}; no iPhone link)..."
  xcodebuild -scheme NotchBuddy -configuration Debug -derivedDataPath "${DERIVED}" -quiet \
    CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="${IDENTITY}" DEVELOPMENT_TEAM="${OWN_TEAM}" build
  BUILT="${DERIVED}/Build/Products/Debug/Coucou.app"
  # Missing audio-input = macOS denies the mic with no prompt (voice toggle stays greyed out).
  codesign --force --options runtime --timestamp=none --sign "${IDENTITY}" \
    --entitlements Resources/Coucou.entitlements "${BUILT}"
fi

echo "Quitting Coucou..."
osascript -e "tell application id \"${BUNDLE_ID}\" to quit" >/dev/null 2>&1 || true
for _ in 1 2 3 4 5; do pgrep -x Coucou >/dev/null || break; sleep 1; done
pkill -x Coucou 2>/dev/null || true

# Permissions are tied to the signer: a new one leaves stale grants, so reset them.
OLD_REQ="$(codesign -d -r- "${TARGET}" 2>/dev/null | sed -n 's/^designated => //p')"
NEW_REQ="$(codesign -d -r- "${BUILT}" 2>/dev/null | sed -n 's/^designated => //p')"

echo "Installing in ${TARGET}..."
rm -rf "${TARGET}"
ditto "${BUILT}" "${TARGET}"

if [ -n "${OLD_REQ}" ] && [ "${OLD_REQ}" != "${NEW_REQ}" ]; then
  echo "Signature changed: resetting Coucou's permissions; macOS asks for them again."
  for service in Accessibility Microphone SpeechRecognition ScreenCapture AudioCapture AppleEvents AddressBook ListenEvent PostEvent; do
    tccutil reset "${service}" "${BUNDLE_ID}" >/dev/null 2>&1 || true
  done
fi

# The build stays in DerivedData for the next (incremental) build, but macOS must not
# count it as another Coucou. Copies from Xcode's own builds (▶, xcodebuild by hand) go.
"${LSREGISTER}" -u "${BUILT}" >/dev/null 2>&1 || true
for old in "${HOME}"/Library/Developer/Xcode/DerivedData/NotchBuddy-*/Build/Products/*/Coucou.app; do
  [ -d "$old" ] || continue
  "${LSREGISTER}" -u "$old" >/dev/null 2>&1 || true
  rm -rf "$old"
  echo "Removed an old build: $old"
done
"${LSREGISTER}" -f "${TARGET}" >/dev/null 2>&1 || true

# Launch arguments override saved preferences for this launch only; `<false/>` is a plist Bool
# (a bare NO would arrive as a string).
if [ "${COUCOU_BACKGROUND:-}" = "1" ]; then
  open -g "${TARGET}" --args -coucouOpenAtLaunch '<false/>'
else
  open "${TARGET}"
fi
echo "Coucou is running from ${TARGET}."
