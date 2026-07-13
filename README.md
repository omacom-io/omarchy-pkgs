# Omarchy Package Repository

Build system for the Omarchy Package Repository. Builds PKGBUILDs from local sources and AUR, signs them, and syncs to production.

**Multi-Architecture**: Supports both x86_64 and aarch64 (ARM64).

## PKGBUILDs

Each package lives directly under `pkgbuilds/<package>/` and carries Omarchy metadata in `.omarchy/package.json`.

The filesystem no longer encodes release policy. Instead:

- all packages build for `edge`
- packages with `"release_ring": "fast"` also build directly for `stable`
- all other packages reach `stable` by promoting tested edge artifacts with `bin/repo migrate`
- AUR sync behavior is controlled by `source`, `sync`, `aur`, patches, and hooks in `.omarchy/`
- packages can opt out of unscoped builds with `skip_build`; explicit `--package` builds remain available

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

### Full release

Promote packages from edge build, then sync stable:

```
bin/repo migrate
bin/repo sync --mirror stable
```

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

# Show what would build without signing/promoting/syncing
bin/repo release --dry-run
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
bin/repo build --dry-run                         # Show what would build
```

**Output**: Unsigned `.pkg.tar.zst` in `build-output/`. Only builds packages that are newer than what is in the repository.

Use `--dry-run` to show the build plan without running `makepkg`.

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

### Sync Repository

```bash
bin/repo sync                           # Sync current arch/mirror
bin/repo sync --mirror stable           # Sync stable
bin/repo sync --arch aarch64            # Sync ARM64
bin/repo sync --skip-prod-check         # No confirmation
```

Syncs package repositories to the remote server using rclone based on the configured mirror and architecture.

### Sync AUR PKGBUILDs

```bash
bin/sync-aur                            # Sync all AUR packages with sync enabled
bin/sync-aur yay v4l2-relayd            # Sync specific packages
```

AUR sync is metadata-driven. It preserves `.omarchy/`, replaces the package root with AUR contents, applies `.omarchy/patches/*.patch`, runs `.omarchy/post-sync.sh` when present, applies pkgrel metadata, removes AUR-only `.SRCINFO` and `.gitignore` files, and records `upstream_commit`.

### Other

```bash
bin/repo migrate --arch x86_64       # Promote tested edge artifacts -> stable, then clean + update
bin/repo migrate --dry-run           # Preview migration and cleanup
bin/repo list                        # List package metadata
bin/add-package <package>            # Add an AUR/local package with metadata
bin/package-worktree <package>       # Create upstream/patched/current scratch workspace
bin/repo remove <package>            # Remove package
bin/clean-docker                     # Clear Docker images/cache (forces fresh rebuild)
```

### Package Metadata Tools

```bash
bin/add-package yay                  # Add AUR package, create metadata, sync from AUR
bin/add-package spotify --fast       # Add package to the fast release ring
bin/add-package foo --no-sync        # Sync once, then mark AUR sync disabled
bin/add-package my-package --local   # Create local package metadata

bin/repo list                        # Table view of source package metadata
bin/repo list --json                 # Agent/script-friendly JSON
bin/repo list --repo --mirror stable # List packages in a published repo database

bin/package-worktree v4l2-relayd     # Create upstream/patched/current scratch workspace
```

## Directory Structure

```
omarchy-pkgs/
├── pkgbuilds/                  # Source PKGBUILDs
│   └── package-name/
│       ├── PKGBUILD
│       └── .omarchy/
│           ├── package.json    # Source/sync/release metadata
│           ├── patches/        # Omarchy patches reapplied after AUR sync
│           └── post-sync.sh    # Optional dynamic post-sync customization hook
├── build/
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

## Package Metadata

Each source package has Omarchy metadata at `pkgbuilds/<package>/.omarchy/package.json`.

Minimal examples:

```json
{ "source": "aur" }
```

```json
{ "source": "aur", "sync": false }
```

```json
{ "source": "aur", "release_ring": "fast" }
```

```json
{ "source": "local" }
```

```json
{ "source": "local", "skip_build": true }
```

```json
{ "source": "aur", "pkgrel": { "suffix": 1 } }
```

Fields:

- `source`: `aur` or `local`
- `sync`: optional for AUR packages; defaults to `true`. Set `false` for AUR-origin packages that Omarchy maintains manually.
- `aur`: optional AUR package name when it differs from the local package directory, usually for split packages.
- `release_ring`: optional. `fast` means the package is built directly for stable as well as edge. Packages without a ring build in edge and reach stable through tested artifact promotion (`bin/repo migrate`).
- `skip_build`: optional boolean; defaults to `false`. Set `true` to exclude a package from scheduled version checks and unscoped builds. The package can still be built explicitly with `bin/repo release --package <name>`.
- `pkgrel`: optional Omarchy pkgrel suffix for a version-pinned rebuild bump. This emits `<aur pkgrel>.<suffix>` instead of replacing AUR's pkgrel. `offset` can be used only when preserving monotonic upgrades from old absolute pkgrel bumps. The metadata is removed automatically when AUR sync changes `pkgver`; the current package version is read from the checked-in PKGBUILD, so the version is not duplicated in JSON.
- `upstream_commit`: set by `bin/sync-aur` for AUR packages. Used by `bin/package-worktree` to recreate the exact raw AUR package that Omarchy last synced.

### Build Matrix

- **Edge unscoped builds** (`--mirror edge`): packages in `pkgbuilds/*` unless `"skip_build": true`
- **Stable unscoped builds** (`--mirror stable`): packages with `"release_ring": "fast"` unless `"skip_build": true`
- **Explicit builds** (`--package <name>`): the selected package, including packages with `"skip_build": true`, subject to mirror eligibility
- **Stable promotion** (`bin/repo migrate`): copies tested edge artifacts into stable

## Adding Packages

### From AUR

```bash
bin/add-package package-name
bin/repo release --package package-name
```

### From AUR, fast release ring

```bash
bin/add-package package-name --fast
bin/repo release --package package-name
bin/repo release --mirror stable --package package-name
```

### AUR-origin, manually maintained by Omarchy

```bash
bin/add-package package-name --no-sync
```

### Local Customizations for AUR Packages

For static changes, create `pkgbuilds/package-name/.omarchy/patches/*.patch` to maintain modifications across AUR syncs.

The recommended workflow is to use a scratch workspace:

```bash
bin/package-worktree package-name --dir /tmp/package-name-worktree
```

This creates:

```text
upstream/  # raw AUR package at upstream_commit
patched/   # AUR + existing Omarchy .omarchy customizations
current/   # current checked-in package directory
```

Patch-authoring flow:

```bash
# 1. Make the intended change in pkgbuilds/package-name/

# 2. Recreate the scratch workspace
bin/package-worktree package-name --dir /tmp/package-name-worktree

# 3. Inspect drift from patched -> current
# For multi-file changes, inspect this and split into focused patches.
diff -ruN /tmp/package-name-worktree/patched /tmp/package-name-worktree/current

# For a single PKGBUILD change, write a patch like this:
mkdir -p pkgbuilds/package-name/.omarchy/patches
(
  cd /tmp/package-name-worktree/patched
  diff -u --label a/PKGBUILD --label b/PKGBUILD \
    PKGBUILD /tmp/package-name-worktree/current/PKGBUILD || true
) > pkgbuilds/package-name/.omarchy/patches/my-fix.patch

# 4. Verify the package is reproducible from AUR + .omarchy
bin/sync-aur package-name
bin/package-worktree package-name --dir /tmp/package-name-check
diff -ruN /tmp/package-name-check/patched /tmp/package-name-check/current
```

For dynamic changes that depend on the current upstream version, add `pkgbuilds/package-name/.omarchy/post-sync.sh`. The hook runs after the AUR package is copied into a temporary worktree and before the Omarchy pkgrel suffix is applied. After patches/hooks/metadata pkgrel overrides, `bin/sync-aur` removes AUR-only `.SRCINFO` and `.gitignore` files before writing the package back.

### Custom Package

```bash
bin/add-package my-package --local --scaffold
# Fill in PKGBUILD and package files
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

1. **sync-aur.yml** (Every 6 hours): Syncs AUR packages according to `.omarchy/package.json` and opens a PR when changes are found.

#### Systemd Services

1. **check-versions** (Every 6 hours at :30): Pulls latest from git, compares PKGBUILD versions to published versions, creates state files if builds are needed
2. **auto-release-edge** (Every 6 hours at +1:00): If state file exists, builds all edge packages that need updates
3. **auto-release-stable** (Every 6 hours at +1:00): If state file exists, builds `release_ring=fast` packages for stable (runs in parallel with edge)

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
