#!/bin/bash
# Simplified build script - builds all packages in /pkgbuilds/

# Import GPG keys
/build/import-gpg-keys.sh || exit 1

# Setup directories
ARCH=${ARCH:-x86_64}
MIRROR=${MIRROR:-edge}
BUILD_OUTPUT_DIR="/build-output/$MIRROR/$ARCH"
FINAL_OUTPUT_DIR="/pkgs.omarchy.org/$MIRROR/$ARCH"

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

echo "==> Package Builder"
echo "==> Target architecture: $ARCH"
echo "==> Mirror: $MIRROR"
echo "==> Build workspace: $BUILD_OUTPUT_DIR"
echo "==> Final output: $FINAL_OUTPUT_DIR"

FAILED_PACKAGES=""
SUCCESSFUL_PACKAGES=""
SKIPPED_PACKAGES=""

# Get version from final output (production packages)
get_local_version() {
  local pkg="$1"
  if [[ -f "$FINAL_OUTPUT_DIR/omarchy.db.tar.zst" ]]; then
    local desc_file=$(tar -tf "$FINAL_OUTPUT_DIR/omarchy.db.tar.zst" | grep "^${pkg}-[0-9r].*/desc$" | head -1)
    if [[ -n "$desc_file" ]]; then
      tar -xOf "$FINAL_OUTPUT_DIR/omarchy.db.tar.zst" "$desc_file" 2>/dev/null |
        awk '/%VERSION%/{getline; print; exit}'
    fi
  fi
}

