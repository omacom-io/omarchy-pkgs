#!/bin/bash
set -euo pipefail

sed -i "s/arch=('x86_64')/arch=('x86_64' 'aarch64')/" PKGBUILD
sed -i '/^source=(/,/^rg.sh)$/c\source=(\n  "https://gitlab.archlinux.org/archlinux/packaging/packages/code/-/raw/main/code.sh"\n  "https://gitlab.archlinux.org/archlinux/packaging/packages/code/-/raw/main/code.mjs"\n  rg.sh\n)\nsource_x86_64=("cursor_${pkgver}_amd64.deb::https://downloads.cursor.com/production/${_commit}/linux/x64/deb/amd64/deb/cursor_${pkgver}_amd64.deb")\nsource_aarch64=("cursor_${pkgver}_arm64.deb::https://downloads.cursor.com/production/${_commit}/linux/arm64/deb/arm64/deb/cursor_${pkgver}_arm64.deb")' PKGBUILD
sed -i \
  -e "s/^sha512sums=('SKIP'/sha512sums=(/" \
  -e "s/^sha512sums\[0\]=\(.*\)$/sha512sums_x86_64=(\1)\nsha512sums_aarch64=('SKIP')/" \
  -e '/^noextract=/i _deb_arch=$([[ $CARCH == aarch64 ]] \&\& echo arm64 || echo amd64)' \
  -e 's/^noextract=.*/noextract=(cursor_${pkgver}_${_deb_arch}.deb)/' \
  PKGBUILD

sed -i '/^depends=(xdg-utils ripgrep $_electron nodejs$/,/^  .*libxkbfile.*)$/c\depends=(xdg-utils '\''gcc-libs'\'' '\''hicolor-icon-theme'\'' '\''libxkbfile'\'')\ndepends_x86_64=(ripgrep $_electron nodejs)\ndepends_aarch64=(\n  alsa-lib at-spi2-core cairo cups curl dbus expat glib2 gtk3 mesa nspr nss\n  pango systemd-libs libx11 libxcb libxcomposite libxdamage libxext libxfixes\n  libxkbcommon libxrandr\n)' PKGBUILD

pkgver=$(sed -n 's/^pkgver=//p' PKGBUILD)
_commit=$(sed -n 's/^_commit=//p' PKGBUILD)
arm_url="https://downloads.cursor.com/production/${_commit}/linux/arm64/deb/arm64/deb/cursor_${pkgver}_arm64.deb"
arm_checksum=$(curl -fsSL --retry 3 "$arm_url" | sha512sum | awk '{ print $1 }')
sed -i "s/sha512sums_aarch64=('SKIP')/sha512sums_aarch64=('${arm_checksum}')/" PKGBUILD
sed -i '0,/^package() {/s//_package_system_electron() {/' PKGBUILD

cat >> PKGBUILD <<'EOF'

package() {
  if [[ $CARCH != aarch64 ]]; then
    _package_system_electron
    return
  fi

  bsdtar -xOf "${noextract[0]}" data.tar.xz | tar -xJf - -C "$pkgdir"
  cd "$pkgdir"
  mv usr/share/zsh/{vendor-completions,site-functions}
  find usr/share/cursor/resources/app/extensions/ms-vscode.js-debug/src \
    -maxdepth 1 -type f \( -name '*win32*.node' -o -name 'w32appcontainertokens*.node' \) \
    -delete
  chmod u-s usr/share/cursor/chrome-sandbox
  install -d usr/bin
  ln -sf /usr/share/cursor/cursor usr/bin/cursor
}
EOF
