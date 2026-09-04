# GitHub-releases upstream provider for bin/sync-upstream.
#
# A package whose upstream ships tagged GitHub releases with a checksum
# manifest asset needs no upstream.sh hook: the whole feed is data, declared
# in .omarchy/package.json --
#
#   "upstream": {
#     "github": "jdx/mise",
#     "checksums": "SHASUMS256.txt",
#     "assets": {
#       "x86_64": "mise-{tag}-linux-x64.tar.xz",
#       "aarch64": "mise-{tag}-linux-arm64.tar.xz"
#     }
#   }
#
# {tag} and {pkgver} interpolate into asset names; tags may carry a leading
# "v", which is stripped for pkgver. Drafts and prereleases are ignored. The
# provider emits the same JSON contract as an upstream.sh hook, so
# bin/sync-upstream's validation and min_release_age backstop apply
# unchanged; a feed that fits no convention keeps a bespoke upstream.sh.

package_upstream_github_repo() {
  local pkgdir="$1"
  # `objects` drops a non-object upstream value (validation rejects those
  # separately) instead of erroring the jq pipeline.
  package_metadata_value "$pkgdir" '(.upstream? | objects | .github)' ""
}

# Fetches sit behind functions so the self-test can replace them with fixture
# readers; everything below the fetch is deterministic and testable offline.
# Only the 100 most recent releases are considered -- a bounded search, not
# pagination. Quarantined releases report no update and wait for the next
# run; a page with no stable release at all (drafts and prereleases only)
# fails the sync instead, because a provider-tracked feed suddenly shipping
# nothing stable is an anomaly worth a loud error, not a silent skip.
github_fetch_releases() {
  local repo="$1"
  curl -fsSL "https://api.github.com/repos/$repo/releases?per_page=100"
}

github_fetch_checksums() {
  local repo="$1" tag="$2" asset="$3"
  curl -fsSL "https://github.com/$repo/releases/download/$tag/$asset"
}

github_fetch_repo() {
  local repo="$1"
  curl -fsSL "https://api.github.com/repos/$repo"
}

# Confirms the repository serving a feed is still the one that was declared.
#
# upstream.github is metadata a person wrote once, in a pull request, and has no
# reason to revisit. Two things change underneath it without anything in the
# sync noticing, and neither is a judgement call:
#
#   renamed   GitHub redirects a renamed or transferred repository, so a stale
#             owner/repo keeps resolving and every sync keeps passing. The
#             abandoned name is then free for anyone to register, and whoever
#             takes it inherits this package's release feed. Comparing the
#             full_name GitHub returns against what is declared is the whole
#             defense, and it costs one field.
#
#   archived  An archived repository cannot publish anything, so a feed that
#             appears to ship a new release from one is not the feed we believe
#             we are reading -- the same class of anomaly this provider already
#             treats as a loud error.
#
# Deliberately not checked: repository age and release count. Neither says
# anything about whether an artifact is safe -- a project can be new and sound,
# or old and never once reviewed -- and a threshold on either would reject
# perfectly good young upstreams while stopping no attacker who is willing to
# wait. Every check here reports a fact about the repository as it is now.
github_repo_identity_status() {
  local repo_json="$1" declared="$2"
  local full_name archived

  full_name=$(jq -r '.full_name // ""' <<<"$repo_json")
  archived=$(jq -r 'if has("archived") then .archived else "missing" end' <<<"$repo_json")

  # Fail closed on a response this cannot read, for the same reason an unusable
  # tag fails the sync: a repository we cannot verify is not one to adopt a
  # release from.
  if [[ -z "$full_name" || "$archived" == "missing" ]]; then
    echo "could not read repository metadata for $declared" >&2
    return 1
  fi

  # GitHub treats owner and repository names case-insensitively, so a difference
  # in case is not a rename.
  if [[ "${full_name,,}" != "${declared,,}" ]]; then
    echo "upstream.github declares $declared but GitHub serves $full_name: the repository was renamed or transferred, and the declared name is now free for anyone to register" >&2
    return 1
  fi

  if [[ "$archived" == "true" ]]; then
    echo "$declared is archived upstream and cannot be publishing new releases" >&2
    return 1
  fi

  return 0
}