# Check if package should be built for current architecture
# Returns 0 (success) if should build, 1 if should skip
should_build_for_arch() {
  local pkg="$1"
  local current_arch="$ARCH"
  local pkgbuild="/pkgbuilds/$pkg/PKGBUILD"

  [[ ! -f "$pkgbuild" ]] && return 1

  # Check PKGBUILD arch=() array
  local pkgbuild_archs=$(cd "/pkgbuilds/$pkg" && bash -c 'source PKGBUILD 2>/dev/null; echo "${arch[@]}"')

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

# Build a package from /pkgbuilds/
build_package() {
  local pkg="$1"

  echo ""
  echo "  -> Processing: $pkg"

  # Copy to build directory
  cd /src
  rm -rf "$pkg"
  cp -r "/pkgbuilds/$pkg" "$pkg"
  cd "/src/$pkg" || return 1

  # Get PKGBUILD version (including epoch if present)
  local pkgbuild_version=$(bash -c 'source PKGBUILD; if [[ -n "$epoch" ]]; then echo "${epoch}:${pkgver}-${pkgrel}"; else echo "${pkgver}-${pkgrel}"; fi' 2>/dev/null)

  if [[ -z "$pkgbuild_version" ]]; then
    echo "    ❌ Failed to read PKGBUILD version"
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

  # Import package-specific PGP keys if they exist
  if [[ -d "keys/pgp" ]]; then
    echo "    Importing package-specific PGP keys..."
    for keyfile in keys/pgp/*.asc; do
      if [[ -f "$keyfile" ]]; then
        gpg --import "$keyfile" 2>/dev/null && echo "      ✓ Imported $(basename "$keyfile")" || echo "      ⚠ Failed to import $(basename "$keyfile")"
      fi
    done
  fi

  # Build package without signing (signing is done separately)
  MAKEPKG_FLAGS="-scf --noconfirm"

  if makepkg $MAKEPKG_FLAGS; then
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

    echo "    ✓ Successfully built $pkg"
    SUCCESSFUL_PACKAGES="$SUCCESSFUL_PACKAGES $pkg"
    return 0
  else
    echo "    ❌ Makepkg failed for $pkg"
    echo "    DEBUG: Files in build directory:"
    ls -lah *.pkg.tar.* 2>&1 | head -20 || echo "    No package files found"
    FAILED_PACKAGES="$FAILED_PACKAGES $pkg"
    return 1
  fi
}

# Get package dependencies from PKGBUILD
get_package_deps() {
  local pkg="$1"
  local pkgbuild="/pkgbuilds/$pkg/PKGBUILD"

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
    if [[ -d "/pkgbuilds/$dep" ]]; then
      echo "$dep"
    fi
  done
}

# Simple dependency-aware build order
# Build packages with no internal deps first, then those that depend on them
build_order() {
  local -a all_packages=()
  local -a result=()
  local -A package_deps_count=()

  # Collect all packages
  for pkgdir in /pkgbuilds/*/; do
    [[ ! -d "$pkgdir" ]] && continue
    local pkg=$(basename "$pkgdir")
    [[ ! -f "$pkgdir/PKGBUILD" ]] && continue
    all_packages+=("$pkg")

    # Count internal dependencies
    local dep_count=0
    while read -r dep; do
      ((dep_count++))
    done < <(get_package_deps "$pkg")
    package_deps_count[$pkg]=$dep_count
  done

  # Sort: packages with fewer deps first
  while IFS= read -r pkg; do
    result+=("$pkg")
  done < <(
    for pkg in "${all_packages[@]}"; do
      echo "${package_deps_count[$pkg]} $pkg"
    done | sort -n | cut -d' ' -f2-
  )

  # Output in build order
  printf '%s\n' "${result[@]}"
}

# Check which packages need building (version check only)
check_needs_build() {
  local pkg="$1"
  local pkgbuild="/pkgbuilds/$pkg/PKGBUILD"

  [[ ! -f "$pkgbuild" ]] && return 1

  # Get PKGBUILD version (including epoch if present)
  local pkgbuild_version=$(cd "/pkgbuilds/$pkg" && bash -c 'source PKGBUILD; if [[ -n "$epoch" ]]; then echo "${epoch}:${pkgver}-${pkgrel}"; else echo "${pkgver}-${pkgrel}"; fi' 2>/dev/null)
  [[ -z "$pkgbuild_version" ]] && return 1

  # Check if already built
  local local_version=$(get_local_version "$pkg")

  if [[ "$local_version" == "$pkgbuild_version" ]]; then
    return 1  # Already up to date
  else
    return 0  # Needs building
  fi
}

# Main execution
cd /src

TOTAL_COUNT=0

echo "==> Checking which packages need building..."

# First pass: determine which packages need building
PACKAGES_TO_BUILD=()

# If PACKAGES is specified, only check those packages
if [[ -n "$PACKAGES" ]]; then
  echo "==> Checking specified packages: $PACKAGES"
  for pkg_name in $PACKAGES; do
    if [[ ! -f "/pkgbuilds/$pkg_name/PKGBUILD" ]]; then
      echo "==> ERROR: Package '$pkg_name' not found in /pkgbuilds/"
      exit 1
    fi

    # Check if package should be built for this architecture
    if ! should_build_for_arch "$pkg_name"; then
      echo "  ⊘ $pkg_name - not built for $ARCH"
      SKIPPED_PACKAGES="$SKIPPED_PACKAGES $pkg_name"
      continue
    fi

    if check_needs_build "$pkg_name"; then
      PACKAGES_TO_BUILD+=("$pkg_name")
    else
      echo "  ✓ $pkg_name - already up to date"
      SKIPPED_PACKAGES="$SKIPPED_PACKAGES $pkg_name"
    fi
  done
else
  # Build all packages that need updates
  for pkgdir in /pkgbuilds/*/; do
    [[ ! -d "$pkgdir" ]] && continue
    pkg=$(basename "$pkgdir")
    [[ ! -f "$pkgdir/PKGBUILD" ]] && continue

    # Check if package should be built for this architecture
    if ! should_build_for_arch "$pkg"; then
      echo "  ⊘ $pkg - not built for $ARCH"
      SKIPPED_PACKAGES="$SKIPPED_PACKAGES $pkg"
      continue
    fi

    if check_needs_build "$pkg"; then
      PACKAGES_TO_BUILD+=("$pkg")
    else
      echo "  ✓ $pkg - already up to date"
      SKIPPED_PACKAGES="$SKIPPED_PACKAGES $pkg"
    fi
  done
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
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "==> Build Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Count results
SUCCESS_COUNT=$(echo $SUCCESSFUL_PACKAGES | wc -w)
SKIPPED_COUNT=$(echo $SKIPPED_PACKAGES | wc -w)
FAILED_COUNT=$(echo $FAILED_PACKAGES | wc -w)

echo "  Total packages: $TOTAL_COUNT"
echo "  ✓ Built:        $SUCCESS_COUNT"
echo "  ⏭  Skipped:      $SKIPPED_COUNT (already up-to-date)"
echo "  ❌ Failed:       $FAILED_COUNT"

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
