#!/bin/bash
# Build script that handles both AUR and GitHub packages inside Docker container

# Import GPG keys
/build/import-gpg-keys.sh || exit 1

# Sync pacman database
sudo pacman -Sy

# Get architecture (default to x86_64 if not set)
ARCH=${ARCH:-x86_64}
OUTPUT_DIR="/output/$ARCH"

echo "==> Package Builder (AUR & GitHub)"
echo "==> Target architecture: $ARCH"
echo "==> Output directory: $OUTPUT_DIR"
echo "==> Processing omarchy-aur.packages"

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Track failures
FAILED_PACKAGES=""
SUCCESSFUL_PACKAGES=""
SKIPPED_PACKAGES=""

# Get version from local repo database
get_local_version() {
  local pkg="$1"
  if [[ -f "$OUTPUT_DIR/omarchy.db.tar.zst" ]]; then
    # Find the exact desc file for this package
    # For VCS packages, version might start with 'r' instead of a digit
    local desc_file=$(tar -tf "$OUTPUT_DIR/omarchy.db.tar.zst" | grep "^${pkg}-[0-9r].*/desc$" | head -1)

    if [[ -n "$desc_file" ]]; then
      # Extract that specific file and get the version
      tar -xOf "$OUTPUT_DIR/omarchy.db.tar.zst" "$desc_file" 2>/dev/null |
        awk '/%VERSION%/{getline; print; exit}'
    fi
  fi
}

# Build a GitHub package
build_github_package() {
  local github_repo="$1"
  local opts="$2"

  echo ""
  echo "  -> Processing GitHub: $github_repo..."

  # Extract owner and repo name
  local owner=$(echo "$github_repo" | cut -d'/' -f1)
  local repo=$(echo "$github_repo" | cut -d'/' -f2)

  if [[ -z "$owner" ]] || [[ -z "$repo" ]]; then
    echo "    ❌ Invalid GitHub format. Use: owner/repo"
    FAILED_PACKAGES="$FAILED_PACKAGES $github_repo"
    return 1
  fi

  # Use repo name as package name for local tracking
  local pkg="$repo"

  echo "    GitHub repository: https://github.com/$github_repo"

  # Check for always-build option
  if [[ "$opts" == *"always-build"* ]]; then
    echo "    Note: Package flagged as always-build, will use timestamp version"
    # Skip version checking for always-build packages
  elif [[ "$pkg" == *-git ]]; then
    # For -git packages, check if we need to rebuild based on commit
    # Check if a source repo is specified (for packages where PKGBUILD repo != source repo)
    local source_repo=""
    if [[ "$opts" =~ source:([^ ]+) ]]; then
      source_repo="${BASH_REMATCH[1]}"
      echo "    Checking source repository: $source_repo"
    fi

    # Use source repo if specified, otherwise use the PKGBUILD repo
    local check_repo="${source_repo:-$github_repo}"
    local latest_commit=$(git ls-remote "https://github.com/${check_repo}.git" HEAD 2>/dev/null | cut -f1 | head -c 7)

    if [[ -n "$latest_commit" ]]; then
      local local_version=$(get_local_version "$pkg")

      if [[ -n "$local_version" ]]; then
        # Extract commit hash from version (format: r<rev>.<commit>-<pkgrel>)
        local local_commit=$(echo "$local_version" | grep -oE '\.[a-f0-9]{7}' | cut -d'.' -f2)

        if [[ "$local_commit" == "$latest_commit" ]]; then
          echo "    ✓ Up to date: commit $latest_commit - Skipping"
          SKIPPED_PACKAGES="$SKIPPED_PACKAGES $github_repo"

          # If install option is set, install the existing package for dependencies
          if [[ "$opts" == *"install"* ]]; then
            echo "    Installing existing package for dependencies..."
            local latest_pkg=$(ls -t $OUTPUT_DIR/${pkg}-*.pkg.tar.* 2>/dev/null | grep -v '\.sig$' | head -1)
            if [[ -f "$latest_pkg" ]]; then
              sudo pacman -U --noconfirm --needed "$latest_pkg" 2>/dev/null || true
            fi
          fi
          return 0
        else
          echo "    Update available: $local_commit -> $latest_commit"
        fi
      else
        echo "    New package (commit: $latest_commit)"
      fi
    fi
  else
    echo "    Note: Non-git GitHub package, will check PKGBUILD version"
  fi

  # Fresh clone for building
  cd /src
  rm -rf "$pkg"

  git clone "https://github.com/${github_repo}.git" "$pkg" || {
    echo "    ❌ Failed to clone $github_repo"
    FAILED_PACKAGES="$FAILED_PACKAGES $github_repo"
    return 1
  }

  cd "$pkg"

  # Check if PKGBUILD exists
  if [[ ! -f "PKGBUILD" ]]; then
    echo "    ❌ No PKGBUILD found in repository"
    FAILED_PACKAGES="$FAILED_PACKAGES $github_repo"
    cd /src
    return 1
  fi

  # For always-build packages, inject timestamp into pkgver to ensure unique filename
  if [[ "$opts" == *"always-build"* ]]; then
    # Get current date/time as version suffix
    local timestamp=$(date +%Y%m%d.%H%M%S)
    echo "    Injecting timestamp: $timestamp"

    # Modify PKGBUILD to append timestamp to pkgver
    if grep -q '^pkgver=' PKGBUILD; then
      # Get current pkgver and append timestamp
      local current_pkgver=$(grep '^pkgver=' PKGBUILD | cut -d'=' -f2 | tr -d "'\"")
      sed -i "s/^pkgver=.*/pkgver=${current_pkgver}.${timestamp}/" PKGBUILD
      echo "    Modified pkgver to: ${current_pkgver}.${timestamp}"
    fi
  fi

  # Build package with signing
  MAKEPKG_FLAGS="-sc --noconfirm"

  # Only add sign flag if we have a GPG key configured
  if grep -q "^GPGKEY=" ~/.makepkg.conf 2>/dev/null; then
    GPG_KEY=$(grep "^GPGKEY=" ~/.makepkg.conf | cut -d'"' -f2)
    echo "    Using GPG key: $GPG_KEY"
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
        cp "$pkg_file" $OUTPUT_DIR/
        # Check for install option to make package available for dependencies
        if [[ "$opts" == *"install"* ]] && [[ "$pkg_file" =~ ^${pkg}-[0-9].*\.pkg\.tar\..* ]] && [[ "$pkg_file" != *.sig ]]; then
          echo "    Installing locally for dependencies..."
          sudo pacman -U --noconfirm --needed "$pkg_file" 2>/dev/null || true
        fi
      fi
    done
    echo "    ✓ Successfully built $github_repo"
    SUCCESSFUL_PACKAGES="$SUCCESSFUL_PACKAGES $github_repo"
  else
    echo "    ❌ Failed to build $github_repo"
    FAILED_PACKAGES="$FAILED_PACKAGES $github_repo"
    cd /src
    return 1
  fi

  cd /src
}

