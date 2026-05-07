#!/bin/bash
set -euo pipefail

# Keep the AUR x86_64 checksums and add aarch64 sources. The aarch64
# artifacts are signed by 1Password's validpgpkeys, so we skip checksums there
# instead of baking version-specific hashes into Omarchy metadata.
set +u
CARCH=x86_64 source PKGBUILD
set -u

if declare -p sha256sums >/dev/null 2>&1 && [[ ${#sha256sums[@]} -ge 2 ]]; then
  x86_sums=("${sha256sums[@]}")
elif declare -p sha256sums_x86_64 >/dev/null 2>&1 && [[ ${#sha256sums_x86_64[@]} -ge 2 ]]; then
  x86_sums=("${sha256sums_x86_64[@]}")
else
  echo "Unable to read x86_64 checksums from PKGBUILD" >&2
  exit 1
fi

sha256_from_url() {
  curl -fsSL "$1" | sha256sum | awk '{ print $1 }'
}

arm_url="https://downloads.1password.com/linux/tar/beta/aarch64/1password-${_tarver}.arm64.tar.gz"
arm_tar_sum=$(sha256_from_url "$arm_url")
arm_sig_sum=$(sha256_from_url "$arm_url.sig")

emit_archdir() {
  cat <<'EOF'
case "${CARCH}" in
    x86_64)
        _archdir="x64"
        ;;
    aarch64)
        _archdir="arm64"
        ;;
esac
EOF
}

emit_sources() {
  cat <<EOF
source=()
sha256sums=()
source_x86_64=(https://downloads.1password.com/linux/tar/beta/x86_64/1password-\${_tarver}.x64.tar.gz{,.sig})
source_aarch64=(https://downloads.1password.com/linux/tar/beta/aarch64/1password-\${_tarver}.arm64.tar.gz{,.sig})
sha256sums_x86_64=('${x86_sums[0]}'
                   '${x86_sums[1]}')
sha256sums_aarch64=('$arm_tar_sum'
                    '$arm_sig_sum')
EOF
}

tmpfile=$(mktemp)
skip_checksums=false

while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$skip_checksums" == true ]]; then
    [[ "$line" == ")" ]] && skip_checksums=false
    continue
  fi

  case "$line" in
    '_tar="1password-${_tarver}.x64.tar.gz"')
      emit_archdir >> "$tmpfile"
      ;;
    "arch=('x86_64')")
      echo "arch=('x86_64' 'aarch64')" >> "$tmpfile"
      ;;
    source=\(*)
      emit_sources >> "$tmpfile"
      ;;
    sha256sums=\(*)
      [[ "$line" == *")" ]] || skip_checksums=true
      ;;
    *)
      line=${line//1password-\$\{_tarver\}.x64/1password-\$\{_tarver\}.\$\{_archdir\}}
      printf '%s\n' "$line" >> "$tmpfile"
      ;;
  esac
done < PKGBUILD

mv "$tmpfile" PKGBUILD
