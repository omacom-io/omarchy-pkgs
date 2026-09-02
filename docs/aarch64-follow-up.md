# AArch64 release follow-up proposal

This pull request is deliberately limited to AArch64 package recipes and the
minimum builder changes required to build, sign, and index those packages. It
does not redesign the upstream scheduler or release train.

In particular, this change does not add an emulated GitHub Actions job or
change upstream's existing optional cross-architecture build behavior. Release
acceptance should be performed on a native AArch64 builder.

## Included in this pull request

- An Arch Linux ARM build-container bootstrap.
- Architecture-specific `depends`, `makedepends`, and `checkdepends` handling.
- Correct dependency ordering across package names and virtual `provides`, plus
  indexing for all split-package outputs.
- Native ARM container selection for architecture-neutral signing, repository
  database updates, and package removal on an ARM host.
- An explicit, fingerprint-pinned public-key handoff for incremental builds
  that must consume a signed repository before its keyring package can be
  installed from that repository.
- AArch64 sources, checksums, dependencies, patches, and metadata for the
  package set covered by this pull request.
- An AArch64 Gradle bootstrap package in the normal build plan so packages such
  as Limine do not depend on a package that the ARM repository cannot provide.
- A bounded final-package architecture audit that recursively opens Electron
  ASAR, SquashFS/AppImage, and libarchive-supported containers before an
  AArch64 artifact is admitted to the build repository.
- Metadata and dry-run tests that do not require changes to upstream's CI
  runner architecture.

The existing manual command shape is preserved. An operator can select an
architecture with commands such as `bin/repo build --arch aarch64`; repository
outputs remain separated under `<channel>/aarch64`.

Package-specific exceptions remain inside their package directories. See
`docs/aarch64-package-notes.md` for their maintenance and review boundaries.

## Package scope

Relative to the `upstream/master` revision used as this pull request's base,
all 116 existing package directories remain present. This change extends 27 of
those existing recipes and adds 20 package directories, for 136 in total. The
47 package bases exercised by `test/aarch64-support-test.sh` are 27 adapted
recipes plus the 20 additions; the test does not claim that every
unchanged recipe requires an AArch64 exception.

The added package directories are grouped by their role:

- build, runtime, or compatibility closure: `bindfs`, `dotnet-runtime-bin`
  (pkgbase `dotnet-core-bin`), `gradle`, `gtk-engine-murrine`, and `gtk2`;
- applications and command-line tools: `bitwarden`, `brave-bin`,
  `brave-origin-bin`, `ghostty`, `google-chrome`, `obsidian`, `ollama`,
  `pandoc-cli`, `pinta`, `zed`, and `zen-browser-bin`;
- libretro cores: `libretro-blastem`, `libretro-desmume`, `libretro-kronos`,
  and `libretro-ppsspp`.

This source-tree scope is not a claim that the published x86_64 repository has
the same package-base list. Published channel databases retain historical
artifacts until an operator explicitly removes them, while some AArch64
recipes are needed because an equivalent package is obtained from a different
source on x86_64. Reviewers should therefore evaluate each addition as a
package recipe, not as a byte-for-byte mirror of the current x86_64 database.

## Validation performed for this pull request

The repository's existing Docker entry point was exercised on a native
AArch64 host with an AArch64 Docker daemon, without QEMU or binfmt emulation:

```sh
bin/build --arch aarch64 --mirror edge --package rustdesk
```

The command bootstrapped the Arch Linux ARM builder image, imported the
existing verification keys, resolved the AArch64 package repositories, and
completed the RustDesk build with one package built and no failures. The
resulting package reported `arch = aarch64`; its main executable and all 12
bundled shared objects were AArch64 ELF files. The generated
`omarchy-build.db` entry named the same package file and recorded the same
SHA-256 digest as an independent checksum of that file.

The native Docker path was also exercised for the source-built
`libretro-blastem` core:

```sh
bin/build --arch aarch64 --mirror edge --package libretro-blastem
```

