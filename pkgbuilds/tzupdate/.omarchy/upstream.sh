#!/bin/bash
# tzupdate publishes version tags but no GitHub Releases. Track its semver
# tags and hash the tagged source archive when a new version appears.
set -euo pipefail

REPO="https://github.com/cdown/tzupdate.git"
best=""
while read -r tag; do
  tag=${tag%\^\{\}}
  [[ $tag =~ ^v?([0-9]+\.[0-9]+\.[0-9]+)$ ]] || continue
  version=${BASH_REMATCH[1]}
  if [[ -z $best || $(vercmp "$version" "$best") -gt 0 ]]; then
    best=$version
  fi
done < <(git ls-remote --tags "$REPO" | sed 's#^.*refs/tags/##')

[[ -n $best ]] || { echo "No usable tzupdate version tag found" >&2; exit 1; }
current=$(grep -m1 '^pkgver=' PKGBUILD | cut -d= -f2- | tr -d "\"'")
if [[ $(vercmp "$best" "$current") -le 0 ]]; then
  echo '{}'
  exit 0
fi

sum=$(curl -fsSL "https://github.com/cdown/tzupdate/archive/refs/tags/${best}.tar.gz" | sha256sum | cut -d' ' -f1)
jq -n --arg pkgver "$best" --arg sha256 "$sum" \
  '{pkgver: $pkgver, sha256sums: {any: [$sha256]}}'
