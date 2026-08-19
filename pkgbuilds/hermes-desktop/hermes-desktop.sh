#!/bin/bash

# The desktop app is only a shell: it runs `hermes serve` against a Hermes CLI
# it does not ship. Finding none, it clones its own copy with the upstream
# install script -- an unpinned checkout in ~/.hermes that no package manages.
#
# So make sure the CLI is there first. Omarchy installs it with its own script;
# elsewhere, say so rather than letting the app quietly bootstrap a second
# Hermes behind the user's back.
if ! command -v hermes >/dev/null 2>&1; then
  if command -v omarchy-install-hermes-cli >/dev/null 2>&1; then
    omarchy-install-hermes-cli --now
  else
    echo "The Hermes CLI is not installed, so Hermes Desktop will install its" >&2
    echo "own copy under ~/.hermes. Install the CLI first to avoid that." >&2
  fi
fi

exec /opt/hermes-desktop/Hermes "$@"