The build used BlastEm's standard `-flto` path; no `NOLTO`, QEMU, or binfmt
override was required. It completed with one package built and no failures.
The package metadata reported `arch = aarch64`, and its only payload was a
stripped AArch64 ELF shared object. `ldd -r` found no unresolved symbols, all
required libretro entry points were exported, and a direct dynamic-load smoke
test returned API version 1 and the expected `BlastEm 0.6.3-pre` system
metadata. No game ROM was used in this packaging test. BlastEm's native
AArch64 enablement commit separately records a RetroArch gameplay test:
<https://github.com/libretro/blastem/commit/b817f113b36b9ebe12956bc60f40697408eb2c34>.

The self-tests also generated verified AArch64 metadata for all 47 package
bases covered by this pull request and checked the preserved x86_64 paths,
AUR post-sync patches, dynamic checksum hooks, split-package indexing, and
architecture guards in the repository tools.

A vendor-payload audit additionally found foreign ELF files bundled inside
five nominally ARM64 packages. Package-local fixes were then rebuilt natively:
`cursor-cli`, `github-copilot-cli`, `obsidian`, `openai-codex-desktop`, and
`visual-studio-code-bin`. A complete scan of each rebuilt archive reported no
non-AArch64 ELF. Clean-container installation succeeded; Copilot CLI, VS Code,
and OpenAI Desktop returned their expected versions, with VS Code also
reporting `arm64`. Obsidian reached its Electron main package but, both before
and after the cleanup, crashed in the headless container after failing to find
D-Bus. That result establishes no packaging regression but is not a desktop
runtime acceptance test.

That original audit established the architecture of ELF payloads only. A later
multi-format check found that Typora's official ARM64 Debian archive also
carried an unused macOS x86_64 `cld.node` addon. The AArch64 recipe now removes
that exact Mach-O payload and fails closed if the vendor replaces it with an
unknown format; the persistent recipe patch keeps the correction across AUR
synchronization.

The corrected Typora recipe was then rebuilt through the normal Docker entry
point on a native AArch64 daemon. Its final `1.14.9-1.1` package passed the
build gate with 4,264 expanded files, 12 AArch64 ELF files, three recursively
opened ASAR containers, and no foreign executable or audit error. An
independent invocation returned the same counts, the removed `cld.node` path
was absent from the archive, and the temporary repository database recorded
the package archive's independently calculated SHA-256 digest.

The generic build path now runs `bin/audit-package-architecture` against every
final AArch64 archive before copying it to `build-output` or adding it to the
temporary repository database. It validates every ELF machine and recursively
opens standard Electron ASAR, SquashFS/AppImage, tar, zip, Debian, RPM, and
other libarchive-supported containers. AppImages are inspected with
`unsquashfs`; their vendor runtime is never executed. ECMA-335 managed assemblies are counted
separately from native Windows PE files. Wrong-architecture ELF, Mach-O, native
PE, and DOS executables fail unless a package-local review pins either that
exact relative file or its deliberate cross-platform container by SHA-256.
Changed digests, missing paths, unused entries, and malformed allowlists all
fail; reviewed violations remain counted in the JSON evidence. This keeps
Gradle's intentional platform-matrix JARs and Heroic's Wine shims auditable
without a package-wide or directory-wide exemption. Unreachable foreign
prebuilds in Cursor, Copilot CLI, T3 Code, Typora, and VS Code are removed by
their recipes instead.

Split PKGBUILDs may scope a policy to one output with
`.omarchy/aarch64-audit-allowlist.<pkgname>`. The builder rejects an ambiguous
generic/output-specific pair and any policy that matches no emitted package.
The .NET recipe uses this for `dotnet-sdk-bin`: 2,454 managed assemblies are
classified separately, while five Windows-target test/debugging tools are
reviewed by exact path and digest only for that split output.

The hardened gate was exercised through the normal native Docker build path
against Cursor, GitHub Copilot CLI, T3 Code, and Visual Studio Code. All four
recipes built successfully without QEMU. Cursor, Copilot, and T3 produced no
foreign executable or wrong-architecture ELF; T3 retained the locally compiled
AArch64 `node-pty` binding. VS Code retained only its one documented x64
`apply-seccomp` helper inside ASAR, which matched the exact review digest; its
other Windows/macOS helpers were absent. The six-output .NET recipe was then
built in the same clean path: five outputs needed no exception, while only
`dotnet-sdk-bin` selected the output-specific five-file policy. Every output
completed with zero audit errors.

