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
7. Remove unreachable foreign native payloads when that does not change the
   application's supported Linux behavior. If a package must retain deliberate
   cross-platform runtime data, record only exact relative paths and SHA-256
   digests in `.omarchy/aarch64-audit-allowlist`; split PKGBUILDs use
   `.omarchy/aarch64-audit-allowlist.<pkgname>` when only one output needs the
   review. Never exempt a package or directory broadly. Changed, missing,
   unused, ambiguous, or output-mismatched entries fail the build.

## Current upstream-delta audit

The package deltas were re-audited on 2026-08-31 against
`omacom-io/omarchy-pkgs` commit `28a4cfc6626801398b5748e0793509f5a19f6aeb`
(the current master, two commits after the Omarchy 4.0.2 release). The review covered every package directory changed
relative to that revision, not only the packages that had failed an earlier
build. Current AUR heads were also checked for every changed or added
AUR-backed recipe. Updated recipes were synchronized before re-running the
metadata and payload gates.

The 28 modified upstream package directories fall into the following review
classes:

| Review class | Package bases | Result |
| --- | --- | --- |
| AArch64 vendor artifact, source fallback, or foreign-payload cleanup | `1password`, `cursor-bin`, `cursor-cli`, `github-copilot-cli`, `grok-bot`, `heroic-games-launcher-bin`, `lmstudio-bin`, `openai-codex-desktop`, `rustdesk`, `t3code-bin`, `typora`, `visual-studio-code-bin`, `voxtype-bin` | Still required. The current upstream recipes either remain x86_64-only or do not remove unreachable foreign executables from their ARM64 payloads. |
| Portable source build whose recipe omits AArch64 | `asdcontrol`, `hermes-desktop`, `hyprland-preview-share-picker`, `libretro-uae-git`, `omasnap`, `qmk-hid`, `symfony-cli`, `tensaku`, `tzupdate`, `v4l2-relayd` | Still required. Their current source builds are portable, but the checked recipe still does not expose an AArch64 package. |
| Architecture-specific dependency, boot, or DKMS correction | `limine-mkinitcpio-hook`, `sunshine`, `xpadneo-dkms`, `yt6801-dkms` | Still required. Each change remains package-local and preserves the existing x86_64 path. |
| Explicit unsupported-runtime guard | `dropbox-cli` | Retained as a safety correction: the Python CLI is portable, but its required proprietary Dropbox daemon remains x86_64-only. |

The review removed or narrowed differences that no longer had the same
justification:

- `github-copilot-cli` dropped its stale `pkgrel` suffix metadata when its AUR
  `pkgver` advanced. The ordinary local `.1` rebuild suffix is sufficient for
  the new version.
- `xpadneo-dkms` no longer removes the AUR `LINUX-HEADERS` placeholder for every
  architecture. A top-level `CARCH` guard retains that dependency for the
  existing x86_64 kernel path and omits it only from the AArch64 dependency
  graph; an unsupported `checkdepends_x86_64` field is intentionally not used.
- The Limine runtime patch no longer adds a `LIMINE_FORCE_UEFI` bypass. Native
  firmware detection is unchanged. Limine 1.38 absorbed generic
  multi-architecture UEFI selection, so the remaining adaptation is limited to
  Arch Linux ARM's kernel name and `/boot/Image` plus the rEFInd AA64 filename.
- Cursor, Copilot CLI, Voxtype, LM Studio, and Zen were refreshed to their
  current AUR revisions. The three persistent recipe patches were regenerated
  against those exact baselines and apply without fuzz.
- `grok-bot` was deliberately not replaced by the current AUR recipe: the
  upstream package metadata already sets `sync: false`, and this tree carries
  0.29.0 while AUR is still at 0.20. The AArch64 delta remains only the vendor's
  architecture-specific asset mapping; following AUR here would be a downgrade.
- Copilot CLI 1.0.82 removed the old clipboard addon and introduced a new core
  ARM64 prebuild layout. The package now validates that layout and removes the
  two remaining x64 search helpers; it does not preserve an obsolete file
  assertion merely because the previous release used it.
