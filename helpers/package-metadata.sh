# Package metadata helpers for Omarchy package build tooling
#
# Expects package directories in $PKGBUILDS_DIR, each with:
#   .omarchy/package.json
#
# Minimal schema:
#   { "source": "aur" }
#   { "source": "aur", "sync": false }
#   { "source": "aur", "aur": "different-aur-name" }
#   { "source": "aur", "release_ring": "fast" }
#   { "source": "aur", "pkgrel": { "suffix": 1, "offset": 1 } }
#   { "source": "local" }
#
# bin/sync-aur also writes upstream_commit for AUR-backed packages.

if [[ -z "${PKGBUILDS_DIR:-}" ]]; then
  if [[ -n "${BUILD_ROOT:-}" ]]; then
    PKGBUILDS_DIR="$BUILD_ROOT/pkgbuilds"
  elif [[ -d /pkgbuilds ]]; then
    PKGBUILDS_DIR="/pkgbuilds"
  else
    PKGBUILDS_DIR="pkgbuilds"
  fi
fi

metadata_file_for_dir() {
  local pkgdir="$1"
  echo "$pkgdir/.omarchy/package.json"
}

package_dir_for_name() {
  local package="$1"
  local pkgdir="$PKGBUILDS_DIR/$package"

  [[ -d "$pkgdir" && -f "$pkgdir/PKGBUILD" ]] || return 1
  echo "$pkgdir"
}

package_metadata_value() {
  local pkgdir="$1"
  local jq_filter="$2"
  local default="${3:-}"
  local metadata

  metadata=$(metadata_file_for_dir "$pkgdir")
  if [[ ! -f "$metadata" ]]; then
    echo "$default"
    return 0
  fi

  jq -r --arg default "$default" "$jq_filter // \$default" "$metadata"
}

package_sync_enabled() {
  local pkgdir="$1"
  local metadata source sync

  metadata=$(metadata_file_for_dir "$pkgdir")
  [[ -f "$metadata" ]] || return 1

  source=$(jq -r '.source // ""' "$metadata")
  [[ "$source" == "aur" ]] || return 1

  sync=$(jq -r 'if has("sync") then .sync else true end' "$metadata")
  [[ "$sync" != "false" ]]
}

package_release_ring() {
  local pkgdir="$1"
  package_metadata_value "$pkgdir" '.release_ring' ""
}

package_is_fast_ring() {
  local pkgdir="$1"
  [[ "$(package_release_ring "$pkgdir")" == "fast" ]]
}

package_has_metadata() {
  local pkgdir="$1"
  [[ -f "$(metadata_file_for_dir "$pkgdir")" ]]
}

package_has_pkgbuild() {
  local pkgdir="$1"
  [[ -f "$pkgdir/PKGBUILD" ]]
}

package_builds_for_mirror() {
  local pkgdir="$1"
  local mirror="$2"

  package_has_pkgbuild "$pkgdir" || return 1
  package_has_metadata "$pkgdir" || return 1

  case "$mirror" in
    edge)
      return 0
      ;;
    stable)
      package_is_fast_ring "$pkgdir"
      ;;
    *)
      return 1
      ;;
  esac
}

package_dirs() {
  [[ -d "$PKGBUILDS_DIR" ]] || return 0

  find "$PKGBUILDS_DIR" -mindepth 1 -maxdepth 1 -type d -print | sort | while IFS= read -r pkgdir; do
    package_has_pkgbuild "$pkgdir" || continue
    package_has_metadata "$pkgdir" || continue
    echo "$pkgdir"
  done
}

packages_for_aur_sync() {
  package_dirs | while IFS= read -r pkgdir; do
    if package_sync_enabled "$pkgdir"; then
      basename "$pkgdir"
    fi
  done
}

packages_for_mirror() {
  local mirror="$1"

  package_dirs | while IFS= read -r pkgdir; do
    if package_builds_for_mirror "$pkgdir" "$mirror"; then
      basename "$pkgdir"
    fi
  done
}

package_extract_vcs_hash_from_version() {
  local version="$1"
  local version_no_pkgrel="${version%-*}"
  local candidate hash=""

  # Drop an epoch prefix before scanning for commit-looking components.
  if [[ "$version_no_pkgrel" == *:* ]]; then
    version_no_pkgrel="${version_no_pkgrel#*:}"
  fi

  while IFS= read -r candidate; do
    # Prefer candidates explicitly prefixed with `g`, but also accept bare hex
    # hashes that contain at least one a-f character (e.g. r21251.626ee68).
    if [[ "$candidate" == g* || "$candidate" =~ [a-f] ]]; then
      hash="${candidate#g}"
    fi
  done < <(echo "$version_no_pkgrel" | grep -oE 'g?[a-f0-9]{7,40}')

  [[ -n "$hash" ]] && echo "${hash:0:7}"
}

