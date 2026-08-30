#!/bin/bash

set -euo pipefail
sed -i "s/^arch=.*/arch=('x86_64' 'aarch64')/" PKGBUILD
sed -i \
  's#^  cd "${srcdir}/${_srcdir}/apps/desktop/release/linux-unpacked"$#  local unpacked_dir='"'"'linux-unpacked'"'"'\n  [[ $CARCH != aarch64 ]] || unpacked_dir='"'"'linux-arm64-unpacked'"'"'\n  cd "${srcdir}/${_srcdir}/apps/desktop/release/${unpacked_dir}"#' \
  PKGBUILD
