# Build All Packages - Helper Script

## Overview

The `bin/build-all` script intelligently builds all packages for your architecture in one shot by combining the appropriate `.packages` files from the Omarchy install directory.

## Usage

### Basic Usage (Build all packages for current architecture)

```bash
bin/build-all
```

### Verbose Mode (Show package list before building)

```bash
bin/build-all -v
# or
bin/build-all --verbose
```

## How It Works

The script:

1. **Detects Architecture** - Automatically detects ARM (aarch64/arm64) vs x86_64
2. **Combines Package Lists** - Merges the appropriate `.packages` files:
   - **ARM**: `omarchy-arm-omacom-io.packages` + `omarchy-base-aur.packages` + `omarchy-arm-aur.packages`
   - **x86**: `omarchy-x86.packages` + `omarchy-base-aur.packages`
3. **Filters & Cleans** - Removes comments and blank lines
4. **Builds Everything** - Runs `bin/repo build` with all packages at once

## Package Sources

### ARM (40 packages total)
- **omarchy-arm-omacom-io.packages** (15 packages) - Custom ARM builds:
  - Hyprland ecosystem (hyprwayland-scanner-git, hyprutils-git, hyprlang-git, hyprgraphics-git, hyprcursor-git, aquamarine-git, hyprland)
  - Applications (signal-desktop-beta, obs-studio-git, omarchy-nvim, pinta-git, wl-clip-persist)
  - 1Password (1password-beta, 1password-cli)
  - yay
- **omarchy-base-aur.packages** (23 packages) - AUR packages for both architectures:
  - Hyprland tools (hyprshade, aether)
  - Elephant launcher suite (13 packages)
  - Utilities (python-terminaltexteffects, ttf-ia-writer, typora, tzupdate, ufw-docker, walker, wayfreeze-git, yaru-icon-theme)
- **omarchy-arm-aur.packages** (2 packages) - ARM-specific AUR:
  - localsend-bin
  - omarchy-chromium-bin

## Build Features

- **Automatic Cleanup** - Build artifacts are removed after each package to prevent OOM
- **Dependency Resolution** - Auto-resolves and builds dependencies (e.g., Ruby gems, .NET packages)
- **Architecture Detection** - Automatically selects correct packages for your system
- **Verbose Output** - Use `-v` to see exactly what will be built

## Output

- Built packages: `/Users/jon/Code/omarchy-pkgs/build-output/<arch>/`
- Final repository: `/Users/jon/Code/omarchy-pkgs/pkgs.omarchy.org/<arch>/`
- Package list saved to: `/tmp/omarchy-all-packages-<arch>.txt`

## Examples

```bash
# Build all ARM packages
bin/build-all

# Build with verbose output to see package list first
bin/build-all -v

# Check what packages will be built without actually building
bin/build-all -v 2>&1 | head -60
```

## Notes

- The script uses the package files from `/Users/jon/Code/Omarchy/install/*.packages`
- Auto-resolved dependencies (like Ruby gems for FPM, .NET for pinta) are built automatically
- Total build time: ~30-60 minutes for all 40 packages (depends on cache and system)
- Expected result: ~53-67 package files (40 requested + auto-resolved dependencies + split packages)
