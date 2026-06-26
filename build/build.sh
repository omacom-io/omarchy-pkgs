#!/bin/bash
# Build script - builds packages based on package metadata
# Edge builds all packages. Stable builds only packages in the fast release ring.

# Setup directories
ARCH=${ARCH:-x86_64}
MIRROR=${MIRROR:-edge}
DRY_RUN=${DRY_RUN:-false}
PKGBUILDS_DIR=${PKGBUILDS_DIR:-/pkgbuilds}
BUILD_OUTPUT_DIR=${BUILD_OUTPUT_DIR:-/build-output/$MIRROR/$ARCH}
FINAL_OUTPUT_DIR=${FINAL_OUTPUT_DIR:-/pkgs.omarchy.org/$MIRROR/$ARCH}
HELPERS_DIR=${HELPERS_DIR:-/helpers}
SRC_DIR=${SRC_DIR:-/src}

source "$HELPERS_DIR/package-metadata.sh"

if [[ "$DRY_RUN" != true ]]; then
  # Import GPG keys
  /build/import-gpg-keys.sh || exit 1

  mkdir -p "$BUILD_OUTPUT_DIR" "$FINAL_OUTPUT_DIR"

  # Configure Omarchy repositories for dependency resolution
  echo "==> Configuring Omarchy repositories for dependency resolution..."

  # Always add omarchy-build repo (for incremental builds)
  # Packages in build-output are unsigned, so use SigLevel = Never
  sudo tee -a /etc/pacman.conf > /dev/null <<EOF

[omarchy-build]
SigLevel = Never
Server = file://$BUILD_OUTPUT_DIR
EOF
  echo "  -> omarchy-build (priority 1): $BUILD_OUTPUT_DIR"

  # Initialize empty build database if it doesn't exist
  cd "$BUILD_OUTPUT_DIR"
  if [[ ! -f "omarchy-build.db.tar.zst" ]]; then
    # Create an empty database
    repo-add omarchy-build.db.tar.zst >/dev/null 2>&1
    ln -sf omarchy-build.db.tar.zst omarchy-build.db
  else
    # Database exists, check if we need to rebuild it from packages
    if ls *.pkg.tar.* 2>/dev/null | grep -v '\.sig$' | grep -v 'omarchy-build\.db' | grep -q .; then
      echo "==> Rebuilding build database from existing packages..."
      ls *.pkg.tar.* | grep -v '\.sig$' | grep -v 'omarchy-build\.db' | xargs -r repo-add omarchy-build.db.tar.zst >/dev/null 2>&1
      ln -sf omarchy-build.db.tar.zst omarchy-build.db
    fi
  fi

  # Add omarchy repo if it has a database (stable packages)
  if [[ -f "$FINAL_OUTPUT_DIR/omarchy.db.tar.zst" ]] || [[ -f "$FINAL_OUTPUT_DIR/omarchy.db" ]]; then
    sudo tee -a /etc/pacman.conf > /dev/null <<EOF

[omarchy]
SigLevel = Optional TrustAll
Server = file://$FINAL_OUTPUT_DIR
EOF
    echo "  -> omarchy (priority 2): $FINAL_OUTPUT_DIR"
  fi

  # Sync pacman database
  sudo pacman -Sy
fi

echo "==> Package Builder"
echo "==> Target architecture: $ARCH"
echo "==> Mirror: $MIRROR"
echo "==> Package root: $PKGBUILDS_DIR"
echo "==> Build workspace: $BUILD_OUTPUT_DIR"
echo "==> Final output: $FINAL_OUTPUT_DIR"
if [[ "$DRY_RUN" == true ]]; then
  echo "==> Dry run: yes (plan only; makepkg will not run)"
fi

FAILED_PACKAGES=""
SUCCESSFUL_PACKAGES=""
SKIPPED_PACKAGES=""

# Find package directory
find_package_dir() {
  local pkg="$1"
  package_dir_for_name "$pkg"
}

# Get version from final output (production packages)
#
# Source package directories are named after the PKGBUILD pkgbase, but split
# packages are stored in the repo DB under their individual pkgname entries.
# Cache versions by both %NAME% and %BASE% so a pkgbase like
# libretro-vice-git can be found even though the DB only contains packages like
# libretro-vice-x64-git.
declare -A LOCAL_VERSION_BY_NAME=()
declare -A LOCAL_VERSION_BY_BASE=()
LOCAL_VERSION_CACHE_LOADED=false
LOCAL_VERSION_CACHE_DB=""

