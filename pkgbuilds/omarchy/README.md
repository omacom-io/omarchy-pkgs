# Omarchy Package

Meta-package that pulls in the full Omarchy desktop environment.

## Package Split

### omarchy-settings
- User configs (`/etc/skel/`)
- System configs (`/etc/`)
- Default configs (`/usr/share/omarchy/default/`)
- Plymouth theme
- System fonts
- Branding assets (logo, icons)
- ISO helper binaries (`omarchy-debug`, `omarchy-upload-log`)

### omarchy-installer
- Installation scripts (`/usr/share/omarchy/install/`)
- Installer binaries (`omarchy-install`, `omarchy-disk-config`)

### omarchy (this package)
- User binaries (`omarchy-*` commands)
- Themes for runtime switching
- System migrations
- Desktop environment dependencies (Hyprland, Wayland, apps)

## Dependencies

Depends on both `omarchy-settings` and `omarchy-installer`.

## Files

- `/usr/bin/omarchy-*` - User commands (excludes ISO helpers)
- `/usr/share/omarchy/themes/` - Theme switching configs
