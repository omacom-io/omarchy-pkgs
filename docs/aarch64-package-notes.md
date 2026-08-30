# AArch64 package-specific notes

This document records package-level exceptions in the AArch64 pull request.
They are intentionally kept out of the global builder and release scripts so
each exception can be reviewed, updated, or removed with its package.

## Maintenance rules

1. Prefer standard PKGBUILD architecture arrays such as `source_aarch64`,
   `depends_aarch64`, and `makedepends_aarch64`.
2. For AUR-synchronized packages, persist stable recipe diffs under
   `.omarchy/patches` and use `.omarchy/post-sync.sh` for values that must be
   discovered dynamically; editing only the checked-in PKGBUILD would be lost
   on the next sync.
3. Keep source patches under the package's `.omarchy/patches` or
   `.omarchy/files` directory and pin their checksums in the PKGBUILD.
4. Use `.omarchy/upstream.sh` for packages that follow a vendor release feed
   rather than the AUR.
5. Do not add package-name conditionals to `build/build.sh`. The builder should
   only implement behavior shared by all packages.
6. Do not declare AArch64 support when the vendor provides no suitable source
   and a source build has not been validated.

## AUR post-sync exceptions

| Package | AArch64-specific reason | Persistent handling |
| --- | --- | --- |
| `1password` | Vendor publishes a separate signed ARM64 archive. | `post-sync.sh` creates architecture-specific sources and selects the matching archive while retaining vendor signature verification. |
| `asdcontrol` | The upstream recipe unnecessarily restricts the package to x86_64. | `post-sync.sh` extends the architecture declaration only. |
| `cursor-bin` | ARM64 uses the vendor Debian bundle, while the x86_64 recipe repackages against system Electron. | `post-sync.sh` adds the ARM source, computes its checksum during sync, separates dependencies, and installs the vendor bundle through an ARM-only package function. |
| `cursor-cli` | The vendor's ARM64 archive contains a working native `tree-sitter-bash` binding but also bundles unused x86_64, Windows, and macOS prebuilds. | An AUR-sync recipe patch verifies the native binding and removes the foreign prebuild directory only from the AArch64 package. The x86_64 package path is unchanged. |
| `ghostty` | The Arch Linux ARM toolchain does not supply the same Zig input expected by the upstream recipe. | `post-sync.sh` adds a pinned upstream AArch64 Zig archive and selects it only for the ARM build. The upstream dependency-cache fetch is retried at most three times so a transient download failure does not invalidate an otherwise reproducible build. |
| `github-copilot-cli` | The vendor artifact supports ARM64 but the AUR architecture list is narrower, and its ARM npm payload also retains x64 clipboard/search helpers alongside native copies. | `post-sync.sh` extends the architecture declaration. A recipe patch requires the native clipboard, `rg`, and `tgrep` files and removes only their x64 counterparts on AArch64. |
| `grok-bot` | Vendor download paths and archives differ by architecture. | `post-sync.sh` adds the ARM64 Debian source and computes its checksum during sync. |
| `heroic-games-launcher-bin` | The AUR package follows Heroic's x86_64 archive, but Heroic does not publish a Linux ARM64 application artifact. | A recipe patch preserves the AUR x86_64 path and builds the same tag from source for ARM64. Its `post-sync.sh` scopes the AUR artifact to x86_64, pins the ARM source checksum, and stops for review if Heroic changes any helper-binary version. |
| `hermes-desktop` | The application build emits `linux-arm64-unpacked` instead of `linux-unpacked`. | `post-sync.sh` selects the architecture-specific output directory. |
| `hyprland-preview-share-picker` | The source build is architecture-neutral but the AUR declaration is x86_64-only. | `post-sync.sh` extends the architecture declaration. |
| `libretro-blastem` | Arch still pins the 2022 x86-only core, while BlastEm added its generated, architecture-independent CPU cores and a native Linux AArch64 CI target in July 2026. | The recipe pins the checksum-verified current libretro revision and uses BlastEm's standard build on both architectures. The recipe diff and build-flags patch survive the next Arch package sync and intentionally fail to apply if that baseline changes. |
| `libretro-desmume` | The ARM64 libretro target needs a platform flag and an upstream build fix. | `post-sync.sh` copies a pinned package-local patch and injects ARM-only make options. |
| `libretro-kronos` | The core needs ARM64 platform and CD-ROM feature flags. | `post-sync.sh` injects those make options only for AArch64. |
| `libretro-ppsspp` | Adreno-specific code is not valid for the generic Linux ARM64 target. | `post-sync.sh` applies the package-local exclusion patch and selects the ARM64 make target. |
| `libretro-uae-git` | AArch64 is already supported by the source build but omitted from the recipe. | `post-sync.sh` extends the architecture declaration. |
| `limine-mkinitcpio-hook` | The AUR recipe can compile on AArch64, but its installed runtime selects x86_64 UEFI filenames and discovers kernels only through Arch's `pkgbase` files. | A recipe patch carries a checksum-pinned runtime patch, while `post-sync.sh` restores that source patch after AUR synchronization. The runtime selects `BOOTAA64.EFI` and ARM bootloader filenames and accepts Arch Linux ARM kernel presets. |
| `lmstudio-bin` | The vendor ships architecture-specific AppImages. | `post-sync.sh` selects the ARM64 asset and computes its checksum during sync. |
| `omasnap` | The source build supports ARM64 but the recipe declaration is narrower. | `post-sync.sh` extends the architecture declaration. |
| `qmk-hid` | The source build supports ARM64 but the recipe declaration is narrower. | `post-sync.sh` extends the architecture declaration. |
| `rustdesk` | RustDesk publishes an Arch package only for x86_64. The existing AUR `rustdesk` recipe is an x86_64 source build, while AUR `rustdesk-bin` uses the vendor's official RPM for AArch64. | A package-local recipe patch leaves the existing x86_64 source build unchanged and follows `rustdesk-bin`'s dependencies, RPM source, and install layout only on AArch64. `post-sync.sh` pins the RPM checksum after each `rustdesk` sync. |
| `sunshine` | `libmfx` is an x86_64-only dependency. | `post-sync.sh` moves it to `depends_x86_64`. |
| `symfony-cli` | The vendor provides an ARM64 binary but the recipe declaration is narrower. | `post-sync.sh` extends the architecture declaration. |
| `tensaku` | Its Rust/GTK source build is portable but the AUR recipe declares x86_64 only. | A small recipe patch extends only the architecture declaration. |
| `tzupdate` | Its Rust source build is portable but the AUR recipe declares x86_64 only. | A small recipe patch extends only the architecture declaration. |
| `v4l2-relayd` | The source build supports ARM64 but the recipe declaration is narrower. | `post-sync.sh` extends the architecture declaration. |
| `visual-studio-code-bin` | Microsoft's ARM64 Debian bundle includes native Copilot search helpers alongside x64 copies, and currently carries only an x64 optional `apply-seccomp` helper. | A recipe patch requires and retains the ARM64 Copilot helpers, removes their x64 copies, and removes non-ARM seccomp directories only on AArch64. The missing ARM64 seccomp helper remains a documented vendor limitation. |
| `voxtype-bin` | Upstream publishes its full prebuilt matrix only for x86_64. AArch64 must build the same signed tag from source. | A recipe patch keeps all vendor binaries x86_64-only, adds a checksum-pinned and signature-verified ARM source build, and updates the install hook to select the native binary. `post-sync.sh` refreshes the source checksum after each AUR update. The default and Vulkan engines are built; optional ONNX engines remain conditional on `onnxruntime` being deliberately installed in the clean builder. |
| `xpadneo-dkms` | Kernel headers are supplied by the target environment rather than the AUR placeholder. | `post-sync.sh` removes the placeholder dependency without introducing an architecture-specific global rule. |
| `yt6801-dkms` | This is a DKMS source package; the vendor also replaced an old download in place. | `post-sync.sh` declares `any` and carries a checksum-pinned transition for the affected vendor release until AUR catches up. |

