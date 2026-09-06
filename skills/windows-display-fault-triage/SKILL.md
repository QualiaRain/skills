---
name: windows-display-fault-triage
description: >-
  Find WHY a Windows display looks wrong by MEASURING the colour stack instead of guessing. Triggers: colours look off, washed out, too dark, a green or purple tint, fringing on text, blurry or pixelated text, scaling looks weird, HDR looks wrong, my monitor might be dying, something looks off on my screen. Not for FPS (game-perf-tuning-windows) or mouse feel (mouse-dpi).
---

# Windows display fault triage

A "the screen looks wrong" report can come from five layers. They are cheap to separate, and the
order below is deliberate: each step is one script, runs in seconds, needs no browser and no
screenshot, and each result rules a layer IN or OUT so the next step is smaller.

```
0 NVIDIA CAM  Color accuracy mode: Enhanced applies the Windows ICC profile to the WHOLE desktop
1 wire        what signal the GPU is actually sending (encoding, bpc, HDR)
2 LUT/ICC     is anything bending the desktop gamma right now (Windows side only, see step 0)
3 driver      NVIDIA dynamic range, colour format, vibrance
4 OS render   ClearType, subpixel order, colour filters, night light, magnifier
5 link        does a lower refresh rate make it go away
6 panel       only after 0-5 are clean
```

Run everything from `scripts/`. Steps 1-4 are read-only and unelevated. Writes, all reversible:
`set_hz.ps1` (step 5) changes the live display mode until the next sign-in; `nvapi_color.ps1
-FixRange` is the only persistent write; `display_history.ps1` writes `dxdiag.txt` into the
`-OutDir` you give it. `nvapi_color.ps1` needs PowerShell 7 (`pwsh`), not 5.1.

## Procedure

0. **NVIDIA Color accuracy mode, first, 5 seconds, no script exists for it.** NVIDIA App > System >
   Display (or NVIDIA Control Panel > Display) > "Color accuracy mode". If it reads **Enhanced**,
   have the owner tick **"Override to reference mode"** and look. Observed fact (2026-09-05, n=1): with a
   chat-assigned ICC profile associated and Enhanced on, the desktop colours were wrong and
   reference mode fixed them instantly. Working explanation, not verified from any probe: Enhanced
   has the driver apply the display's associated Windows ICC profile (matrix/TRC) to the whole
   desktop, so no vcgt tag is needed and step 2's gamma-ramp check cannot see it. Either way, if
   reference mode fixes the colours, the associated ICC profile is the cause. Fix: keep reference mode, or remove the per-user profile
   assignments so Windows falls back to the monitor's own INF profile:
   `HKCU:\Software\Microsoft\Windows NT\CurrentVersion\ICM\ProfileAssociations\Display\{4d36e96e-e325-11ce-bfc1-08002be10318}\000N`
   (back up first; `reg export` fails silently on paths over 260 chars, so export to a short path
   or dump the keys to JSON with PowerShell). Real case 2026-09-05: a downloaded RTINGS profile a
   chat had assigned to every slot on 2026-08-29 was the whole fault, and every probe below was
   clean.

1. **Wire format, HDR, DPI** - `pwsh -File scripts/display_color.ps1`
   Gives per active path: monitor, output tech, refresh, colour encoding, bits per channel, HDR
   on/off, SDR white level, DPI current vs Windows-recommended.
   `YCbCr 4:2:0` or `4:2:2`, or 8 bpc where 10 is expected at 4K high refresh, means the link ran
   out of bandwidth and Windows silently fell back. That is a cable / DSC / DP-or-HDMI-version
   problem, and it looks exactly like "fringing" on red or blue text. Check the monitor OSD for its
   DisplayPort version or DSC setting before touching anything else.
   DPI current far from recommended explains "scaling looks weird" on its own.

2. **Is anything actually bending the colours** - `pwsh -File scripts/gamma_icc_probe.ps1`
   Reports the live GPU gamma ramp against identity, the Windows calibration toggle, and every
   candidate ICC profile parsed for its `vcgt` tag.
   Max deviation `0` means nothing is loading a calibration curve, full stop. Non-zero means the
   Calibration Loader or a colour tool is live and is a real suspect.
   An ICC profile with **no vcgt tag cannot touch the desktop through Windows** - the loader has
   nothing to load, and only colour-managed apps read the matrix. It CAN still touch the desktop
   through NVIDIA's Enhanced color accuracy mode (step 0). Measure the LUT, but do not call a
   profile "ruled out" until step 0 is answered: on 2026-09-05 a transcript audit named an ICC
   rewrite as the cause, this script showed ramp identity and vcgt absent, the profile was declared
   harmless, and it was in fact the cause via NVIDIA Enhanced mode. A "ruled out" needs every
   consumer of the artifact listed, not one.

