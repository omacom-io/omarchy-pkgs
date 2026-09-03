#!/bin/bash
set -euo pipefail

source_patch=.omarchy/files/libretro-blastem-flags.patch
expected_patch_sum=0973d8d0ebc5f71e132950eca6321c15eec8944c747d24a9e6bf15e79343249290b3f66b9761569e31b41ffc5cb05ea7be6d2e9926790a67fbe1bb2d3805c1db

[[ $(b2sum "$source_patch" | awk '{print $1}') == "$expected_patch_sum" ]] || {
  echo 'BlastEm build-flags patch checksum changed; update the PKGBUILD deliberately' >&2
  exit 1
}

grep -Fqx 'pkgver=20260813.175226.gaeb16cd0750f' PKGBUILD || {
  echo 'BlastEm AArch64 source revision was not applied' >&2
  exit 1
}
grep -Fqx 'arch=(x86_64 aarch64)' PKGBUILD || {
  echo 'BlastEm AArch64 architecture declaration was not applied' >&2
  exit 1
}
cp "$source_patch" libretro-blastem-flags.patch
