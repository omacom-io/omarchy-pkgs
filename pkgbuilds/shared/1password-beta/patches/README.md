# 1Password Beta - aarch64 Support Patch

## Overview

This patch adds aarch64 (ARM64) architecture support to the 1Password Beta PKGBUILD.

## Background

1Password officially provides ARM64 builds for Linux:
- https://downloads.1password.com/linux/tar/beta/aarch64/
- https://downloads.1password.com/linux/tar/stable/aarch64/

The original PKGBUILD only supported x86_64, but the source URLs use `${CARCH}` which should work for both architectures.

## Changes Made

1. **Added aarch64 to arch array**: `arch=('x86_64' 'aarch64')`

2. **Architecture-specific variables**: 
   - x86_64: Uses `.x64.tar.gz` files and `x64` directory
   - aarch64: Uses `.arm64.tar.gz` files and `arm64` directory

3. **Architecture-specific checksums**:
   - `sha256sums_x86_64=()` - Kept original checksums
   - `sha256sums_aarch64=()` - Downloaded and verified real checksums

4. **Dynamic directory names**: Changed hardcoded `.x64` to `${_archdir}`

## Testing

To test on aarch64:

```bash
# Build for aarch64
bin/repo build --arch aarch64 --package 1password-beta

# The package should download from:
# https://downloads.1password.com/linux/tar/beta/aarch64/1password-8.11.16-30.BETA.arm64.tar.gz
```

## Applying the Patch

If syncing from AUR in the future, apply this patch:

```bash
cd pkgbuilds/1password-beta
patch -p0 < patches/add-aarch64-support.patch
```

Or if the patch is in the patches/ directory, it will be auto-applied by the sync script.

## Checksums

The aarch64 checksums were obtained by downloading directly from 1Password:

```bash
# Tarball
curl -sSL https://downloads.1password.com/linux/tar/beta/aarch64/1password-8.11.16-30.BETA.arm64.tar.gz | sha256sum
# 661a45bb57f8b6e184d7b7603221cf938774aec674a357672d6cc1d4387fab40

# Signature
curl -sSL https://downloads.1password.com/linux/tar/beta/aarch64/1password-8.11.16-30.BETA.arm64.tar.gz.sig | sha256sum
# 5cec37c65607760df4cc1734a51154b70ff660b5147160323905178aee23b7e2
```

## TODO

- [ ] Test installation on actual aarch64 hardware (Asahi Linux)
- [ ] Consider upstreaming to AUR (if maintainer is interested)
- [ ] Update checksums when 1Password beta version changes

## Notes

- The 1Password desktop app is proprietary and distributed as binary
- GPG signature verification works for both architectures using the same key
- The package structure is identical between x86_64 and aarch64 versions