- Voxtype 1.0.0 still hangs while linking its embedded `whisper.cpp` build with
  upstream release-profile LTO on this native AArch64 host. Its two ARM64
  engine builds therefore disable LTO package-locally; this is not a builder
  flag, does not affect x86_64, and is unrelated to BlastEm, which continues to
  use its normal LTO build.
- LM Studio's vendor revision is now captured before Omarchy adds its local
  rebuild suffix. This keeps the repository `pkgrel` monotonic without
  accidentally requesting a non-existent vendor asset such as `1.1`.
- The latest upstream Hermes Desktop `pkgrel=2` keyring fix is inherited in
  full, including its `libsecret` dependency and launcher behavior. Relative to
  that new baseline, the remaining delta only declares AArch64 and selects
  electron-builder's `linux-arm64-unpacked` output.

- PPSSPP's generic assets-path patch was rebased against the pinned libretro
  source revision. Its install path is unchanged, but it now applies without
  fuzz. The package-local post-sync hook preserves that exact replacement only
  when the fetched upstream patch still matches the reviewed old digest; a new
  upstream baseline therefore stops for review instead of silently restoring
  the stale hunk.

### Upstream additions reviewed on 2026-09-01

Rebasing onto upstream commit `a3d150e2b02c05fa5f7736d82bd42839516d2a3f`
introduced or restored five package bases. `python-sounddevice` declares
`arch=(any)`, has no native payload, and joins native AArch64 builds without a
recipe change. The remaining four are deliberately excluded until their
native paths are proved:

| Package base | Current blocker |
| --- | --- |
| `python-mediapipe` | The recipe downloads and executes `bazel-7.4.1-linux-x86_64`, declares only x86_64, and depends on `python-tensorflow`. A native Bazel/toolchain and dependency closure must be validated before enabling it. |
| `link-studio` | The source itself is plausibly portable, but its required `python-mediapipe` dependency is not yet available on AArch64. |
| `omakade` | The Qt/CMake source recipe declares only x86_64. It may be enabled after a clean native AArch64 build and payload audit. |
| `omapresent` | Upstream explicitly describes AArch64 as plausible but unproven. Its Qt WebEngine build and resulting payload require the same native validation. |

These are tracked capability gaps, not replacement slots. The maintained scope
follows every upstream package whose AArch64 recipe and dependency closure are
actually validated; it is not padded with unrelated packages merely to keep a
historical package count equal to x86_64.

### Upstream addition reviewed on 2026-09-02

Upstream commit `22e908d831f1e3b494abd018f14f9a66e942d5af` adds
`perplexity`. Its vendor repository publishes matching amd64 and arm64 Debian
packages, the recipe pins independent checksums for both, and its package
metadata places it in the fast ring. It therefore needs no change in this pull
request and no architecture-audit exception.

The shared AArch64 scope retains the 20 reviewed coverage additions selected
during the original alignment. Fork-only keyring, image-integration,
runtime-pin, and GitHub Release changes are not part of this pull request.

All 20 shared additions remain absent from the audited upstream 4.0.2 tree, so
none has become a duplicate that can simply be removed. They do not all have
the same necessity: `bindfs`, `dotnet-runtime-bin`, `gradle`,
`gtk-engine-murrine`, and `gtk2` provide build, dependency, or selected runtime
closure. The 15 deliberate coverage replacements are `bitwarden`, `brave-bin`,
`brave-origin-bin`, `ghostty`, `google-chrome`, `obsidian`, `ollama`,
`pandoc-cli`, `pinta`, `zed`, `zen-browser-bin`, `libretro-blastem`,
`libretro-desmume`, `libretro-kronos`, and `libretro-ppsspp`. These are a
reviewable product-scope choice, not a hidden prerequisite of the generic
AArch64 builder. Removing one would require an explicit scope decision and a
corresponding count/test update; it must not happen accidentally during sync.

The bespoke vendor feeds were checked in the same pass. Obsidian and Ollama
were already current; Pandoc, T3 Code, and OpenAI Desktop advanced to the
newest release accepted by their existing quarantine and cross-architecture
parity rules before native validation was repeated.

