#!/bin/bash

set -euo pipefail

ROOT=$(realpath "${BASH_SOURCE[0]%/*}/..")
metadata_work=$(mktemp -d)
repo_root=""

cleanup() {
  rm -rf "$metadata_work"
  [[ -z $repo_root ]] || rm -rf "$repo_root"
}
trap cleanup EXIT

print_srcinfo() {
  local package_dir=$1 arch=$2 package_work
  package_work="$metadata_work/${package_dir##*/}-$arch"
  mkdir -p "$package_work"
  (
    cd "$package_dir"
    CARCH=$arch BUILDDIR="$package_work" PKGDEST="$package_work" \
      SRCDEST="$package_work" SRCPKGDEST="$package_work" LOGDEST="$package_work" \
      makepkg --printsrcinfo
  )
}

packages=(
  1password
  asdcontrol
  bindfs
  bitwarden
  brave-bin
  brave-origin-bin
  cursor-bin
  cursor-cli
  dotnet-runtime-bin
  ghostty
  github-copilot-cli
  google-chrome
  gradle
  grok-bot
  gtk-engine-murrine
  gtk2
  hermes-desktop
  heroic-games-launcher-bin
  hyprland-preview-share-picker
  libretro-blastem
  libretro-desmume
  libretro-kronos
  libretro-ppsspp
  libretro-uae-git
  limine-mkinitcpio-hook
  lmstudio-bin
  obsidian
  ollama
  openai-codex-desktop
  omasnap
  pandoc-cli
  pinta
  qmk-hid
  rustdesk
  sunshine
  symfony-cli
  t3code-bin
  tensaku
  tzupdate
  v4l2-relayd
  visual-studio-code-bin
  voxtype-bin
  xpadneo-dkms
  yt6801-dkms
  zed
  zen-browser-bin
)

for package in "${packages[@]}"; do
  package_dir="$ROOT/pkgbuilds/$package"
  [[ -f $package_dir/PKGBUILD ]] || {
    echo "Missing AArch64 package recipe: $package" >&2
    exit 1
  }

  srcinfo=$(print_srcinfo "$package_dir" aarch64) || {
    echo "Failed to generate AArch64 metadata: $package" >&2
    exit 1
  }
  grep -Eq '^[[:space:]]+arch = (any|aarch64)$' <<< "$srcinfo" || {
    echo "Package does not declare AArch64 support: $package" >&2
    exit 1
  }

  # 1Password verifies its archives exclusively with vendor signatures.
  # Voxtype pins the source archive checksum and verifies its detached
  # signature, so exactly the signature entry may remain SKIP.
  case $package in
    1password) ;;
    voxtype-bin)
      [[ $(grep -Ec '^[[:space:]]+sha256sums_aarch64 = [0-9a-f]{64}$' <<< "$srcinfo") -eq 1 &&
         $(grep -Ec '^[[:space:]]+sha256sums_aarch64 = SKIP$' <<< "$srcinfo") -eq 1 ]] || {
        echo "Voxtype AArch64 source verification is incomplete" >&2
        exit 1
      }
      grep -Eq '^[[:space:]]+validpgpkeys = [0-9A-F]{40}$' <<< "$srcinfo" || {
        echo "Voxtype detached signature has no pinned signing key" >&2
        exit 1
      }
      ;;
    *)
      if grep -Eq '^[[:space:]]+[a-z0-9]+sums_aarch64 = SKIP$' <<< "$srcinfo"; then
        echo "Unverified AArch64 source in $package" >&2
        exit 1
      fi
      ;;
  esac
done

# Dropbox's CLI is architecture-independent Python, but it cannot run without
# Dropbox's proprietary x86_64-only daemon. Keep that exclusion explicit and
# persistent across AUR synchronization.
dropbox_cli_srcinfo=$(print_srcinfo "$ROOT/pkgbuilds/dropbox-cli" aarch64)
grep -Fq 'pkgrel = 2.1' <<< "$dropbox_cli_srcinfo" || {
  echo 'Dropbox CLI architecture correction does not carry a repository revision' >&2
  exit 1
}
grep -Eq '^[[:space:]]+arch = x86_64$' <<< "$dropbox_cli_srcinfo" || {
  echo 'Dropbox CLI no longer records its x86_64 runtime constraint' >&2
  exit 1
}
if grep -Eq '^[[:space:]]+arch = (any|aarch64)$' <<< "$dropbox_cli_srcinfo"; then
  echo 'Dropbox CLI incorrectly advertises an installable AArch64 package' >&2
  exit 1
