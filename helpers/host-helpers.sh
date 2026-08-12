# Resolving the Omarchy repository host
#
# One machine both serves pkgs.omarchy.org and runs the scheduled builds. The
# commands that reach it are doing repository work — uploading artifacts,
# signing, publishing — so the setting is named for the repository rather than
# for building, which happens on whatever machine the operator prefers.

# Usage: resolve_repo_host [explicit-host]
# Prints the host, or nothing when none is configured.
resolve_repo_host() {
  local explicit="${1:-}"

  if [[ -n "$explicit" ]]; then
    echo "$explicit"
    return 0
  fi

  if [[ -n "${OMARCHY_REPO_HOST:-}" ]]; then
    echo "$OMARCHY_REPO_HOST"
    return 0
  fi

  if [[ -f "$BUILD_ROOT/.repo-host" ]]; then
    # Ignore blank lines and comments so the file can be annotated.
    local value
    value=$(grep -vE '^\s*(#|$)' "$BUILD_ROOT/.repo-host" | head -1 | tr -d '[:space:]')
    if [[ -n "$value" ]]; then
      echo "$value"
      return 0
    fi
  fi

  return 1
}

# Shared wording so every command explains configuration the same way.
print_no_repo_host() {
  print_error "No repository host configured"
  echo ""
  echo "Pass --host, set OMARCHY_REPO_HOST, or write the destination to:"
  echo "  $BUILD_ROOT/.repo-host"
  echo ""
  echo "That file also arms the automatic build trigger in 'bin/omarchy-pkgs"
  echo "release'. Use --host or OMARCHY_REPO_HOST to keep them separate."
}
