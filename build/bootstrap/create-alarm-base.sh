#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$BUILD_ROOT/helpers/message-helpers.sh"

TARBALL_URL="http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz"
TARBALL_MD5_URL="http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz.md5"
TARBALL_SIG_URL="http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz.sig"
ALARM_KEY_ID="68B3537F39A313B3E574D06777193F152BDBE6A6"

TARBALL_FILE="$SCRIPT_DIR/ArchLinuxARM-aarch64-latest.tar.gz"
MD5_FILE="$SCRIPT_DIR/ArchLinuxARM-aarch64-latest.tar.gz.md5"
SIG_FILE="$SCRIPT_DIR/ArchLinuxARM-aarch64-latest.tar.gz.sig"

print_header "Arch Linux ARM Bootstrap"

print_info "This will create the omarchy-alarm-base:latest Docker image"
print_info "Source: https://archlinuxarm.org/platforms/armv8/generic"
echo ""

if docker images | grep -q "omarchy-alarm-base.*latest"; then
    print_warning "Image omarchy-alarm-base:latest already exists"
    read -p "Rebuild it? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Skipping bootstrap"
        exit 0
    fi
fi

cd "$SCRIPT_DIR"

print_info "Downloading ALARM aarch64 tarball (~450MB)..."
if [[ -f "$TARBALL_FILE" ]]; then
    print_info "Tarball already exists, skipping download"
else
    wget -O "$TARBALL_FILE" "$TARBALL_URL"
fi

print_info "Downloading checksum and signature..."
wget -O "$MD5_FILE" "$TARBALL_MD5_URL" || true
wget -O "$SIG_FILE" "$TARBALL_SIG_URL" || true

if [[ -f "$MD5_FILE" ]]; then
    print_info "Verifying MD5 checksum..."
    if md5sum -c "$MD5_FILE"; then
        print_success "✓ MD5 checksum verified"
    else
        print_error "MD5 checksum verification failed"
        exit 1
    fi
fi

if [[ -f "$SIG_FILE" ]]; then
    print_info "Verifying GPG signature..."
    
    if ! gpg --list-keys "$ALARM_KEY_ID" &>/dev/null; then
        print_info "Importing ALARM signing key..."
        if [[ -f "$SCRIPT_DIR/alarm-signing-key.asc" ]]; then
            gpg --import "$SCRIPT_DIR/alarm-signing-key.asc"
        else
            gpg --keyserver keyserver.ubuntu.com --recv-keys "$ALARM_KEY_ID"
        fi
    fi
    
    if gpg --verify "$SIG_FILE" "$TARBALL_FILE"; then
        print_success "✓ GPG signature verified"
    else
        print_error "GPG signature verification failed"
        exit 1
    fi
else
    print_warning "No signature file found, skipping GPG verification"
fi

print_info "Building Docker image from tarball..."

docker build --platform linux/arm64 -t omarchy-alarm-base:latest -f "$SCRIPT_DIR/Dockerfile.alarm-base" "$SCRIPT_DIR"

if [[ $? -eq 0 ]]; then
    print_success "Successfully created omarchy-alarm-base:latest"
    echo ""
    print_info "Testing the image..."
    docker run --rm --platform linux/arm64 omarchy-alarm-base:latest uname -a
    echo ""
    print_success "Bootstrap complete!"
    print_info "You can now build the aarch64 builder: docker build -f build/Dockerfile.aarch64"
else
    print_error "Failed to create Docker image"
    exit 1
fi

print_info "Cleaning up downloaded files..."
rm -f "$TARBALL_FILE" "$MD5_FILE" "$SIG_FILE"

print_success "Done!"
