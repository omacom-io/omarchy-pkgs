# Omarchy Package Repository

Build system for the Omarchy Package Repository. Builds PKGBUILDs from local sources and AUR, signs them, and syncs to production.

**Multi-Architecture**: Supports both x86_64 and aarch64 (ARM64).

## Prerequisites
### aarch64 Builds (Optional)

To build ARM64 packages on x86_64, enable QEMU emulation:

```bash
# Run after each reboot
docker run --privileged --rm tonistiigi/binfmt --install arm64

# Verify
docker run --rm --platform linux/arm64 alpine:latest uname -m
# Should output: aarch64
```

**Note**: aarch64 builds use QEMU and slower than native x86_64 builds.

## Quick Start

### Complete Workflow

The release command is smart and **incremental** - it only builds packages that have changed or are missing. You generally don't need to specify a package manually unless you are debugging a specific failure.

```bash
# Build changed/new packages, sign, promote, clean, update, and sync
bin/repo release

# Stable Mirror
bin/repo release --mirror stable

# ARM64
bin/repo release --arch aarch64

# Force build specific package (useful for debugging failures)
bin/repo release --package omarchy-nvim
```

### Step-by-Step

```bash
bin/repo build                          # Build (unsigned)
bin/repo sign                           # Sign packages
bin/repo promote                        # Copy to production
bin/repo clean                          # Remove old versions
bin/repo update                         # Update database
bin/repo sync                           # Sync to remote
```

## Commands

### Global Flags

These flags can be used with all commands:

- `--mirror <edge|stable>`: Selects the repository mirror (default: `edge`).
- `--arch <x86_64|aarch64>`: Selects the target architecture (default: `x86_64`).

### Build

```bash
bin/repo build                                   # All packages (x86_64, edge)
bin/repo build --arch aarch64                    # ARM64
bin/repo build --mirror stable                   # Stable mirror
bin/repo build --package yay cursor-bin          # Specific packages
```

**Output**: Unsigned `.pkg.tar.zst` in `build-output/`. Only builds packages that are newer than what is in the repository.

### Sign

```bash
bin/repo sign
```

Fetches GPG key from 1Password or environment, signs all packages in `build-output/`. Supports `--arch` and `--mirror`.

### Promote

```bash
bin/repo promote                    # Copy to production
bin/repo promote --arch aarch64     # ARM64
bin/repo promote --dry-run          # Preview
```

Copies signed packages from `build-output/` → `pkgs.omarchy.org/`.

### Clean

```bash
bin/repo clean                      # Keep 2 versions
bin/repo clean --keep 3             # Keep 3 versions
bin/repo clean --dry-run            # Preview
```

Removes old package versions from the file system. **Does not update the database.**

### Update

```bash
bin/repo update                     # Update database
```

Updates the repository database (adding the newest version of each package). Run this after `promote` or `clean`.

### Sync

```bash
bin/repo sync                           # Sync current arch/mirror
bin/repo sync --mirror stable           # Sync stable
bin/repo sync --arch aarch64            # Sync ARM64
bin/repo sync --skip-prod-check         # No confirmation
```

Syncs to remote server using rclone based on the configured mirror and architecture.

### Other

```bash
bin/repo list                       # List packages
bin/repo remove <package>           # Remove package
```

## Directory Structure

```
omarchy-pkgs/
├── pkgbuilds/              # Source PKGBUILDs
├── build-output/           # Unsigned packages (temporary)
│   ├── x86_64/
│   └── aarch64/
├── pkgs.omarchy.org/       # Signed packages (production)
│   ├── x86_64/
│   └── aarch64/
├── build/                  # Build scripts (in container)
└── bin/                    # CLI tools (on host)
```

## Adding Packages

### From AUR

```bash
# Add to sync list
echo "package-name" >> build/packages/omarchy-aur.packages

# Sync PKGBUILD
bin/sync-aur package-name

# Build and release
bin/repo release --package package-name
```

#### Local Patches for AUR Packages

Create `pkgbuilds/package-name/patches/*.patch` to maintain modifications across AUR syncs:

```bash
cd pkgbuilds/package-name
# Make changes
git diff > patches/my-fix.patch
# Next sync will auto-apply patches
```

### Custom Package

```bash
mkdir pkgbuilds/my-package
# Add PKGBUILD and files
bin/repo release --package my-package
```

## Architecture-Specific Notes

### x86_64
- Native builds (fast)
- Mirrors: mirror.omarchy.org, rackspace, pkgbuild.com

### aarch64
- QEMU emulation required on x86_64 hosts (slower)
- Uses Arch Linux ARM repositories
- Additional repos: `[alarm]`, `[aur]`
- Same workflow, just add `--arch aarch64`

### Building for Both Architectures

```bash
# Build x86_64
bin/repo release --package myapp

# Build aarch64
bin/repo release --arch aarch64 --package myapp

# Sync both
bin/repo sync
bin/repo sync --arch aarch64
```

## Dependency Resolution

The build system automatically handles inter-package dependencies:

1. Parses `depends=()` and `makedepends=()` from PKGBUILDs
2. Builds in correct order
3. Makes newly-built packages available via temporary `[omarchy-build]` repo

Example: If `aether` depends on `hyprshade`, `hyprshade` is built first.

## Version Management

Packages are only rebuilt if:
- PKGBUILD version is newer than repository version
- Package doesn't exist in production

## Automated Releases

The repository includes a GitHub workflow and systemd services for automated daily releases.

### How It Works

1. **GitHub Action** (6:00 AM UTC): Syncs AUR packages and opens a PR if there are updates
2. **Merge PR**: Review and merge the PR to trigger the release pipeline
3. **check-upstream** (2:00 PM Eastern): Detects the merged changes, pulls them, creates state files
4. **auto-release** (3:00 PM Eastern): If state file exists, runs full release workflow and removes state file on success

State files are stored in `/root/.state/`:
- `.sync-needed-edge`
- `.sync-needed-stable`

### Installation

```bash
# Copy systemd units
cp /root/omarchy-pkgs/systemd/*.service /root/omarchy-pkgs/systemd/*.timer /etc/systemd/system/

# Reload systemd
systemctl daemon-reload

# Enable and start timers
systemctl enable --now omarchy-check-upstream.timer
systemctl enable --now omarchy-auto-release-edge.timer
systemctl enable --now omarchy-auto-release-stable.timer

# Create state directory
mkdir -p /root/.state
```

### Management

```bash
# Check timer status
systemctl list-timers omarchy-*

# Manual trigger
systemctl start omarchy-check-upstream.service
systemctl start omarchy-auto-release-edge.service

# View logs
journalctl -u omarchy-check-upstream.service
journalctl -u omarchy-auto-release-edge.service
```
