#!/bin/bash

# Recursively audit final package payloads for target-architecture executables.
# Nested ASAR, SquashFS/AppImage, and libarchive-supported containers are
# opened with bounded recursion. Wrong-architecture ELF files fail unless an exact reviewed
# exception covers them; native non-Linux formats are reported and may be
# rejected with --reject-foreign. Managed ECMA-335 assemblies are counted
# separately from native PE files.

set -euo pipefail

BUILD_ROOT=$(realpath "${BASH_SOURCE[0]%/*}/..")
ASAR_EXTRACTOR="$BUILD_ROOT/helpers/extract-asar.mjs"

ARCH=aarch64
MAX_DEPTH=4
MAX_FILES=250000
MAX_BYTES=4294967296
REJECT_FOREIGN=false
JSON=false
ALLOWLIST=""
INPUTS=()

usage() {
  cat <<'EOF'
Usage: audit-package-architecture [OPTIONS] <archive-or-directory>...

Options:
  --arch <aarch64|x86_64>  Expected ELF architecture (default: aarch64)
  --max-depth <count>      Maximum nested-container depth (default: 4)
  --max-files <count>      Maximum expanded regular files per input (default: 250000)
  --max-bytes <count>      Maximum expanded bytes per input (default: 4294967296)
  --allowlist <path>       Reviewed exceptions (TSV: kind, SHA-256, relative path)
  --reject-foreign         Reject Mach-O, PE, and DOS executables as unreviewed
  --json                   Emit one compact JSON result per input
  -h, --help               Show this help

Wrong-architecture Linux ELF files fail unless an exact reviewed allowlist
entry covers the file or its checksum-pinned container. Without
--reject-foreign, native non-Linux executable formats are reported for
package-specific review. ECMA-335 assemblies are counted as managed PE.
EOF
}

positive_integer() {
  [[ $1 =~ ^[1-9][0-9]*$ ]]
}

while (($# > 0)); do
  case $1 in
  --arch)
    (($# >= 2)) || { echo "ERROR: --arch requires a value" >&2; exit 2; }
    ARCH=$2
    shift 2
    ;;
  --max-depth)
    (($# >= 2)) || { echo "ERROR: --max-depth requires a value" >&2; exit 2; }
    MAX_DEPTH=$2
    shift 2
    ;;
  --max-files)
    (($# >= 2)) || { echo "ERROR: --max-files requires a value" >&2; exit 2; }
    MAX_FILES=$2
    shift 2
    ;;
  --max-bytes)
    (($# >= 2)) || { echo "ERROR: --max-bytes requires a value" >&2; exit 2; }
    MAX_BYTES=$2
    shift 2
    ;;
  --allowlist)
    (($# >= 2)) || { echo "ERROR: --allowlist requires a value" >&2; exit 2; }
    ALLOWLIST=$2
    shift 2
    ;;
  --reject-foreign)
    REJECT_FOREIGN=true
    shift
    ;;
  --json)
    JSON=true
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  --)
    shift
    INPUTS+=("$@")
    break
    ;;
  -*)
    echo "ERROR: unknown option: $1" >&2
    usage >&2
    exit 2
    ;;
  *)
    INPUTS+=("$1")
    shift
    ;;
  esac
done

case $ARCH in
aarch64) EXPECTED_MACHINE=AArch64 ;;
x86_64) EXPECTED_MACHINE='Advanced Micro Devices X86-64' ;;
*)
  echo "ERROR: unsupported architecture: $ARCH" >&2
  exit 2
  ;;
esac

