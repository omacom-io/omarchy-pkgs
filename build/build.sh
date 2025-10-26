#!/bin/bash
# Simplified build script - builds all packages in /pkgbuilds/

# Import GPG keys
/build/import-gpg-keys.sh || exit 1

# Add Omarchy repository to pacman.conf if database exists
ARCH=${ARCH:-x86_64}
OUTPUT_DIR="/output/$ARCH"

if [[ -f "$OUTPUT_DIR/omarchy.db.tar.zst" ]]; then
  echo "==> Configuring Omarchy repository for dependency resolution..."
  sudo tee -a /etc/pacman.conf > /dev/null <<EOF

[omarchy]
SigLevel = Optional TrustAll
Server = file://$OUTPUT_DIR
EOF
  echo "  -> Omarchy repository added to pacman.conf"
else
  echo "==> No Omarchy repository database found (this is normal for first build)"
fi

# Sync pacman database
sudo pacman -Sy

echo "==> Package Builder"
echo "==> Target architecture: $ARCH"
echo "==> Output directory: $OUTPUT_DIR"

mkdir -p "$OUTPUT_DIR"

FAILED_PACKAGES=""
SUCCESSFUL_PACKAGES=""
SKIPPED_PACKAGES=""

# Get version from local repo database
get_local_version() {
  local pkg="$1"
  if [[ -f "$OUTPUT_DIR/omarchy.db.tar.zst" ]]; then
    local desc_file=$(tar -tf "$OUTPUT_DIR/omarchy.db.tar.zst" | grep "^${pkg}-[0-9r].*/desc$" | head -1)
    if [[ -n "$desc_file" ]]; then
      tar -xOf "$OUTPUT_DIR/omarchy.db.tar.zst" "$desc_file" 2>/dev/null |
        awk '/%VERSION%/{getline; print; exit}'
    fi
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
  
  # Get PKGBUILD version
  local pkgbuild_version=$(bash -c 'source PKGBUILD; echo "${pkgver}-${pkgrel}"' 2>/dev/null)
  
  if [[ -z "$pkgbuild_version" ]]; then
    echo "    ❌ Failed to read PKGBUILD version"
    FAILED_PACKAGES="$FAILED_PACKAGES $pkg"
    return 1
  fi
  
  # Check if already built
  local local_version=$(get_local_version "$pkg")
  
  if [[ "$local_version" == "$pkgbuild_version" ]]; then
    echo "    ✓ Up to date: $local_version - Skipping"
    SKIPPED_PACKAGES="$SKIPPED_PACKAGES $pkg"
    return 0
  elif [[ -n "$local_version" ]]; then
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
  
  # Build package with signing
  MAKEPKG_FLAGS="-scf --noconfirm"
  
  # Only add sign flag if we have a GPG key configured
  if grep -q "^GPGKEY=" ~/.makepkg.conf 2>/dev/null; then
    GPG_KEY=$(grep "^GPGKEY=" ~/.makepkg.conf | cut -d'"' -f2)
    echo "    Using GPG key: $GPG_KEY"
    MAKEPKG_FLAGS="$MAKEPKG_FLAGS --sign --key $GPG_KEY"
  else
    echo "    No GPG key configured in makepkg.conf"
  fi
  
  if makepkg $MAKEPKG_FLAGS; then
    # Copy to output (including signature files)
    for pkg_file in *.pkg.tar.*; do
      if [[ -f "$pkg_file" ]]; then
        cp "$pkg_file" $OUTPUT_DIR/
      fi
    done
    echo "    ✓ Successfully built $pkg"
    SUCCESSFUL_PACKAGES="$SUCCESSFUL_PACKAGES $pkg"
    return 0
  else
    echo "    ❌ Failed to build $pkg"
    FAILED_PACKAGES="$FAILED_PACKAGES $pkg"
    return 1
  fi
}

# Main execution
cd /src

TOTAL_COUNT=0

# Build all packages in /pkgbuilds/
for pkgdir in /pkgbuilds/*/; do
  [[ ! -d "$pkgdir" ]] && continue
  
  pkg=$(basename "$pkgdir")
  
  # Skip if no PKGBUILD exists
  [[ ! -f "$pkgdir/PKGBUILD" ]] && continue
  
  ((TOTAL_COUNT++))
  
  build_package "$pkg"
done

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
