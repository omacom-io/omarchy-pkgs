#!/bin/bash
# Symfony publishes a checksum manifest with every stable GitHub release.
# The `latest` URL is its vendor-maintained stable feed, so no GitHub API or
# AUR state is involved in selecting and verifying the source tarball.
set -euo pipefail

CHECKSUMS_URL="https://github.com/symfony-cli/symfony-cli/releases/latest/download/checksums.txt"
checksums=$(curl -fsSL "$CHECKSUMS_URL")

best=""
best_sum=""
while read -r sum filename; do
  [[ $filename =~ ^symfony-cli-([0-9]+\.[0-9]+\.[0-9]+)\.tar\.gz$ ]] || continue
  version=${BASH_REMATCH[1]}
  [[ $sum =~ ^[0-9a-f]{64}$ ]] || continue
  if [[ -z $best || $(vercmp "$version" "$best") -gt 0 ]]; then
    best=$version
    best_sum=$sum
  fi
done <<<"$checksums"

[[ -n $best ]] || { echo "Symfony's latest checksum manifest names no source tarball" >&2; exit 1; }
current=$(grep -m1 '^pkgver=' PKGBUILD | cut -d= -f2- | tr -d "\"'")
if [[ $(vercmp "$best" "$current") -le 0 ]]; then
  echo '{}'
  exit 0
fi

jq -n --arg pkgver "$best" --arg sha256 "$best_sum" \
  '{pkgver: $pkgver, sha256sums: {any: [$sha256]}}'
