#!/bin/bash
set -euo pipefail

sed -i 's/arch=(x86_64)/arch=(x86_64 aarch64)/' PKGBUILD
