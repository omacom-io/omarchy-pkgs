#!/bin/bash
set -euo pipefail

# The desktop app is only a shell: it runs `hermes serve` against a Hermes CLI
# it does not ship. Finding none it offers to install its own, which clones an
# unpinned checkout into ~/.hermes/hermes-agent -- and that copy then wins
# forever, because the app checks ~/.hermes before it checks PATH.
#
# So guarantee the CLI here rather than relying on anything else having run.

tool='pipx:hermes-agent[extras=all]'
python='3.13'

# Hermes declares Requires-Python <3.14; left to itself uv builds the venv
# against Arch's 3.14 anyway and only fails later, inside a dependency. The
# cooldown override is exported so the version resolved to run is the one just
# installed. Both mirror omarchy-install-hermes-cli -- keep them in step.
export UV_PYTHON="$python"
export MISE_MINIMUM_RELEASE_AGE=0

if command -v omarchy-install-hermes-cli >/dev/null 2>&1; then
  omarchy-install-hermes-cli --now
elif ! [[ -d "$(mise where "$tool" 2>/dev/null)/hermes-agent/lib/python$python" ]]; then
  echo "Installing the Hermes CLI (this takes a minute)..." >&2
  mise use -g --quiet --force "$tool" || true
fi

# Hand the app the real executable rather than leaving it to search. Its PATH
# probe allows 15 seconds, which nothing that still has installing to do can
# meet.
hermes_bin="$(mise where "$tool" 2>/dev/null)/bin"
[[ -d $hermes_bin ]] && export PATH="$hermes_bin:$PATH"

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
