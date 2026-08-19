#!/bin/bash
set -euo pipefail

# The desktop app is only a shell: it runs `hermes serve` against a Hermes CLI
# it does not ship. Finding none, it clones its own copy with the upstream
# install script -- an unpinned checkout in ~/.hermes that no package manages.
#
# command -v rather than omarchy-cmd-present: no other launcher in this repo
# makes a package depend on omarchy, and this has to behave on a plain Arch box.
# Run the installer even when hermes is already on PATH. A stub can be there
# and cold, and `mise up` can leave one pointing at a Hermes built against the
# wrong Python; repairing either costs minutes, and the app allows 15 seconds
# before it gives up and bootstraps. Installing here is a no-op when healthy.
if command -v omarchy-install-hermes-cli >/dev/null 2>&1; then
  omarchy-install-hermes-cli --now
elif ! command -v hermes >/dev/null 2>&1; then
  echo "The Hermes CLI is not installed, so Hermes Desktop will install its" >&2
  echo "own copy under ~/.hermes. Install the CLI first to avoid that." >&2
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
