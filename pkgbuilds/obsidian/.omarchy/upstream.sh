#!/bin/bash

set -euo pipefail

# GitHub's newest Obsidian release can be mobile-only. Select the newest stable
# release that actually carries the official Linux ARM64 desktop tarball.
releases=$(curl -fsSL --retry 3 \
  'https://api.github.com/repos/obsidianmd/obsidian-releases/releases?per_page=100')

release=$(jq -c '
  [
    .[]
    | select(.draft == false and .prerelease == false)
    | (.tag_name | sub("^v"; "")) as $version
    | .assets[]?
    | select(.name == "obsidian-\($version)-arm64.tar.gz")
    | select((.digest // "") | startswith("sha256:"))
    | {
        pkgver: $version,
        published_at: .created_at,
        sha256sums: {aarch64: [(.digest | sub("^sha256:"; ""))]}
      }
  ]
  | first // empty
' <<<"$releases")

[[ -n $release ]] || {
  echo 'No stable Obsidian desktop release with a verified ARM64 tarball was found' >&2
  exit 1
}

printf '%s\n' "$release"