load_local_versions() {
  local db="$FINAL_OUTPUT_DIR/omarchy.db.tar.zst"

  if [[ ! -f "$db" ]]; then
    db="$FINAL_OUTPUT_DIR/omarchy.db"
  fi

  [[ -f "$db" ]] || return 0
  [[ "$LOCAL_VERSION_CACHE_LOADED" == true && "$LOCAL_VERSION_CACHE_DB" == "$db" ]] && return 0

  LOCAL_VERSION_BY_NAME=()
  LOCAL_VERSION_BY_BASE=()

  local name base version
  while IFS=$'\t' read -r name base version; do
    [[ -n "$name" && -n "$version" ]] && LOCAL_VERSION_BY_NAME["$name"]="$version"
    [[ -n "$base" && -n "$version" ]] && LOCAL_VERSION_BY_BASE["$base"]="$version"
  done < <(
    tar -xOf "$db" --wildcards '*/desc' 2>/dev/null | awk '
      function emit() {
        if (name != "" && version != "") print name "\t" base "\t" version
        name=""; base=""; version=""
      }
      $0 == "%FILENAME%" { emit(); next }
      $0 == "%NAME%" { if (name != "" && version != "") emit(); getline; name=$0; next }
      $0 == "%BASE%" { getline; base=$0; next }
      $0 == "%VERSION%" { getline; version=$0; next }
      END { emit() }
    '
  )

  LOCAL_VERSION_CACHE_LOADED=true
  LOCAL_VERSION_CACHE_DB="$db"
}

get_local_version() {
  local pkg="$1"

  load_local_versions

  if [[ -n "${LOCAL_VERSION_BY_NAME[$pkg]:-}" ]]; then
    echo "${LOCAL_VERSION_BY_NAME[$pkg]}"
  elif [[ -n "${LOCAL_VERSION_BY_BASE[$pkg]:-}" ]]; then
    echo "${LOCAL_VERSION_BY_BASE[$pkg]}"
  fi
}

# Check if package should be built for current architecture
# Returns 0 (success) if should build, 1 if should skip
should_build_for_arch() {
  local pkg="$1"
  local current_arch="$ARCH"
  local pkgdir=$(find_package_dir "$pkg")
  local pkgbuild="$pkgdir/PKGBUILD"

  [[ ! -f "$pkgbuild" ]] && return 1

  # Check PKGBUILD arch=() array
  local pkgbuild_archs=$(cd "$pkgdir" && bash -c 'source PKGBUILD 2>/dev/null; echo "${arch[@]}"')

  # If arch=('any'), build for all architectures
  if [[ "$pkgbuild_archs" == "any" ]]; then
    return 0
  fi

  # Check if current arch is in PKGBUILD arch=()
  if echo "$pkgbuild_archs" | grep -qw "$current_arch"; then
    return 0  # Build
  else
    return 1  # Skip
  fi
}