positive_integer "$MAX_DEPTH" || { echo "ERROR: invalid --max-depth" >&2; exit 2; }
positive_integer "$MAX_FILES" || { echo "ERROR: invalid --max-files" >&2; exit 2; }
positive_integer "$MAX_BYTES" || { echo "ERROR: invalid --max-bytes" >&2; exit 2; }
((${#INPUTS[@]} > 0)) || { usage >&2; exit 2; }

for command in bsdtar file find jq readelf sha256sum timeout; do
  command -v "$command" >/dev/null || {
    echo "ERROR: required audit command is missing: $command" >&2
    exit 2
  }
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

file_count=0
byte_count=0
elf_count=0
non_target_elf_count=0
managed_pe_count=0
archive_count=0
foreign_count=0
reviewed_non_target_elf_count=0
reviewed_foreign_count=0
max_depth_seen=0
errors=0
extract_sequence=0
input_sequence=0
metadata_sequence=0
current_work=""
declare -A allowed_files=()
declare -A allowed_containers=()
declare -A allowlist_used=()

load_allowlist() {
  [[ -n $ALLOWLIST ]] || return 0
  [[ -f $ALLOWLIST ]] || {
    echo "ERROR: audit allowlist does not exist: $ALLOWLIST" >&2
    return 1
  }

  local line line_number=0 kind digest path extra key
  while IFS= read -r line || [[ -n $line ]]; do
    ((line_number += 1))
    line=${line%$'\r'}
    [[ $line =~ ^[[:space:]]*(#|$) ]] && continue
    IFS=$'\t' read -r kind digest path extra <<< "$line"
    [[ -z ${extra:-} && -n ${kind:-} && -n ${digest:-} && -n ${path:-} ]] || {
      echo "ERROR: malformed audit allowlist row $line_number (expected three tab-separated fields)" >&2
      return 1
    }
    case $kind in
    file | container) ;;
    *)
      echo "ERROR: invalid audit allowlist kind on row $line_number: $kind" >&2
      return 1
      ;;
    esac
    [[ $digest =~ ^[0-9a-f]{64}$ ]] || {
      echo "ERROR: invalid audit allowlist SHA-256 on row $line_number" >&2
      return 1
    }
    if [[ $path == /* || $path == .. || $path == ../* || $path == */../* || $path == */.. ]]; then
      echo "ERROR: unsafe audit allowlist path on row $line_number: $path" >&2
      return 1
    fi
    key="$kind:$path"
    [[ -z ${allowlist_used[$key]+set} ]] || {
      echo "ERROR: duplicate audit allowlist entry on row $line_number: $key" >&2
      return 1
    }
    if [[ $kind == file ]]; then
      allowed_files["$path"]=$digest
    else
      allowed_containers["$path"]=$digest
    fi
    allowlist_used["$key"]=false
  done < "$ALLOWLIST"
}

reset_allowlist_usage() {
  local key
  for key in "${!allowlist_used[@]}"; do
    allowlist_used["$key"]=false
  done
}

reviewed_file() {
  local path=$1 candidate=$2 expected actual key
  [[ -n ${allowed_files[$path]+set} ]] || return 1
  expected=${allowed_files[$path]}
  actual=$(sha256sum "$candidate" | awk '{ print $1 }') || return 1
  key="file:$path"
  if [[ $actual != "$expected" ]]; then
    echo "ERROR: audit allowlist digest mismatch for $path" >&2
    ((errors += 1))
    return 1
  fi
  allowlist_used["$key"]=true
}

reviewed_container() {
  local path=$1 candidate=$2 expected actual key
  [[ -n ${allowed_containers[$path]+set} ]] || return 1
  expected=${allowed_containers[$path]}
  actual=$(sha256sum "$candidate" | awk '{ print $1 }') || return 1
  key="container:$path"
  if [[ $actual != "$expected" ]]; then
    echo "ERROR: audit allowlist digest mismatch for $path" >&2
    ((errors += 1))
    return 1
  fi
  allowlist_used["$key"]=true
}

validate_allowlist_usage() {
  local key
  for key in "${!allowlist_used[@]}"; do
    [[ ${allowlist_used[$key]} == true ]] && continue
    echo "ERROR: unused audit allowlist entry: ${key#*:}" >&2
    ((errors += 1))
  done
}

load_allowlist || exit 2

record_tree_size() {
  local root=$1 manifest size
  ((metadata_sequence += 1))
  manifest="$current_work/sizes-$metadata_sequence"
  if ! find "$root" -type f -printf '%s\0' > "$manifest"; then
    echo "ERROR: cannot enumerate expanded files under $root" >&2
    return 1
  fi
  while IFS= read -r -d '' size; do
    ((file_count += 1))
    ((byte_count += size))
    if ((file_count > MAX_FILES)); then
      echo "ERROR: expanded file limit exceeded: $file_count > $MAX_FILES" >&2
      return 1
    fi
    if ((byte_count > MAX_BYTES)); then
      echo "ERROR: expanded byte limit exceeded: $byte_count > $MAX_BYTES" >&2
      return 1
    fi
  done < "$manifest"
}

safe_archive_members() {
  local archive=$1 member
  while IFS= read -r member; do
    if [[ $member == /* || $member == .. || $member == ../* || $member == */../* || $member == */.. ]]; then
      echo "ERROR: unsafe path in nested archive $archive: $member" >&2
      return 1
    fi
  done < <(bsdtar -tf "$archive")
}

extract_libarchive() {
  local archive=$1 destination=$2 blocks
  safe_archive_members "$archive" || return 1
  blocks=$(((MAX_BYTES + 511) / 512))
  mkdir -p "$destination"
  timeout 120 bash -c '
    ulimit -f "$1"
    exec bsdtar --no-same-owner --no-same-permissions -xf "$2" -C "$3"
  ' _ "$blocks" "$archive" "$destination"
}

find_squashfs_offset() {
  local archive=$1 match offset
  local -a valid_offsets=()

  # Type-2 AppImages prepend an ELF runtime to their SquashFS. Find candidate
  # little-endian superblock magics and let unsquashfs validate them; do not
  # execute the vendor-provided AppImage runtime merely to ask for its offset.
  while IFS= read -r match; do
    offset=${match%%:*}
    [[ $offset =~ ^[0-9]+$ ]] || continue
    if timeout 30 unsquashfs -o "$offset" -s "$archive" >/dev/null 2>&1; then
      valid_offsets+=("$offset")
    fi
  done < <(LC_ALL=C grep -abo 'hsqs' -- "$archive" || true)

  if ((${#valid_offsets[@]} != 1)); then
    echo "ERROR: expected exactly one valid SquashFS filesystem in $archive; found ${#valid_offsets[@]}" >&2
    return 1
  fi
  printf '%s\n' "${valid_offsets[0]}"
}

extract_squashfs() {
  local archive=$1 destination=$2 remaining_files=$3 remaining_bytes=$4
  local offset inventory entries expanded_bytes blocks

  command -v unsquashfs >/dev/null || {
    echo "ERROR: unsquashfs is required to inspect SquashFS/AppImage payload: $archive" >&2
    return 1
  }
  offset=$(find_squashfs_offset "$archive") || return 1

  inventory=$(LC_ALL=C timeout 60 unsquashfs -o "$offset" -lln "$archive" |
    awk 'NF >= 6 && $3 ~ /^[0-9]+$/ { entries += 1; bytes += $3 }
      END { printf "%d %.0f\n", entries, bytes }') || return 1
  read -r entries expanded_bytes <<< "$inventory"
  [[ $entries =~ ^[0-9]+$ && $expanded_bytes =~ ^[0-9]+$ ]] || {
    echo "ERROR: cannot determine SquashFS extraction budget: $archive" >&2
    return 1
  }
  if ((entries > remaining_files)); then
    echo "ERROR: SquashFS file limit would be exceeded: $entries > $remaining_files" >&2
    return 1
  fi
  if ((expanded_bytes > remaining_bytes)); then
    echo "ERROR: SquashFS byte limit would be exceeded: $expanded_bytes > $remaining_bytes" >&2
    return 1
  fi

  blocks=$(((remaining_bytes + 511) / 512))
  mkdir -p "$destination"
  timeout 120 bash -c '
    ulimit -f "$1"
    exec unsquashfs -no-progress -no-xattrs -processors 1 \
      -o "$2" -d "$3" "$4"
  ' _ "$blocks" "$offset" "$destination" "$archive" >/dev/null
}

is_nested_archive() {
  local candidate=$1 type=$2
  case $type in
  *'Electron ASAR archive'*) return 0 ;;
  *'Zip archive data'* | *'POSIX tar archive'* | *'GNU tar archive'* | \
    *'cpio archive'* | *'7-zip archive data'* | *'RAR archive data'* | \
    *'Debian binary package'* | *'RPM '* | *'Squashfs filesystem'*) return 0 ;;
  esac
  case ${candidate,,} in
  *.asar | *.zip | *.jar | *.tar | *.tgz | *.tar.gz | *.tar.xz | *.tar.zst | \
    *.deb | *.rpm | *.appimage) return 0 ;;
  esac
  return 1
}

scan_tree() {
  local root=$1 depth=$2 display_root=$3 logical_root=$4 inherited_review=$5
  local candidate relative type machine destination remaining_files remaining_bytes
  local classification index logical_path reviewed container_reviewed
  local -a archives=()
  local -a archive_types=()
  local -a archive_logical_paths=()
  local -a archive_reviewed=()

  ((depth > max_depth_seen)) && max_depth_seen=$depth
  record_tree_size "$root" || { ((errors += 1)); return; }

  ((metadata_sequence += 1))
  classification="$current_work/types-$metadata_sequence"
  if ! find "$root" -type f -print0 | xargs -0 -r file -N -0 -- > "$classification"; then
    echo "ERROR: cannot classify files under $display_root" >&2
    ((errors += 1))
    return
  fi

  while IFS= read -r -d '' candidate; do
    if ! IFS= read -r type; then
      echo "ERROR: truncated file-classification output under $display_root" >&2
      ((errors += 1))
      break
    fi
    type=${type#: }
    relative=${candidate#"$root"/}
    logical_path=${logical_root:+$logical_root/}$relative

    if [[ $type == ELF\ * ]]; then
      ((elf_count += 1))
      machine=$(readelf -h -- "$candidate" 2>/dev/null |
        sed -n 's/^[[:space:]]*Machine:[[:space:]]*//p')
      if [[ $machine != "$EXPECTED_MACHINE" ]]; then
        ((non_target_elf_count += 1))
        reviewed=$inherited_review
        if [[ $reviewed == true ]] || reviewed_file "$logical_path" "$candidate"; then
          ((reviewed_non_target_elf_count += 1))
          echo "REVIEWED: non-$ARCH ELF: $display_root/$relative (${machine:-unknown})" >&2
        else
          echo "ERROR: non-$ARCH ELF: $display_root/$relative (${machine:-unknown})" >&2
          ((errors += 1))
        fi
      fi
    elif [[ $type == PE32* && $type == *'Mono/.Net assembly'* ]]; then
      # ECMA-335 assemblies use the PE container even when their IL is
      # architecture-neutral. Keep them distinct from native Windows PE files
      # so an AArch64 .NET package is not rejected for its normal managed code.
      ((managed_pe_count += 1))
    elif [[ $type == Mach-O\ * || $type == PE32* || $type == MS-DOS\ executable* ]]; then
      ((foreign_count += 1))
      reviewed=$inherited_review
      if [[ $reviewed == true ]] || reviewed_file "$logical_path" "$candidate"; then
        ((reviewed_foreign_count += 1))
        echo "REVIEWED: $display_root/$relative ($type)" >&2
      else
        echo "FOREIGN: $display_root/$relative ($type)" >&2
      fi
    fi

    if is_nested_archive "$candidate" "$type"; then
      container_reviewed=$inherited_review
      if [[ $container_reviewed == false ]] && reviewed_container "$logical_path" "$candidate"; then
        container_reviewed=true
      fi
      archives+=("$candidate")
      archive_types+=("$type")
      archive_logical_paths+=("$logical_path")
      archive_reviewed+=("$container_reviewed")
    fi
  done < "$classification"

  for ((index = 0; index < ${#archives[@]}; index += 1)); do
    candidate=${archives[$index]}
    type=${archive_types[$index]}
    logical_path=${archive_logical_paths[$index]}
    container_reviewed=${archive_reviewed[$index]}
    relative=${candidate#"$root"/}
    if ((depth >= MAX_DEPTH)); then
      echo "ERROR: nested archive depth exceeds $MAX_DEPTH: $display_root/$relative" >&2
      ((errors += 1))
      continue
    fi

    ((archive_count += 1))
    ((extract_sequence += 1))
    destination="$current_work/nested-$extract_sequence"
    remaining_files=$((MAX_FILES - file_count))
    remaining_bytes=$((MAX_BYTES - byte_count))
    if ((remaining_files < 1 || remaining_bytes < 1)); then
      echo "ERROR: no extraction budget remains for $display_root/$relative" >&2
      ((errors += 1))
      continue
    fi

    if [[ $type == *'Squashfs filesystem'* || ${candidate,,} == *.appimage ]]; then
      if ! extract_squashfs "$candidate" "$destination" \
        "$remaining_files" "$remaining_bytes"; then
        echo "ERROR: cannot extract nested SquashFS/AppImage: $display_root/$relative" >&2
        ((errors += 1))
        continue
      fi
    elif [[ $type == *'Electron ASAR archive'* || ${candidate,,} == *.asar ]]; then
      command -v node >/dev/null || {
        echo "ERROR: node is required to inspect ASAR archive: $display_root/$relative" >&2
        ((errors += 1))
        continue
      }
      if ! timeout 120 node "$ASAR_EXTRACTOR" "$candidate" "$destination" \
        "$remaining_files" "$remaining_bytes"; then
        echo "ERROR: cannot extract nested ASAR: $display_root/$relative" >&2
        ((errors += 1))
        continue
      fi
    elif ! extract_libarchive "$candidate" "$destination"; then
      case $type:${candidate,,} in
      *archive*:* | *filesystem*:* | *:*.zip | *:*.jar | *:*.tar | *:*.tgz | \
        *:*.tar.gz | *:*.tar.xz | *:*.tar.zst | *:*.deb | *:*.rpm | *:*.appimage)
        echo "ERROR: cannot extract nested archive: $display_root/$relative" >&2
        ((errors += 1))
        ;;
      esac
      continue
    fi

    scan_tree "$destination" "$((depth + 1))" "$display_root/$relative" \
      "$logical_path" "$container_reviewed"
  done
}

audit_input() {
  local input=$1 input_root result_errors unreviewed_foreign_count

  file_count=0
  byte_count=0
  elf_count=0
  non_target_elf_count=0
  managed_pe_count=0
  archive_count=0
  foreign_count=0
  reviewed_non_target_elf_count=0
  reviewed_foreign_count=0
  max_depth_seen=0
  errors=0
  extract_sequence=0
  metadata_sequence=0
  reset_allowlist_usage
  ((input_sequence += 1))
  current_work="$work/input-$input_sequence"
  mkdir -p "$current_work"

  if [[ -d $input ]]; then
    input_root=$(realpath "$input")
  elif [[ -f $input ]]; then
    input_root="$current_work/outer"
    if ! extract_libarchive "$input" "$input_root"; then
      echo "ERROR: cannot extract input archive: $input" >&2
      errors=1
    fi
  else
    echo "ERROR: audit input does not exist: $input" >&2
    errors=1
    input_root=""
  fi

  [[ -z $input_root || $errors -ne 0 ]] || \
    scan_tree "$input_root" 0 "${input##*/}" "" false
  validate_allowlist_usage
  unreviewed_foreign_count=$((foreign_count - reviewed_foreign_count))
  if [[ $REJECT_FOREIGN == true && $unreviewed_foreign_count -gt 0 ]]; then
    echo "ERROR: $unreviewed_foreign_count unreviewed non-Linux executable(s) in ${input##*/}" >&2
    ((errors += unreviewed_foreign_count))
  fi
  result_errors=$errors

  if [[ $JSON == true ]]; then
    jq -cn \
      --arg input "$input" \
      --arg target_architecture "$ARCH" \
      --argjson file_count "$file_count" \
      --argjson expanded_bytes "$byte_count" \
      --argjson elf_count "$elf_count" \
      --argjson non_target_elf_count "$non_target_elf_count" \
      --argjson reviewed_non_target_elf_count "$reviewed_non_target_elf_count" \
      --argjson managed_pe_count "$managed_pe_count" \
      --argjson nested_archive_count "$archive_count" \
      --argjson foreign_executable_count "$foreign_count" \
      --argjson reviewed_foreign_executable_count "$reviewed_foreign_count" \
      --argjson max_depth_seen "$max_depth_seen" \
      --argjson errors "$result_errors" \
      '{input: $input, target_architecture: $target_architecture,
        file_count: $file_count, expanded_bytes: $expanded_bytes,
        elf_count: $elf_count, non_target_elf_count: $non_target_elf_count,
        reviewed_non_target_elf_count: $reviewed_non_target_elf_count,
        managed_pe_count: $managed_pe_count,
        nested_archive_count: $nested_archive_count,
        foreign_executable_count: $foreign_executable_count,
        reviewed_foreign_executable_count: $reviewed_foreign_executable_count,
        max_depth_seen: $max_depth_seen, errors: $errors}'
  else
    printf '%s: files=%d bytes=%d ELF=%d wrong-ELF=%d managed-PE=%d nested=%d foreign=%d reviewed=%d errors=%d\n' \
      "${input##*/}" "$file_count" "$byte_count" "$elf_count" \
      "$non_target_elf_count" "$managed_pe_count" "$archive_count" \
      "$foreign_count" "$((reviewed_non_target_elf_count + reviewed_foreign_count))" \
      "$result_errors"
  fi

  ((result_errors == 0))
}

failures=0
for input in "${INPUTS[@]}"; do
  audit_input "$input" || ((failures += 1))
done

((failures == 0))
