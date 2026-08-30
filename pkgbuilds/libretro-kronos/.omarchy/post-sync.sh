#!/bin/bash
set -euo pipefail

sed -i 's/arch=(x86_64)/arch=(x86_64 aarch64)/' PKGBUILD
sed -i '/^build() {/a\  local make_options=()\n  [[ $CARCH != aarch64 ]] || make_options+=(platform=arm64 HAVE_CDROM=1)' PKGBUILD
sed -i 's|make -C libretro-yabause/yabause/src/libretro$|make -C libretro-yabause/yabause/src/libretro "${make_options[@]}"|' PKGBUILD
