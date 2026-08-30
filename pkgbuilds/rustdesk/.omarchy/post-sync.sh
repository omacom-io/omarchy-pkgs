#!/bin/bash
set -euo pipefail

grep -Fq "arch=('x86_64' 'aarch64')" PKGBUILD || {
  echo 'RustDesk AArch64 recipe patch was not applied' >&2
  exit 1
}

pkgver=$(sed -n "s/^_pkgver='\([^']*\)'/\1/p" PKGBUILD)
[[ -n $pkgver ]] || {
  echo 'RustDesk pkgver could not be read' >&2
  exit 1
}

arm_filename="rustdesk-${pkgver}-0.aarch64.rpm"
grep -Fq '_arm_filename="rustdesk-${_pkgver}-0.aarch64.rpm"' PKGBUILD || {
  echo 'RustDesk AArch64 no longer follows the rustdesk-bin RPM layout' >&2
  exit 1
}
[[ $(grep -Fc "sha256sums_aarch64=('SKIP')" PKGBUILD) -eq 1 ]] || {
  echo 'RustDesk AArch64 checksum placeholder is missing or ambiguous' >&2
  exit 1
}

arm_url="https://github.com/rustdesk/rustdesk/releases/download/${pkgver}/${arm_filename}"
arm_checksum=$(curl -fsSL --retry 3 "$arm_url" | sha256sum | awk '{print $1}')
[[ $arm_checksum =~ ^[0-9a-f]{64}$ ]] || {
  echo 'RustDesk AArch64 checksum could not be computed' >&2
  exit 1
}
sed -i \
  "s/sha256sums_aarch64=('SKIP')/sha256sums_aarch64=('${arm_checksum}')/" \
  PKGBUILD
