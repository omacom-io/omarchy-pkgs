#!/bin/bash

set -euo pipefail

package_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
extractor="$package_dir/qcom-firmware-extract"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

# macOS' install(1) gives -D a different meaning. Prefer GNU coreutils when
# this focused test runs on a contributor's Mac; Arch uses GNU install already.
test_bin="$scratch/bin"
mkdir -p "$test_bin"
if command -v ginstall >/dev/null 2>&1; then
  ln -s "$(command -v ginstall)" "$test_bin/install"
fi

dt_root="$scratch/device-tree"
firmware_root="$scratch/firmware"
driver_store="$scratch/DriverStore"
stage="$scratch/stage"
node="$dt_root/remoteproc@0"
firmware_path="qcom/x1e80100/LENOVO/83ED"

mkdir -p "$node" "$firmware_root/$firmware_path" \
  "$driver_store/wrong" "$driver_store/matching"
printf '%s\0%s\0' \
  "$firmware_path/qccdsp8380.mbn" \
  "$firmware_path/cdsp_dtbs.elf" >"$node/firmware-name"

# Make the incompatible Windows firmware newer than the matching variant.
printf 'installed-cdsp' >"$firmware_root/$firmware_path/qccdsp8380.mbn"
printf 'other-cdsp' >"$driver_store/wrong/qccdsp8380.mbn"
printf 'wrong-dtb' >"$driver_store/wrong/cdsp_dtbs.elf"
printf 'installed-cdsp' >"$driver_store/matching/qccdsp8380.mbn"
printf 'matching-dtb' >"$driver_store/matching/cdsp_dtbs.elf"
touch -t 203001010000 "$driver_store/wrong/cdsp_dtbs.elf"
touch -t 202001010000 "$driver_store/matching/cdsp_dtbs.elf"

QCOM_FW_DT_ROOT="$dt_root" \
  QCOM_FW_FIRMWARE_ROOT="$firmware_root" \
  PATH="$test_bin:$PATH" \
  bash "$extractor" --stage "$stage" -d "$driver_store"

[[ $(<"$stage/$firmware_path/cdsp_dtbs.elf") == matching-dtb ]] || {
  echo "not ok - extractor did not select the DTB matching the installed DSP image" >&2
  exit 1
}

echo "ok - extractor selects an ambiguous DTB by its companion firmware hash"