# Emits the newest qualifying release as hook-contract JSON. min_release_age
# is honored during selection (newest release older than the window wins,
# even when a younger one exists) and BYPASS_MIN_RELEASE_AGE=1 lifts it.
# Unusable tags or timestamps anywhere in the feed fail the sync rather than
# being skipped: a feed this provider cannot fully read is a feed it should
# not silently choose from.
github_upstream_release() {
  local package_dir="$1" min_age="${2:-0}"
  local metadata repo checksums_name
  metadata=$(metadata_file_for_dir "$package_dir")

  repo=$(jq -r '(.upstream? | objects | .github) // ""' "$metadata")
  if [[ ! "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    echo "invalid upstream.github repository: '${repo:-<empty>}'" >&2
    return 1
  fi
  checksums_name=$(jq -r '(.upstream? | objects | .checksums) // ""' "$metadata")
  if [[ -z "$checksums_name" ]]; then
    echo "upstream.checksums names the checksum manifest asset and is required" >&2
    return 1
  fi
  local arches
  mapfile -t arches < <(jq -r '(.upstream? | objects | .assets) // {} | keys[]' "$metadata")
  if [[ ${#arches[@]} -eq 0 ]]; then
    echo "upstream.assets must map at least one architecture to an asset name" >&2
    return 1
  fi

  local releases now
  now=$(date +%s)
  if ! releases=$(github_fetch_releases "$repo"); then
    echo "could not fetch the release feed for $repo" >&2
    return 1
  fi

  local candidates=0 best_tag="" best_pkgver="" best_published_at=""
  local tag published_at pkgver published_epoch
  while IFS=$'\t' read -r tag published_at; do
    if [[ ! "$tag" =~ ^v?([A-Za-z0-9._+]+)$ ]]; then
      echo "$repo release has an unusable tag: ${tag:-<empty>}" >&2
      return 1
    fi
    pkgver=${BASH_REMATCH[1]}

    if [[ -z "$published_at" ]] || ! published_epoch=$(date --date="$published_at" +%s 2>/dev/null); then
      echo "$repo release $tag has an invalid published_at: ${published_at:-<empty>}" >&2
      return 1
    fi
    candidates=$((candidates + 1))

    if (( now - published_epoch < min_age )); then
      if [[ "${BYPASS_MIN_RELEASE_AGE:-}" == "1" ]]; then
        echo "Bypassing release-age gate for $repo $tag" >&2
      else
        continue
      fi
    fi

    if [[ -z "$best_pkgver" ]] || [[ "$(vercmp "$pkgver" "$best_pkgver")" -gt 0 ]]; then
      best_tag=$tag
      best_pkgver=$pkgver
      best_published_at=$published_at
    fi
  # `// ""` rather than `// empty`: empty would drop the field and shift the
  # columns, so a malformed row could masquerade as a different one instead
  # of tripping the per-field checks above.
  done < <(jq -r '.[] | select((.draft or .prerelease) | not) | [.tag_name // "", .published_at // ""] | @tsv' <<<"$releases")

  if (( candidates == 0 )); then
    echo "no stable releases found in the feed for $repo" >&2
    return 1
  fi
  if [[ -z "$best_tag" ]]; then
    echo "every recent $repo release is still inside the release-age quarantine; skipping" >&2
    echo '{}'
    return 0
  fi

  # Already checked in: report no update instead of re-fetching checksums.
  local current_pkgver
  current_pkgver=$(grep -m1 '^pkgver=' "$package_dir/PKGBUILD" | cut -d= -f2- | tr -d "\"'")
  if [[ "$best_pkgver" == "$current_pkgver" ]]; then
    echo '{}'
    return 0
  fi

  # Confirmed here rather than before selection so a scheduled sync over every
  # package pays for the extra call only when a release is actually about to be
  # adopted -- the same place the checksum manifest is already fetched.
  local repo_json
  if ! repo_json=$(github_fetch_repo "$repo"); then
    echo "could not fetch repository metadata for $repo" >&2
    return 1
  fi
  github_repo_identity_status "$repo_json" "$repo" || return 1

  local checksums
  if ! checksums=$(github_fetch_checksums "$repo" "$best_tag" "$checksums_name"); then
    echo "could not fetch $checksums_name for $repo $best_tag" >&2
    return 1
  fi

  local jq_args=(--arg pkgver "$best_pkgver" --arg published_at "$best_published_at")
  local jq_filter='{pkgver: $pkgver, published_at: $published_at, sha256sums: {}}'
  local arch template filename checksum
  for arch in "${arches[@]}"; do
    if [[ ! "$arch" =~ ^[a-z0-9_]+$ ]]; then
      echo "invalid architecture key in upstream.assets: '$arch'" >&2
      return 1
    fi
    template=$(jq -r --arg arch "$arch" '.upstream.assets[$arch]' "$metadata")
    filename=${template//\{pkgver\}/$best_pkgver}
    filename=${filename//\{tag\}/$best_tag}
    # Manifest lines are "<sha256>  <name>", with the name sometimes prefixed
    # "./" (sha256sum of a local path) or "*" (binary-mode marker).
    checksum=$(awk -v f="$filename" '$2 == f || $2 == "./" f || $2 == "*" f { print $1; exit }' <<<"$checksums")
    if [[ ! "$checksum" =~ ^[0-9a-f]{64}$ ]]; then
      echo "no valid checksum for $filename in $repo $best_tag $checksums_name" >&2
      return 1
    fi
    jq_args+=(--arg "sum_$arch" "$checksum")
    jq_filter+=" | .sha256sums[\"$arch\"] = [\$sum_$arch]"
  done

  jq -n "${jq_args[@]}" "$jq_filter"
}
