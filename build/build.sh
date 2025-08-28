#!/bin/bash
# Simplified AUR-only build script that runs inside Docker container

# Import GPG keys
/build/import-gpg-keys.sh || exit 1

# Sync pacman database
sudo pacman -Sy

echo "==> AUR Package Builder"
echo "==> Processing omarchy-aur.packages"

# Track failures
FAILED_PACKAGES=""
SUCCESSFUL_PACKAGES=""
SKIPPED_PACKAGES=""

# Get version from local repo database
get_local_version() {
  local pkg="$1"
  if [[ -f /output/omarchy.db.tar.zst ]]; then
    # Find the exact desc file for this package
    local desc_file=$(tar -tf /output/omarchy.db.tar.zst | grep "^${pkg}-[0-9].*/desc$" | head -1)

    if [[ -n "$desc_file" ]]; then
      # Extract that specific file and get the version
      tar -xOf /output/omarchy.db.tar.zst "$desc_file" 2>/dev/null |
        awk '/%VERSION%/{getline; print; exit}'
    fi
  fi
}

# Build an AUR package
build_aur_package() {
  local pkg="$1"
  local opts="$2"

  echo ""
  echo "  -> Processing $pkg..."

  # Get version from AUR API (also gets package base)
  local aur_info=$(curl -s "https://aur.archlinux.org/rpc/?v=5&type=info&arg[]=$pkg")
  local aur_version=$(echo "$aur_info" | jq -r '.results[0].Version // empty')
  local pkg_base=$(echo "$aur_info" | jq -r '.results[0].PackageBase // empty')

  if [[ -z "$aur_version" ]]; then
    echo "    ❌ Package not found in AUR"
    FAILED_PACKAGES="$FAILED_PACKAGES $pkg"
    return 1
  fi

  # Use package name as base if not specified
  if [[ -z "$pkg_base" ]]; then
    pkg_base="$pkg"
  elif [[ "$pkg_base" != "$pkg" ]]; then
    echo "    Using package base: $pkg_base"
  fi

  # Check if we need to build
  local local_version=$(get_local_version "$pkg")

  if [[ "$local_version" == "$aur_version" ]]; then
    echo "    ✓ Up to date: $local_version - Skipping"
    SKIPPED_PACKAGES="$SKIPPED_PACKAGES $pkg"
    return 0
  elif [[ -n "$local_version" ]]; then
    echo "    Update available: $local_version -> $aur_version"
  else
    echo "    New package (AUR: $aur_version)"
  fi

  # Always fresh clone when building
  cd /src
  rm -rf "$pkg"

  git clone "https://aur.archlinux.org/${pkg_base}.git" "$pkg" || {
    echo "    ❌ Failed to clone $pkg_base"
    FAILED_PACKAGES="$FAILED_PACKAGES $pkg"
    return 1
  }

  cd "$pkg"

  # Build package with signing
  MAKEPKG_FLAGS="-sc --noconfirm"

  # Only add sign flag if we have a GPG key configured
  if grep -q "^GPGKEY=" ~/.makepkg.conf 2>/dev/null; then
    GPG_KEY=$(grep "^GPGKEY=" ~/.makepkg.conf | cut -d'"' -f2)
    echo "    Using GPG key: $GPG_KEY"
    # We already tested signing in import-gpg-keys.sh, just add the flags
    MAKEPKG_FLAGS="$MAKEPKG_FLAGS --sign --key $GPG_KEY"
  else
    echo "    No GPG key configured in makepkg.conf"
  fi

  # Check for skip-pgp in options
  if [[ "$opts" == *"skip-pgp"* ]]; then
    MAKEPKG_FLAGS="$MAKEPKG_FLAGS --skippgpcheck"
    echo "    (skipping PGP verification)"
  fi

  if makepkg $MAKEPKG_FLAGS; then
    # Copy to output (including signature files)
    for pkg_file in *.pkg.tar.*; do
      if [[ -f "$pkg_file" ]]; then
        cp "$pkg_file" /output/
      fi
    done
    echo "    ✓ Successfully built $pkg"
    SUCCESSFUL_PACKAGES="$SUCCESSFUL_PACKAGES $pkg"
  else
    echo "    ❌ Failed to build $pkg"
    FAILED_PACKAGES="$FAILED_PACKAGES $pkg"
    cd /src
    return 1
  fi

  cd /src
}

# Main execution
cd /src

# Read and process the AUR package file
if [[ -f /build/packages/omarchy-aur.packages ]]; then
  TOTAL_COUNT=0

  while IFS= read -r line || [ -n "$line" ]; do
    [[ "$line" =~ ^#.*$ ]] && continue
    [[ -z "$line" ]] && continue

    ((TOTAL_COUNT++))

    # Parse package name and options
    package=$(echo "$line" | awk '{print $1}')
    options=$(echo "$line" | awk '{$1=""; print $0}' | xargs)

    # Build the package
    build_aur_package "$package" "$options"
  done </build/packages/omarchy-aur.packages

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
  else
    echo ""
    echo "==> All packages processed successfully!"
  fi
else
  echo "Error: /build/packages/omarchy-aur.packages not found"
  exit 1
fi

