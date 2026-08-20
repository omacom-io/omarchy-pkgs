# Serialize commands that mutate the build workspace or the published repository.
#
# bin/build wipes build-output/ at startup, bin/promote-build moves files into
# pkgs.omarchy.org/, and every mirror shares src/ and .srcdest/. Two overlapping
# runs therefore delete each other's artifacts mid-flight and can promote an
# incomplete package set. On 2026-08-12 two edge releases started 42 seconds
# apart; both read the repository database before the first had updated it, both
# rebuilt omarchy 4.0.0rc2, and only promote-build's refusal to overwrite a
# published file stopped the second from republishing what was already live.
#
# Wait rather than fail: a queued run re-reads the database once the holder has
# updated it and correctly skips what was just published, and the edge and
# stable auto-release timers are scheduled for the same minute by design.

OMARCHY_PKGS_LOCK_TIMEOUT="${OMARCHY_PKGS_LOCK_TIMEOUT:-3600}"

# True when this process already holds the lock through an ancestor: bin/repo
# calls bin/build, bin/upload-prebuilt calls bin/repo four times, and those
# nested calls must not deadlock waiting on their own parent.
#
# Confirming the inherited descriptor still points at the same file, rather than
# trusting the exported path alone, keeps a stale or hand-set variable from
# waving a run through unserialized. A descriptor that fails to check out falls
# through to a real acquire, which blocks loudly instead of running unprotected.
repo_lock_held() {
  local lock_file="$1"

  [[ "${OMARCHY_PKGS_LOCK_HELD:-}" == "$lock_file" ]] || return 1
  [[ -n "${OMARCHY_PKGS_LOCK_FD:-}" ]] || return 1
  [[ -e "/proc/self/fd/$OMARCHY_PKGS_LOCK_FD" ]] || return 1
  [[ "/proc/self/fd/$OMARCHY_PKGS_LOCK_FD" -ef "$lock_file" ]]
}

acquire_repo_lock() {
  local label="$1"
  local lock_file="$BUILD_ROOT/.repo.lock"

  repo_lock_held "$lock_file" && return 0

  if ! command -v flock >/dev/null; then
    print_error "flock not found (install util-linux); refusing to run unserialized"
    exit 1
  fi

  # Append mode: opening with > would truncate the current holder's details
  # before we get a chance to report them.
  exec {OMARCHY_PKGS_LOCK_FD}>>"$lock_file"

  if ! flock -n "$OMARCHY_PKGS_LOCK_FD"; then
    local holder
    holder=$(<"$lock_file")
    print_warning "Another repository command is running: ${holder:-unknown}"
    print_info "Waiting up to ${OMARCHY_PKGS_LOCK_TIMEOUT}s for it to finish..."

    if ! flock -w "$OMARCHY_PKGS_LOCK_TIMEOUT" "$OMARCHY_PKGS_LOCK_FD"; then
      print_error "Timed out after ${OMARCHY_PKGS_LOCK_TIMEOUT}s waiting for the repository lock"
      print_warning "Holder: ${holder:-unknown}"
      print_info "Lock file: $lock_file"
      exit 1
    fi

    print_success "Lock acquired, continuing"
  fi

  printf 'pid=%s command=%s started=%s\n' "$$" "$label" "$(date -Is)" >"$lock_file"

  # Both are exported so nested calls can find and verify the descriptor. The
  # descriptor itself is inherited across exec, which is what makes the check
  # in repo_lock_held meaningful.
  export OMARCHY_PKGS_LOCK_HELD="$lock_file"
  export OMARCHY_PKGS_LOCK_FD
}