Recursion depth, expanded file count, expanded byte count, and extraction time
are bounded. File sizes and types are enumerated in batches, so a Gradle
archive expanding to more than 100,000 files completes in tens of seconds
rather than spawning one classifier process per file. The dependency-free ASAR
reader avoids an npm or network dependency in the release environment.
Synthetic tests cover good, bad, and malformed ASAR and AppImage payloads,
nested tar payloads, managed PE, native foreign formats, exact
file/container reviews, changed and stale
allowlists, false-positive archive signatures, both supported target
architectures, and every configured resource limit.

Maintainers can audit an unpacked tree or a completed archive directly:

```sh
bin/audit-package-architecture --arch aarch64 --reject-foreign \
  --allowlist pkgbuilds/example/.omarchy/aarch64-audit-allowlist \
  path/to/package.pkg.tar.zst
```

Omit `--allowlist` for packages with no reviewed exception; that is the normal
case.

The targeted commands above used no signing key, rclone credential, production
remote, or release-train state. They establish package-level behavior, not
release acceptance by themselves.

A separate, zero-baseline acceptance run exercised the complete shared package
range locally on native AArch64 hardware. After excluding `dropbox-cli`, whose
portable Python code still cannot run without Dropbox's x86_64-only daemon, all
116 upstream-aligned package bases built successfully. They produced 145
archives: 112 declared `aarch64` and 33 declared `any`. Those archives contained
92,505 regular files and 562 ELF files; every ELF reported AArch64.

The shared range was validated inside a disposable 118-base repository that
also contained two explicitly downstream-only packages. All 147 resulting
archives and repository databases were signed with an ephemeral local key. The
manifest, audit, signed database, and 305-entry checksum file named the same 147
archives, and dependency resolution succeeded separately for every scoped
output. The two downstream packages account exactly for the remaining two
archives, 30 regular files, and one AArch64 ELF, so they do not mask a missing
or misclassified upstream package. No package archive, baseline, credential, or
result was uploaded, and neither GitHub Actions nor QEMU was used.

That acceptance run predates the recursive multi-format gate. It proves native
construction, direct ELF architecture, signing, repository completeness, and
dependency solvability, but it is not evidence that every nested ASAR/JAR or
non-ELF payload was clean. A later read-only audit of the 147 published fork
archives recursively expanded 288,990 files (21.8 GB) and 424 containers. It
found the Typora defect, four Electron/Node packages with removable foreign
prebuilds, Gradle and Heroic's deliberate cross-platform runtime data, normal
.NET managed assemblies, and one `file(1)` false positive on Limine's
`ESP_PATH` configuration. Those findings produced the package cleanups,
managed-PE classification, explicit container signatures, and exact reviewed
exceptions described above. Historical published archives remain historical;
only rebuilt packages passing the new gate qualify as current evidence.

The fork's stable snapshot was audited independently because its 145 archive
hashes differed from edge and therefore could not reuse that evidence. All 145
downloads matched the stable Release checksums before scanning. The audit
expanded 287,417 files (21.8 GB) and 422 containers: 140 archives passed the
hardened policy, while the five historical Cursor, Copilot CLI, T3 Code,
Typora, and VS Code archives contained exactly the already identified
unreachable foreign payloads. There was no stable-only finding. Those archive
revisions predate the recipe cleanups; replacement packages must still pass
the build-time gate before they can be published.

The first repository audit rejected one extra `omarchy-chromium` archive. Its
recipe consumes an official `.pkg.tar.zst` as input, and the generic builder's
output glob had mistaken that input for a makepkg result. The builder now uses
`makepkg --packagelist`; an isolated native rebuild emitted and indexed only
`omarchy-chromium-bin`, after which the complete audit passed. This is a generic
builder correction, not a Chromium-specific release exception.

A signed-baseline rehearsal also exposed the trust bootstrap at the opposite
end of the build: pacman cannot synchronize an existing repository signed by a
new publisher until that public key is in the builder image's system keyring.
The generic builder now accepts `OMARCHY_REPOSITORY_KEY` and an optional pinned
`OMARCHY_REPOSITORY_KEY_FINGERPRINT`, imports exactly one public key, and
pins it before repository synchronization. Release backends remain
responsible for mounting the intended public key and pinning its fingerprint;
the builder does not embed a downstream key or weaken repository signature
policy.

