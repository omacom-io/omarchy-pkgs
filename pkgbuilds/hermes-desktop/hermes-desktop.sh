#!/bin/bash
set -euo pipefail

# Hermes Desktop is a shell around a Hermes runtime, and it only works against
# one built from its own commit. A CLI from PyPI is always a different release
# -- PyPI trails the tags -- and the mismatch fails the app's readiness probe
# with 401 Unauthorized. So keep it away from whatever `hermes` is on PATH,
# which on Omarchy is the mise CLI installed for the terminal agent, and let
# the app provision and manage its own runtime under ~/.hermes. That is the
# arrangement upstream ships, and the only one that starts.
export HERMES_DESKTOP_IGNORE_EXISTING=1

# Reconcile every launch rather than trusting whatever installed us. A plain
# `pacman -S hermes-desktop`, or an install interrupted partway, leaves any
# Hermes the terminal agent had built still sitting there, and by then the
# menu entry that would have tidied it up is disabled because we are present.
if command -v omarchy-install-hermes-cli >/dev/null 2>&1; then
  omarchy-install-hermes-cli >/dev/null 2>&1 || true
fi

# Chromium's own Ozone detection falls back to XWayland often enough to matter,
# and the result is a blurry window on every scaled display. Ask for Wayland
# directly, unless the user has already picked a platform themselves.
platform_flags=()
if [[ -n "${WAYLAND_DISPLAY:-}" || ${XDG_SESSION_TYPE:-} == wayland ]]; then
  platform_flags=(--ozone-platform=wayland)

  for flag in "$@"; do
    case "$flag" in
    --ozone-platform=* | --ozone-platform-hint=*) platform_flags=() ;;
    esac
  done
fi

exec /opt/hermes-desktop/Hermes "${platform_flags[@]}" "$@"
