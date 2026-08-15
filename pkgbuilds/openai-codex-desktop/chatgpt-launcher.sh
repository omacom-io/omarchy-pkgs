#!/bin/bash
set -euo pipefail

user_flags=()
flags_file="${XDG_CONFIG_HOME:-${HOME:-}/.config}/codex-flags.conf"

if [[ -r "$flags_file" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    [[ -n "${line//[[:space:]]/}" ]] || continue
    read -r -a flags <<<"$line"
    user_flags+=("${flags[@]}")
  done <"$flags_file"
fi

# Chromium's own Ozone detection falls back to XWayland often enough to matter,
# and the result is a blurry window on every scaled display. Ask for Wayland
# directly, unless the user has already picked a platform themselves.
platform_flags=()
if [[ -n "${WAYLAND_DISPLAY:-}" || "${XDG_SESSION_TYPE:-}" == wayland ]]; then
  platform_flags=(--ozone-platform=wayland)

  for flag in "${user_flags[@]}" "$@"; do
    case "$flag" in
      --ozone-platform=* | --ozone-platform-hint=*) platform_flags=() ;;
    esac
  done
fi

exec /usr/lib/chatgpt/ChatGPT "${platform_flags[@]}" "${user_flags[@]}" "$@"