3. **NVIDIA driver output state** - `pwsh -File scripts/nvapi_color.ps1`
   Look for `dynamicRange = LIMITED` (crushed blacks, grey-looking whites - the classic "washed
   out"), a non-RGB `format`, or a digital vibrance `currentLevel` above 0 (oversaturation).
   `-FixRange` sets Full if it is Limited; that is the only persistent write in this skill, so say
   what it will do before running it.
   Struct-version probing is deliberate - driver 616.56 rejects v3 and accepts v2/size 12. The
   script tries 12/2, 12/3, 16/4, 16/5 in order; do not hard-code one.

4. **OS-level rendering and colour tampering** - `pwsh -File scripts/display_text_color.ps1`
   ClearType on/off and subpixel orientation (RGB vs BGR - wrong here IS colour fringing on text),
   the per-display ClearType tuner, colour filters, high contrast, a Magnifier left running (looks
   exactly like "pixelation"), night light, NVIDIA per-display registry values, NVCP profile
   database write times, monitor vendor tooling, and any running gamma-bending process.

5. **Refresh-rate A/B** - `pwsh -File scripts/set_hz.ps1 -Hz 120`, look, then `-Hz 240`
   Not saved to the registry, reverts at next sign-in. If the fault disappears at the lower rate the
   link is at fault (cable, DSC, negotiated version). If it is identical at both, the link is
   cleared and so is most of the PC.

6. **Only now, the monitor.** Nothing above has found it, so ask the owner for the panel side, cheapest
   first: OSD preset and any sharpness / overdrive / aspect setting, power cycle at the wall,
   factory reset in the OSD, then the same picture from another source (console, laptop, phone).
   A fault that survives a factory reset and follows the panel to another source is the monitor.

Optional, when dates matter: `pwsh -File scripts/display_history.ps1 -OutDir <scratch>` adds ICC
associations, the Calibration Loader task state, per-monitor DPI overrides, GPU driver events,
recent driver installs and the dxdiag Display Devices block. Slower (dxdiag up to 90 s), so use
`-SkipDxdiag` unless you need it.

## Decision table

| Result | Rules IN | Rules OUT |
|---|---|---|
| encoding YCbCr 420/422, or 8 bpc at 4K high Hz | link bandwidth fallback: cable, DSC, DP/HDMI version | PC colour stack |
| encoding RGB 4:4:4, bpc as expected, HDR as expected | - | wire format, HDR mismatch |
| DPI current != recommended | scaling complaint explained | colour complaint |
| gamma max deviation > 0 | Calibration Loader or a colour tool is live | - |
| gamma deviation 0 | - | the Windows Calibration Loader and colour tools; NOT NVIDIA Enhanced mode |
| ICC bound but vcgt absent | desktop-wide transform if NVIDIA Color accuracy mode is Enhanced; else colour-managed apps only | the Windows loader |
| reference mode changes the picture | the associated ICC profile | everything below |
| dynamicRange LIMITED | washed out / crushed blacks explained | - |
| vibrance currentLevel > 0 | oversaturation explained | - |
| ClearType off, or orientation wrong for the panel | text fringing / blur explained | - |
| Magnifier RunningState on, colour filter Active | "pixelation" / wrong colours explained | - |
| same fault at 120 Hz and 240 Hz | monitor or panel | cable, DSC, link negotiation |
| all of the above clean | the monitor | the whole PC side |

The real case this came from (2026-09-05) walked steps 1-6 in this order: wire RGB 4:4:4 10 bpc
HDR off, gamma ramp identity, suspect ICC without vcgt, NVAPI Full range RGB vibrance 0, ClearType
and filters normal, 120 Hz identical to 240 Hz, monitor power-cycled and factory reset. The verdict
"it is the monitor" was wrong. the owner then opened NVIDIA App, saw Color accuracy mode = Enhanced, ticked
reference mode, and the colours were fixed. That is why step 0 exists and runs first. Also: an ASUS
OLED goes dark for several minutes (status light off) after a factory reset while it runs a pixel
refresh; that is normal, not a fault.

## Two things that waste the owner's time

A full-window screenshot cannot show subpixel colour fringing - the resampling destroys the very
thing being judged. If ClearType or fringing is suspected, ask him for a 100% crop of a small patch
of text, not a screenshot of the desktop.

Do not narrate the layers to him. Run the probes, then tell him what is true now, what you ruled
out, and the one thing he does next.
