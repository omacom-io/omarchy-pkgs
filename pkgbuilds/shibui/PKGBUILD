# Maintainer: Gabriel Vaquer <brielov@icloud.com>

pkgname=shibui
pkgver=0.1.1
pkgrel=1
pkgdesc='Quiet, keyboard-first graphical file manager for Omarchy and Hyprland'
arch=('x86_64')
url='https://github.com/brielov/shibui'
license=('MIT')
depends=(
  'fd'
  'fontconfig'
  'gcc-libs'
  'glib2'
  'glibc'
  'hicolor-icon-theme'
  'qt6-base'
  'qt6-declarative'
  'xdg-utils'
)
checkdepends=(
  'libarchive'
  'poppler'
)
optdepends=(
  'gvfs: SFTP and WebDAV network locations'
  'gvfs-nfs: NFS network locations'
  'gvfs-smb: SMB network locations'
  'hyprland: live Omarchy window geometry integration'
  'libarchive: archive creation and extraction'
  'poppler: PDF previews'
  'udisks2: removable-device actions'
  'util-linux: removable-device discovery'
  'xdg-terminal-exec: terminal integration'
)
options=('!debug')
source=("$pkgname-$pkgver.tar.gz::$url/archive/refs/tags/v$pkgver.tar.gz")
sha256sums=('995258f7b3fc2559f77fc559c78988d3f35f6e00f10b64c94a219c0b8e420f55')

build() {
  mkdir -p build
  cd build
  qmake6 "$srcdir/$pkgname-$pkgver/shibui.pro" PREFIX=/usr
  make
}

check() {
  mkdir -p build-tests
  cd build-tests
  qmake6 "$srcdir/$pkgname-$pkgver/tests/tests.pro"
  make
  QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software ./shibui-tests
}

package() {
  make -C build INSTALL_ROOT="$pkgdir" install
  install -Dm644 "$pkgname-$pkgver/LICENSE" \
    "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
