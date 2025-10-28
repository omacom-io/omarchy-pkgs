# Omarchy Package Repository

This repository manages the Omarchy Package Repository, building a host of PKGBUILDs and facilitating syncing from AUR where necessary.

## Overview

The build system uses Docker to create a clean, reproducible build environment. Packages are built unsigned, then signed in a separate step, promoted to production, and synced to a remote server.

**Multi-Architecture Support**: The build system supports both **x86_64** and **aarch64** (ARM64) architectures. See [docs/AARCH64_BUILDS.md](docs/AARCH64_BUILDS.md) for aarch64 setup and usage.

### Directory Structure

```
omarchy-pkgs/
├── pkgbuilds/              # Source PKGBUILDs (one directory per package)
├── build-output/           # Temporary build workspace
├── pkgs.omarchy.org/       # Final signed packages
├── build/                  # Build scripts that run inside of the Docker container
├── bin/                    # Command-line tools
└── logs/                   # Build and operation logs
```

## Quick Start

### Complete Release Workflow

Build, sign, promote, clean, and sync in one command:

```bash
bin/repo release
```

With options:
```bash
bin/repo release --skip-prod-check                    # Skip production confirmation
bin/repo release --sync-remote dev-pkgs:/             # Sync to dev remote instead
bin/repo release --package omarchy-nvim               # Build only one package
bin/repo release --package yay cursor-bin omarchy-nvim # Build multiple packages
```

### Step-by-Step Workflow

```bash
# 1. Build packages (unsigned)
bin/repo build

# 2. Sign all built packages (sitting in `build-output`)
bin/repo sign

# 3. Promote to production directory (copy from `build-output` -> `pkgs.omarchy.org`)
bin/repo promote

# 4. Clean old versions and update database
bin/repo clean

# 5. Sync to remote server
bin/repo sync pkgs.omarchy.org/x86_64
```

## Commands

### `bin/repo build`

Builds packages from `pkgbuilds/` directory in a Docker container.

**Options:**
- `--package <name>` - Build only a specific package
- `--arch <arch>` - Target architecture (default: x86_64)

**What it does:**
- Clears `build-output/` directory
- Builds packages in dependency order
- Creates unsigned `.pkg.tar.zst` files in `build-output/x86_64/`
- Skips packages that are already up-to-date in `pkgs.omarchy.org/`

**Examples:**
```bash
bin/repo build                                   # Build all packages (x86_64)
bin/repo build --package omarchy-nvim            # Build only one package
bin/repo build --package yay omarchy-nvim cursor-bin  # Build multiple packages
bin/repo build --arch aarch64                    # Build for ARM64/aarch64
```

### `bin/repo sign`

Signs all unsigned packages in `build-output/`.

**What it does:**
- Fetches GPG key and passphrase from env or 1Password
- Signs all `.pkg.tar.zst` files

### `bin/repo promote`

Copies signed packages from `build-output/` to `pkgs.omarchy.org/`.

**Options:**
- `--arch <arch>` - Target architecture (default: x86_64)
- `--dry-run` - Preview what would be copied

**What it does:**
- Copies all packages and signatures to production directory
- Cleans up `build-output/` after successful promotion

**Examples:**
```bash
bin/repo promote
bin/repo promote --dry-run
```

### `bin/repo clean`

Removes old package versions and updates the repository database.

**Options:**
- `--keep N` - Keep N versions of each package (default: 2)
- `--dry-run` - Preview what would be removed
- `--usage` - Show disk usage statistics

**What it does:**
- Removes old package versions (keeps latest 2 by default)
- Updates `omarchy.db.tar.zst` repository database
- Shows disk usage and statistics

**Examples:**
```bash
bin/repo clean                      # Keep 2 versions
bin/repo clean --keep 3             # Keep 3 versions
bin/repo clean --dry-run            # Preview cleanup
bin/repo clean --usage              # Show disk usage
```

### `bin/repo sync`

