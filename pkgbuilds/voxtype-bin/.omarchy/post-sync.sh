#!/bin/bash
set -euo pipefail

grep -Fq "arch=('x86_64' 'aarch64')" PKGBUILD || {
  echo 'Voxtype AArch64 recipe patch was not applied' >&2
  exit 1
}

pkgver=$(sed -n 's/^pkgver=//p' PKGBUILD)
[[ -n $pkgver ]] || {
  echo 'Voxtype pkgver could not be read' >&2
  exit 1
}

source_url="https://github.com/peteonrails/voxtype/archive/refs/tags/v${pkgver}.tar.gz"
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
