#!/bin/bash

set -euo pipefail

ROOT=$(realpath "${BASH_SOURCE[0]%/*}/..")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

node "$ROOT/test/fixtures/create-architecture-audit-fixtures.mjs" "$work/fixtures"

mkdir -p "$work/good/payload" "$work/bad-asar/payload" \
  "$work/bad-tar/payload" "$work/depth/payload" \
  "$work/foreign/payload" "$work/malformed/payload" \
  "$work/x86-good/payload" "$work/good-appimage/payload" \
  "$work/bad-appimage/payload" "$work/malformed-appimage/payload" \
  "$work/bin"
cp "$work/fixtures/aarch64.elf" "$work/good/payload/native"
cp "$work/fixtures/nested-aarch64.asar" "$work/good/payload/modules.asar"
cp "$work/fixtures/managed-anycpu.dll" "$work/good/payload/managed.dll"
printf 'ESP_PATH="/boot"\n' > "$work/good/payload/default.conf"
cp "$work/fixtures/nested-x86_64.asar" "$work/bad-asar/payload/modules.asar"
cp "$work/fixtures/x86_64.node" "$work/foreign/payload/vendor.node"
cp "$work/fixtures/x86_64.exe" "$work/foreign/payload/vendor.exe"
cp "$work/fixtures/malformed.asar" "$work/malformed/payload/modules.asar"
cp "$work/fixtures/x86_64.elf" "$work/x86-good/payload/native"

# A type-2 AppImage is an ELF runtime followed by a SquashFS filesystem. The
# fixture stub validates that the scanner discovers the embedded offset and
# recursively audits the extracted tree without executing the AppImage.
cp "$work/fixtures/aarch64.elf" "$work/good-appimage/payload/good.AppImage"
printf 'hsqs' >> "$work/good-appimage/payload/good.AppImage"
cp "$work/fixtures/aarch64.elf" "$work/bad-appimage/payload/bad.AppImage"
printf 'hsqs' >> "$work/bad-appimage/payload/bad.AppImage"
cp "$work/fixtures/aarch64.elf" \
  "$work/malformed-appimage/payload/malformed.AppImage"
cp "$ROOT/test/fixtures/unsquashfs-stub" "$work/bin/unsquashfs"
chmod +x "$work/bin/unsquashfs"
export PATH="$work/bin:$PATH"
export APPIMAGE_TEST_OFFSET
APPIMAGE_TEST_OFFSET=$(LC_ALL=C grep -abo hsqs \
  "$work/good-appimage/payload/good.AppImage" | cut -d: -f1)
export APPIMAGE_GOOD_PAYLOAD="$work/fixtures/aarch64.elf"
export APPIMAGE_BAD_PAYLOAD="$work/fixtures/x86_64.elf"

mkdir -p "$work/tar-contents"
cp "$work/fixtures/x86_64.elf" "$work/tar-contents/hidden-helper"
bsdtar -cf "$work/bad-tar/payload/vendor.tar" -C "$work/tar-contents" .

mkdir -p "$work/depth-inner" "$work/depth-middle"
cp "$work/fixtures/aarch64.elf" "$work/depth-inner/native"
bsdtar -cf "$work/depth-middle/layer-2.tar" -C "$work/depth-inner" .
bsdtar -cf "$work/depth/payload/layer-1.tar" -C "$work/depth-middle" .

for package in good bad-asar bad-tar depth foreign malformed x86-good \
  good-appimage bad-appimage malformed-appimage; do
  bsdtar -cf "$work/$package.pkg.tar" -C "$work/$package" .
done

good_json=$(
  "$ROOT/bin/audit-package-architecture" --arch aarch64 --reject-foreign \
    --json "$work/good.pkg.tar"
)
jq -e '.errors == 0 and .elf_count == 2 and .non_target_elf_count == 0 and
       .managed_pe_count == 1 and .reviewed_non_target_elf_count == 0 and
       .nested_archive_count == 1 and .foreign_executable_count == 0' \
  <<<"$good_json" >/dev/null || {
  echo "Good recursive architecture fixture produced unexpected evidence" >&2
  exit 1
}