# For VCS packages, makepkg recalculates pkgver() before the build. If the
# recalculated pkgver differs from the static PKGBUILD value, makepkg resets
# pkgrel to 1. That is right for stock VCS packages, but wrong for Omarchy's
# patched AUR packages where sync-aur intentionally applies a dotted local
# pkgrel suffix (for example 1.1) to sort above the upstream/AUR package.
# Refresh pkgver once, then restore the local dotted pkgrel before the real
# build so the produced package filename carries the Omarchy revision.
refresh_vcs_pkgver_preserving_local_pkgrel() {
  local pkg="$1"
  local pkgbuild="PKGBUILD"

  grep -qE '^pkgver[[:space:]]*\(\)' "$pkgbuild" || return 0

  local original_pkgver original_pkgrel refreshed_pkgver refreshed_pkgrel
  original_pkgver=$(bash -c 'source PKGBUILD 2>/dev/null; echo "${pkgver:-}"')
  original_pkgrel=$(bash -c 'source PKGBUILD 2>/dev/null; echo "${pkgrel:-}"')

  # Omarchy local rebuilds use dotted pkgrels (AUR pkgrel + .suffix). Plain
  # integer pkgrels can keep makepkg's normal reset-to-1 behavior on new VCS
  # revisions.
  [[ "$original_pkgrel" == *.* ]] || return 0

  echo "    Refreshing VCS pkgver before build (preserving local pkgrel=$original_pkgrel)..."
  if [[ -x /usr/local/bin/pacman-for-makepkg ]]; then
    PACMAN=/usr/local/bin/pacman-for-makepkg makepkg --nobuild --nodeps --skipinteg --skippgpcheck --noprepare --noconfirm
  else
    makepkg --nobuild --nodeps --skipinteg --skippgpcheck --noprepare --noconfirm
  fi

  if [[ $? -ne 0 ]]; then
    echo "    Failed to refresh VCS pkgver for $pkg"
    return 1
  fi

  refreshed_pkgver=$(bash -c 'source PKGBUILD 2>/dev/null; echo "${pkgver:-}"')
  refreshed_pkgrel=$(bash -c 'source PKGBUILD 2>/dev/null; echo "${pkgrel:-}"')

  if [[ "$refreshed_pkgrel" != "$original_pkgrel" ]]; then
    sed -i "s/^pkgrel=.*/pkgrel=$original_pkgrel/" PKGBUILD
    echo "    Restored local pkgrel suffix: $refreshed_pkgrel -> $original_pkgrel"
  fi

  if [[ -n "$refreshed_pkgver" && "$refreshed_pkgver" != "$original_pkgver" ]]; then
    echo "    Refreshed VCS version: $original_pkgver -> $refreshed_pkgver"
  fi
}

