#!/bin/bash
set -euo pipefail

mapfile -t hashes < <(
  sed -n '/^sha256sums=(/,/)/p' PKGBUILD | grep -oE '[0-9a-f]{64}'
)
(( ${#hashes[@]} == 3 )) || {
  echo "ERROR: expected three LM Studio source checksums" >&2
  exit 1
}

vendor_pkgrel=$(sed -n 's/^pkgrel=//p' PKGBUILD)
grep -Fxq '_pkgver=${pkgver}-${pkgrel}' PKGBUILD || {
  echo 'ERROR: LM Studio vendor version baseline changed' >&2
  exit 1
}
sed -i "s/^_pkgver=.*/_vendor_pkgrel=${vendor_pkgrel}\n_pkgver=\${pkgver}-\${_vendor_pkgrel}/" PKGBUILD

sed -i "s/arch=('x86_64')/arch=('x86_64' 'aarch64')/" PKGBUILD
sed -i '/^source=(/,/lmstudio.desktop")$/c\source=(\n  "lmstudio.png"\n  "lmstudio.desktop"\n)\nsource_x86_64=("LM-Studio.AppImage::https://installers.lmstudio.ai/linux/x64/${_pkgver}/LM-Studio-${_pkgver}-x64.AppImage")\nsource_aarch64=("LM-Studio.AppImage::https://installers.lmstudio.ai/linux/arm64/${_pkgver}/LM-Studio-${_pkgver}-arm64.AppImage")' PKGBUILD
sed -i "/^sha256sums=(/,/)/c\\sha256sums=(\\n  '${hashes[1]}'\\n  '${hashes[2]}'\\n)\\nsha256sums_x86_64=('${hashes[0]}')\\nsha256sums_aarch64=('SKIP')" PKGBUILD
sed -i 's|${source\[0\]##\*/}|LM-Studio.AppImage|g' PKGBUILD

pkgver=$(sed -n 's/^pkgver=//p' PKGBUILD)
arm_url="https://installers.lmstudio.ai/linux/arm64/${pkgver}-${vendor_pkgrel}/LM-Studio-${pkgver}-${vendor_pkgrel}-arm64.AppImage"
arm_checksum=$(curl -fsSL --retry 3 "$arm_url" | sha256sum | awk '{ print $1 }')
sed -i "s/sha256sums_aarch64=('SKIP')/sha256sums_aarch64=('${arm_checksum}')/" PKGBUILD
