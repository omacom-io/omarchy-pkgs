#!/bin/bash
set -euo pipefail

ppsspp_upstream_assets_b2=b46c8f4a147f1b8fddb8664982c4568e9cac74afad65cb16adbccaba26b93baf0f59dd51693a422bd64782c4a95cf8e2ff55e848701b2fb1e1e785ca611d1dc6
ppsspp_rebased_assets_b2=d23da7c7b52de9dbc9a72ea05f52071843853f423421bfdbcd56334bcd11d210bc83b177d92b0e752b84be18685f4d78f224cf84c246da271946a3f14e72652d
printf '%s  %s\n' "$ppsspp_upstream_assets_b2" libretro-ppsspp-assets-path.patch |
  b2sum --check --status || {
  echo "ERROR: Upstream PPSSPP assets patch changed" >&2
  exit 1
}
cp .omarchy/libretro-ppsspp-assets-path.patch .

sed -i 's/arch=(x86_64)/arch=(x86_64 aarch64)/' PKGBUILD
cp .omarchy/libretro-ppsspp-linux-arm64-no-adrenotools.patch .
sed -i '/^  libretro-ppsspp-assets-path\.patch$/a\  libretro-ppsspp-linux-arm64-no-adrenotools.patch' PKGBUILD
sed -i "s|'$ppsspp_upstream_assets_b2')|'$ppsspp_rebased_assets_b2'\\n        '33522d817b712f4dbb6f5fc896d0fead3a8f96e879c026d11335eb6cb84092bbab71e392a1beca351749fee0420e92db248c1b943e6d3d9a291c0a50289b0336')|" PKGBUILD
grep -Fq "$ppsspp_rebased_assets_b2" PKGBUILD || {
  echo "ERROR: Could not pin the rebased PPSSPP assets patch" >&2
  exit 1
}
sed -i '/patch -Np1 -i ..\/libretro-ppsspp-assets-path.patch/a\  patch -Np1 -i ../libretro-ppsspp-linux-arm64-no-adrenotools.patch' PKGBUILD
sed -i '/^build() {/a\  local make_options=()\n  [[ $CARCH != aarch64 ]] || make_options+=(platform=arm64)' PKGBUILD
sed -i 's|make -C libretro-ppsspp/libretro$|make -C libretro-ppsspp/libretro "${make_options[@]}"|' PKGBUILD
