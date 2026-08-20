# What Arch itself ships, in pacman's resolution order.
#
# Omarchy's pacman.conf keeps [core] above [omarchy] and puts [omarchy] above
# [extra] and [multilib]. pacman takes the first repository carrying a name and
# never compares versions across the rest, so a name Arch ships from core is
# unreachable here, while a name from extra or multilib is one Omarchy answers
# for -- and has to stay ahead of.

OUTRANKING_REPOS=(core)
SHADOWED_REPOS=(extra multilib)

declare -A official_repo official_version

load_official_packages() {
  local repo listing name version

  for repo in "${OUTRANKING_REPOS[@]}" "${SHADOWED_REPOS[@]}"; do
    # Not `|| true`: a listing that fails after emitting some rows would leave a
    # partial repository behind and check fewer names while reporting success.
    if ! listing=$(pacman -Sl "$repo" 2>/dev/null); then
      print_error "[$repo] could not be listed; enable it and sync the package databases first"
      return 1
    fi

    if [[ -z $listing ]]; then
      print_error "[$repo] lists no packages; enable it and sync the package databases first"
      return 1
    fi

    while read -r _ name version _; do
      [[ -n $name ]] || continue
      [[ -n ${official_repo[$name]:-} ]] && continue
      official_repo[$name]="$repo"
      official_version[$name]="$version"
    done <<<"$listing"
  done
}

repo_outranks_omarchy() {
  [[ " ${OUTRANKING_REPOS[*]} " == *" $1 "* ]]
}
