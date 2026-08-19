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
- packages that follow a vendor release feed instead of the AUR carry an `.omarchy/upstream.sh` hook

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

**Note**: aarch64 builds use QEMU and slower than native x86_64 builds. To avoid the
emulation entirely, run the **Build aarch64 Packages** workflow, which builds on native
ARM64 runners.

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

### Building Heavy Packages Locally

Large packages build faster on a local machine than on the server. Build them
here, then hand the artifacts to the repository host, which signs and publishes
them:

```bash
bin/repo deploy --package nvidia-580xx-utils   # Build here, publish from the host
```

`deploy` is `build` followed by `push`. The two steps are also available
separately when a build needs inspecting before it ships:

```bash
bin/repo build --package nvidia-580xx-utils    # Build on the fast machine
bin/repo push --package nvidia-580xx-utils     # Upload + publish on the host
```

`push` uploads to the host's `build-output/`, verifies checksums, and runs
`bin/upload-prebuilt` there. Do not publish from a local checkout instead: only
the repository host holds the complete repository and the signing key.

**Name the package.** `build` asks the local repository database which packages
are already built, and a build machine has no such database, so an unscoped run
treats every package as out of date and rebuilds the whole repository. `deploy`
refuses to run unscoped when that database is missing. Unscoped builds belong on
the repository host, where `bin/repo release` does the same job against a real
database.

