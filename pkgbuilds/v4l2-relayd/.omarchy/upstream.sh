#!/bin/bash
# v4l2-relayd uses GitLab tags named upstream/<version>. Keep Omarchy's local
# patches and follow that authoritative tag stream directly.
set -euo pipefail

REPO="https://gitlab.com/vicamo/v4l2-relayd.git"
best=""
while read -r tag; do
  tag=${tag%\^\{\}}
  [[ $tag =~ ^upstream/([0-9]+\.[0-9]+\.[0-9]+)$ ]] || continue
  version=${BASH_REMATCH[1]}
  if [[ -z $best || $(vercmp "$version" "$best") -gt 0 ]]; then
    best=$version
  fi
done < <(git ls-remote --tags "$REPO" | sed 's#^.*refs/tags/##')

[[ -n $best ]] || { echo "No usable v4l2-relayd upstream tag found" >&2; exit 1; }
current=$(grep -m1 '^pkgver=' PKGBUILD | cut -d= -f2- | tr -d "\"'")
if [[ $(vercmp "$best" "$current") -le 0 ]]; then
  echo '{}'
  exit 0
fi

sum=$(curl -fsSL "https://gitlab.com/vicamo/v4l2-relayd/-/archive/upstream/${best}/v4l2-relayd-upstream-${best}.tar.gz" | sha256sum | cut -d' ' -f1)
jq -n --arg pkgver "$best" --arg sha256 "$sum" \
  '{pkgver: $pkgver, sha256sums: {any: [$sha256, "SKIP", "SKIP"]}}'