LM Studio 0.4.23 was rebuilt through the normal native AArch64 Docker path and
then audited through its AppImage boundary. The recursive scan expanded 2,254
files (3,792,351,870 bytes), inspected 55 ELF files and four nested containers,
and found no wrong-architecture ELF, foreign executable, or extraction error.
This replaces the weaker evidence obtained when the AppImage had been treated
as an opaque outer ELF file.

The refresh pass also rebuilt the changed source and vendor packages on the
same native host. T3 Code 0.0.37 expanded to 14,772 files with 17 AArch64 ELF
files and one nested AppImage; OpenAI Desktop 26.825.51511 expanded to 14,581
files with 33 AArch64 ELF files and one nested container; both reported no
foreign executable or audit error. The source tag for T3 Code 0.0.37 still
declares 0.0.36 in electron-builder's internal artifact name, so the recipe
selects the unique ARM64 artifact instead of rewriting vendor metadata.

After rebasing this branch onto upstream `master` on 2026-09-03, T3 Code had
advanced to 0.0.38. Its new source checksum and frozen lockfile verified, and a
fresh native AArch64 Docker build produced
`t3code-bin-0.0.38-1-aarch64.pkg.tar.zst`. The recursive audit expanded 14,770
files (723,185,733 bytes), found 17 AArch64 ELF files and one nested AppImage,
and reported no wrong-architecture ELF, foreign executable, reviewed exception,
or extraction error. This tag likewise declares the previous 0.0.37 internally,
so the version-independent artifact selection was exercised again. No QEMU or
binfmt emulation was used.

That rebase also replaced the removed x86-only `t3code-patched-bin` recipe with
upstream's new `strata` source recipe. A native AArch64 build of Strata 0.8.0,
together with its repository-local `xdg-terminal-exec` dependency, passed all
375 upstream tests. The final Strata package contained nine files and one
AArch64 ELF; the recursive audit reported no wrong-architecture ELF, foreign
executable, reviewed exception, nested container, or extraction error. The
dependency package also passed its own 24 tests and payload audit. No recipe or
network-policy change was needed, and neither build used QEMU or binfmt
emulation.

After upstream advanced during the audit, Hermes Desktop 2026.8.18-2 was
rebuilt again from the new baseline. Its package expanded to 477 files with
nine AArch64 ELF files and two nested containers, including the source-built
`linux-arm64` node-pty binding, with no foreign executable or audit error.
The refreshed Limine recipe was likewise rebuilt after narrowing its runtime
patch: its GraalVM native image was AArch64 and the 33-file package passed with
no foreign payload or audit error. Neither build used QEMU or binfmt emulation.

## AUR post-sync exceptions

