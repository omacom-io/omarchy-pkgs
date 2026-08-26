# linux-aarch64-pkgbase-shim

Arch Linux ARM's kernel packages install the kernel as `/boot/Image` and ship
no `usr/lib/modules/<ver>/pkgbase` or `usr/lib/modules/<ver>/vmlinuz`.
mkinitcpio's and limine-entry-tool's pacman hooks find kernels through those
two files, so on an Arch Linux ARM system nothing builds an initramfs or UKI,
and nothing writes a Limine entry, when a kernel is installed or upgraded.

This package is one pacman hook. After a kernel package is installed or
upgraded (`usr/lib/modules/*/`), and when the shim itself is installed, it
writes into every package-owned modules directory that lacks `pkgbase`:

- `pkgbase`: the name of the package that owns the directory
- `vmlinuz`: a copy of `/boot/Image` (the owner must own that too)

It runs as `85-`, before `90-mkinitcpio-install`, so the usual hook then builds
the initramfs/UKI and the Limine entry. If that hook would not run in the same
transaction (the shim installed after the kernel, or a kernel package that
does not touch `usr/lib/initcpio/`), the script runs
`limine-mkinitcpio-install` itself. Leftover directories of removed kernels
that hold nothing but these two files are cleaned up.

`limine-mkinitcpio-hook` needs its carried
`0002-accept-pkgbase-in-package-owned-kernel-dir.patch` to accept a `pkgbase`
that no package owns.

## Retirement

Delete this package, and the limine-mkinitcpio-hook patch above, when Arch
Linux ARM's `linux-aarch64` ships `pkgbase` and `vmlinuz` itself
(archlinuxarm/PKGBUILDs#2215 or its successor). A directory that already has
`pkgbase` is never touched, so the two can coexist during the transition.
