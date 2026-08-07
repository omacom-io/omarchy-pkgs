# HP EliteBook X G2i webcam

OmniVision **OV05C10** sensor on an Intel **IPU7** ISP. This package makes the
camera work in Chrome, Firefox, OBS and the Omarchy screen recorder.

**It is a bypass of Intel's CamHAL, not a fix.** Read "Trade-offs" before
assuming it behaves like a normal webcam stack.

## Why CamHAL cannot be used

Diagnosed with `cameraDebug=0xFF` on `v4l2-relayd`:

```
GraphConfig: <out w="2944" h="1632">
PlatformData: Isp raw crop [0, 88, -56, 88], wxh [2944 x 1632]
                                   ^^^ negative: 2888 - 2944 = -56
```

The graph settings binary (`OV05C10_CJFPE50.IPU75XA.bin`) is built for a
**2944-wide** sensor readout. The `ov05c10` driver exposes **2888x1808**, and so
does Intel's own `sensors/ov05c10-uf.json`. CamHAL therefore hands the ISP a crop
wider than the frame it receives.

psys is **not** broken — it processes frames happily (`frame id N is done`); they
are simply produced from an impossible region, so the output is uniformly black.
That is also why the failure presents two ways: some runs log `Sof poll time out`
and hang, others return black frames.

Correct graph settings require Intel's internal tooling, so this is not fixable
downstream. HP's Windows `graph_settings_ov05c10_CJFPE50_PTL.bin` loads (header
compatible) but contains no matching settings and is not interchangeable. Filed
upstream against `intel/ipu7-camera-hal`.

## What this package does instead

```
ov05c10 -> CSI2 -> ISYS (raw Bayer) -> debayer + AE + WB -> v4l2loopback
```

The kernel path underneath is healthy — raw capture from `/dev/video0` yields
real images on demand. Only psys/CamHAL is skipped.

## Trade-offs

- **No HP ISP tuning.** Colour, denoise and sharpening come from a plain
  debayer, not Intel's AIQ with HP's `.aiqb`. Noticeably softer and noisier,
  most visible in low light.
- **Simple 3A.** Auto-exposure is a proportional loop over exposure, then
  analogue gain, then digital gain. White balance is static gray-world gains
  (`WB_R`/`WB_B`) because this sensor exposes no
  `V4L2_CID_RED_BALANCE`/`BLUE_BALANCE`.
- **Continuous CPU cost.** One ffmpeg runs whenever the service is up.
- **The service must stay enabled.** See below.

## Two coupled requirements

**1. `exclusive_caps=1` + a permanent writer.** Chrome only enumerates V4L2
devices advertising CAPTURE without OUTPUT. With `exclusive_caps=0` the loopback
reports `Capture+Output` and Chrome omits the camera entirely — while Firefox and
OBS work fine, which makes this confusing to diagnose. `exclusive_caps=1` reports
capture-only *while a writer is attached*, so the service holds `/dev/video50`
open permanently. Disabling the service without reverting
`/usr/lib/modprobe.d/99-hp-elitebook-x-g2i-v4l2loopback.conf` leaves every reader
failing with `VIDIOC_STREAMON: Input/output error`.

**2. Frame-aligned source switching.** The privacy LED follows the *sensor*, so
the sensor is powered down when nothing is using the camera. To keep a writer
attached anyway, one persistent ffmpeg reads NV12 from a FIFO whose *source*
switches between black frames and the sensor. Because that FIFO carries raw
frames with no boundary markers, a feeder killed mid-frame desyncs the stream
permanently — every later frame splits across two, showing as a torn image with
green/magenta bands (Y and UV misaligned). Both switch directions therefore stop
on a frame boundary: the idle feeder exits on a flag checked between whole
frames, and the sensor feeder gets SIGTERM plus a bounded wait.

## Behaviour

- Privacy LED lights only while an application is using the camera.
- Device appears as **Hardware ISP Camera**, `/dev/video50`, NV12 1920x1080@30.
- An app opening the camera sees black for 1–2s while the sensor spins up.

## Kernel modules

Ships an `ov05c10` sensor driver (none exists in mainline or in Omarchy's
`intel-ipu7-camera` DKMS) plus an `ipu-bridge` patch widening the `OVTI05C1`
entry from one link frequency (480MHz) to two (480MHz + 900MHz). Without the
latter, probing fails with `no link frequency 900000000 supported`.

**Never `rmmod`/`insmod` the `intel_ipu7*` stack on a running system** —
unloading `intel_ipu7_psys` while active hard-hangs the machine with no panic
logged. File-based install plus reboot only.

## Tuning

Environment variables in the unit: `AE_TARGET` (default 105), `WB_R` (1.50),
`WB_B` (1.25), `IDLE_STOP` (5s), `OUT_W`/`OUT_H` (1920x1080).
