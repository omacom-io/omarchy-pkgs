#!/bin/bash
# Cursor publishes Grok Bot version+commit on the darwin-arm64 sand feed.
# Linux has no feed (linux-x64-user is unknown); the .deb lives at the same
# commit. Darwin can ship first — report {} until the Linux URL is 200 so the
# scheduled sync does not fail the rest of the run.
#
# bin/sync-upstream only rewrites pkgver/pkgrel/sha256sums, so this hook also
# writes _commit into the PKGBUILD. Without that, a later auto-PR would pin a
# new pkgver to the old commit URL.
set -euo pipefail

FEED='https://api2.cursor.sh/updates/api/update/darwin-arm64/sand/0.0.0/00000000-0000-0000-0000-000000000000/stable'

json=$(curl -fsSL -H 'cache-control: no-cache' "$FEED")
ver=$(jq -er '.name // .version' <<<"$json")
feed_url=$(jq -er '.url' <<<"$json")
commit=$(sed -nE 's@.*/(grokbot|sand)/stable/([0-9a-f]{40})/.*@\2@p' <<<"$feed_url")

if [[ -z "$ver" || -z "$commit" ]]; then
  echo "Could not parse version/commit from feed: $json" >&2
  exit 1
fi

current=$(awk -F= '/^pkgver=/ { print $2; exit }' PKGBUILD | tr -d "\"'")
if [[ -n "$current" ]] && command -v vercmp >/dev/null && [[ "$(vercmp "$ver" "$current")" -le 0 ]]; then
  echo '{}'
  exit 0
fi
if [[ -n "$current" && "$ver" == "$current" ]]; then
  echo '{}'
  exit 0
fi

deb_url="https://downloads.cursor.com/grokbot/stable/${commit}/linux/x64/Grok_Bot_${ver}.deb"
code=$(curl -sSIL -o /dev/null -w '%{http_code}' "$deb_url")
if [[ "$code" != "200" ]]; then
  echo "Linux deb not fetchable yet ($code): $deb_url" >&2
  echo '{}'
  exit 0
fi

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
curl -fL --retry 3 -o "$tmp" "$deb_url"
deb_sum=$(sha256sum "$tmp" | awk '{print $1}')
script_sum=$(sha256sum grok-bot.sh | awk '{print $1}')
desktop_sum=$(sha256sum grok-bot.desktop | awk '{print $1}')

if [[ $(grep -c '^_commit=' PKGBUILD) -ne 1 ]]; then
  echo "Expected exactly one _commit= assignment in PKGBUILD" >&2
  exit 1
fi
sed -i "s/^_commit=.*/_commit=${commit}/" PKGBUILD

jq -n \
  --arg pkgver "$ver" \
  --arg deb "$deb_sum" \
  --arg script "$script_sum" \
  --arg desktop "$desktop_sum" \
  '{pkgver: $pkgver, sha256sums: {any: [$deb, $script, $desktop]}}'