if "$ROOT/bin/audit-package-architecture" --arch aarch64 \
  "$work/bad-asar.pkg.tar" >"$work/bad-asar.out" 2>"$work/bad-asar.err"; then
  echo "Nested x86_64 ELF passed the AArch64 audit" >&2
  exit 1
fi
grep -Fq 'non-aarch64 ELF' "$work/bad-asar.err"
grep -Fq 'modules.asar/binding.node' "$work/bad-asar.err"

if "$ROOT/bin/audit-package-architecture" --arch aarch64 \
  "$work/bad-tar.pkg.tar" >"$work/bad-tar.out" 2>"$work/bad-tar.err"; then
  echo "x86_64 ELF in a nested tar archive passed the AArch64 audit" >&2
  exit 1
fi
grep -Fq 'vendor.tar/hidden-helper' "$work/bad-tar.err"

good_appimage_json=$(
  "$ROOT/bin/audit-package-architecture" --arch aarch64 --reject-foreign \
    --json "$work/good-appimage.pkg.tar"
)
jq -e '.errors == 0 and .elf_count == 2 and
       .non_target_elf_count == 0 and .nested_archive_count == 1' \
  <<< "$good_appimage_json" >/dev/null || {
  echo "Good AppImage fixture produced unexpected evidence" >&2
  exit 1
}

if "$ROOT/bin/audit-package-architecture" --arch aarch64 \
  "$work/bad-appimage.pkg.tar" \
  >"$work/bad-appimage.out" 2>"$work/bad-appimage.err"; then
  echo "x86_64 ELF in an AppImage passed the AArch64 audit" >&2
  exit 1
fi
grep -Fq 'bad.AppImage/squashfs-root/native' "$work/bad-appimage.err"

if "$ROOT/bin/audit-package-architecture" --arch aarch64 \
  "$work/malformed-appimage.pkg.tar" \
  >"$work/malformed-appimage.out" 2>"$work/malformed-appimage.err"; then
  echo "Malformed AppImage passed the recursive audit" >&2
  exit 1
fi
grep -Fq 'exactly one valid SquashFS filesystem' \
  "$work/malformed-appimage.err"

file_allowlist="$work/file-allowlist.tsv"
printf 'file\t%s\tpayload/native\n' \
  "$(sha256sum "$work/fixtures/x86_64.elf" | awk '{ print $1 }')" \
  > "$file_allowlist"
reviewed_file_json=$(
  "$ROOT/bin/audit-package-architecture" --arch aarch64 --reject-foreign \
    --allowlist "$file_allowlist" --json "$work/x86-good.pkg.tar" \
    2>"$work/reviewed-file.err"
)
jq -e '.errors == 0 and .non_target_elf_count == 1 and
       .reviewed_non_target_elf_count == 1' <<< "$reviewed_file_json" >/dev/null
grep -Fq 'REVIEWED: non-aarch64 ELF' "$work/reviewed-file.err"

container_allowlist="$work/container-allowlist.tsv"
printf 'container\t%s\tpayload/vendor.tar\n' \
  "$(sha256sum "$work/bad-tar/payload/vendor.tar" | awk '{ print $1 }')" \
  > "$container_allowlist"
reviewed_container_json=$(
  "$ROOT/bin/audit-package-architecture" --arch aarch64 --reject-foreign \
    --allowlist "$container_allowlist" --json "$work/bad-tar.pkg.tar" \
    2>"$work/reviewed-container.err"
)
jq -e '.errors == 0 and .non_target_elf_count == 1 and
       .reviewed_non_target_elf_count == 1' \
  <<< "$reviewed_container_json" >/dev/null

printf 'file\t%064d\tpayload/native\n' 0 > "$work/mismatch-allowlist.tsv"
if "$ROOT/bin/audit-package-architecture" --arch aarch64 \
  --allowlist "$work/mismatch-allowlist.tsv" "$work/x86-good.pkg.tar" \
  >"$work/mismatch.out" 2>"$work/mismatch.err"; then
  echo "A changed reviewed executable passed its pinned allowlist" >&2
  exit 1
