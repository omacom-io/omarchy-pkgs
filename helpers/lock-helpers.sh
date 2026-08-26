# Release lock: one channel mutation at a time on this host.
#
# Everything that changes a published channel (release runs, advance, promote,
# upload-prebuilt) takes this lock, so a timer firing mid-advance or two
# operators colliding serializes instead of interleaving partial publishes.
#
# The lock lives beside the published tree (REPO_ROOT), not the checkout, so
# the primary checkout and the rc branch worktree contend on the same file.
# Reentrant across child scripts: acquire_release_lock exports
# OMARCHY_RELEASE_LOCK_HELD, and children skip acquisition when they see it
# (the flock fd is inherited, so the lock stays held for the whole tree).

RELEASE_LOCK_FD=9

acquire_release_lock() {
  local timeout="${1:-3600}"

  if [[ -n "${OMARCHY_RELEASE_LOCK_HELD:-}" ]]; then
    return 0
  fi

  local lock_file="${REPO_ROOT:-$BUILD_ROOT/pkgs.omarchy.org}/.release.lock"
  mkdir -p "$(dirname "$lock_file")"

  eval "exec $RELEASE_LOCK_FD>>\"\$lock_file\""

  if ! flock -n "$RELEASE_LOCK_FD"; then
    local holder
    holder=$(cat "$lock_file" 2>/dev/null | tail -1)
    echo "Waiting for release lock (up to ${timeout}s)${holder:+ — held by: $holder}" >&2
    if ! flock -w "$timeout" "$RELEASE_LOCK_FD"; then
      echo "Could not acquire release lock within ${timeout}s: $lock_file" >&2
      echo "If no release is actually running, remove the file and retry." >&2
      return 1
    fi
  fi

  # Record the holder for the "waiting for" message above. Truncate first so a
  # crashed holder's stale line does not linger once we own the lock.
  : >"$lock_file"
  echo "pid $$ ($0) since $(date '+%Y-%m-%d %H:%M:%S')" >>"$lock_file"

  export OMARCHY_RELEASE_LOCK_HELD=1
}
