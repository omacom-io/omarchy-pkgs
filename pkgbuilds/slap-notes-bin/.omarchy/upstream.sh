#!/bin/bash
# Slap Notes publishes SHA256SUMS beside every release, so the new version and
# its checksum both come from the release feed and nothing has to be downloaded
# to hash it.
set -euo pipefail

REPO="Onefailatatime/slap-notes"

release=$(curl -fsSL -H 'Accept: application/vnd.github+json' \
  "https://api.github.com/repos/${REPO}/releases/latest")
version=$(jq -r '.tag_name // ""' <<<"$release" | sed 's/^v//')

if [[ -z "$version" ]]; then
  echo "Upstream feed carried no version" >&2
  exit 1
fi

current=$(awk -F= '/^pkgver=/ { print $2; exit }' PKGBUILD)
if [[ -n "$current" ]] && [[ "$(vercmp "$version" "$current")" -le 0 ]]; then
  echo '{}'
  exit 0
fi

asset="slap-notes-${version}-linux-x64.tar.zst"

# The checksums file is published with the release, so a rename upstream shows
# up as a missing line here rather than as a checksum pinned to a URL that will
# never be fetched.
sums=$(curl -fsSL "https://github.com/${REPO}/releases/download/${version}/SHA256SUMS")
sha256=$(awk -v a="$asset" '$2 == a { print $1; exit }' <<<"$sums")

if [[ -z "$sha256" ]]; then
  echo "Release ${version} has no checksum for ${asset}" >&2
  exit 1
fi

jq -n --arg pkgver "$version" --arg sha256 "$sha256" \
  '{pkgver: $pkgver, sha256sums: {x86_64: [$sha256]}}'
