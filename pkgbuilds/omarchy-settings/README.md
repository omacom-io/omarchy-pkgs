# Omarchy Settings

Base configuration package for Omarchy - provides system settings, user defaults, and essential utilities.

## Purpose

This package is designed to be:
1. **Lightweight** - Only configs, theme, and essential tools (~2-5MB)
2. **ISO-ready** - Pre-installed in Omarchy ISO for installation
3. **Standalone** - Can be used without the full `omarchy` desktop package

## Contents

This package provides **everything needed for the Omarchy ISO environment**:

### Configuration Files
- `/etc/skel/` - User skeleton files (configs for new users)
- `/etc/` - System-wide configurations (cups, nsswitch, security, etc.)

### Visual Elements
- `/usr/share/plymouth/themes/omarchy/` - Plymouth boot theme

### Essential Binaries
- `/usr/bin/omarchy-debug` - System debugging and log collection
- `/usr/bin/omarchy-upload-log` - Upload logs for support
- `/usr/bin/omarchy-upload-install-log` - Symlink for install script compatibility

### Install Helpers (Minimal)
- `/usr/share/omarchy/install/helpers/` - Helper scripts for ISO configurator
- `/usr/share/omarchy/install/*.packages` - Package lists for offline mirror

**These are used by:**
- ISO configurator (`/root/configurator`) - Sources helpers
- ISO builder (`build-iso.sh`) - Reads package lists

**Full install scripts come from the `omarchy` package.**

## Usage

### Standalone Installation
```bash
# Install just the settings and configs
pacman -S omarchy-settings
```

### With Full Desktop
```bash
# The omarchy package depends on omarchy-settings
pacman -S omarchy
```

### In ISO
This package is pre-installed in the Omarchy ISO to provide:
- Plymouth theme during boot
- User skeleton files for archinstall
- Debug/logging tools during installation
- System configurations

## Building

```bash
# Build the package
makepkg -si

# Or using the omarchy-pkgs build system
cd ../..
bin/repo build --package omarchy-settings
```

## Post-Install

The package automatically:
- Sets up Plymouth theme
- Handles .pacnew files for backed-up configs
- Places configuration files in `/etc/skel/` for new users

Existing users should manually copy configs from `/etc/skel/` if desired.