| Package | AArch64-specific reason | Persistent handling |
| --- | --- | --- |
| `1password` | Vendor publishes a separate signed ARM64 archive. | `post-sync.sh` creates architecture-specific sources and selects the matching archive while retaining vendor signature verification. |
| `asdcontrol` | The upstream recipe unnecessarily restricts the package to x86_64. | `post-sync.sh` extends the architecture declaration only. |
| `cursor-bin` | ARM64 uses the vendor Debian bundle, while the x86_64 recipe repackages against system Electron. The ARM bundle also contains a Windows x64 JS-debug native module. | `post-sync.sh` adds the ARM source, computes its checksum during sync, separates dependencies, installs the vendor bundle through an ARM-only package function, and removes Windows-only JS-debug modules. |
| `cursor-cli` | The vendor's ARM64 archive contains a working native `tree-sitter-bash` binding but also bundles unused x86_64, Windows, and macOS prebuilds. | An AUR-sync recipe patch verifies the native binding and removes the foreign prebuild directory only from the AArch64 package. The x86_64 package path is unchanged. |
| `ghostty` | The Arch Linux ARM toolchain does not supply the same Zig input expected by the upstream recipe. | `post-sync.sh` adds a pinned upstream AArch64 Zig archive and selects it only for dependency resolution and the ARM build. |
| `github-copilot-cli` | The vendor artifact supports ARM64 but the AUR architecture list is narrower, and its ARM npm payload also retains x64 Linux search helpers alongside native copies. | `post-sync.sh` extends the architecture declaration. A recipe patch requires the ARM64 core runtime, native addons, `rg`, and `tgrep`, then removes only the x64 Linux search helpers on AArch64. |
| `grok-bot` | Vendor download paths and archives differ by architecture. | `post-sync.sh` adds the ARM64 Debian source and computes its checksum during sync. |
| `heroic-games-launcher-bin` | The AUR package follows Heroic's x86_64 archive, but Heroic does not publish a Linux ARM64 application artifact. Two x86_64 Windows shims are intentional runtime data for its Wine integrations. | A recipe patch preserves the AUR x86_64 path and builds the same tag from source for ARM64. Its `post-sync.sh` scopes the AUR artifact to x86_64, pins the ARM source checksum, and stops for review if Heroic changes any helper-binary version. The two Wine shims are retained only under exact path-and-digest audit entries. |
| `hermes-desktop` | The application build emits `linux-arm64-unpacked` instead of `linux-unpacked`. | `post-sync.sh` selects the architecture-specific output directory. |
| `hyprland-preview-share-picker` | The source build is architecture-neutral but the AUR declaration is x86_64-only. | `post-sync.sh` extends the architecture declaration. |
| `libretro-blastem` | Arch still pins the 2022 x86-only core, while BlastEm added its generated, architecture-independent CPU cores and a native Linux AArch64 CI target in July 2026. | The recipe pins the checksum-verified current libretro revision and uses BlastEm's standard build on both architectures. The recipe diff and build-flags patch survive the next Arch package sync and intentionally fail to apply if that baseline changes. |
| `libretro-desmume` | The ARM64 libretro target needs a platform flag and an upstream build fix. | `post-sync.sh` copies a pinned package-local patch and injects ARM-only make options. |
| `libretro-kronos` | The core needs ARM64 platform and CD-ROM feature flags. | `post-sync.sh` injects those make options only for AArch64. |
| `libretro-ppsspp` | Adreno-specific code is not valid for the generic Linux ARM64 target. | `post-sync.sh` applies the package-local exclusion patch and selects the ARM64 make target. |
| `libretro-uae-git` | AArch64 is already supported by the source build but omitted from the recipe. | `post-sync.sh` extends the architecture declaration. |
| `limine-mkinitcpio-hook` | Upstream 1.38 now selects the correct Limine UEFI binary on AArch64. Arch Linux ARM's generic kernel still uses the package name `linux-aarch64` and `/boot/Image`, while Limine expects an Arch-style kernel name and module-tree `vmlinuz`; its rEFInd probe also remains x64-specific. | The reduced recipe patch carries only those residual corrections: it maps the generic kernel to the stable `linux` entry and `/boot/Image`, passes that image explicitly to mkinitcpio, normalizes removal bookkeeping, and selects rEFInd's AA64 filename. `post-sync.sh` restores the checksum-pinned patch after AUR synchronization. |
| `lmstudio-bin` | The vendor ships architecture-specific AppImages and includes its own release revision in the asset path. | `post-sync.sh` selects the ARM64 asset, computes its checksum during sync, and keeps the vendor revision separate from Omarchy's local `pkgrel` suffix. The generic auditor recursively opens the embedded SquashFS without executing the AppImage runtime. |
| `omasnap` | The source build supports ARM64 but the recipe declaration is narrower. | `post-sync.sh` extends the architecture declaration. |
| `qmk-hid` | The source build supports ARM64 but the recipe declaration is narrower. | `post-sync.sh` extends the architecture declaration. |
| `rustdesk` | RustDesk publishes an Arch package only for x86_64. The existing AUR `rustdesk` recipe is an x86_64 source build, while AUR `rustdesk-bin` uses the vendor's official RPM for AArch64. | A package-local recipe patch leaves the existing x86_64 source build unchanged and follows `rustdesk-bin`'s dependencies, RPM source, and install layout only on AArch64. `post-sync.sh` pins the RPM checksum after each `rustdesk` sync. |
| `sunshine` | `libmfx` is an x86_64-only dependency. | `post-sync.sh` moves it to `depends_x86_64`. |
| `symfony-cli` | The vendor provides an ARM64 binary but the recipe declaration is narrower. | `post-sync.sh` extends the architecture declaration. |
| `tensaku` | Its Rust/GTK source build is portable but the AUR recipe declares x86_64 only. | A small recipe patch extends only the architecture declaration. |
| `typora` | The official ARM64 Debian archive contains an unused macOS x86_64 `cld.node` addon under the spellchecker dependencies. | A recipe patch verifies and retains a future AArch64 ELF replacement, removes only the known Mach-O x86_64 addon from AArch64 packages, and fails closed for any unexpected replacement. The x86_64 package path is unchanged. |
| `tzupdate` | Its Rust source build is portable but the AUR recipe declares x86_64 only. | A small recipe patch extends only the architecture declaration. |
| `v4l2-relayd` | The source build supports ARM64 but the recipe declaration is narrower. | `post-sync.sh` extends the architecture declaration. |
| `visual-studio-code-bin` | Microsoft's ARM64 Debian bundle includes native Copilot and MXC Linux helpers alongside Windows/macOS tools, and currently carries only an x64 optional `apply-seccomp` helper inside ASAR. | A recipe patch requires the ARM64 Linux helpers, removes x64 Copilot and non-Linux native files only on AArch64, and removes non-ARM unpacked seccomp directories. The exact nested x64 helper is checksum-reviewed until Microsoft ships an ARM64 replacement or removes it. |
| `voxtype-bin` | Upstream publishes its full prebuilt matrix only for x86_64. AArch64 must build the same signed tag from source. | A recipe patch keeps all vendor binaries x86_64-only, adds a checksum-pinned and signature-verified ARM source build, and updates the install hook to select the native binary. `post-sync.sh` refreshes the source checksum after each AUR update. The default and Vulkan engines are built; optional ONNX engines remain conditional on `onnxruntime` being deliberately installed in the clean builder. |
| `xpadneo-dkms` | The AUR header placeholder is provided by Omarchy's x86_64 kernel package, which is intentionally absent from the AArch64 scope. | `post-sync.sh` rewrites the dependency behind a top-level `CARCH` guard, retaining `LINUX-HEADERS` for x86_64 while omitting it from the AArch64 dependency graph. |
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
from its Rust helper. Before packaging it requires the locally built AArch64
`node-pty` binding and removes the unreachable Darwin/Windows prebuild matrix.
Gradle is the opposite case: its official distribution is intentionally a
cross-platform Java toolchain, so removing native implementations from its
JARs would change the product. The reviewed JARs are instead pinned by path and
SHA-256 in Gradle's package-local audit allowlist; every update must refresh
those entries after inspection. Other new local recipes, including `dotnet-runtime-bin`,
`brave-bin`, `brave-origin-bin`, `google-chrome`, and `zen-browser-bin`, keep
their asset mapping directly in the package directory rather than adding a
global binary-repackaging mechanism. Obsidian's official ARM64 archive still
contains two x86_64-only Node addons; the package drops those unusable files
without changing the x86_64 package. `openai-codex-desktop` follows OpenAI's
architecture-specific Debian repository and, on AArch64 only, requires a
native `linux-arm64` entry in every bundled Node prebuild matrix before
removing the other platform directories.

The scanner counts ECMA-335 assemblies separately from native Windows PE
files. This is required for `dotnet-runtime-bin` and `pinta`: their normal
managed IL and ReadyToRun assemblies use PE as a container on Linux, while
native Windows DLLs or executables remain foreign and require an exact reviewed
entry. The split `dotnet-sdk-bin` output retains five Microsoft Windows-target
test/debugging tools under an output-specific allowlist; the other five outputs
from the same PKGBUILD receive no exception. A managed-assembly count therefore
remains visible in audit evidence; it is not reported as zero or hidden by a
package-wide exception.

## Review and validation expectations

For every special package, reviewers should be able to verify all of the
following without reading the global release scripts:

- why the standard upstream recipe is insufficient;
- which source, dependency, patch, or install path differs on AArch64;
- how the change survives the next AUR or vendor sync;
- whether every added source is checksum- or signature-verified;
- why every retained foreign native payload is runtime data rather than a
  Linux host executable, and whether its exact audit digest still matches;
- whether x86_64 behavior remains unchanged;
- what condition will allow a temporary workaround to be removed.

Small declarative exceptions can remain in this package-support pull request.
Any exception requiring a new global policy, release-state transition, or
credentialed service should be proposed separately in
`docs/aarch64-follow-up.md`.
