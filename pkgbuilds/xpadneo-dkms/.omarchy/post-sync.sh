#!/bin/bash
set -euo pipefail

expected="checkdepends=('dkms' 'fakeroot' 'LINUX-HEADERS')"
grep -Fxq "$expected" PKGBUILD || {
  echo 'ERROR: xpadneo checkdepends baseline changed' >&2
  exit 1
}

# The AUR placeholder is provided by Omarchy's x86_64 kernel package. Keep
# that path intact while avoiding an unsatisfiable dependency on AArch64.
sed -i "s/^checkdepends=.*/checkdepends=('dkms' 'fakeroot')\nif [[ \$CARCH == x86_64 ]]; then\n  checkdepends+=('LINUX-HEADERS')\nfi/" PKGBUILD
