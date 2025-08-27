#!/bin/bash
# Main build script that runs inside Docker container
# Don't use set -e so we can handle errors gracefully

# Import GPG keys
/build/import-gpg-keys.sh

# Sync pacman database
sudo pacman -Sy

echo "==> Processing package lists..."
FAILED_PACKAGES=""
PROCESSED_PACKAGES=""

# Merge and deduplicate all *.packages files from /build/packages
cat /build/packages/*.packages 2>/dev/null | \
    grep -v '^#' | grep -v '^$' | \
    awk '!seen[$1]++ {print}' > /tmp/packages.merged

# If ONLY_PACKAGES is set, filter the merged list
if [[ -n "$ONLY_PACKAGES" ]]; then
    echo "==> Filtering packages: $ONLY_PACKAGES"
    > /tmp/packages.filtered
    for pkg in $ONLY_PACKAGES; do
        grep "^$pkg\( \|$\)" /tmp/packages.merged >> /tmp/packages.filtered || echo "  -> Warning: $pkg not found in package lists"
    done
    mv /tmp/packages.filtered /tmp/packages.merged
fi

# Separate packages into official and AUR
> /tmp/packages.official
> /tmp/packages.aur

while IFS= read -r line || [ -n "$line" ]; do
    # Parse package name and options
    package=$(echo "$line" | awk '{print $1}')
    options=$(echo "$line" | awk '{$1=""; print $0}' | xargs)
    
    # Check if it's in official repos
    if pacman -Si "$package" &>/dev/null; then
        echo "$package" >> /tmp/packages.official
    else
        echo "$line" >> /tmp/packages.aur  # Keep options for AUR packages
    fi
done < /tmp/packages.merged

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
OFFICIAL_FAILED=""
if [[ -s /tmp/packages.official ]]; then
    while IFS= read -r package || [ -n "$package" ]; do
        echo "  -> Downloading $package..."
        
        # Download package without installing (will use default cache which is now /output)
        if ! sudo pacman -Sw --noconfirm "$package" 2>/dev/null; then
            # Fallback to direct download
            url=$(pacman -Sp "$package" 2>/dev/null)
            if [[ -n "$url" ]]; then
                if ! wget -q -P /output "$url"; then
                    echo "    -> Failed to download $package"
                    OFFICIAL_FAILED="$OFFICIAL_FAILED $package"
                fi
            else
                echo "    -> Failed to download $package"
                OFFICIAL_FAILED="$OFFICIAL_FAILED $package"
            fi
        fi
    done < /tmp/packages.official
fi

# Source the AUR build functions
source /build/build-aur.sh

# Build AUR packages
build_aur_packages

echo ""
echo "==> Build Summary:"

# Count successes
TOTAL_OFFICIAL=$(wc -l < /tmp/packages.official 2>/dev/null || echo 0)
TOTAL_AUR=$(wc -l < /tmp/packages.aur 2>/dev/null || echo 0)

# Report official packages
if [[ -n "$OFFICIAL_FAILED" ]]; then
    OFFICIAL_FAILED_COUNT=$(echo $OFFICIAL_FAILED | wc -w)
    OFFICIAL_SUCCESS=$((TOTAL_OFFICIAL - OFFICIAL_FAILED_COUNT))
    echo "  Official packages: $OFFICIAL_SUCCESS/$TOTAL_OFFICIAL succeeded"
    echo "  Failed official packages:"
    for pkg in $OFFICIAL_FAILED; do
        echo "    - $pkg"
    done
else
    echo "  Official packages: $TOTAL_OFFICIAL/$TOTAL_OFFICIAL succeeded"
fi

# Report AUR packages (FAILED_PACKAGES comes from build-aur.sh)
if [[ -n "$FAILED_PACKAGES" ]]; then
    AUR_FAILED_COUNT=$(echo $FAILED_PACKAGES | wc -w)
    AUR_SUCCESS=$((TOTAL_AUR - AUR_FAILED_COUNT))
    echo "  AUR packages: $AUR_SUCCESS/$TOTAL_AUR succeeded"
    echo "  Failed AUR packages:"
    for pkg in $FAILED_PACKAGES; do
        echo "    - $pkg"
    done
else
    echo "  AUR packages: $TOTAL_AUR/$TOTAL_AUR succeeded"
fi

# Exit with error if any packages failed
if [[ -n "$OFFICIAL_FAILED" ]] || [[ -n "$FAILED_PACKAGES" ]]; then
    echo ""
    echo "==> Some packages failed to build/download"
    exit 1
else
    echo ""
    echo "==> All packages processed successfully!"
fi