fi
[[ -f $ROOT/pkgbuilds/dropbox-cli/.omarchy/patches/x86-only.patch ]] || {
  echo 'AUR synchronization would discard the Dropbox CLI architecture constraint' >&2
  exit 1
}

# Ghostty fetches a pinned Zig dependency graph before building. A transient
# mirror failure must be retried, but never indefinitely.
ghostty_pkgbuild="$ROOT/pkgbuilds/ghostty/PKGBUILD"
ghostty_post_sync="$ROOT/pkgbuilds/ghostty/.omarchy/post-sync.sh"
for recipe in "$ghostty_pkgbuild" "$ghostty_post_sync"; do
  grep -Fq 'for attempt in 1 2 3' "$recipe" &&
    grep -Fq 'fetch-zig-cache.sh' "$recipe" &&
    grep -Fq 'attempt < 3' "$recipe" || {
    echo "Ghostty lacks a persistent bounded dependency-fetch retry: $recipe" >&2
    exit 1
  }
done
grep -Fq 'Upstream Ghostty dependency-fetch command changed' "$ghostty_post_sync" || {
  echo 'Ghostty post-sync does not fail closed when its upstream baseline changes' >&2
  exit 1
}

# Zed ships already-stripped binaries. Re-stripping them is both unnecessary
# and rejected by current binutils for some custom ELF sections.
zed_srcinfo=$(print_srcinfo "$ROOT/pkgbuilds/zed" aarch64)
grep -Fq 'pkgrel = 2.1' <<< "$zed_srcinfo" || {
  echo 'Zed no-strip rebuild does not carry a repository revision' >&2
  exit 1
}
grep -Fq '	options = !strip' <<< "$zed_srcinfo" || {
  echo 'Zed no longer preserves its prebuilt binaries without re-stripping' >&2
  exit 1
}
grep -Fq "options=('!strip')" "$ROOT/pkgbuilds/zed/.omarchy/post-sync.sh" || {
  echo 'AUR synchronization would discard the Zed no-strip policy' >&2
  exit 1
}

# Adding the ARM64 vendor archive must not alter 1Password's existing x86_64
# filename. Evaluate both target architectures so an initialization-order bug
# cannot silently produce a URL with an empty architecture component.
onepassword_arm_srcinfo=$(print_srcinfo "$ROOT/pkgbuilds/1password" aarch64)
onepassword_x86_srcinfo=$(print_srcinfo "$ROOT/pkgbuilds/1password" x86_64)
grep -Fq '/stable/aarch64/1password-8.12.34.arm64.tar.gz' \
  <<< "$onepassword_arm_srcinfo" || {
  echo '1Password lost its ARM64 vendor archive path' >&2
  exit 1
}
grep -Fq '/stable/x86_64/1password-8.12.34.x64.tar.gz' \
  <<< "$onepassword_x86_srcinfo" || {
  echo '1Password ARM support broke the existing x86_64 vendor archive path' >&2
  exit 1
}

# Cursor's ARM64 vendor archive carries a native build/Release binding plus
# unused foreign prebuilds. Keep the cleanup package-local, fail closed if the
# native binding disappears, and preserve both vendor download paths.
cursor_pkgbuild="$ROOT/pkgbuilds/cursor-cli/PKGBUILD"
grep -Eq '^pkgrel=[0-9]+\.1$' "$cursor_pkgbuild" || {
  echo 'Cursor CLI AArch64 cleanup does not carry a repository revision' >&2
  exit 1
}
if ! grep -Fq 'build/Release/tree_sitter_bash_binding.node' "$cursor_pkgbuild" ||
  ! grep -Fq 'rm -rf -- "${tree_sitter_bash}/prebuilds"' "$cursor_pkgbuild"; then
  echo 'Cursor CLI does not verify its native binding before pruning foreign prebuilds' >&2
  exit 1
