#!/bin/bash
set -euo pipefail

sed -i '/^makedepends=(blueprint-compiler$/,/^[[:space:]]*zig)$/c\makedepends=(blueprint-compiler)\nmakedepends_x86_64=(pandoc-cli zig)\nmakedepends_i686=(pandoc-cli zig)\nmakedepends_aarch64=(pandoc-cli)' PKGBUILD
sed -i '/^_archive=/i\_zig_version=0.15.2' PKGBUILD
sed -i "/^source=(/a\\source_aarch64=(\"https://ziglang.org/download/\$_zig_version/zig-aarch64-linux-\$_zig_version.tar.xz\")" PKGBUILD
sed -i "/^sha256sums=/a\\sha256sums_aarch64=('958ed7d1e00d0ea76590d27666efbf7a932281b3d7ba0c6b01b0ff26498f667f')" PKGBUILD
grep -Fqx $'\tZIG_GLOBAL_CACHE_DIR="$srcdir/zig-global-cache/" ./nix/build-support/fetch-zig-cache.sh' PKGBUILD || {
  echo 'Upstream Ghostty dependency-fetch command changed; update the AArch64 hook deliberately' >&2
  exit 1
}
sed -i '/ZIG_GLOBAL_CACHE_DIR=.*fetch-zig-cache.sh/c\	local zig_path=$PATH\n	local attempt\n	[[ $CARCH != aarch64 ]] || zig_path="$srcdir/zig-aarch64-linux-$_zig_version:$PATH"\n	for attempt in 1 2 3; do\n		if PATH="$zig_path" ZIG_GLOBAL_CACHE_DIR="$srcdir/zig-global-cache/" \\\n			./nix/build-support/fetch-zig-cache.sh; then\n			return\n		fi\n		(( attempt < 3 )) || {\n			echo "Failed to fetch the Zig dependency cache after 3 attempts" >&2\n			return 1\n		}\n		echo "Retrying the Zig dependency cache fetch ($attempt/3)" >&2\n		sleep $((attempt * 5))\n	done' PKGBUILD
sed -i '/^build() {/,/^}/ { /^[[:space:]]*cd "$_archive"$/a\	local zig_cmd=zig\n	[[ $CARCH != aarch64 ]] || zig_cmd="$srcdir/zig-aarch64-linux-$_zig_version/zig"
}' PKGBUILD
sed -i 's/DESTDIR=build zig build/DESTDIR=build "$zig_cmd" build/' PKGBUILD
