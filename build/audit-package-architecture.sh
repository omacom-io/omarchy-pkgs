#!/bin/bash

# Recursively audit final package payloads for target-architecture executables.
# Nested ASAR and libarchive-supported containers are opened with bounded
# recursion. Wrong-architecture ELF files always fail; non-Linux executable
# formats are reported and may be rejected with --reject-foreign.

set -euo pipefail

BUILD_ROOT=$(realpath "${BASH_SOURCE[0]%/*}/..")
ASAR_EXTRACTOR="$BUILD_ROOT/helpers/extract-asar.mjs"

ARCH=aarch64
MAX_DEPTH=4
MAX_FILES=250000
MAX_BYTES=4294967296
REJECT_FOREIGN=false
JSON=false
INPUTS=()

usage() {
  cat <<'EOF'
Usage: audit-package-architecture [OPTIONS] <archive-or-directory>...

Options:
  --arch <aarch64|x86_64>  Expected ELF architecture (default: aarch64)
  --max-depth <count>      Maximum nested-container depth (default: 4)
  --max-files <count>      Maximum expanded regular files per input (default: 250000)
  --max-bytes <count>      Maximum expanded bytes per input (default: 4294967296)
  --reject-foreign         Reject Mach-O, PE, and DOS executables as unreviewed
  --json                   Emit one compact JSON result per input
  -h, --help               Show this help

Wrong-architecture Linux ELF files always fail. Without --reject-foreign,
non-Linux executable formats are reported for package-specific review.
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

for command in bsdtar file find jq readelf stat timeout; do
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
archive_count=0
foreign_count=0
max_depth_seen=0
errors=0
extract_sequence=0
input_sequence=0
current_work=""

record_tree_size() {
  local root=$1 candidate size
  while IFS= read -r -d '' candidate; do
    size=$(stat -c %s -- "$candidate") || return 1
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
  done < <(find "$root" -type f -print0)
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

is_nested_archive() {
  local candidate=$1 type=$2
  case $type in
  *'Electron ASAR archive'*) return 0 ;;
  *'Zip archive'* | *'archive data'* | *'tar archive'* | \
    *'Debian binary package'* | *'RPM '* | *'Squashfs filesystem'*) return 0 ;;
  esac
  case ${candidate,,} in
  *.asar | *.zip | *.jar | *.tar | *.tgz | *.tar.gz | *.tar.xz | *.tar.zst | \
    *.deb | *.rpm) return 0 ;;
  esac
  return 1
}

scan_tree() {
  local root=$1 depth=$2 display_root=$3
  local candidate relative type machine destination remaining_files remaining_bytes
  local -a archives=()

  ((depth > max_depth_seen)) && max_depth_seen=$depth
  record_tree_size "$root" || { ((errors += 1)); return; }

  while IFS= read -r -d '' candidate; do
    relative=${candidate#"$root"/}
    type=$(file -b -- "$candidate") || {
      echo "ERROR: cannot classify $display_root/$relative" >&2
      ((errors += 1))
      continue
    }

    if [[ $type == ELF\ * ]]; then
      ((elf_count += 1))
      machine=$(readelf -h -- "$candidate" 2>/dev/null |
        sed -n 's/^[[:space:]]*Machine:[[:space:]]*//p')
      if [[ $machine != "$EXPECTED_MACHINE" ]]; then
        echo "ERROR: non-$ARCH ELF: $display_root/$relative (${machine:-unknown})" >&2
        ((errors += 1))
      fi
    elif [[ $type == Mach-O\ * || $type == PE32* || $type == MS-DOS\ executable* ]]; then
      ((foreign_count += 1))
      echo "FOREIGN: $display_root/$relative ($type)" >&2
    fi

    if is_nested_archive "$candidate" "$type"; then
      archives+=("$candidate")
    fi
  done < <(find "$root" -type f -print0)

  for candidate in "${archives[@]}"; do
    relative=${candidate#"$root"/}
    type=$(file -b -- "$candidate")
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

    if [[ $type == *'Electron ASAR archive'* || ${candidate,,} == *.asar ]]; then
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
        *:*.tar.gz | *:*.tar.xz | *:*.tar.zst | *:*.deb | *:*.rpm)
        echo "ERROR: cannot extract nested archive: $display_root/$relative" >&2
        ((errors += 1))
        ;;
      esac
      continue
    fi

    scan_tree "$destination" "$((depth + 1))" "$display_root/$relative"
  done
}

audit_input() {
  local input=$1 input_root result_errors

  file_count=0
  byte_count=0
  elf_count=0
  archive_count=0
  foreign_count=0
  max_depth_seen=0
  errors=0
  extract_sequence=0
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

  [[ -z $input_root || $errors -ne 0 ]] || scan_tree "$input_root" 0 "${input##*/}"
  if [[ $REJECT_FOREIGN == true && $foreign_count -gt 0 ]]; then
    echo "ERROR: $foreign_count unreviewed non-Linux executable(s) in ${input##*/}" >&2
    ((errors += foreign_count))
  fi
  result_errors=$errors

  if [[ $JSON == true ]]; then
    jq -cn \
      --arg input "$input" \
      --arg target_architecture "$ARCH" \
      --argjson file_count "$file_count" \
      --argjson expanded_bytes "$byte_count" \
      --argjson elf_count "$elf_count" \
      --argjson nested_archive_count "$archive_count" \
      --argjson foreign_executable_count "$foreign_count" \
      --argjson max_depth_seen "$max_depth_seen" \
      --argjson errors "$result_errors" \
      '{input: $input, target_architecture: $target_architecture,
        file_count: $file_count, expanded_bytes: $expanded_bytes,
        elf_count: $elf_count, nested_archive_count: $nested_archive_count,
        foreign_executable_count: $foreign_executable_count,
        max_depth_seen: $max_depth_seen, errors: $errors}'
  else
    printf '%s: files=%d bytes=%d ELF=%d nested=%d foreign=%d errors=%d\n' \
      "${input##*/}" "$file_count" "$byte_count" "$elf_count" \
      "$archive_count" "$foreign_count" "$result_errors"
  fi

  ((result_errors == 0))
}

failures=0
for input in "${INPUTS[@]}"; do
  audit_input "$input" || ((failures += 1))
done

((failures == 0))