Syncs the repository to a remote server using rclone.

**Arguments:**
- `<directory>` - Local directory to sync (e.g., `pkgs.omarchy.org/x86_64`)

**Options:**
- `--remote <remote>` - Rclone remote destination (default: `pkgs.omarchy.org:omarchy-pkgs`)
- `--skip-prod-check` - Skip production confirmation

**What it does:**
- Syncs packages to remote (uses `--ignore-existing` to preserve versions)
- Syncs database files with checksums
- Prompts for confirmation when syncing to production

**Examples:**
```bash
bin/repo sync pkgs.omarchy.org/x86_64                    # Sync to production
bin/repo sync pkgs.omarchy.org/x86_64 --skip-prod-check  # Skip confirmation
bin/repo sync pkgs.omarchy.org/x86_64 --remote dev-pkgs:/# Sync to dev
```

### `bin/repo release`

Runs the complete release workflow in sequence.

**Options:**
- `--package <names>` - Build only specific package(s) (space-separated)
- `--arch <arch>` - Target architecture (default: x86_64)
- `--sync-remote <path>` - Rclone remote for sync (default: production)
- `--skip-prod-check` - Skip production confirmation

**What it does:**
1. Builds packages
2. Signs packages
3. Promotes to production
4. Cleans old versions
5. Syncs to remote

**Examples:**
```bash
bin/repo release                                          # Full workflow
bin/repo release --skip-prod-check                        # Skip prod confirmation
bin/repo release --sync-remote dev-pkgs:/                 # Sync to dev
bin/repo release --package omarchy-nvim                   # Single package
bin/repo release --package yay cursor-bin omarchy-nvim    # Multiple packages
```

### Other Commands

**`bin/repo list`** - List all packages in the repository
```bash
bin/repo list
```

**`bin/repo remove <package>`** - Remove a package from the repository
```bash
bin/repo remove yay
```

**`bin/repo update`** - Update the repository database (usually done automatically by `clean`)
```bash
bin/repo update
```

## Adding New Packages

### From AUR

1. Add package name to `build/packages/omarchy-aur.packages` (for future syncing)
2. Sync PKGBUILD to local directory:
   ```bash
   bin/sync-aur package-name
   ```
3. Build and release:
   ```bash
   bin/repo release --package package-name
   ```

#### Maintaining Local Patches for AUR Packages

If you need to maintain local modifications to AUR packages that persist through `aur-sync` updates:

1. Create a `patches/` directory inside the package directory:
   ```bash
   mkdir pkgbuilds/package-name/patches
   ```

2. Create patch files for your modifications:
   ```bash
   cd pkgbuilds/package-name
   # Make your changes to PKGBUILD or other files
   git diff > patches/my-fix.patch
   ```

3. When `bin/sync-aur` runs, it will automatically apply all `.patch` files found in the `patches/` directory after syncing from AUR.

**Example:** The `opencode` package has `patches/fix-parcel-watcher.patch` which adds platform-specific `@parcel/watcher` installation to the build process.

### Custom Package

1. Create directory in `pkgbuilds/`:
   ```bash
   mkdir pkgbuilds/my-package
   ```
2. Add PKGBUILD and any additional files
3. Build and release:
   ```bash
   bin/repo release --package my-package
   ```

## Package Dependencies

The build system automatically handles dependencies between packages being built. For example, if `aether` depends on `hyprshade`, the build system will:

1. Detect the dependency relationship
2. Build `hyprshade` first
3. Add it to the `omarchy-build` temporary repository
4. Build `aether` (which can now install `hyprshade` from `omarchy-build`)

This works through two internal repositories:
- **`omarchy-build`** - Temporary repo in `build-output/` (unsigned packages, used during build)
- **`omarchy`** - Production repo in `pkgs.omarchy.org/` (signed packages)

## Version Management

Packages are only rebuilt if:
- PKGBUILD version is newer than the version in the repository DB
- Package doesn't exist in production yet