fi
cursor_arm_srcinfo=$(print_srcinfo "$ROOT/pkgbuilds/cursor-cli" aarch64)
cursor_x86_srcinfo=$(print_srcinfo "$ROOT/pkgbuilds/cursor-cli" x86_64)
grep -Fq '/linux/arm64/agent-cli-package.tar.gz' <<< "$cursor_arm_srcinfo" || {
  echo 'Cursor CLI lost its ARM64 vendor source' >&2
  exit 1
}
grep -Fq '/linux/x64/agent-cli-package.tar.gz' <<< "$cursor_x86_srcinfo" || {
  echo 'Cursor CLI cleanup changed the x86_64 vendor source' >&2
  exit 1
}

if ! grep -Fq "Copilot's ARM64 package lacks" \
  "$ROOT/pkgbuilds/github-copilot-cli/PKGBUILD" ||
  ! grep -Fq 'tgrep/bin/linux-x64' \
    "$ROOT/pkgbuilds/github-copilot-cli/PKGBUILD"; then
  echo 'GitHub Copilot CLI does not validate native helpers before pruning x64 copies' >&2
  exit 1
fi
grep -Fq 'Unexpected Obsidian addon architecture' \
  "$ROOT/pkgbuilds/obsidian/PKGBUILD" || {
  echo 'Obsidian does not reject unknown vendor addon architectures' >&2
  exit 1
}
grep -Fq 'ChatGPT prebuild matrix lacks Linux ARM64' \
  "$ROOT/pkgbuilds/openai-codex-desktop/PKGBUILD" || {
  echo 'OpenAI Desktop does not require native entries in vendor prebuild matrices' >&2
  exit 1
}
if ! grep -Fq "VS Code's ARM64 Copilot payload lacks" \
  "$ROOT/pkgbuilds/visual-studio-code-bin/PKGBUILD" ||
  ! grep -Fq '! -name arm64' \
    "$ROOT/pkgbuilds/visual-studio-code-bin/PKGBUILD"; then
  echo 'VS Code does not validate native helpers before pruning foreign payloads' >&2
  exit 1
fi

# A recipe may consume an official package archive as a source. The builder
# must copy makepkg's declared outputs, not mistake every .pkg.tar.zst in the
# working directory for a newly built package.
builder_script="$ROOT/build/build.sh"
grep -Fq 'makepkg --packagelist' "$builder_script" || {
  echo 'Builder does not use makepkg output metadata' >&2
  exit 1
}
if grep -Fq 'for pkg_file in *.pkg.tar.*' "$builder_script"; then
  echo 'Builder can mistake a package-shaped source archive for an output' >&2
  exit 1
fi

# Keep the reviewer-facing exclusion table synchronized with every checked-in
# recipe that the builder will skip on AArch64. Evaluate the same PKGBUILD
# architecture array used by the builder instead of maintaining a second list
# in this test.
exclusions_doc=$(sed -n \
  '/^## Known package exclusions$/,/^## Proposal 1:/p' \
  "$ROOT/docs/aarch64-follow-up.md")
