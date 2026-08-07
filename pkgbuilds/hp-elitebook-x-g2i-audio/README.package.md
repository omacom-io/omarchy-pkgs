# HP EliteBook X G2i audio

Speakers and microphone for the HP EliteBook X G2i (Panther Lake): RT712 SDCA
codec plus four TAS2783 smart amps over SoundWire.

**Without this package the machine has no Speaker device at all** — not quiet,
absent. `pactl list cards` shows the card stuck on profile `off` with no usable
sink.

## What it installs, and why each piece is needed

### 1. ACPI match-table entry (DKMS)

Panther Lake's match table in `sound/soc/intel/common/soc-acpi-intel-ptl-match.c`
has no entry for this board's RT712 + quad-TAS2783 pairing, so the SOF stack
falls back to a barebones machine driver and never instantiates the amps.

Shipped as **DKMS, not a copied `.ko`**: replacing the stock module in place
silently stops applying at the next kernel upgrade, and the failure mode is a
full regression to no speakers with no warning.

### 2. Firmware filename links

`tas2783-sdw.c` requests `8E86-2-{9,A,C,D}.bin`. `linux-firmware` ships the same
per-amp calibration blobs as `8E86-2-0x{9,A,C,D}.bin.zst`. A naming bug, not
missing firmware — so the package symlinks rather than copies, leaving
`linux-firmware` owning the real files. `post_remove` removes only symlinks it
created, never a real file.

### 3. UCM profile

Makes the HiFi profile expose real `Speaker` and `Mic` devices instead of
pro-audio passthrough.

### 4. Boot-race guard

WirePlumber can start before the TAS2783 amp's kcontrols exist, landing the card
on profile `off` with zero sinks and sources — "no audio, no mic" on a random
subset of boots. `wait-tas2783-controls` waits (bounded, 12s) for the kcontrol
before WirePlumber starts. It returns instantly once present and never blocks
login.

## Upstream status

Two of these belong elsewhere and are being filed there. This package is the
interim, in the same spirit as `dell-xps-touchpad-haptics`:

| Piece | Real home |
|---|---|
| Match-table entry | Linux, `soc-acpi-intel-ptl-match.c` |
| Firmware naming | `linux-firmware` / `tas2783-sdw.c` |
| UCM profile | `alsa-ucm-conf` |

## Scope

This package carries **enablement only** — it makes the hardware work, and
contains no vendor-derived tuning data. The perceptual voicing (HP's factory
DTS:X Ultra curve) ships separately as an Omarchy audio tuning, matched on the
DMI SKU, and is an independent decision.

## Verifying

```bash
pactl list cards | grep 'Active Profile'   # expect HiFi
wpctl status                               # expect a Speaker sink and a Mic source
```

A reboot is required after install: the match-table module cannot be swapped
under a live SOF/SoundWire stack.
