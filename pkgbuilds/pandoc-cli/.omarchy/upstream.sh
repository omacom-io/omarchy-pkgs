#!/bin/bash

set -euo pipefail

releases=$(curl -fsSL --retry 3 \
  'https://api.github.com/repos/jgm/pandoc/releases?per_page=100')
now=$(date +%s)
min_age=${MIN_RELEASE_AGE_SECONDS:-0}
bypass=${BYPASS_MIN_RELEASE_AGE:-0}

release=$(jq -c \
  --argjson now "$now" \
  --argjson min_age "$min_age" \
  --arg bypass "$bypass" '
  [
    .[]
    | select(.draft == false and .prerelease == false)
    | select($bypass == "1" or ($now - (.published_at | fromdateiso8601)) >= $min_age)
    | .tag_name as $version
    | .published_at as $published_at
    | .assets[]?
    | select(.name == "pandoc-\($version)-linux-arm64.tar.gz")
    | select((.digest // "") | startswith("sha256:"))
    | {
        pkgver: $version,
        published_at: $published_at,
        sha256sums: {aarch64: [(.digest | sub("^sha256:"; ""))]}
      }
  ]
  | first // empty
' <<<"$releases")

[[ -n $release ]] || {
  echo 'No stable, aged Pandoc release with a verified Linux ARM64 archive was found' >&2
  exit 1
}

printf '%s\n' "$release"
