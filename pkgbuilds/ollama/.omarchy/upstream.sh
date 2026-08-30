#!/bin/bash
set -euo pipefail

release=$(curl -fsSL https://api.github.com/repos/ollama/ollama/releases/latest)
version=$(jq -r '.tag_name | sub("^v"; "")' <<< "$release")
published_at=$(jq -r '.published_at' <<< "$release")
current=$(sed -n 's/^pkgver=//p' PKGBUILD)

if [[ -z $version || $version == null || $(vercmp "$version" "$current") -le 0 ]]; then
  echo '{}'
  exit 0
fi

assets=(
  ollama-linux-arm64.tar.zst
  ollama-linux-arm64-jetpack5.tar.zst
  ollama-linux-arm64-jetpack6.tar.zst
)
checksums=()
for asset in "${assets[@]}"; do
  digest=$(jq -r --arg name "$asset" \
    '.assets[] | select(.name == $name) | .digest // ""' <<< "$release")
  [[ $digest =~ ^sha256:([0-9a-f]{64})$ ]] || {
    echo "Ollama Release is missing a SHA256 digest for $asset" >&2
    exit 1
  }
  checksums+=("${BASH_REMATCH[1]}")
done

jq -n \
  --arg pkgver "$version" \
  --arg published_at "$published_at" \
  --arg c0 "${checksums[0]}" --arg c1 "${checksums[1]}" --arg c2 "${checksums[2]}" \
  '{pkgver: $pkgver, published_at: $published_at, sha256sums: {aarch64: [$c0, $c1, $c2]}}'