`bitwarden` and `zed` also use post-sync hooks to preserve Omarchy's package
names, `provides`, and `conflicts` after AUR synchronization. Zed additionally
retains `!strip` because its vendor binaries are already stripped and contain
custom ELF sections that current binutils cannot rewrite. Those rules are not
AArch64-specific, but keeping them package-local prevents the new ARM recipes
from changing global naming behavior.

## Recipe patches versus source patches

The files named `aarch64.patch` under `bindfs`, `gtk2`, `tensaku`, and
`tzupdate` only extend the PKGBUILD architecture declaration; they do not
modify project source code. Limine's `aarch64-uefi.patch` changes its package
recipe so the runtime correction is checksum-pinned and applied after every
AUR sync. The Heroic, RustDesk, and Voxtype patches also change their package
recipes, but still do not patch any project's compiled source.

RustDesk is intentionally not switched wholesale from the AUR `rustdesk`
source recipe to `rustdesk-bin`: doing so would replace upstream's existing
x86_64 source build. The ARM half of the package instead mirrors the
`rustdesk-bin` revision recorded as `aarch64_reference` in the package
metadata. Maintainers should compare that recipe whenever either AUR package
updates. This package-local exception can be removed once the source recipe
supports and is validated on AArch64, or once RustDesk publishes a native
AArch64 Arch package.

