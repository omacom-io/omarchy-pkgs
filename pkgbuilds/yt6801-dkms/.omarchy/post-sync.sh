#!/bin/bash

set -euo pipefail
sed -i "s/^arch=.*/arch=('any')/" PKGBUILD

# Motorcomm replaced download id 1817 in place with v1.0.34, so the old AUR
# recipe can no longer be reproduced. Keep this transition until AUR catches up.
if grep -q '^pkgver=1\.0\.31$' PKGBUILD; then
  cp .omarchy/files/1.0.34.patch patch.diff
  sed -i \
    -e 's/^pkgver=1\.0\.31$/pkgver=1.0.34/' \
    -e 's/9ea62182bd520483df5fd3ec320262cbdddcc763f3128ae37abd26905a97e14c/877e6953fc6eb47232a74e47b0daf33de0e7f9e9a395d3bc10d500d3c4150af8/' \
    -e 's/6cdb77774c483b640c8f0499fd54a79e773cd3f96a426cd99eec385972d9d5bb/cf0d3b655c6a8cd61857f847d71b4fa1806246c29c0f9b1c6274496f8c8aed50/' \
    -e 's/mkdir src/mkdir -p src/' \
    PKGBUILD
fi
