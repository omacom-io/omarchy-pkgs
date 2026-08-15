#!/bin/bash
# OpenAI ships the ChatGPT desktop app from its own Debian repository. The
# per-architecture package index carries both the version and the SHA256 of
# every deb, so an update costs two small HTTP requests instead of a 750 MB
# download, and the pool keeps old versions, so the URLs pinned in the PKGBUILD
# stay resolvable after the next release.
set -euo pipefail

BASE_URL="https://persistent.oaistatic.com/codex-app-prod/linux/deb"
declare -A DEB_ARCHES=([x86_64]=amd64 [aarch64]=arm64)

# Print "<version> <sha256>" for the newest stanza in a Packages index.
newest_release() {
  local index="$1"

  awk '
    { sub(/\r$/, "") }
    /^Version:/ { version = $2 }
    /^SHA256:/  { sha256 = $2 }
    /^$/        { if (version && sha256) print version, sha256; version = sha256 = "" }
    END         { if (version && sha256) print version, sha256 }
  ' <<<"$index" | sort -V | tail -n 1
}

versions=()
declare -A checksums=()

for arch in "${!DEB_ARCHES[@]}"; do
  index=$(curl -fsSL "$BASE_URL/dists/stable/main/binary-${DEB_ARCHES[$arch]}/Packages")

  read -r version sha256 <<<"$(newest_release "$index")"
  if [[ -z "${version:-}" || -z "${sha256:-}" ]]; then
    echo "No usable release found for $arch in the upstream package index" >&2
    exit 1
  fi

  versions+=("$version")
  checksums[$arch]="$sha256"
done

# A release lands one architecture at a time, and a single pkgver has to cover
# both. Report no update until they agree; the next run picks it up.
for version in "${versions[@]}"; do
  if [[ "$version" != "${versions[0]}" ]]; then
    echo "Upstream architectures are mid-release (${versions[*]}); skipping" >&2
    echo '{}'
    exit 0
  fi
done

jq -n \
  --arg pkgver "${versions[0]}" \
  --arg x86_64 "${checksums[x86_64]}" \
  --arg aarch64 "${checksums[aarch64]}" \
  '{pkgver: $pkgver, sha256sums: {x86_64: [$x86_64], aarch64: [$aarch64]}}'