# Build a package
build_package() {
  local pkg="$1"
  local pkgdir=$(find_package_dir "$pkg")

  echo ""
  echo "  -> Processing: $pkg"

  # Copy to build directory
  cd /src
  rm -rf "$pkg"
  cp -r "$pkgdir" "$pkg"
  cd "/src/$pkg" || return 1

  refresh_vcs_pkgver_preserving_local_pkgrel "$pkg" || {
    FAILED_PACKAGES="$FAILED_PACKAGES $pkg"
    return 1
  }

  # Get PKGBUILD version (including epoch if present)
  local pkgbuild_version=$(bash -c 'source PKGBUILD; if [[ -n "$epoch" ]]; then echo "${epoch}:${pkgver}-${pkgrel}"; else echo "${pkgver}-${pkgrel}"; fi' 2>/dev/null)

  if [[ -z "$pkgbuild_version" ]]; then
    echo "    Failed to read PKGBUILD version"
    FAILED_PACKAGES="$FAILED_PACKAGES $pkg"
    return 1
  fi

  # Show version info (version check already done in first pass)
  local local_version=$(get_local_version "$pkg")
  if [[ -n "$local_version" ]]; then
    echo "    Update available: $local_version -> $pkgbuild_version"
  else
    echo "    New package (version: $pkgbuild_version)"
  fi

  # Import PGP keys from PKGBUILD validpgpkeys and keys/pgp/ directory
  local pgp_keys=$(bash -c 'source PKGBUILD 2>/dev/null; echo "${validpgpkeys[@]}"')
  if [[ -n "$pgp_keys" ]]; then
    echo "    Importing PGP keys from validpgpkeys..."
    for key in $pgp_keys; do
      gpg --receive-keys "$key" 2>/dev/null && echo "      Received $key" || echo "      Failed to receive $key"
    done
  fi
  if [[ -d "keys/pgp" ]]; then
    echo "    Importing package-specific PGP keys..."
    for keyfile in keys/pgp/*.asc; do
      if [[ -f "$keyfile" ]]; then
        gpg --import "$keyfile" 2>/dev/null && echo "      Imported $(basename "$keyfile")" || echo "      Failed to import $(basename "$keyfile")"
      fi
    done
  fi

  # Build package without signing (signing is done separately)
  # PACMAN override uses a wrapper that adds --ask 4 to auto-resolve conflicts
  # (e.g. rustup replacing rust) since --noconfirm defaults to 'N' on those prompts
  MAKEPKG_FLAGS="-scf --noconfirm"

  if PACMAN=/usr/local/bin/pacman-for-makepkg makepkg $MAKEPKG_FLAGS; then
    # Ensure output directory exists
    mkdir -p "$BUILD_OUTPUT_DIR"
    
    for pkg_file in *.pkg.tar.*; do
      [[ -f "$pkg_file" ]] && cp "$pkg_file" "$BUILD_OUTPUT_DIR/"
    done

    cd "$BUILD_OUTPUT_DIR"

    # Find ALL package files (handles split packages)
    local new_pkgs=($(ls -t ${pkg}-*.pkg.tar.* 2>/dev/null | grep -v '\.sig$' | grep -v 'omarchy-build\.db'))

    if [[ ${#new_pkgs[@]} -gt 0 ]]; then
      repo-add omarchy-build.db.tar.zst "${new_pkgs[@]}" >/dev/null 2>&1
      ln -sf omarchy-build.db.tar.zst omarchy-build.db
      sudo pacman -Sy >/dev/null 2>&1
    fi

    cd /src/$pkg

    echo "    Successfully built $pkg"
    SUCCESSFUL_PACKAGES="$SUCCESSFUL_PACKAGES $pkg"
    return 0
  else
    echo "    Makepkg failed for $pkg"
    echo "    DEBUG: Files in build directory:"
    ls -lah *.pkg.tar.* 2>&1 | head -20 || echo "    No package files found"
    FAILED_PACKAGES="$FAILED_PACKAGES $pkg"
    return 1
  fi
}

# Get package dependencies from PKGBUILD
get_package_deps() {
  local pkg="$1"
  local pkgdir=$(find_package_dir "$pkg")
  local pkgbuild="$pkgdir/PKGBUILD"

  if [[ ! -f "$pkgbuild" ]]; then
    return
  fi

  # Extract depends and makedepends, filter for packages in our pkgbuilds/
  (
    source "$pkgbuild" 2>/dev/null
    echo "${depends[@]} ${makedepends[@]}"
  ) | tr ' ' '\n' | while read -r dep; do
    # Strip version constraints (e.g., 'hyprshade>=1.0' -> 'hyprshade')
    dep=$(echo "$dep" | sed 's/[<>=].*$//')
    # Check if this dependency exists in our pkgbuilds
    if find_package_dir "$dep" >/dev/null 2>&1; then
      echo "$dep"
    fi
  done
}

# For VCS packages (those with a pkgver() function), the static pkgver= in the
# PKGBUILD is just a placeholder; the real version is computed at build time
# from the git checkout. Without this check, version comparison always reports a
# mismatch and we rebuild on every run, producing a package with the same
# name+version as one already in production. Detect this by comparing the
# upstream commit hash to the hash suffix already in the production version
# (both `...gabcdef0` and `...abcdef0` styles are common). Returns 0 when
# upstream is unchanged (build can be skipped).
check_vcs_unchanged() {
  local pkg="$1"
  local pkgdir="$2"
  local pkgbuild="$pkgdir/PKGBUILD"

  grep -qE '^pkgver[[:space:]]*\(\)' "$pkgbuild" || return 1

  local local_version=$(get_local_version "$pkg")
  [[ -z "$local_version" ]] && return 1

  # If epoch or pkgrel changed in PKGBUILD, rebuild even if upstream is unchanged
  local pkgbuild_epoch=$(cd "$pkgdir" && bash -c 'source PKGBUILD 2>/dev/null; echo "${epoch:-}"')
  local pkgbuild_pkgrel=$(cd "$pkgdir" && bash -c 'source PKGBUILD 2>/dev/null; echo "${pkgrel}"')

  local prod_pkgrel="${local_version##*-}"
  local prod_no_pkgrel="${local_version%-*}"
  local prod_epoch=""
  if [[ "$prod_no_pkgrel" == *:* ]]; then
    prod_epoch="${prod_no_pkgrel%%:*}"
  fi

  [[ "$pkgbuild_epoch" != "$prod_epoch" ]] && return 1
  [[ "$pkgbuild_pkgrel" != "$prod_pkgrel" ]] && return 1

  # Compare the commit represented in the published version to the current
  # upstream ref. Supports unfragmented git sources as well as #branch=,
  # #tag=, and #commit= fragments.
  local prod_hash=$(package_extract_vcs_hash_from_version "$local_version")
  [[ -z "$prod_hash" ]] && return 1

  local upstream_hash=$(package_git_upstream_hash "$pkgdir")
  [[ -z "$upstream_hash" ]] && return 1

  [[ "$prod_hash" == "$upstream_hash" ]]
}

# Check which packages need building (version check only)
check_needs_build() {
  local pkg="$1"
  local pkgdir=$(find_package_dir "$pkg")
  local pkgbuild="$pkgdir/PKGBUILD"

  [[ ! -f "$pkgbuild" ]] && return 1

  # Get PKGBUILD version (including epoch if present)
  local pkgbuild_version=$(cd "$pkgdir" && bash -c 'source PKGBUILD; if [[ -n "$epoch" ]]; then echo "${epoch}:${pkgver}-${pkgrel}"; else echo "${pkgver}-${pkgrel}"; fi' 2>/dev/null)
  [[ -z "$pkgbuild_version" ]] && return 1

  # Check if already built
  local local_version=$(get_local_version "$pkg")

  if grep -qE '^pkgver[[:space:]]*\(\)' "$pkgbuild"; then
    if [[ -n "$local_version" && -n "$(package_extract_vcs_hash_from_version "$local_version")" ]]; then
      if check_vcs_unchanged "$pkg" "$pkgdir"; then
        return 1  # VCS upstream ref is already represented in the repo
      else
        return 0  # New VCS ref, missing repo package, or pkgrel/epoch changed
      fi
    elif [[ "$local_version" == "$pkgbuild_version" ]]; then
      return 1  # VCS package does not expose a hash; fall back to static version
    else
      return 0
    fi
  fi

  if [[ "$local_version" == "$pkgbuild_version" ]]; then
    return 1  # Already up to date
  else
    return 0  # Needs building
  fi
}

# Collect packages that should be built for the selected mirror
collect_packages() {
  packages_for_mirror "$MIRROR"
}

# Main execution
if [[ "$DRY_RUN" != true ]]; then
  cd "$SRC_DIR"
fi

TOTAL_COUNT=0

echo "==> Checking which packages need building..."

# First pass: determine which packages need building
PACKAGES_TO_BUILD=()

# If PACKAGES is specified, only check those packages
if [[ -n "$PACKAGES" ]]; then
  echo "==> Checking specified packages: $PACKAGES"
  for pkg_name in $PACKAGES; do
    pkgdir=$(find_package_dir "$pkg_name")
    if [[ -z "$pkgdir" || ! -f "$pkgdir/PKGBUILD" ]]; then
      echo "==> ERROR: Package '$pkg_name' not found in $PKGBUILDS_DIR"
      exit 1
    fi

    if ! package_builds_for_mirror "$pkgdir" "$MIRROR"; then
      if [[ "$MIRROR" == "stable" ]]; then
        echo "  - $pkg_name - not in release_ring=fast; build edge and promote with repo migrate"
      else
        echo "  - $pkg_name - not configured for direct $MIRROR builds"
      fi
      SKIPPED_PACKAGES="$SKIPPED_PACKAGES $pkg_name"
      continue
    fi

    # Check if package should be built for this architecture
    if ! should_build_for_arch "$pkg_name"; then
      echo "  - $pkg_name - not built for $ARCH"
      SKIPPED_PACKAGES="$SKIPPED_PACKAGES $pkg_name"
      continue
    fi

    if check_needs_build "$pkg_name"; then
      PACKAGES_TO_BUILD+=("$pkg_name")
    else
      echo "  + $pkg_name - already up to date"
      SKIPPED_PACKAGES="$SKIPPED_PACKAGES $pkg_name"
    fi
  done
else
  # Build all packages that need updates from the relevant directories
  while IFS= read -r pkg; do
    # Check if package should be built for this architecture
    if ! should_build_for_arch "$pkg"; then
      echo "  - $pkg - not built for $ARCH"
      SKIPPED_PACKAGES="$SKIPPED_PACKAGES $pkg"
      continue
    fi

    if check_needs_build "$pkg"; then
      PACKAGES_TO_BUILD+=("$pkg")
    else
      echo "  + $pkg - already up to date"
      SKIPPED_PACKAGES="$SKIPPED_PACKAGES $pkg"
    fi
  done < <(collect_packages)
fi

if [[ ${#PACKAGES_TO_BUILD[@]} -eq 0 ]]; then
  echo "==> All packages are up to date!"
else
  echo "==> ${#PACKAGES_TO_BUILD[@]} package(s) need building: ${PACKAGES_TO_BUILD[@]}"
  echo "==> Determining build order based on dependencies..."

  # Second pass: order only the packages that need building
  # Strategy: build packages with no unmet dependencies first
  declare -A unmet_deps_count  # How many dependencies does this package still need?
  declare -A blocks_packages    # Which packages are waiting for this one?

  # Count unmet dependencies for each package
  for pkg in "${PACKAGES_TO_BUILD[@]}"; do
    unmet_deps_count[$pkg]=0
  done

  # Build the dependency relationships
  for pkg in "${PACKAGES_TO_BUILD[@]}"; do
    while IFS= read -r dep; do
      # Only care about deps that are being built in this run
      for build_pkg in "${PACKAGES_TO_BUILD[@]}"; do
        if [[ "$dep" == "$build_pkg" ]]; then
          # pkg needs dep, so increment pkg's unmet count
          ((unmet_deps_count[$pkg]++))
          # Track that dep blocks pkg from building
          blocks_packages[$dep]="${blocks_packages[$dep]} $pkg"
        fi
      done
    done < <(get_package_deps "$pkg")
  done

  # Start with packages that have all dependencies met (count = 0)
  ready_to_build=()
  for pkg in "${PACKAGES_TO_BUILD[@]}"; do
    if [[ ${unmet_deps_count[$pkg]} -eq 0 ]]; then
      ready_to_build+=("$pkg")
    fi
  done

  # Build packages as dependencies become available
  ORDERED_PACKAGES=()
  while [[ ${#ready_to_build[@]} -gt 0 ]]; do
    # Take the first ready package
    current="${ready_to_build[0]}"
    ready_to_build=("${ready_to_build[@]:1}")
    ORDERED_PACKAGES+=("$current")

    # This package is now built, so packages waiting for it can proceed
    for blocked_pkg in ${blocks_packages[$current]}; do
      ((unmet_deps_count[$blocked_pkg]--))
      if [[ ${unmet_deps_count[$blocked_pkg]} -eq 0 ]]; then
        ready_to_build+=("$blocked_pkg")
      fi
    done
  done

  # Check for circular dependencies
  if [[ ${#ORDERED_PACKAGES[@]} -ne ${#PACKAGES_TO_BUILD[@]} ]]; then
    echo "ERROR: Circular dependency detected!"
    exit 1
  fi

  echo "==> Build order: ${ORDERED_PACKAGES[@]}"

  if [[ "$DRY_RUN" == true ]]; then
    echo ""
    echo "==> Dry run complete. Packages that would build: ${ORDERED_PACKAGES[@]}"
    exit 0
  fi

  # Determine which packages need to be installed for other packages being built
  declare -A INSTALL_PACKAGES
  for pkg in "${ORDERED_PACKAGES[@]}"; do
    while IFS= read -r dep; do
      [[ -z "$dep" ]] && continue
      # Only install if it's being built in this run
      for build_pkg in "${ORDERED_PACKAGES[@]}"; do
        [[ "$dep" == "$build_pkg" ]] && INSTALL_PACKAGES["$dep"]=1
      done
    done < <(get_package_deps "$pkg")
  done

  if [[ ${#INSTALL_PACKAGES[@]} -gt 0 ]]; then
    echo "==> Packages needed as dependencies: ${!INSTALL_PACKAGES[@]}"
  fi

  # Build packages in dependency order
  for pkg in "${ORDERED_PACKAGES[@]}"; do
    ((TOTAL_COUNT++))
    build_package "$pkg"
  done
fi

echo ""
echo "========================================"
echo "==> Build Summary"
echo "========================================"

# Count results
SUCCESS_COUNT=$(echo $SUCCESSFUL_PACKAGES | wc -w)
SKIPPED_COUNT=$(echo $SKIPPED_PACKAGES | wc -w)
FAILED_COUNT=$(echo $FAILED_PACKAGES | wc -w)

echo "  Total packages: $TOTAL_COUNT"
echo "  Built:          $SUCCESS_COUNT"
echo "  Skipped:        $SKIPPED_COUNT (already up-to-date)"
echo "  Failed:         $FAILED_COUNT"

# List failures if any
if [[ -n "$FAILED_PACKAGES" ]]; then
  echo ""
  echo "Failed packages:"
  for pkg in $FAILED_PACKAGES; do
    echo "  - $pkg"
  done
  echo ""
  echo "==> Some packages failed to build"
  exit 1
fi

echo ""
echo "==> All packages processed successfully!"
