#!/bin/bash
set -euo pipefail

sed -i 's/arch=(x86_64)/arch=(x86_64 aarch64)/' PKGBUILD
cp .omarchy/patches/desmume-arm64-build-fix.patch .

sed -i '/^build() {/a\  local make_options=()\n  [[ $CARCH != aarch64 ]] || make_options+=(platform=arm64-unix)' PKGBUILD
sed -i 's|-f Makefile.libretro$|-f Makefile.libretro "${make_options[@]}"|' PKGBUILD
cat >> PKGBUILD <<'EOF'

source+=(desmume-arm64-build-fix.patch)
b2sums+=('49d6e542135d5a45707f7113e1dc26b0cf4ad898779dfe4b08a5a20e76e914511973dc0c5f65b433a455b6f40a654a4345edb6cb6984e430644494a2e9c35b57')

prepare() {
  cd libretro-desmume
  patch -Np1 -i ../desmume-arm64-build-fix.patch
}
EOF
