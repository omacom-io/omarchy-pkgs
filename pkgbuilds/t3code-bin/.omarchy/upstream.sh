#!/bin/bash
# T3 Code publishes electron-builder's update feed beside every release, so the
# newest version costs one small request. The feed's checksum is a base64
# SHA-512 and makepkg wants hex SHA-256, so a release that is actually new still
# has to be downloaded once to hash -- hence the version check before the fetch.
set -euo pipefail

FEED_URL="https://github.com/pingdotgg/t3code/releases/latest/download/latest-linux.yml"
RELEASE_URL="https://github.com/pingdotgg/t3code/releases/download"

feed=$(curl -fsSL "$FEED_URL")
version=$(awk '/^version:/ { print $2; exit }' <<<"$feed" | tr -d '"'\''')
asset=$(awk '/^path:/ { print $2; exit }' <<<"$feed" | tr -d '"'\''')

if [[ -z "$version" || -z "$asset" ]]; then
  echo "Upstream feed carried no version or asset name" >&2
  exit 1
fi

current=$(awk -F= '/^pkgver=/ { print $2; exit }' PKGBUILD)
if [[ -n "$current" ]] && [[ "$(vercmp "$version" "$current")" -le 0 ]]; then
  echo '{}'
  exit 0
fi

sha256=$(curl -fsSL "$RELEASE_URL/v${version}/${asset}" | sha256sum | cut -d' ' -f1)

jq -n --arg pkgver "$version" --arg sha256 "$sha256" \
  '{pkgver: $pkgver, sha256sums: {x86_64: [$sha256]}}'
