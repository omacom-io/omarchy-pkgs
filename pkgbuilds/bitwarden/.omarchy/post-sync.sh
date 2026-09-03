#!/bin/bash
set -euo pipefail

sed -i \
  -e 's/^pkgname=bitwarden-bin$/pkgname=bitwarden/' \
  -e 's/^provides=.*/provides=("bitwarden-bin=$pkgver")/' \
  -e 's/^conflicts=.*/conflicts=("bitwarden-bin")/' \
  PKGBUILD
