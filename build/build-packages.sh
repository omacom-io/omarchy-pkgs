#!/bin/bash
# Main build script that runs inside Docker container
set -e

echo "==> Setting up local repository..."
# Create a temporary repo directory for build dependencies
mkdir -p /tmp/build-repo

# Add local repo to pacman.conf so AUR packages can find their dependencies
sudo tee -a /etc/pacman.conf > /dev/null << EOF

[omarchy-build]
SigLevel = Optional TrustAll
Server = file:///tmp/build-repo
EOF

# Create initial empty database
repo-add /tmp/build-repo/omarchy-build.db.tar.gz 2>/dev/null || true

# Sync pacman to recognize the new repo
sudo pacman -Sy

echo "==> Processing package list..."
FAILED_PACKAGES=""
PROCESSED_PACKAGES=""

# Separate packages into official and AUR
> /tmp/packages.official
> /tmp/packages.aur

if [[ -f /home/builder/packages ]]; then
    while IFS= read -r line || [ -n "$line" ]; do
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "$line" ]] && continue
        
        # Parse package name and options
        package=$(echo "$line" | awk '{print $1}')
        options=$(echo "$line" | awk '{$1=""; print $0}' | xargs)
        
        # Check if it's in official repos
        if pacman -Si "$package" &>/dev/null; then
            echo "$package" >> /tmp/packages.official
        else
            echo "$line" >> /tmp/packages.aur  # Keep options for AUR packages
        fi
    done < /home/builder/packages
fi

# Show package counts
echo "==> Package breakdown:"
echo "  -> Official packages: $(wc -l < /tmp/packages.official 2>/dev/null || echo 0)"
echo "  -> AUR packages: $(wc -l < /tmp/packages.aur 2>/dev/null || echo 0)"

# Debug: Show AUR packages if any
if [[ -s /tmp/packages.aur ]]; then
    echo "==> AUR packages to build:"
    cat /tmp/packages.aur | while read line; do
        echo "    - $line"
    done
fi

echo "==> Downloading official packages..."
if [[ -s /tmp/packages.official ]]; then
    while IFS= read -r package || [ -n "$package" ]; do
        echo "  -> Downloading $package..."
        
        # Download package without installing (will use default cache which is now /output)
        sudo pacman -Sw --noconfirm "$package" || {
            # Fallback to direct download
            url=$(pacman -Sp "$package" 2>/dev/null)
            if [[ -n "$url" ]]; then
                wget -q -P /output "$url" || echo "  -> Failed: $package"
            fi
        }
    done < /tmp/packages.official
fi

# Source the AUR build functions
source /home/builder/build-aur.sh

# Build AUR packages
build_aur_packages

echo "==> Build complete!"