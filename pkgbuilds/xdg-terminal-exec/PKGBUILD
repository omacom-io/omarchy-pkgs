# Maintainer: Max Gautier <mg@max.gautier.name>
pkgname=xdg-terminal-exec
pkgver=0.13.3
pkgrel=1
pkgdesc="Proposed standard to launching desktop apps with Terminal=true"
arch=(any)
url="https://gitlab.freedesktop.org/Vladimir-csp/$pkgname"
makedepends=('scdoc')
checkdepends=('bats')
license=('GPL-3.0-or-later')
source=("${pkgname}-${pkgver}::$url/-/archive/v${pkgver}/${pkgname}-v${pkgver}.tar.gz")
sha256sums=('4c8db6be925a5260683a20870d470e6d0deca427e5efce0c322374502eb9b184')
b2sums=('20a6920503f6a364b460b892fd11c0307725bee4a137c230f6ddddaf5c23eddf3aa4d2aec649e7a134f67b6597a8057fcd4646c9aec3071493596415ff9872ea')

check() {
    cd "$pkgname-v$pkgver"
    bats "test/"
}

build() {
    make -C "$pkgname-v$pkgver"
}

package() {
    make -C "$pkgname-v$pkgver" prefix="$pkgdir/usr" install
}