# Build an AUR package
build_aur_package() {
  local pkg="$1"
  local opts="$2"

  echo ""
  echo "  -> Processing AUR: $pkg..."

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

    # If install option is set, install the existing package for dependencies
    if [[ "$opts" == *"install"* ]]; then
      echo "    Installing existing package for dependencies..."
      # Find the main package file in output directory (match package-version pattern, not debug)
      local latest_pkg=$(ls -t $OUTPUT_DIR/${pkg}-[0-9]*.pkg.tar.* 2>/dev/null | grep -v '\.sig$' | head -1)
      if [[ -f "$latest_pkg" ]]; then
        sudo pacman -U --noconfirm --needed "$latest_pkg" 2>/dev/null || true
      else
        echo "    Warning: Package file not found in /output"
      fi
    fi

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
        cp "$pkg_file" $OUTPUT_DIR/
        # Check for install option to make package available for dependencies
        if [[ "$opts" == *"install"* ]] && [[ "$pkg_file" =~ ^${pkg}-[0-9].*\.pkg\.tar\..* ]] && [[ "$pkg_file" != *.sig ]]; then
          echo "    Installing locally for dependencies..."
          sudo pacman -U --noconfirm --needed "$pkg_file" 2>/dev/null || true
        fi
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

    # Check if this is a GitHub package (contains /)
    if [[ "$package" == *"/"* ]]; then
      # GitHub package format: owner/repo
      build_github_package "$package" "$options"
    else
      # Regular AUR package
      build_aur_package "$package" "$options"
    fi
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