fi
grep -Fq 'audit allowlist digest mismatch' "$work/mismatch.err"

printf 'file\t%s\tpayload/missing\n' \
  "$(sha256sum "$work/fixtures/x86_64.elf" | awk '{ print $1 }')" \
  > "$work/stale-allowlist.tsv"
if "$ROOT/bin/audit-package-architecture" --arch aarch64 \
  --allowlist "$work/stale-allowlist.tsv" "$work/good.pkg.tar" \
  >"$work/stale.out" 2>"$work/stale.err"; then
  echo "An unused architecture exception passed the audit" >&2
  exit 1
fi
grep -Fq 'unused audit allowlist entry' "$work/stale.err"

foreign_json=$(
  "$ROOT/bin/audit-package-architecture" --arch aarch64 --json \
    "$work/foreign.pkg.tar" 2>"$work/foreign-warning.err"
)
jq -e '.errors == 0 and .foreign_executable_count == 2' \
  <<<"$foreign_json" >/dev/null
grep -Fq 'FOREIGN:' "$work/foreign-warning.err"

if "$ROOT/bin/audit-package-architecture" --arch aarch64 --reject-foreign \
  "$work/foreign.pkg.tar" >"$work/foreign.out" 2>"$work/foreign.err"; then
  echo "Strict audit accepted an unreviewed Mach-O payload" >&2
  exit 1
fi
grep -Fq 'unreviewed non-Linux executable' "$work/foreign.err"

if "$ROOT/bin/audit-package-architecture" --arch aarch64 \
  "$work/malformed.pkg.tar" >"$work/malformed.out" 2>"$work/malformed.err"; then
  echo "Malformed ASAR passed the recursive audit" >&2
  exit 1
fi
grep -Fq 'cannot extract nested ASAR' "$work/malformed.err"

if "$ROOT/bin/audit-package-architecture" --arch aarch64 --max-depth 1 \
  "$work/depth.pkg.tar" >"$work/depth.out" 2>"$work/depth.err"; then
  echo "Nested-container depth limit was not enforced" >&2
  exit 1
fi
grep -Fq 'nested archive depth exceeds 1' "$work/depth.err"

if "$ROOT/bin/audit-package-architecture" --arch aarch64 --max-files 1 \
  "$work/good.pkg.tar" >"$work/files.out" 2>"$work/files.err"; then
  echo "Expanded file limit was not enforced" >&2
  exit 1
fi
grep -Fq 'expanded file limit exceeded' "$work/files.err"

if "$ROOT/bin/audit-package-architecture" --arch aarch64 --max-bytes 63 \
  "$work/foreign.pkg.tar" >"$work/bytes.out" 2>"$work/bytes.err"; then
  echo "Expanded byte limit was not enforced" >&2
  exit 1
fi
grep -Fq 'expanded byte limit exceeded' "$work/bytes.err"

"$ROOT/bin/audit-package-architecture" --arch x86_64 --reject-foreign \
  "$work/x86-good.pkg.tar" >/dev/null

mkdir -p "$work/same-a" "$work/same-b"
cp "$work/good.pkg.tar" "$work/same-a/duplicate.pkg.tar"
cp "$work/bad-asar.pkg.tar" "$work/same-b/duplicate.pkg.tar"
if multi_json=$(
  "$ROOT/bin/audit-package-architecture" --arch aarch64 --json \
    "$work/same-a/duplicate.pkg.tar" "$work/same-b/duplicate.pkg.tar" \
    2>"$work/multi.err"
); then
  echo "Multi-input audit accepted its bad second archive" >&2
  exit 1
fi
jq -se 'length == 2 and .[0].errors == 0 and .[1].errors > 0' \
  <<<"$multi_json" >/dev/null || {
  echo "Multi-input audit did not isolate same-named archives" >&2
  exit 1
}

echo "PASS: recursive package architecture audit"
