# omarchy-dell-haptic-touchpad

This package installs a configurable replacement for Omarchy's stock Dell XPS
haptic touchpad daemon.

What it installs:

- `/usr/bin/omarchy-haptic-touchpad-user`
- `/usr/bin/omarchy-update-dell-haptic.sh`

What the pacman install hook does:

- verifies `dell-xps-haptic-touchpad.service` already exists
- configures the service to run the packaged daemon
- writes `OMARCHY_HAPTIC_HOME` to `/etc/omarchy-dell-haptic-touchpad.env`
- creates `~/.config/omarchy/dell-haptic.conf` for the target desktop user if needed
- applies a default `INTENSITY=90`
- resets the trackpad controller before restarting the service

Usage:

```bash
omarchy-update-dell-haptic.sh --intensity 90
```

Notes:

- The exposed Synaptics interface is a single shared HID PID `Device Gain`
  field, so this package uses one shared `INTENSITY` value.
- The updater can rewrite the service override if it is missing or still points
  at an older manual setup.
