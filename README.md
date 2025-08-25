# Omarchy Repository

A custom Arch Linux repository for managing and distributing packages.

## Directory Structure

```
omarchy-repo/
├── x86_64/              # Repository packages and database
├── src/                 # AUR package build sources
├── build/               # Docker build files
├── bin/                 # Management scripts
└── packages             # Package list
```

## Quick Start

1. **Add packages to track:**
   - Edit `packages` file (system auto-detects if official or AUR)

2. **Build packages in Docker:**
   ```bash
   ./bin/build
   ```

3. **Update repository database:**
   ```bash
   ./bin/update-repo
   ```

## Configuration

### Local Usage

Add this to `/etc/pacman.conf` (before other repositories for priority):

```ini
[omarchy]
SigLevel = Optional TrustAll
Server = file:///home/ryan/Dev/omarchy-repo/x86_64
```

### Remote Server Setup

To serve this repository over HTTP:

1. **Using Python (temporary):**
   ```bash
   cd /home/ryan/Dev/omarchy-repo/x86_64
   python -m http.server 8080
   ```

2. **Using nginx (permanent):**
   ```nginx
   server {
       listen 80;
       server_name repo.yourdomain.com;
       root /home/ryan/Dev/omarchy-repo/x86_64;
       autoindex on;
   }
   ```

3. **Client configuration:**
   ```ini
   [omarchy]
   SigLevel = Optional TrustAll
   Server = http://repo.yourdomain.com
   ```

## Scripts Usage

### build

Builds all packages in Docker container (no local installation).

```bash
# Build everything
./bin/build

# Options:
./bin/build --only "yay walker-bin"  # Build specific packages
./bin/build --skip-pgp               # Skip PGP signature verification  
./bin/build --force                  # Force rebuild even if no updates
./bin/build --keep-image             # Keep Docker image after build
```

### update-repo

Updates the repository database with all packages in x86_64/.

```bash
# Update database
./bin/update-repo

# Options:
./bin/update-repo --verify  # Only verify the database
./bin/update-repo --sign    # Sign database with GPG
./bin/update-repo --stats   # Show repository statistics
```

### clean-repo

Maintains the repository by removing old packages.

```bash
# Keep only latest 2 versions
./bin/clean-repo

# Options:
./bin/clean-repo --keep 3     # Keep 3 versions
./bin/clean-repo --dry-run    # Preview what would be removed
./bin/clean-repo --all        # Remove all packages (dangerous!)
```

### sync-repo

Syncs repository to remote server.

```bash
# Sync to configured remote
./bin/sync-repo ./x86_64
```

## ISO Integration

To include this repository in an Arch ISO:

1. Copy the entire `x86_64/` directory to the ISO
2. Add the repository configuration to the ISO's `pacman.conf`
3. The packages will be available during installation

## Package Management

### Adding Packages

1. Add package name to `packages.official` or `packages.aur`
2. Run `./scripts/build-packages.sh`
3. Run `./scripts/update-repo.sh`

### Removing Packages

1. Remove package name from the list files
2. Delete the package file from `x86_64/`
3. Run `./scripts/update-repo.sh`

### Updating Packages

Simply run the build script again - it will download/build the latest versions:

```bash
./scripts/build-packages.sh
./scripts/update-repo.sh
```

## Security

### Package Signing (Optional)

1. **Create a GPG key:**
   ```bash
   gpg --gen-key
   ```

2. **Export public key:**
   ```bash
   gpg --export --armor "Your Name" > omarchy-repo.key
   ```

3. **Sign packages during build:**
   ```bash
   ./scripts/update-repo.sh --sign
   ```

4. **Client configuration:**
   ```ini
   [omarchy]
   SigLevel = Required
   Server = file:///home/ryan/Dev/omarchy-repo/x86_64
   ```

## Maintenance

### Regular Updates

Create a systemd timer or cron job for automatic updates:

```bash
# /etc/cron.daily/omarchy-repo-update
#!/bin/bash
cd /home/ryan/Dev/omarchy-repo
./scripts/build-packages.sh
./scripts/update-repo.sh
./scripts/clean-repo.sh --keep 2
```

### Backup

Important files to backup:
- `packages.official`
- `packages.aur`
- `x86_64/*.pkg.tar.*`
- GPG keys (if using signing)

## Troubleshooting

### Common Issues

1. **"No packages found"**
   - Run `./scripts/build-packages.sh` first

2. **AUR build failures**
   - Check build dependencies
   - Try manual mode: `./scripts/build-packages.sh --manual`

3. **Repository not recognized by pacman**
   - Ensure the repository is listed before other repos in `/etc/pacman.conf`
   - Run `sudo pacman -Sy` to sync databases

4. **Permission errors**
   - Some operations need sudo (downloading official packages)
   - Ensure scripts are executable: `chmod +x scripts/*.sh`

## Advanced Usage

### Mirror Synchronization

To sync with another omarchy instance:

```bash
rsync -av --delete \
    user@remote:/path/to/omarchy-repo/x86_64/ \
    /home/ryan/Dev/omarchy-repo/x86_64/
```

### Custom Build Flags

For AUR packages, edit `/etc/makepkg.conf` to customize:
- `CFLAGS` / `CXXFLAGS` for optimization
- `MAKEFLAGS` for parallel compilation
- `PACKAGER` for package attribution

## License

This repository structure and scripts are provided as-is for personal use.
