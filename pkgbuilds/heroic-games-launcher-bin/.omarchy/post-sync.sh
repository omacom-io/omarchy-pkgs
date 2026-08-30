#!/bin/bash
set -euo pipefail

grep -Fq "arch=('x86_64' 'aarch64')" PKGBUILD || {
  echo 'Heroic AArch64 recipe patch was not applied' >&2
  exit 1
}

# The AUR recipe's vendor archive is x86_64-only. Keep its versioned filename,
# URL, and checksum under the architecture-specific arrays supplied by makepkg.
sed -i '0,/^source=(/{s/^source=(/source_x86_64=(/}' PKGBUILD
sed -i '0,/^sha256sums=(/{s/^sha256sums=(/sha256sums_x86_64=(/}' PKGBUILD

# Read the simple scalar assignments without executing the recipe during sync.
read_scalar() {
  local name=$1
  sed -n "s/^${name}=//p" PKGBUILD
}

pkgver=$(read_scalar pkgver)
tag="v${pkgver}"
helper_manifest=$(curl -fsSL --retry 3 \
  "https://raw.githubusercontent.com/Heroic-Games-Launcher/HeroicGamesLauncher/${tag}/meta/downloadHelperBinaries.ts")
declare -A expected=(
  [legendary]="$(read_scalar _legendary_tag)"
  [gogdl]="$(read_scalar _gogdl_tag)"
  [nile]="$(read_scalar _nile_tag)"
  [comet]="$(read_scalar _comet_tag)"
  [epic-integration]="$(read_scalar _epic_integration_tag)"
)
for helper in legendary gogdl nile comet epic-integration; do
  actual=$(sed -n -E \
    "s/^[[:space:]]*'?${helper}'?:[[:space:]]*'([^']+)'.*/\\1/p" \
    <<<"$helper_manifest")
  [[ -n $actual && $actual == "${expected[$helper]}" ]] || {
    echo "Heroic $tag changes the $helper helper tag; audit the PKGBUILD" >&2
    exit 1
  }
done

source_url="https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/archive/refs/tags/${tag}.tar.gz"
source_checksum=$(curl -fsSL --retry 3 "$source_url" | sha256sum | awk '{print $1}')

rewritten=$(mktemp)
awk -v checksum="$source_checksum" '
  /^sha256sums_aarch64=\(/ { in_arm_sums = 1 }
  in_arm_sums && !replaced && /'\''SKIP'\''/ {
    sub(/'\''SKIP'\''/, "'\''" checksum "'\''")
    replaced = 1
  }
  { print }
  in_arm_sums && /^\)/ { in_arm_sums = 0 }
  END { if (!replaced) exit 1 }
' PKGBUILD > "$rewritten"
chmod --reference=PKGBUILD "$rewritten"
mv "$rewritten" PKGBUILD