The corresponding `gtk-engine-murrine` patch also regenerates its Autotools
files, and the `pinta` patch selects the ARM64 .NET runtime identifier and the
repository's `-bin` .NET packages. These are recipe patches used by the
package-sync mechanism.

Only the following changes patch compiled source or its project build system
specifically for ARM64:

- `libretro-desmume` disables JIT implementations that support only x86 or
  32-bit ARM and selects the generic ARM64 interpreter target.
- `libretro-ppsspp` enables its ARM libpng sources and limits Android-only
  Adreno loader code to Android rather than generic Linux ARM64.

Limine's source patch changes installed shell hooks rather than compiled code.
It selects architecture-correct UEFI binaries and recognizes the kernel preset
layout used by Arch Linux ARM.

The BlastEm build-flags patch only preserves makepkg's `CFLAGS` and `LDFLAGS`
in the upstream Makefile; it is not an ARM port. The GTK2 XID/module-loading
patches, Murrine crash fix, PPSSPP asset-path patch, and `yt6801-dkms` Linux
6.16 compatibility change are likewise carried by their package recipes but
are not AArch64-specific source changes. The BlastEm and yt6801 transition
files are kept under `.omarchy/files` so they can be removed when their
upstream recipes catch up.

Temporary patches should be removed when their upstream project or recipe
adopts an equivalent fix. They must not be generalized into builder-side text
rewriting.

## Vendor-fed local packages

`obsidian`, `ollama`, `pandoc-cli`, and `t3code-bin` use package-local
`upstream.sh` hooks to track vendor releases. T3 Code retains its published
x86_64 archive and builds the same tagged source on AArch64 because the vendor
does not publish a Linux ARM64 application artifact. The ARM build uses the
Node.js 24 LTS line required by the source tree and remaps temporary build paths
from its Rust helper. Other new local recipes, including `dotnet-runtime-bin`,
`brave-bin`, `brave-origin-bin`, `google-chrome`, and `zen-browser-bin`, keep
their asset mapping directly in the package directory rather than adding a
global binary-repackaging mechanism. Obsidian's official ARM64 archive still
contains two x86_64-only Node addons; the package drops those unusable files
without changing the x86_64 package. `openai-codex-desktop` follows OpenAI's
architecture-specific Debian repository and, on AArch64 only, requires a
native `linux-arm64` entry in every bundled Node prebuild matrix before
removing the other platform directories.

## Review and validation expectations

For every special package, reviewers should be able to verify all of the
following without reading the global release scripts:

- why the standard upstream recipe is insufficient;
- which source, dependency, patch, or install path differs on AArch64;
- how the change survives the next AUR or vendor sync;
- whether every added source is checksum- or signature-verified;
- whether x86_64 behavior remains unchanged;
- what condition will allow a temporary workaround to be removed.

Small declarative exceptions can remain in this package-support pull request.
Any exception requiring a new global policy, release-state transition, or
credentialed service should be proposed separately in
`docs/aarch64-follow-up.md`.