The audit also makes the later `arch=('any')` policy work concrete:
`omarchy-nvim` is declared `any` but its native build produced two AArch64 ELF
files. The zero-baseline run rebuilt it on ARM and the repositories are
architecture-separated, so the validated AArch64 snapshot is internally
consistent. The same `any` archive must nevertheless not be reused for x86_64;
the bootstrap proposal below records the required policy decision rather than
silently treating this host-built payload as architecture-neutral.

That run validates the shared native builder and complete local repository
assembly paths. It does not exercise upstream's production repository host,
rclone staging, or edge/rc/stable release train. Acceptance on that environment,
followed by installation from a staged upstream repository, remains
release-operations follow-up work as described below.

### Zero-baseline refresh on 2026-09-02

After the latest upstream additions, a second native AArch64 zero-baseline run
selected 120 package bases: all 118 bases in the then-current shared pull-request
scope plus the fork's two explicitly separated integration packages. The full
sweep built 118 bases. `dbxcli-bin` stopped on a transient GitHub DNS failure,
and a temporary attempt to tune pnpm network behavior also made `t3code-bin`
reject an untyped option. The experiment was discarded rather than becoming
package policy. Subsequent native targeted builds completed both packages,
successful staging archives were preserved, and the repository database was
regenerated from the combined output. No generic download retry, timeout, or
concurrency policy was retained because those concerns are independent of
AArch64 support.

The resulting repository contains exactly 120 unique `pkgbase` values and 149
package archives: 114 declare `aarch64` and 35 declare `any`. The expected and
actual package-base sets match exactly after accounting for the existing
`dotnet-runtime-bin` → `dotnet-core-bin` and `yaru-icon-theme` → `yaru`
pkgbase names. All 149 database filenames and SHA-256 values match independent
checks of the archives.

Every final archive passed the recursive architecture policy. The only host-side
rescan failure was environmental: the host lacked `unsquashfs` for LM Studio's
nested AppImage. Repeating that one read-only audit in the same native AArch64
builder image expanded 2,254 files across four containers, inspected 55 ELF
files, and reported zero wrong-architecture, foreign, or unreviewed payloads.
The exact .NET, Gradle, Heroic, and VS Code exceptions remained the only reviewed
foreign artifacts; no new exception was added during this run. The refreshed
Sunshine recursive source graph, Symfony CLI source build, rebased PPSSPP asset
patch, T3 Code source build, and BlastEm's normal LTO path all completed
natively.

No QEMU or binfmt emulation was used. This refresh intentionally stopped at an
unsigned local repository because the production private key and publication
credentials were not present on the validation host. Production signing,
rclone staging, and a clean-client install/upgrade from the upstream staging
remote therefore remain operator acceptance work.

## Known vendor payload limitations

Two official ARM64 application archives still have upstream feature gaps that
cannot be completed solely by changing an Arch package recipe:

- Obsidian's ARM64 archive contains x86_64-only `btime` and `get-fonts` Node
  addons and no ARM64 replacements. Those binaries cannot load on AArch64 and
  are removed from the package. The application itself and CLI must be smoke
  tested, but birth-time and native font-enumeration behavior remain vendor
  follow-up work.
- Visual Studio Code's ARM64 archive contains ARM64 Copilot `rg` and `tgrep`
  helpers, which the recipe retains, but its optional sandbox runtime carries
  only an x64 `apply-seccomp`. The runtime already treats an absent helper as
  unsupported and emits a warning. Unpacked foreign helpers are removed; the
  copy inside Microsoft's ASAR is retained without rewriting the vendor
  container, but its exact nested path and SHA-256 are reviewed by the build
  gate. Full seccomp support requires Microsoft to ship the documented ARM64
  helper.

These limitations are recorded rather than hidden by weakening the package
architecture audit. Neither package uses emulation, and their x86_64 packaging
paths are unchanged.

## Not included in this pull request

The current automatic version-check, queue, rebuild-trigger, and release-train
logic is designed around the published x86_64 repository. Enabling those paths
for a second architecture changes production scheduling and failure semantics,
so it should be reviewed separately from package compatibility.