Every other command in `bin/` — `sign`, `promote`, `update`, `clean`, `migrate`,
`remove`, `sync`, `release` — works on the published tree directly and is meant
to run on the repository host. `build`, `push` and `deploy` are the three that
may run elsewhere.

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
bin/repo sync --prune                   # Also delete remote packages missing locally
```

Syncs package repositories to the remote server using rclone based on the configured mirror and architecture.

**Uploads are additive.** A local tree is not authoritative about what belongs on
the remote — `pkgs.omarchy.org/` is gitignored, and packages built on another
machine exist only there — so sync never deletes by default. Removing packages
from the remote requires `--prune`, which only makes sense from a complete tree.

For the same reason sync refuses to publish a repository database built from a
tree holding fewer packages than the remote database already lists. The database
is what pacman resolves against, so a partial one hides every package it does not
know about even though the files are still on the mirror. Use `bin/repo push` to
publish packages built on another machine.

### Deploy

```bash
bin/repo deploy --package nvidia-580xx-utils   # Build locally, publish from the host
bin/repo deploy --host root@example.com        # Point at a specific repo host
bin/repo deploy --dry-run                      # Show the plan, change nothing
```

Runs `build` then `push` in one command. The repository host is resolved before
the build starts, so a missing `--host` fails immediately rather than after a long
compile.

### Push to the Repository Host

```bash
bin/repo push                                  # Push everything in build-output
bin/repo push --package nvidia-580xx-utils     # Push one package
bin/repo push --mirror stable --arch aarch64   # Pick mirror and architecture
bin/repo push --host root@example.com          # Override the repo host
bin/repo push --dry-run                        # Show the plan, transfer nothing
```

Uploads packages from `build-output/` to the repository host and publishes them there
with `bin/upload-prebuilt` (sign → promote → update → sync). Use it when a package
is quicker to build on a local machine than on the server.

Publishing happens on the host rather than locally for two reasons: the GPG
signing key lives there and nowhere else, and only the host holds the complete
repository that a correct database and sync require. Local machines therefore
need no secrets.

The host comes from `--host`, `$OMARCHY_REPO_HOST`, then `.repo-host`. One
machine both serves pkgs.omarchy.org and runs the scheduled builds, so the
setting is named for the repository rather than for building, which happens
wherever you like. The same setting tells `bin/omarchy-pkgs release` which host
to poke after a release push.

`--package` means the same thing as it does to `build`: a pkgbase, whose every
output ships together. Pushing `nvidia-580xx-utils` carries `nvidia-580xx-dkms`
and `opencl-nvidia-580xx` with it, because that is what the build produced. An
output's own name still selects just that one, for publishing a single package
on purpose. Omit `--package` to push everything built.

Publishing signs and promotes everything staged on the host, not just what this
push uploaded, so `push` stops when it finds packages already staged there —
usually leftovers from a failed run. Remove them on the host, or pass
`--include-staged` to publish them too.

### Sync AUR PKGBUILDs

```bash
bin/sync-aur                            # Sync all AUR packages with sync enabled
bin/sync-aur yay v4l2-relayd            # Sync specific packages
```

AUR sync is metadata-driven. It preserves `.omarchy/`, replaces the package root with AUR contents, applies `.omarchy/patches/*.patch`, runs `.omarchy/post-sync.sh` when present, applies pkgrel metadata, removes AUR-only `.SRCINFO` and `.gitignore` files, and records `upstream_commit`.

### Sync Upstream Releases

```bash
bin/sync-upstream                       # Update every package with an upstream hook
bin/sync-upstream openai-codex-desktop  # Update specific packages
```

Some vendors publish a release feed of their own that is faster and more precise
than the AUR packaging of it. Those packages are `source: local` — Omarchy owns
the PKGBUILD — and provide `.omarchy/upstream.sh`, a hook that reports the newest
upstream release as JSON on stdout:

```json
{
  "pkgver": "1.2.3",
  "sha256sums": { "x86_64": ["<sha256>"], "aarch64": ["<sha256>"] }
}
```

Architecture keys become `sha256sums_<arch>` in the PKGBUILD; the key `any` means
the unsuffixed `sha256sums` array, and only the arrays a hook names are touched.
An empty object (`{}`) reports no update, which is how a hook waits out a release
that has landed for one architecture but not yet the other.

When the reported version is newer than the checked-in one, `bin/sync-upstream`
rewrites `pkgver` and those checksum arrays and resets `pkgrel` to 1. A version
that is equal or older leaves the package alone, so a vendor rolling a release
back cannot walk the repository backwards.

Hooks should read checksums from whatever manifest the vendor publishes rather
than downloading the artifacts — see `pkgbuilds/openai-codex-desktop/.omarchy/upstream.sh`,
which reads OpenAI's Debian package index and never fetches the 750 MB of debs
it describes.

### Other

```bash
bin/repo migrate --arch x86_64       # Promote tested edge artifacts -> stable, then clean + update
bin/repo migrate --package <name>    # Promote a single package -> stable
bin/repo migrate --dry-run           # Preview migration and cleanup
bin/repo list                        # List package metadata
bin/repo deploy                      # Build locally, then publish from the host
bin/repo push                        # Upload local builds to the host and publish
bin/add-package <package>            # Add an AUR/local package with metadata
bin/package-worktree <package>       # Create upstream/patched/current scratch workspace
bin/repo remove <package>            # Remove package
bin/sync-upstream                    # Update packages that track a vendor release feed
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

## Cutting an Omarchy Release

The `omarchy` and `omarchy-settings` packages are released as a pair, always
built from the same upstream commit of basecamp/omarchy. `bin/omarchy-pkgs`
rewrites both PKGBUILDs in lockstep (same `_tag`/`_commit`/`pkgver`/
`sha256sums`), validates ordering with `vercmp`, commits, and pushes the
current branch. On master it pokes the build host directly; from any other
branch add `--pr` to open the release PR — merging it is what goes live.

```bash
bin/omarchy-pkgs release v4.0.0          # Final release from the upstream v4.0.0 tag
bin/omarchy-pkgs release rc v4.0.0       # Newest upstream v4.0.0-rcN tag -> 4.0.0rcN
bin/omarchy-pkgs release beta v4.0.0     # Same for beta (alpha also supported)
bin/omarchy-pkgs release latest          # Newest upstream tag, rc/beta included (prompts)
bin/omarchy-pkgs release rc              # Untagged RC from the quattro tip, auto-numbered
bin/omarchy-pkgs release --commit abc123 --base 4.1.0   # Untagged RC from a commit
bin/omarchy-pkgs release ... --dry-run   # Show the plan; write nothing
bin/omarchy-pkgs release ... --no-push   # Full flow, local commit only (testing)
bin/omarchy-pkgs self-test               # Version normalization + ordering tests
```

### Versioning rules

- Finals are `X.Y.Z`; pre-releases are `X.Y.ZalphaN` / `X.Y.ZbetaN` /
  `X.Y.ZrcN` in the **attached** form only. pacman's vercmp orders
  `4.0.0alpha1 < 4.0.0beta1 < 4.0.0rc1 < 4.0.0`, but separator forms
  (`4.0.0.rc1`, `4.0.0_rc1`) sort **after** `4.0.0` and would strand users on
  the pre-release — the tooling normalizes upstream tags (`v4.0.0-rc1`,
  `v4.0.0-rc.1`, ...) to the attached form and refuses anything it cannot
  normalize. Upstream tags are cut on the quattro branch.
- `pkgrel` resets to 1 on every version change. Bump `pkgrel` by hand only to
  repackage the same source.
- `epoch` is never set by tooling. It is sticky forever; adding one is a
  human decision of last resort.

### Where releases land

- **RCs build for edge only.** Stable never sees an rc version. Edge testers
  upgrade rc1 → rc2 → final naturally.
- **Finals build for edge first.** After the edge build completes and you have
  verified it, promote the exact tested artifacts to stable:

```bash
bin/repo migrate --package omarchy && bin/repo migrate --package omarchy-settings
bin/repo sync --mirror stable
```

Neither package is on the `fast` ring, and `bin/omarchy-pkgs` never touches
stable — promotion is always this explicit step.

### Build trigger

After pushing, the command triggers the build host over ssh when
`OMARCHY_REPO_HOST` is set (env var, or a hostname in the git-ignored
`.repo-host` file). Without it, the 6-hourly auto-release timer picks up the
change on its own.

## Directory Structure

```
omarchy-pkgs/
├── pkgbuilds/                  # Source PKGBUILDs
│   └── package-name/
│       ├── PKGBUILD
│       └── .omarchy/
│           ├── package.json    # Source/sync/release metadata
│           ├── patches/        # Omarchy patches reapplied after AUR sync
│           ├── post-sync.sh    # Optional dynamic post-sync customization hook
│           └── upstream.sh     # Optional vendor release feed hook (non-AUR packages)
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

- `source`: `aur` or `local`. A `local` package can still follow an upstream release with an `.omarchy/upstream.sh` hook.
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
- Or build natively in CI: the **Build aarch64 Packages** workflow runs on GitHub's
  ARM64 runners, which need no emulation. Trigger it from the Actions tab; it uploads
  the packages as an artifact and leaves signing and publishing to a maintainer.

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
2. **sync-upstream.yml** (Every 6 hours): Runs `.omarchy/upstream.sh` for packages that track a vendor release feed and opens a PR when a newer version is out.

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
ssh root@<host> 'cd /root/omarchy-pkgs && bin/setup'
```

`bin/setup` installs the dependencies, ensures Docker is running, creates the
state directory, and installs and enables the release timers. It works on
Debian/Ubuntu and on Arch, and is idempotent, so run it again whenever a
dependency is added.

The host does not need to be Arch: makepkg, repo-add and package signing all
run inside containers, so it needs only Docker, rclone, bsdtar, jq, git and
rsync. Docker is left alone when it already works, rather than replacing a
working installation from Docker's own repository with the distribution's.

```bash
bin/repo setup --check         # Report what is missing, change nothing
bin/repo setup --skip-timers   # Prepare the host without the release timers
```

Signing credentials (`/root/.omarchy/build-credentials`) and the rclone remote
hold secrets, so setup reports on them rather than creating them.

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
