#!/bin/bash
set -euo pipefail

repo="jdx/mise"
release=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest")
tag=$(jq -r '.tag_name // empty' <<<"$release")

if [[ ! "$tag" =~ ^v([A-Za-z0-9._+]+)$ ]]; then
  echo "Latest mise release has an invalid tag: ${tag:-<empty>}" >&2
  exit 1
fi

pkgver=${BASH_REMATCH[1]}
checksums=$(curl -fsSL \
  "https://github.com/$repo/releases/download/$tag/SHASUMS256.txt")

checksum_for() {
  local filename=$1
  local checksum
  checksum=$(awk -v filename="./$filename" '$2 == filename { print $1 }' <<<"$checksums")

  if [[ ! "$checksum" =~ ^[0-9a-f]{64}$ ]]; then
    echo "No valid checksum found for $filename in $tag" >&2
    exit 1
  fi

  echo "$checksum"
}

x86_64=$(checksum_for "mise-v${pkgver}-linux-x64.tar.xz")
aarch64=$(checksum_for "mise-v${pkgver}-linux-arm64.tar.xz")

jq -n \
  --arg pkgver "$pkgver" \
  --arg x86_64 "$x86_64" \
  --arg aarch64 "$aarch64" \
  '{pkgver: $pkgver, sha256sums: {x86_64: [$x86_64], aarch64: [$aarch64]}}'
