#!/usr/bin/env bash
# Generates the Xcode project and archives it unsigned. Signing happens once, at export, with Apple's
# cloud-managed distribution certificate (signing the archive made a new development certificate on every
# fresh runner, and the account's certificate limit filled up).
#
# Version shown in TestFlight: the PokeRogue release it was built from, e.g. v1.12.2.6 -> 1.12.2 (Apple allows
# three numbers; the full tag is in the build summary and in Game/BUILD-INFO.txt). Build number: the run number.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$here/common.sh"
cd "$here/.."

for name in BUNDLE_ID TEAM_ID ASC_KEY_PATH ASC_KEY_ID ASC_ISSUER_ID GITHUB_RUN_NUMBER UPSTREAM_REF; do
  [ -n "${!name:-}" ] || die "$name is not set"
done
test -f Game/index.html || die "Game/ is missing; ci/build_game.sh must run first."
test -f App/Assets.xcassets/AppIcon.appiconset/AppIcon.png || die "App icon is missing; ci/make_icon.py must run first."

marketing="$(echo "${UPSTREAM_REF#v}" | cut -d. -f1-3)"
[[ "$marketing" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Could not make a version from $UPSTREAM_REF"

asc_auth_flags
mkdir -p build

hints() {
  echo "::error::Archive failed. Last error lines from build/archive.log:" >&2
  grep -E 'error:|ARCHIVE FAILED|Cloud signing|No Accounts|No profiles|provisioning' build/archive.log | tail -n 25 >&2 || true
  cat >&2 <<'MSG'

Likely causes, in order:
  1. A Swift compile error (the lines above say "error:").
  2. The API key's Access is not Admin ("Cloud signing permission error").
  3. The bundle ID is not registered, or BUNDLE_ID differs from the registered one.
  4. TEAM_ID is wrong (must match the team that owns the bundle ID and the key).
  5. A network blip that looks like an auth error ("No Accounts with App Store Connect Access"): re-run.
MSG
}
trap hints ERR

echo "Version $marketing (build $GITHUB_RUN_NUMBER) from PokeRogue $UPSTREAM_REF"
xcodegen generate

xcodebuild \
  -project PokeRogue.xcodeproj \
  -scheme PokeRogue \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/PokeRogue.xcarchive \
  "${ASC_AUTH[@]}" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGNING_ALLOWED=NO \
  MARKETING_VERSION="$marketing" \
  CURRENT_PROJECT_VERSION="$GITHUB_RUN_NUMBER" \
  archive 2>&1 | tee build/archive.log

trap - ERR
test -d build/PokeRogue.xcarchive || die "xcodebuild reported success but build/PokeRogue.xcarchive is missing."
echo "Archive OK."
