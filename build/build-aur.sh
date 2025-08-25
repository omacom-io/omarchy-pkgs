#!/bin/bash
# AUR package building functions

# Get version from local repo database
get_local_version() {
  local pkg="$1"
  if [[ -f /output/omarchy.db.tar.zst ]]; then
    # First find the exact desc file for this package (not package-debug, etc)
    # Pattern matches: package-version/desc where version starts with a number
    local desc_file=$(tar -tf /output/omarchy.db.tar.zst | grep "^${pkg}-[0-9].*/desc$" | head -1)

    if [[ -n "$desc_file" ]]; then
      # Extract that specific file and get the version
      tar -xOf /output/omarchy.db.tar.zst "$desc_file" 2>/dev/null |
        awk '/%VERSION%/{getline; print; exit}'
    fi
  fi
}

# Simple function to build an AUR package
build_aur_package() {
  local pkg="$1"
  local opts="$2"

  echo "  -> Processing $pkg..."

  # Get version from AUR API (also gets package base)
  local aur_info=$(curl -s "https://aur.archlinux.org/rpc/?v=5&type=info&arg[]=$pkg")
  local aur_version=$(echo "$aur_info" | jq -r '.results[0].Version // empty')
  local pkg_base=$(echo "$aur_info" | jq -r '.results[0].PackageBase // empty')

  if [[ -z "$aur_version" ]]; then
    echo "    Package not found in AUR"
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

  if [[ "$FORCE_REBUILD" == "true" ]]; then
    echo "    Forcing rebuild (AUR: $aur_version)"
  elif [[ "$local_version" == "$aur_version" ]]; then
    echo "    Up to date: $local_version - Skipping build"
    return 0
  elif [[ -n "$local_version" ]]; then
    echo "    Update available: $local_version -> $aur_version"
  else
    echo "    Not built yet (AUR: $aur_version)"
  fi

  # Always fresh clone when building
  cd /src
  rm -rf "$pkg"

  git clone "https://aur.archlinux.org/${pkg_base}.git" "$pkg" || {
    echo "    Failed to clone $pkg_base"
    FAILED_PACKAGES="$FAILED_PACKAGES $pkg"
    return 1
  }

  cd "$pkg"

  # Build package
  MAKEPKG_FLAGS="-sc --noconfirm"

  # Check for skip-pgp in options or global SKIP_PGP
  if [[ "$SKIP_PGP" == "true" ]] || [[ "$opts" == *"skip-pgp"* ]]; then
    MAKEPKG_FLAGS="$MAKEPKG_FLAGS --skippgpcheck"
    echo "    (skipping PGP verification)"
  fi

  if gpg --list-secret-keys 2>/dev/null | grep -q "sec"; then
    makepkg $MAKEPKG_FLAGS --sign || {
      echo "    Failed to build $pkg"
      FAILED_PACKAGES="$FAILED_PACKAGES $pkg"
      cd /src
      return 1
    }
  else
    makepkg $MAKEPKG_FLAGS || {
      echo "    Failed to build $pkg"
      FAILED_PACKAGES="$FAILED_PACKAGES $pkg"
      cd /src
      return 1
    }
  fi

  # Copy to output and add to temporary build repo
  for pkg_file in *.pkg.tar.*; do
    if [[ -f "$pkg_file" ]] && [[ "$pkg_file" != *.sig ]]; then
      cp "$pkg_file" /output/
      # Add to temporary repo database (pointing to /output files)
      repo-add /tmp/build-repo/omarchy-build.db.tar.gz "/output/$pkg_file"
    fi
  done

  # Update pacman database to see new packages
  sudo pacman -Sy

  echo "    Successfully built $pkg"
  cd /src
}

build_aur_packages() {
  # Work in the mounted src directory
  cd /src

  FAILED_PACKAGES=""

  if [[ -s /tmp/packages.aur ]]; then
    echo "==> Building AUR packages..."
    while IFS= read -r line || [ -n "$line" ]; do
      [[ "$line" =~ ^#.*$ ]] && continue
      [[ -z "$line" ]] && continue

      # Parse package name and options
      package=$(echo "$line" | awk '{print $1}')
      options=$(echo "$line" | awk '{$1=""; print $0}' | xargs)

      # Build the package
      build_aur_package "$package" "$options"
    done </tmp/packages.aur

    # Report failures at the end
    if [[ -n "$FAILED_PACKAGES" ]]; then
      echo ""
      echo "==> Failed packages:"
      for pkg in $FAILED_PACKAGES; do
        echo "  - $pkg"
      done
    fi
  fi
}
