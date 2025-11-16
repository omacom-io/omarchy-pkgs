# Omarchy Package

The main Omarchy desktop environment package.

## Package Split

The Omarchy system is split into two packages:

### omarchy-settings
- Configuration files (`/etc/skel/`)
- System settings (`/etc/`)
- Plymouth boot theme
- Essential ISO/installation binaries (`omarchy-debug`, `omarchy-upload-log`)
- **Purpose**: Minimal package for ISO and base system configuration

### omarchy (this package)
- All other binaries (30+ omarchy-* commands)
- Install scripts and migrations (`/usr/share/omarchy/`)
- Themes for runtime switching
- Branding and assets
- Full desktop environment dependencies
- **Purpose**: Complete Omarchy desktop experience

## Dependencies

This package depends on `omarchy-settings` and will install it automatically.

## Installation

```bash
# Install full desktop environment
pacman -S omarchy

# Run the installer
bash /usr/share/omarchy/install.sh
```

## Building

```bash
# Build the package
makepkg -si

# Or using the omarchy-pkgs build system
cd ../..
bin/repo build --package omarchy
```

## Files

- `/usr/bin/omarchy-*` - All Omarchy commands (except debug and upload-log)
- `/usr/share/omarchy/` - Themes, assets, install scripts, migrations
