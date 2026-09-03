#!/bin/bash
set -euo pipefail

sed -i \
  -e 's/^_tar=.*/_tar_x86_64="1password-${_tarver}.x64.tar.gz"\n_tar_aarch64="1password-${_tarver}.arm64.tar.gz"\n_archive_arch=$([[ $CARCH == aarch64 ]] \&\& echo arm64 || echo x64)/' \
  -e "s/arch=('x86_64')/arch=('x86_64' 'aarch64')/" \
  -e 's|^source=.*|source_x86_64=("${_tar_x86_64}::https://downloads.1password.com/linux/tar/stable/x86_64/${_tar_x86_64}" "${_tar_x86_64}.sig::https://downloads.1password.com/linux/tar/stable/x86_64/${_tar_x86_64}.sig")\nsource_aarch64=("${_tar_aarch64}::https://downloads.1password.com/linux/tar/stable/aarch64/${_tar_aarch64}" "${_tar_aarch64}.sig::https://downloads.1password.com/linux/tar/stable/aarch64/${_tar_aarch64}.sig")|' \
  -e 's/^sha256sums=/sha256sums_x86_64=/' \
  -e '/^validpgpkeys=/i sha256sums_aarch64=(\x27SKIP\x27 \x27SKIP\x27)' \
  -e 's/1password-${_tarver}\.x64/1password-${_tarver}.${_archive_arch}/g' \
  PKGBUILD