The following sections are proposals, not descriptions of functionality
implemented by this branch.

Two fork-only package bases are also deliberately excluded. A separate
`omarchy-aarch64-keyring` would split the repository trust model, while this
proposal uses the existing production key and `omarchy-keyring`. Likewise,
`omarchy-spice-guest-tools` is guest-VM integration rather than architecture
enablement; it should be proposed as an independent package, with its runtime
and default-install policy reviewed separately.

## Known package exclusions

The AArch64 dry-run deliberately skips the following package bases. They are
not silently queued and they do not block publication of the supported set.
Adding any of them later should require either a vendor ARM64 artifact or
validation on the hardware the package is intended to enable.

Against upstream `master` at the 2026-09-03 rebase, the source tree contains
142 package bases. Generating `.SRCINFO` for every recipe with `CARCH=aarch64`
classifies 119 as AArch64-compatible and the following 23 as excluded, with no
metadata-generation failures. The total stayed constant because upstream
removed `t3code-patched-bin` and added the AArch64-enabled `strata` recipe.

| Package bases | Reason for exclusion |
| --- | --- |
| `dropbox`, `makima-bin`, `minecraft-launcher`, `spotify`, `tmog-bin` | The checked-in recipe consumes a vendor x86_64/amd64 application artifact and no validated ARM64 replacement is available. |
| `dropbox-cli`, `nautilus-dropbox` | Their runtime dependency is the excluded proprietary `dropbox` client. The CLI's Python source is portable, but publishing it as `any` would still leave an unsatisfiable AArch64 package. |
| `lib32-nvidia-580xx-utils` | This is explicitly a 32-bit x86 compatibility package. |
| `nvidia-580xx-utils` | The recipe consumes NVIDIA's Linux x86_64 driver bundle; an ARM driver stack must not be inferred from it. |
| `asusctl`, `dell-xps-touchpad-haptics`, `dell-xps13-sidecar-amps`, `intel-ipu7-camera`, `libfprint-git`, `macbook12-spi-driver-dkms`, `macbook8-spi-pxa2xx-nodma-dkms`, `supergfxctl`, `tuxedo-drivers-nocompatcheck-dkms` | These recipes carry enablement for specific x86 laptop platforms or devices. An architecture declaration alone would not demonstrate useful or safe ARM support. |
| `linux-ptl` | This is an x86_64-only Panther Lake kernel variant and is already excluded from unscoped builds with `skip_build`. An ARM kernel must follow the target platform's supported kernel source and configuration instead. |
| `python-mediapipe` | The recipe downloads and executes an x86_64 Bazel binary and depends on `python-tensorflow`; its native AArch64 toolchain and dependency closure have not been validated. |
| `link-studio` | Its source is plausibly portable, but it requires the currently excluded `python-mediapipe` package. |
| `omakade` | The Qt/CMake source recipe declares only x86_64. A clean native AArch64 build and payload audit are still required. |
| `omapresent` | Upstream explicitly records AArch64 as plausible but unproven. Its Qt WebEngine build and payload have not yet passed native AArch64 validation. |

The fork's two additional package bases and the exclusions above are therefore
recorded as product or hardware policy decisions, not worked around in the
global builder.

## Proposal 1: native ARM staging and release builder

Provision a native Arch Linux ARM host with the same repository checkout,
Docker access, rclone credentials, and signing credentials as the existing
builder. Use it first against a non-production remote.

Acceptance criteria:

1. Build a small dependency closure containing both `arch=('any')` and native
   AArch64 packages.
2. Sign every package with the existing production signing key.
3. Generate an `omarchy.db` repository database and install packages from it on
   a clean Arch Linux ARM system.
4. Exercise package promotion through `edge`, `rc`, and `stable` without
   copying artifacts between architectures.
5. Measure large Electron, Rust, kernel-module, and emulator builds before
   choosing service timeouts.

## Proposal 2: architecture-isolated automatic build queues

Extend the existing version checker and timers in a separate pull request.
The implementation should retain the current x86_64 state filenames for
backward compatibility and use architecture-qualified files for additional
targets, for example:

```text
.sync-needed-edge
.build-failed-edge
.sync-needed-edge-aarch64
.build-failed-edge-aarch64
```

