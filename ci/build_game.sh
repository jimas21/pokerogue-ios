#!/usr/bin/env bash
# Builds PokeRogue from the official source at UPSTREAM_REF (a release tag such as v1.12.2.6) and puts the
# finished game in Game/, which the app bundles.
#
# - `build:app` is upstream's own app mode: it includes Import Data / Import Session in Manage Data.
# - VITE_BYPASS_LOGIN=1 plays as a local Guest with saves on the device (no account, no server).
# - VITE_SERVER_URL points at a closed local port, so online-only features fail at once instead of waiting.
# - Events are dated in the source (src/data/balance/timed-events.ts), so each event in this release switches
#   itself on and off by date with no connection.
#
# Inputs: UPSTREAM_REF. Writes upstream/ (source checkout), Game/ and Game/BUILD-INFO.txt.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$here/common.sh"
cd "$here/.."

: "${UPSTREAM_REF:?UPSTREAM_REF is not set}"
[[ "$UPSTREAM_REF" =~ ^v[0-9]+(\.[0-9]+){2,3}$ ]] || die "UPSTREAM_REF must be a release tag like v1.12.2.6 (got $UPSTREAM_REF)."

if [ ! -d upstream/.git ]; then
  git clone --depth 1 --branch "$UPSTREAM_REF" --recurse-submodules --shallow-submodules \
    https://github.com/pagefaultgames/pokerogue.git upstream
fi

pushd upstream >/dev/null
pm="$(node -p "require('./package.json').packageManager")"
npm install -g "$pm"
pnpm install --frozen-lockfile
NODE_ENV=production \
VITE_BYPASS_LOGIN=1 \
VITE_BYPASS_TUTORIAL=0 \
VITE_SERVER_URL=http://127.0.0.1:9 \
  pnpm build:app
upstream_commit="$(git rev-parse HEAD)"
assets_commit="$(git -C assets rev-parse HEAD)"
locales_commit="$(git -C locales rev-parse HEAD)"
popd >/dev/null

rm -rf Game
cp -R upstream/dist Game
# Not needed in the app: the service worker (web views can't run one on an app scheme) and the asset test fixtures.
rm -rf Game/service-worker.js Game/test

for f in index.html asset-manifest.json images audio locales/en; do
  [ -e "Game/$f" ] || die "Built game is missing $f; the upstream build layout may have changed."
done

cat > Game/BUILD-INFO.txt <<INFO
PokeRogue ${UPSTREAM_REF}
source: https://github.com/pagefaultgames/pokerogue (AGPL-3.0-only)
commit: ${upstream_commit}
assets: ${assets_commit}
locales: ${locales_commit}
mode: app, offline (VITE_BYPASS_LOGIN=1)
INFO

echo "Game built: $(du -sh Game | cut -f1), $(find Game -type f | wc -l | tr -d ' ') files."