for package_dir in "$ROOT"/pkgbuilds/*; do
  [[ -f $package_dir/PKGBUILD ]] || continue
  package=${package_dir##*/}
  if ! package_metadata=$(CARCH=aarch64 bash -c '
    source "$1" >/dev/null 2>&1 || exit 1
    printf "%s\t%s\n" "${pkgbase:-${pkgname[0]:-$pkgname}}" "${arch[*]}"
  ' _ "$package_dir/PKGBUILD"); then
    echo "Failed to evaluate architecture metadata: $package" >&2
    exit 1
  fi
  package_base=${package_metadata%%$'\t'*}
  package_arches=${package_metadata#*$'\t'}
  if ! grep -Eq '(^|[[:space:]])(any|aarch64)($|[[:space:]])' <<< "$package_arches"; then
    grep -Fq "\`$package_base\`" <<< "$exclusions_doc" || {
      echo "Undocumented AArch64 package exclusion: $package_base ($package)" >&2
      exit 1
    }
  fi
done

# These recipes retain their pre-existing x86_64 path and add an ARM-only
# declaration, vendor artifact, or source fallback.
hybrid_packages=(
  cursor-cli
  github-copilot-cli
  heroic-games-launcher-bin
  libretro-blastem
  limine-mkinitcpio-hook
  rustdesk
  t3code-bin
  tensaku
  tzupdate
  openai-codex-desktop
  visual-studio-code-bin
  voxtype-bin
)
for package in "${hybrid_packages[@]}"; do
  srcinfo=$(print_srcinfo "$ROOT/pkgbuilds/$package" x86_64)
  grep -Eq '^[[:space:]]+arch = x86_64$' <<< "$srcinfo" || {
    echo "Package no longer declares x86_64 support: $package" >&2
    exit 1
  }
done

# AUR synchronization replaces checked-in recipes. Every hybrid AUR package
# added here must therefore carry its ARM changes as a package-local patch.
aur_hybrid_packages=(
  cursor-cli
  github-copilot-cli
  heroic-games-launcher-bin
  rustdesk
  tensaku
  tzupdate
  visual-studio-code-bin
  voxtype-bin
)
for package in "${aur_hybrid_packages[@]}"; do
  jq -e '.source == "aur"' \
    "$ROOT/pkgbuilds/$package/.omarchy/package.json" >/dev/null || {
    echo "Hybrid package no longer follows its AUR source: $package" >&2
    exit 1
  }
  [[ -f $ROOT/pkgbuilds/$package/.omarchy/patches/aarch64.patch ]] || {
    echo "AUR sync would discard AArch64 support: $package" >&2
    exit 1
  }
done

for package in heroic-games-launcher-bin rustdesk voxtype-bin; do
  [[ -x $ROOT/pkgbuilds/$package/.omarchy/post-sync.sh ]] || {
    echo "Dynamic AArch64 checksums cannot be refreshed: $package" >&2
    exit 1
  }
done

# Limine's AUR recipe already compiles on ARM but its installed shell runtime
# assumes x86_64 UEFI filenames and Arch's /usr/lib/modules/*/pkgbase layout.
# Keep the runtime correction package-local and make it survive every AUR sync.
limine_dir="$ROOT/pkgbuilds/limine-mkinitcpio-hook"
jq -e '.source == "aur"' "$limine_dir/.omarchy/package.json" >/dev/null || {
  echo 'Limine no longer follows its AUR source' >&2
  exit 1
}
[[ -x $limine_dir/.omarchy/post-sync.sh ]] || {
  echo 'Limine cannot restore its AArch64 runtime patch after AUR synchronization' >&2
  exit 1
}
cmp -s \
  "$limine_dir/limine-entry-tool-aarch64.patch" \
  "$limine_dir/.omarchy/files/limine-entry-tool-aarch64.patch" || {
  echo 'Limine AArch64 runtime patch would not survive AUR synchronization' >&2
  exit 1
}
limine_patch_sum=$(sha256sum \
  "$limine_dir/.omarchy/files/limine-entry-tool-aarch64.patch" | awk '{ print $1 }')
grep -Fq "$limine_patch_sum" \
  "$limine_dir/.omarchy/patches/aarch64-uefi.patch" || {
  echo 'Limine AUR synchronization would write a stale runtime patch checksum' >&2
  exit 1
}
for invariant in BOOTAA64.EFI 'etc/mkinitcpio.d/*.preset' is_supported_uefi_arch; do
  grep -Fq "$invariant" "$limine_dir/limine-entry-tool-aarch64.patch" || {
    echo "Limine runtime patch lost AArch64 invariant: $invariant" >&2
    exit 1
  }
done
grep -Eq '^pkgrel=[0-9]+\.1$' "$limine_dir/PKGBUILD" || {
  echo 'Limine runtime patch does not carry an Omarchy package revision' >&2
  exit 1
}

# The Arch recipe still pins BlastEm before its native AArch64 support. The
# package must follow a checksum-pinned revision at or after the upstream ARM
# enablement and retain distro build flags. It uses BlastEm's standard build,
# not a builder-side emulator or architecture-specific optimization override.
blastem_pkgbuild="$ROOT/pkgbuilds/libretro-blastem/PKGBUILD"
grep -Fq 'pkgver=20260813.175226.gaeb16cd0750f' "$blastem_pkgbuild" || {
  echo 'BlastEm does not pin the validated upstream AArch64 revision' >&2
  exit 1
}
cmp -s \
  "$ROOT/pkgbuilds/libretro-blastem/libretro-blastem-flags.patch" \
  "$ROOT/pkgbuilds/libretro-blastem/.omarchy/files/libretro-blastem-flags.patch" || {
  echo 'BlastEm source patch would not survive an Arch package sync' >&2
  exit 1
}
if grep -RIEq 'NOLTO|fno-lto|qemu|binfmt' "$ROOT/pkgbuilds/libretro-blastem"; then
  echo 'BlastEm must retain the standard native AArch64 build without overrides or emulation' >&2
  exit 1
fi

# RustDesk keeps upstream's x86_64 source build, but its AArch64 path must stay
# aligned with the established AUR rustdesk-bin RPM recipe rather than silently
# reverting to the vendor Debian bundle.
rustdesk_pkgver=$(sed -n "s/^_pkgver='\([^']*\)'/\1/p" "$ROOT/pkgbuilds/rustdesk/PKGBUILD")
rustdesk_srcinfo=$(print_srcinfo "$ROOT/pkgbuilds/rustdesk" aarch64)
rustdesk_arm_source="source_aarch64 = rustdesk-${rustdesk_pkgver}-0.aarch64.rpm::https://github.com/rustdesk/rustdesk/releases/download/${rustdesk_pkgver}/rustdesk-${rustdesk_pkgver}-0.aarch64.rpm"
grep -Fq "$rustdesk_arm_source" <<< "$rustdesk_srcinfo" || {
  echo 'RustDesk AArch64 does not follow the rustdesk-bin RPM source' >&2
  exit 1
}
grep -Fq "source_x86_64 = rustdesk-${rustdesk_pkgver}.tar.gz::https://github.com/rustdesk/rustdesk/archive/refs/tags/${rustdesk_pkgver}.tar.gz" <<< "$rustdesk_srcinfo" || {
  echo 'RustDesk no longer preserves the existing x86_64 source build' >&2
  exit 1
}
jq -e '.aarch64_reference.source == "aur" and
       .aarch64_reference.package == "rustdesk-bin" and
       (.aarch64_reference.upstream_commit | test("^[0-9a-f]{40}$"))' \
  "$ROOT/pkgbuilds/rustdesk/.omarchy/package.json" >/dev/null || {
  echo 'RustDesk does not record the rustdesk-bin revision used by AArch64' >&2
  exit 1
}

grep -Fq 'declare -n arch_makedepends="makedepends_$ARCH"' "$ROOT/build/build.sh" || {
  echo "Builder does not resolve architecture-specific build dependencies" >&2
  exit 1
}
grep -Fq 'repo-add omarchy-build.db.tar.zst "${built_filenames[@]}"' "$ROOT/build/build.sh" || {
  echo "Builder does not index every split-package output" >&2
  exit 1
}
grep -Fq 'Cannot initialize the local build repository' "$ROOT/build/build.sh" || {
  echo "Builder does not fail closed when its local repository cannot be initialized" >&2
  exit 1
}

# Bind-mounted workspaces must remain writable when the host user and the
# container's builder user have different numeric UIDs. A locally owned
# workspace must also avoid an unnecessary sudo prompt before granting the
# container user write access.
grep -Fq 'chmod -R a+rwX "$dir"' "$ROOT/helpers/docker-helpers.sh" || {
  echo "Docker bind mounts are not writable across host/container UID differences" >&2
  exit 1
}
permission_work="$metadata_work/permissions"
sudo_marker="$metadata_work/unexpected-sudo"
mkdir -p "$permission_work"
chmod 700 "$permission_work"
(
  # shellcheck source=../helpers/docker-helpers.sh
  source "$ROOT/helpers/docker-helpers.sh"
  if [[ $(id -u) -ne 0 ]]; then
    sudo() {
      : > "$sudo_marker"
      return 1
    }
  fi
  make_dir_writable "$permission_work"
)
[[ ! -e $sudo_marker ]] || {
  echo "Writable Docker bind mount triggered an unnecessary sudo prompt" >&2
  exit 1
}
[[ $(stat -c %a "$permission_work") == 777 ]] || {
  echo "Docker bind mount is not writable across container UID differences" >&2
  exit 1
}

# A first AArch64 release has no older repository copy to satisfy virtual
# dependencies. Verify that local providers participate in build ordering:
# mise-bin must be built before packages whose depends array names `mise`.
provider_plan=$(
  ARCH=aarch64 MIRROR=edge DRY_RUN=true \
    PKGBUILDS_DIR="$ROOT/pkgbuilds" HELPERS_DIR="$ROOT/helpers" \
    BUILD_OUTPUT_DIR="$metadata_work/build-output" \
    FINAL_OUTPUT_DIR="$metadata_work/repository" \
    PACKAGES='omarchy-fish omarchy-zsh mise-bin' \
    bash "$ROOT/build/build.sh"
)
grep -Fq 'Build order: mise-bin omarchy-fish omarchy-zsh' <<< "$provider_plan" || {
  echo "Builder does not order virtual dependencies after their local provider" >&2
  exit 1
}

# Edge contains both stable and development variants. Their conflicts/provides
# metadata makes them mutually exclusive at install time, but both package
# bases must remain buildable in one repository pass. Exact package names take
# precedence over a sibling's virtual provide when ordering the two pairs.
variant_plan=$(
  ARCH=aarch64 MIRROR=edge DRY_RUN=true \
    PKGBUILDS_DIR="$ROOT/pkgbuilds" HELPERS_DIR="$ROOT/helpers" \
    BUILD_OUTPUT_DIR="$metadata_work/variant-build-output" \
    FINAL_OUTPUT_DIR="$metadata_work/variant-repository" \
    PACKAGES='omarchy omarchy-dev omarchy-settings omarchy-settings-dev' \
    bash "$ROOT/build/build.sh"
)
grep -Fq \
  'Build order: omarchy-settings omarchy-settings-dev omarchy omarchy-dev' \
  <<< "$variant_plan" || {
  echo "Builder cannot order mutually exclusive stable/dev package variants" >&2
  exit 1
}
grep -Fq '[[ $ARCH == aarch64 && $(uname -m) == aarch64 ]]' "$ROOT/bin/sign" || {
  echo "Signing would change the existing cross-build host behavior" >&2
  exit 1
}
grep -Fq '[[ $ARCH == aarch64 && $(uname -m) == aarch64 ]]' "$ROOT/bin/update-repo" || {
  echo "Repository updates would change the existing cross-build host behavior" >&2
  exit 1
}

find "$ROOT/pkgbuilds" -path '*/.omarchy/post-sync.sh' -print0 |
  xargs -0 -r -n1 bash -n

jq -e '(.skip_build // false) == false' \
  "$ROOT/pkgbuilds/gradle/.omarchy/package.json" >/dev/null || {
  echo "Gradle remains excluded from the initial AArch64 build" >&2
  exit 1
}

# Repository cleanup must group ARM archive versions under the package name.
repo_root=$(mktemp -d)
mkdir -p "$repo_root/edge/aarch64"
touch -d '@1' "$repo_root/edge/aarch64/example-tool-1.0-1-aarch64.pkg.tar.zst"
touch -d '@2' "$repo_root/edge/aarch64/example-tool-2.0-1-aarch64.pkg.tar.zst"
cleanup_output=$(OMARCHY_REPO_ROOT="$repo_root" \
  "$ROOT/bin/clean-repo" --arch aarch64 --mirror edge --keep 1 --dry-run)
grep -Fq 'Processing example-tool (2 versions found)' <<< "$cleanup_output"
grep -Fq 'Would remove: example-tool-1.0-1-aarch64.pkg.tar.zst' <<< "$cleanup_output"

# Architecture-neutral removal must select the ARM utility image on ARM hosts.
grep -Fq 'IMAGE_ARCH=aarch64' "$ROOT/bin/remove-package" || {
  echo "Package removal does not select the native ARM utility image" >&2
  exit 1
}

echo "PASS: ${#packages[@]} package bases expose verified AArch64 metadata"
