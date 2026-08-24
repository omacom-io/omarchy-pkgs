#!/bin/bash
set -euo pipefail

repo="jdx/mise"

# Keep a compromised mise release from reaching Omarchy before there has been
# time for maintainers and the community to notice and pull it. The window
# comes from min_release_age in .omarchy/package.json, exported by
# bin/sync-upstream as MIN_RELEASE_AGE_SECONDS. Walking the release list
# instead of gating on /releases/latest alone means mise's near-daily cadence
# cannot starve updates: the newest release that has finished its quarantine
# ships even while an even newer one is still inside it. Nothing younger than
# the window ever ships without the explicit BYPASS_MIN_RELEASE_AGE=1 bypass,
# which bin/sync-upstream honors too.
minimum_release_age_seconds=${MIN_RELEASE_AGE_SECONDS:-0}
now=$(date +%s)

releases=$(curl -fsSL "https://api.github.com/repos/$repo/releases?per_page=20")

candidates=0
best_tag=""
best_pkgver=""
best_published_at=""
while IFS=$'\t' read -r tag published_at; do
  if [[ ! "$tag" =~ ^v([A-Za-z0-9._+]+)$ ]]; then
    echo "mise release has an invalid tag: ${tag:-<empty>}" >&2
    exit 1
  fi
  pkgver=${BASH_REMATCH[1]}

  if [[ -z "$published_at" ]] || ! published_epoch=$(date --date="$published_at" +%s); then
    echo "mise release $tag has an invalid published_at: ${published_at:-<empty>}" >&2
    exit 1
  fi
  candidates=$((candidates + 1))

  if (( now - published_epoch < minimum_release_age_seconds )); then
    if [[ "${BYPASS_MIN_RELEASE_AGE:-}" == "1" ]]; then
      echo "Bypassing mise release-age gate for $tag" >&2
    else
      continue
    fi
  fi

  if [[ -z "$best_pkgver" ]] || [[ "$(vercmp "$pkgver" "$best_pkgver")" -gt 0 ]]; then
    best_tag=$tag
    best_pkgver=$pkgver
    best_published_at=$published_at
  fi
done < <(jq -r '.[] | select((.draft or .prerelease) | not) | [.tag_name // empty, .published_at // empty] | @tsv' <<<"$releases")

if (( candidates == 0 )); then
  echo "No stable mise releases found in the release feed" >&2
  exit 1
fi

if [[ -z "$best_tag" ]]; then
  echo "Every recent mise release is still inside the release-age quarantine; skipping" >&2
  echo '{}'
  exit 0
fi

tag=$best_tag
pkgver=$best_pkgver
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
  --arg published_at "$best_published_at" \
  --arg x86_64 "$x86_64" \
  --arg aarch64 "$aarch64" \
  '{pkgver: $pkgver, published_at: $published_at, sha256sums: {x86_64: [$x86_64], aarch64: [$aarch64]}}'
