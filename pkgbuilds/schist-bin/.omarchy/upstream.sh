#!/bin/bash
# Schist ships pacman-format payloads as GitHub release assets, and GitHub's
# release API reports a SHA-256 digest for every asset, so an update costs one
# small request and never downloads the 35 MB packages themselves.
#
# The asset name embeds upstream's own package release (the PKGBUILD's
# _relver), which only moves when the packaging is re-cut under a version
# that has already shipped. This hook can only rewrite pkgver and the
# checksum arrays, so a release whose payloads carry a different release
# number stops the sync rather than pinning checksums to an asset name the
# build would then fail to fetch.
set -euo pipefail

REPO="Infrawrench/schist"
ARCHES=(x86_64 aarch64)

current=$(grep -m1 '^pkgver=' PKGBUILD | cut -d= -f2- | tr -d "\"'")
relver=$(grep -m1 '^_relver=' PKGBUILD | cut -d= -f2- | tr -d "\"'")
if [[ ! $relver =~ ^[0-9]+$ ]]; then
  echo "PKGBUILD carries no numeric _relver" >&2
  exit 1
fi

curl_args=(-fsSL -H 'Accept: application/vnd.github+json')
[[ -n ${GITHUB_TOKEN:-} ]] && curl_args+=(-H "Authorization: Bearer $GITHUB_TOKEN")
releases=$(curl "${curl_args[@]}" "https://api.github.com/repos/$REPO/releases?per_page=100")

# Newest published, non-prerelease vX.Y.Z tag by vercmp's ordering, which is
# what bin/sync-upstream and pacman both use. A release younger than the
# quarantine window (MIN_RELEASE_AGE_SECONDS, when the package sets one) is
# passed over for the newest one that has cleared it.
min_age=${MIN_RELEASE_AGE_SECONDS:-0}
now=$(date -u +%s)
best_version="" best_release=""
while IFS=$'\t' read -r tag published_at; do
  [[ $tag =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]] || continue
  version=${BASH_REMATCH[1]}
  published_epoch=$(date --date="$published_at" +%s 2>/dev/null) || {
    echo "Release $tag has an unusable published_at: '$published_at'" >&2
    exit 1
  }
  (( now - published_epoch >= min_age )) || continue
  if [[ -z $best_version ]] || (( $(vercmp "$version" "$best_version") > 0 )); then
    best_version=$version
    best_release=$tag
  fi
done < <(jq -r '.[] | select(.draft == false and .prerelease == false) | [.tag_name, .published_at] | @tsv' <<<"$releases")

if [[ -z $best_version ]]; then
  echo "No usable release found for $REPO" >&2
  exit 1
fi

if [[ -n $current ]] && (( $(vercmp "$best_version" "$current") <= 0 )); then
  echo '{}'
  exit 0
fi

release=$(jq --arg tag "$best_release" '.[] | select(.tag_name == $tag)' <<<"$releases")
published_at=$(jq -r '.published_at' <<<"$release")

declare -A checksums=()
for arch in "${ARCHES[@]}"; do
  # Every payload for this arch, whatever its release number: a payload
  # under another number means _relver has to be edited by hand first.
  mapfile -t names < <(jq -r --arg prefix "schist-$best_version-" --arg suffix "-$arch.pkg.tar.zst" \
    '.assets[].name | select(startswith($prefix) and endswith($suffix))' <<<"$release")
  expected="schist-$best_version-$relver-$arch.pkg.tar.zst"
  found=false
  for name in "${names[@]}"; do
    if [[ $name == "$expected" ]]; then
      found=true
    else
      echo "Release $best_release ships $name, but the PKGBUILD's _relver=$relver expects $expected" >&2
      exit 1
    fi
  done
  if [[ $found != true ]]; then
    # The release workflow uploads one architecture at a time; report no
    # update until both payloads have landed and the next run picks it up.
    echo "Release $best_release has no $expected yet; skipping" >&2
    echo '{}'
    exit 0
  fi
  digest=$(jq -r --arg name "$expected" '.assets[] | select(.name == $name) | .digest // empty' <<<"$release")
  if [[ ! $digest =~ ^sha256:([0-9a-f]{64})$ ]]; then
    echo "Asset $expected reports no SHA-256 digest ('$digest')" >&2
    exit 1
  fi
  checksums[$arch]=${BASH_REMATCH[1]}
done

jq -n \
  --arg pkgver "$best_version" \
  --arg published_at "$published_at" \
  --arg x86_64 "${checksums[x86_64]}" \
  --arg aarch64 "${checksums[aarch64]}" \
  '{pkgver: $pkgver, published_at: $published_at, sha256sums: {x86_64: [$x86_64], aarch64: [$aarch64]}}'
