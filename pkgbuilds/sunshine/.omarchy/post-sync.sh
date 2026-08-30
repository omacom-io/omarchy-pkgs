#!/bin/bash
set -euo pipefail

sed -i "/^[[:space:]]*'libmfx'$/d" PKGBUILD
sed -i "/^depends=(/i depends_x86_64=('libmfx')" PKGBUILD
