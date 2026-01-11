# Omarchy Package Repository

Build system for the Omarchy Package Repository. Builds PKGBUILDs from local sources and AUR, signs them, and syncs to production.

**Multi-Architecture**: Supports both x86_64 and aarch64 (ARM64).

## PKGBUILDs
There are 3 folders housing PKGBUILD that drive what is ultimately on the respective repos. 

- `edge` - Built and pushed to the edge repo. These are synced daily with AUR if they're set to mirror it.
- `stable` - Built and pushed to the stable repo. These are only synced manually when stable is bumped.
- `shared` - Built and pushed to both stable and edge repo every 6hrs.

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
bin/clean-docker                    # Clear Docker images/cache (forces fresh rebuild)
```

## Directory Structure

```
omarchy-pkgs/
├── pkgbuilds/                  # Source PKGBUILDs (tiered)
│   ├── stable/                 # Manual promotion only, builds for stable
│   ├── edge/                   # Daily sync w/ PR review, builds for edge only
│   └── shared/                 # 6-hourly sync, auto-merge, builds for BOTH
├── build/
│   └── packages/
│       ├── edge.packages       # Package list for daily sync (PR review)
│       └── shared.packages     # Package list for 6-hourly sync (auto-merge)
├── build-output/               # Unsigned packages (temporary)
│   ├── edge/
│   │   ├── x86_64/
│   │   └── aarch64/
│   └── stable/
│       ├── x86_64/
│       └── aarch64/
├── pkgs.omarchy.org/           # Signed packages (production)
│   ├── edge/
│   │   ├── x86_64/
│   │   └── aarch64/
│   └── stable/
│       ├── x86_64/
│       └── aarch64/
└── bin/                        # CLI tools (on host)
```

## Package Tiers

Packages are organized into three tiers based on their release cadence:

| Tier | Directory | Sync Frequency | Review | Builds To |
|------|-----------|----------------|--------|-----------|
| **Stable** | `pkgbuilds/stable/` | Manual | N/A | stable only |
| **Edge** | `pkgbuilds/edge/` | Daily | PR required | edge only |
| **Shared** | `pkgbuilds/shared/` | Every 6 hours | Auto-merge | edge AND stable |

### Build Matrix

- **Edge builds** (`--mirror edge`): `pkgbuilds/edge/*` + `pkgbuilds/shared/*`
- **Stable builds** (`--mirror stable`): `pkgbuilds/stable/*` + `pkgbuilds/shared/*`

## Adding Packages

### From AUR (Edge - Daily Sync, PR Review)

```bash
# Add to edge package list
echo "package-name" >> build/packages/edge.packages

# Sync PKGBUILD
bin/sync-aur --tier edge package-name

# Build and release
bin/repo release --package package-name
```

### From AUR (Shared - 6-Hourly Sync, Auto-Merge)

```bash
# Add to shared package list
echo "package-name" >> build/packages/shared.packages

# Sync PKGBUILD
bin/sync-aur --tier shared package-name

# Build and release (will publish to both edge and stable)
bin/repo release --package package-name
bin/repo release --mirror stable --package package-name
```

### Local Patches for AUR Packages

Create `pkgbuilds/<tier>/package-name/patches/*.patch` to maintain modifications across AUR syncs:

```bash
cd pkgbuilds/edge/package-name
# Make changes
git diff > patches/my-fix.patch
# Next sync will auto-apply patches
```

### Custom Package

```bash
mkdir pkgbuilds/edge/my-package
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

The repository includes GitHub workflows and systemd services for automated releases.

### How It Works

#### GitHub Workflows

1. **sync-aur-edge.yml** (Daily at 6:00 AM UTC): Syncs edge packages from AUR, creates PR for review
2. **sync-aur-shared.yml** (Every 6 hours): Syncs shared packages from AUR, auto-commits to master

#### Systemd Services

1. **check-versions** (Every 6 hours at :30): Pulls latest from git, compares PKGBUILD versions to published versions, creates state files if builds are needed
2. **auto-release-edge** (Every 6 hours at +1:00): If state file exists, builds edge packages
3. **auto-release-stable** (Every 6 hours at +1:00): If state file exists, builds stable packages (runs in parallel with edge)

State files are stored in `/root/.state/`:
- `.sync-needed-edge`
- `.sync-needed-stable`

### Schedule (America/New_York)

| Time | Action |
|------|--------|
| 00:30, 06:30, 12:30, 18:30 | check-versions (git pull + creates state files) |
| 01:00, 07:00, 13:00, 19:00 | auto-release-edge + auto-release-stable (parallel) |

### Installation

```bash
# Copy systemd units
cp /root/omarchy-pkgs/systemd/*.service /root/omarchy-pkgs/systemd/*.timer /etc/systemd/system/

# Reload systemd
systemctl daemon-reload

# Enable and start timers
systemctl enable --now omarchy-check-versions.timer
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
systemctl start omarchy-check-versions.service
systemctl start omarchy-auto-release-edge.service
systemctl start omarchy-auto-release-stable.service

# View logs
journalctl -u omarchy-check-versions.service
journalctl -u omarchy-auto-release-edge.service
journalctl -u omarchy-auto-release-stable.service
```