Package metadata must be evaluated with the target `CARCH`; unsupported
packages must be skipped explicitly rather than entering a queue that can
never succeed. A failure or backoff for one architecture must not suppress
work for the other.

Suggested acceptance criteria:

- x86_64 behavior and state filenames remain unchanged by default;
- configured architectures receive separate queues and backoff records;
- malformed or unreadable package architecture metadata fails closed;
- the timer display identifies the architecture of every queued package;
- retrying one architecture does not rebuild or clear another's queue.

## Proposal 3: multi-architecture release-train coordination

The current `omarchy-release` flow should remain authoritative. A later change
can make architecture a configured dimension of that same release train rather
than adding a second backend.

Before advancing a shared Omarchy version, the coordinator should prove that
every configured architecture has published the same version in the source
channel. It must not declare an RC or stable release complete while an
architecture is absent, lagging, or divergent.

Repository mutations are serialized today, but a release spanning two remote
directories is not an atomic transaction. Commands therefore need to be
idempotent: after one architecture succeeds and the other fails, an operator
must be able to fix the failure and rerun the same command safely.

Suggested acceptance criteria:

- the default configuration continues to release x86_64 only;
- promotion is always scoped to one channel and architecture at a time;
- a publication barrier checks every configured architecture;
- an absent, lagging, or divergent repository blocks shared release progress;
- partial success is reported clearly and is safe to retry.

## Proposal 4: per-architecture rebuild triggers

`bin/sync-rebuilds` currently records one `rebuilt_against` value based on the
x86_64 pacman database. Arch Linux ARM may publish dependency versions at a
different time, so that record cannot safely describe both outputs.

A later pull request should introduce a backward-compatible per-architecture
record, treating the current field as the legacy x86_64 value. Each check must
run against the native architecture's synchronized package databases. A
pkgrel bump should also be ordered above the highest version already published
for any supported architecture; if a configured repository database cannot be
read, the check should fail closed rather than certifying an unknown floor.

## Proposal 5: repository bootstrap and trust rollout

The first AArch64 repository cannot be used to bootstrap itself. Initially,
build the dependency closure without installing an Omarchy ARM repository in
the base image. After the AArch64 channel databases and `omarchy-keyring`
package exist, a separate change can enable the normal repository during ARM
builder creation.

The bootstrap policy must also define how `arch=('any')` artifacts are
produced. That declaration describes the installed files, not whether the
build is host-independent or reproducible. For example, `omarchy-nvim` runs
native Neovim and resolves a large plugin cache during `build()`. A clean ARM
bootstrap therefore exercises work that an incremental repository can hide.
Upstream should either rebuild such packages on each native builder or define
an integrity-checked, architecture-neutral promotion path; it should not
silently mix the two models. Any reuse path should retain verifiable provenance
and be exercised independently of an already-populated target repository.

The trust model should match the existing upstream repository:

- use the existing production signing key and `omarchy-keyring` package;
- sign package archives;
- do not introduce a separate AArch64 key or downstream keyring;
- keep repository database signing behavior consistent with the current
  upstream deployment.

## Production work outside the source repository

An upstream operator must complete these steps because they require production
credentials, storage permissions, or native hardware:

1. Permit the repository host's rclone credentials to create and serve
   `edge/aarch64`, `rc/aarch64`, and `stable/aarch64`.
2. Perform the first signed publication and verify the existing keyring from a
   clean Arch Linux ARM installation.
3. Test build, sign, promote, clean, update, remove, and sync operations against
   a staging remote.
4. Provision the native ARM runner and decide how it is scheduled alongside the
   current x86_64 builder.
5. Monitor the first dual-architecture release and record recovery procedures
   for partial publication.

## Suggested rollout order

1. Merge and review package compatibility independently of release automation.
2. Provision the native ARM staging builder and publish an unpublished
   `edge/aarch64` dependency closure.
3. Validate clean installation and upgrades, then exercise one complete
   staging promotion cycle.
4. Submit the queue and rebuild-trigger proposals as focused pull requests.
5. Submit release-train coordination only after staging has demonstrated the
   required failure and retry semantics.
6. Enable production AArch64 scheduling after all acceptance criteria above are
   met.
