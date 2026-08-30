#!/bin/bash
set -euo pipefail

sed -i \
  -e 's/^pkgname=zed-bin$/pkgname=zed/' \
  -e 's/^provides=.*/provides=("zed-bin=$pkgver")/' \
  -e "s/^conflicts=.*/conflicts=('zed-bin' 'zed-git' 'zed-preview-bin')/" \
  PKGBUILD

if grep -q '^options=' PKGBUILD; then
  grep -Eq "^options=.*'!strip'" PKGBUILD || {
    echo 'Upstream Zed options changed; preserve them and add !strip manually' >&2
    exit 1
  }
else
  sed -i "/^conflicts=/a options=('!strip')" PKGBUILD
fi
