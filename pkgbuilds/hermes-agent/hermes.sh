#!/bin/bash

# Hermes is a Python application that pins every one of its dependencies
# exactly and declares Requires-Python >=3.11,<3.14, so it cannot be built
# against Arch's Python or share the python-* packages. mise builds it a
# private environment instead, on first run and on demand.
#
# The interpreter pin below is not belt-and-braces. Given no compatible
# interpreter to hand, uv builds the venv against the system Python in
# violation of Hermes' own bound, reports success, and leaves the failure to
# surface later inside a dependency.

set -euo pipefail

readonly tool='pipx:hermes-agent[extras=all]'
readonly python="${HERMES_PYTHON:-3.13}"

export UV_PYTHON="$python"

# `mise up` -- which omarchy update runs -- reinstalls without this wrapper's
# UV_PYTHON, so an upgrade can quietly move Hermes onto the system Python.
# Check the interpreter that is actually there, not merely that something is.
hermes_installed_on_pinned_python() {
  local prefix
  prefix=$(mise where "$tool" 2>/dev/null) || return 1
  [[ -d "$prefix/hermes-agent/lib/python$python" ]]
}

if ! hermes_installed_on_pinned_python; then
  echo "Installing Hermes on Python $python (this takes a minute)..." >&2

  # Hermes ships several times a week, so mise's release cooldown would hold a
  # new version back for days. Same call omarchy-mise-install makes.
  MISE_MINIMUM_RELEASE_AGE=0 mise use -g --quiet --force "$tool" || exit 1
fi

# Installed as /usr/bin/hermes, with hermes-agent and hermes-acp symlinked to
# it, so the name we were invoked under picks the entry point. Anything else --
# someone running this file straight out of a checkout -- means hermes.
command=$(basename "$0")
case "$command" in
hermes | hermes-agent | hermes-acp) ;;
*) command='hermes' ;;
esac

exec mise x "$tool" -- "$command" "$@"
