#!/bin/bash
# GitHub Copilot CLI is published to npm. Track npm's stable `latest` tag,
# then hash both inputs the PKGBUILD downloads. AUR is deliberately not part
# of this update path: Omarchy owns the multi-architecture recipe.
set -euo pipefail

REGISTRY_URL="https://registry.npmjs.org/@github%2Fcopilot"
CHANGELOG_BASE="https://raw.githubusercontent.com/github/copilot-cli"

metadata=$(curl -fsSL "$REGISTRY_URL")
version=$(jq -r '."dist-tags".latest // ""' <<<"$metadata")
tarball=$(jq -r --arg version "$version" '.versions[$version].dist.tarball // ""' <<<"$metadata")

if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! $tarball =~ ^https://registry\.npmjs\.org/ ]]; then
  echo "npm returned an unusable Copilot release: version='$version' tarball='$tarball'" >&2
  exit 1
fi

current=$(grep -m1 '^pkgver=' PKGBUILD | cut -d= -f2- | tr -d "\"'")
if [[ $(vercmp "$version" "$current") -le 0 ]]; then
  echo '{}'
  exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
curl -fsSL -o "$work/copilot.tgz" "$tarball"
curl -fsSL -o "$work/changelog.md" "$CHANGELOG_BASE/v${version}/changelog.md"

jq -n \
  --arg pkgver "$version" \
  --arg package_sum "$(sha256sum "$work/copilot.tgz" | cut -d' ' -f1)" \
  --arg changelog_sum "$(sha256sum "$work/changelog.md" | cut -d' ' -f1)" \
  '{pkgver: $pkgver, sha256sums: {any: [$package_sum, $changelog_sum]}}'
