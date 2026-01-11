# 1Password Beta aarch64 Support - Patch Summary

## Changes Made

Updated the 1Password Beta PKGBUILD to support both x86_64 and aarch64 architectures.

### Key Modifications

1. **Architecture Support**: Added `'aarch64'` to the `arch` array
2. **Dynamic Source URLs**: Removed hardcoded `.x64` filename, made it architecture-dependent
3. **Architecture-specific Variables**:
   - `_tar`: Tarball filename (`.x64.tar.gz` or `.arm64.tar.gz`)
   - `_archdir`: Directory name inside tarball (`x64` or `arm64`)
4. **Split Checksums**: Changed from single `sha256sums` to arch-specific arrays
5. **Updated Directory References**: Changed hardcoded `.x64` to `${_archdir}` variable

### Patch Location

- **File**: `patches/add-aarch64-support.patch`
- **Documentation**: `patches/README.md`

### Checksums Verified

Downloaded and verified SHA256 checksums for aarch64 files:

- **Tarball**: `661a45bb57f8b6e184d7b7603221cf938774aec674a357672d6cc1d4387fab40`
- **Signature**: `5cec37c65607760df4cc1734a51154b70ff660b5147160323905178aee23b7e2`

## Testing

### ✅ Build Results

**Successfully built for aarch64!**

```
Package: 1password-beta-8.11.16_30.BETA-30-aarch64.pkg.tar.xz
Size: 139MB
Location: build-output/aarch64/
Built: 2025-10-27
```

The package was successfully:
- Downloaded from 1Password's aarch64 repository
- Verified with SHA256 checksums  
- GPG signature verified
- Extracted and packaged for aarch64

### Syntax Validation

```bash
# Test x86_64 configuration
CARCH=x86_64 source PKGBUILD && echo "Source: ${source_x86_64[0]}"

# Test aarch64 configuration
CARCH=aarch64 source PKGBUILD && echo "Source: ${source_aarch64[0]}"
```

### Expected Behavior

**x86_64**:
- Downloads from: `https://downloads.1password.com/linux/tar/beta/x86_64/`
- Tarball: `1password-8.11.16-30.BETA.x64.tar.gz`
- Extracts to: `1password-8.11.16-30.BETA.x64/`

**aarch64**:
- Downloads from: `https://downloads.1password.com/linux/tar/beta/aarch64/`
- Tarball: `1password-8.11.16-30.BETA.arm64.tar.gz`
- Extracts to: `1password-8.11.16-30.BETA.arm64/`

## Building

```bash
# Build for x86_64
bin/repo build --arch x86_64 --package 1password-beta

# Build for aarch64
bin/repo build --arch aarch64 --package 1password-beta
```

## Patch Stats

- **Lines changed**: 19
- **Lines added**: 29
- **Lines removed**: 10
- **Net change**: +19 lines

## Upstream Source

1Password officially supports ARM64 Linux:
- Stable: https://downloads.1password.com/linux/tar/stable/aarch64/
- Beta: https://downloads.1password.com/linux/tar/beta/aarch64/

## Notes

- GPG signature verification works for both architectures
- Same signing key is used: `3FEF9748469ADBE15DA7CA80AC2D62742012EA22`
- Package structure is identical between architectures
- This patch can be auto-applied by `bin/sync-aur` if placed in `patches/` directory
