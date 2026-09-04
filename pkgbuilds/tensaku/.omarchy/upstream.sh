#!/bin/bash
# Tensaku publishes semver tags but no source checksum manifest. Select the
# newest tag using pacman's ordering and hash its source archive.
set -euo pipefail

REPO="https://github.com/jondkinney/tensaku.git"
version=""
while read -r tag; do
  tag=${tag%\^\{\}}
  [[ $tag =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]] || continue
  candidate=${BASH_REMATCH[1]}
  if [[ -z $version || $(vercmp "$candidate" "$version") -gt 0 ]]; then
    version=$candidate
  fi
done < <(git ls-remote --tags "$REPO" | sed 's#^.*refs/tags/##')

[[ -n $version ]] || { echo "No usable Tensaku version tag found" >&2; exit 1; }
current=$(grep -m1 '^pkgver=' PKGBUILD | cut -d= -f2- | tr -d "\"'")
if [[ $(vercmp "$version" "$current") -le 0 ]]; then
  echo '{}'
  exit 0
fi

sum=$(curl -fsSL "https://github.com/jondkinney/tensaku/archive/refs/tags/v${version}.tar.gz" | sha256sum | cut -d' ' -f1)
jq -n --arg pkgver "$version" --arg sha256 "$sum" \
  '{pkgver: $pkgver, sha256sums: {any: [$sha256]}}'