package_first_git_source() {
  local pkgdir="$1"

  (cd "$pkgdir" && env -u OMARCHY_SRC bash -c '
    source PKGBUILD 2>/dev/null
    for s in "${source[@]}"; do
      url="${s#*::}"
      [[ "$url" == git+* ]] && { echo "${url#git+}"; break; }
    done')
}

package_git_upstream_hash() {
  local pkgdir="$1"
  local source_spec source_url fragment ref hash

  source_spec=$(package_first_git_source "$pkgdir") || return 1
  [[ -n "$source_spec" ]] || return 1

  source_url="${source_spec%%#*}"
  fragment=""
  if [[ "$source_spec" == *"#"* ]]; then
    fragment="${source_spec#*#}"
  fi

  case "$fragment" in
    "")
      hash=$(git ls-remote "$source_url" HEAD 2>/dev/null | awk 'NR == 1 { print substr($1, 1, 7) }')
      ;;
    branch=*)
      ref="${fragment#branch=}"
      [[ -n "$ref" ]] || return 1
      hash=$(git ls-remote "$source_url" "refs/heads/$ref" 2>/dev/null | awk 'NR == 1 { print substr($1, 1, 7) }')
      ;;
    tag=*)
      ref="${fragment#tag=}"
      [[ -n "$ref" ]] || return 1
      hash=$(git ls-remote "$source_url" "refs/tags/$ref^{}" "refs/tags/$ref" 2>/dev/null | awk '
        $2 ~ /\^\{\}$/ { print substr($1, 1, 7); found=1; exit }
        NR == 1 { first=substr($1, 1, 7) }
        END { if (!found && first != "") print first }
      ')
      ;;
    commit=*)
      ref="${fragment#commit=}"
      [[ "$ref" =~ ^[a-f0-9]{7,40}$ ]] || return 1
      hash="${ref:0:7}"
      ;;
    *)
      return 1
      ;;
  esac

  [[ -n "$hash" ]] || return 1
  echo "$hash"
}

validate_package_metadata() {
  local pkgdir="$1"
  local metadata source sync aur ring pkgrel_type

  metadata=$(metadata_file_for_dir "$pkgdir")
  [[ -f "$metadata" ]] || { echo "missing metadata: $metadata"; return 1; }

  jq empty "$metadata" >/dev/null || return 1

  source=$(jq -r '.source // ""' "$metadata")
  case "$source" in
    aur|local) ;;
    *) echo "invalid source for $(basename "$pkgdir"): $source"; return 1 ;;
  esac

  sync=$(jq -r 'if has("sync") then .sync | type else "missing" end' "$metadata")
  case "$sync" in
    boolean|missing) ;;
    *) echo "invalid sync for $(basename "$pkgdir"): must be boolean"; return 1 ;;
  esac

  aur=$(jq -r 'if has("aur") then .aur | type else "missing" end' "$metadata")
  case "$aur" in
    string|missing) ;;
    *) echo "invalid aur for $(basename "$pkgdir"): must be string"; return 1 ;;
  esac

  ring=$(jq -r '.release_ring // ""' "$metadata")
  case "$ring" in
    ""|fast) ;;
    *) echo "invalid release_ring for $(basename "$pkgdir"): $ring"; return 1 ;;
  esac

  pkgrel_type=$(jq -r 'if has("pkgrel") then .pkgrel | type else "missing" end' "$metadata")
  case "$pkgrel_type" in
    object|missing) ;;
    *) echo "invalid pkgrel for $(basename "$pkgdir"): must be an object with optional suffix/offset"; return 1 ;;
  esac

  if ! jq -e '(.pkgrel // {}) | type == "object" and ((.suffix // 1) | type == "number" and floor == . and . >= 1) and ((.offset // 0) | type == "number" and floor == . and . >= 0)' "$metadata" >/dev/null; then
    echo "invalid pkgrel for $(basename "$pkgdir"): must be an object with optional integer suffix >= 1 and offset >= 0"
    return 1
  fi

  if ! jq -e '(.upstream_commit // "") | type == "string"' "$metadata" >/dev/null; then
    echo "invalid upstream_commit for $(basename "$pkgdir"): must be a string"
    return 1
  fi
}
