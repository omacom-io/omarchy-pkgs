#!/bin/bash
# AUR package building functions

# Simple function to build an AUR package
build_aur_package() {
    local pkg="$1"
    local opts="$2"
    
    echo "  -> Building $pkg..."
    cd /src
    
    # Case 1: Directory exists with PKGBUILD - check for updates
    if [[ -d "$pkg" ]] && [[ -f "$pkg/PKGBUILD" ]]; then
        cd "$pkg"
        
        # Store current commit before pull
        OLD_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "none")
        
        # Try to pull updates
        git pull --quiet
        
        # Get new commit after pull
        NEW_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "none")
        
        # Determine if we need to build
        if [[ "$FORCE_REBUILD" == "true" ]]; then
            echo "    Forcing rebuild..."
        elif [[ "$OLD_COMMIT" != "$NEW_COMMIT" ]]; then
            echo "    Updates found, rebuilding..."
        else
            echo "    No updates found, skipping"
            return 0
        fi
    
    # Case 2: Directory exists but no PKGBUILD - reclone
    elif [[ -d "$pkg" ]]; then
        echo "    Incomplete clone detected, removing and recloning..."
        rm -rf "$pkg"
        git clone "https://aur.archlinux.org/${pkg}.git" || {
            echo "    Failed to clone $pkg"
            FAILED_PACKAGES="$FAILED_PACKAGES $pkg"
            return 1
        }
        cd "$pkg"
    
    # Case 3: Directory doesn't exist - clone
    else
        git clone "https://aur.archlinux.org/${pkg}.git" || {
            echo "    Failed to clone $pkg"
            FAILED_PACKAGES="$FAILED_PACKAGES $pkg"
            return 1
        }
        cd "$pkg"
    fi
    
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
        done < /tmp/packages.aur
        
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