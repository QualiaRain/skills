#!/usr/bin/env python3
"""Measure real mouse DPI by counting raw-input counts over a known distance.

Works on ANY mouse, including non-Logitech hardware with no readable protocol -
it measures the sensor instead of asking software what it believes. That makes it
the fallback when the HID++ read is unavailable, and the tie-breaker when HID++
and the vendor software disagree.

CONSENT-GATED, and the strongest gate in this skill. It registers a raw-input
sink that receives EVERY mouse movement system-wide for the whole capture window,
including movement in whatever the owner is doing at the time. So:
  * it refuses to run without --yes;
  * --yes means the owner said yes in the CURRENT conversation, every time, not
    that they agreed to it once last week;
  * never start it while a game, or anything else that matters, is in the
    foreground.
It reads only mouse deltas - no keystrokes, no window titles, nothing is written
to disk, and the counts are discarded when the process exits.

How it works: Windows Raw Input reports the sensor's own counts, untouched by
pointer speed or Enhance Pointer Precision, so counts / inches travelled IS the
DPI. RIDEV_INPUTSINK means the counts keep arriving without focus.

Procedure to hand to the owner
------------------------------
  1. Put a ruler, or a mouse pad of known width, flat on the desk.
  2. Mark a start and an end point at least 20 cm apart - longer is more
     accurate, since a 2 mm placement error over 10 cm is 2% and over 30 cm is
     0.7%.
  3. Lift the mouse onto the start mark, start this, then slide it in ONE
     straight stroke to the end mark without lifting, and stop.
  4. Repeat 3 times and compare. A real 1600 DPI mouse lands within a few percent
     each time. Wide scatter means the stroke wandered or the mouse lifted, not
     that the mouse is broken.

Usage
-----
  python rawinput_dpi_test.py --distance-cm 20 --seconds 8 --yes
  python rawinput_dpi_test.py --distance-in 8 --seconds 8 --countdown 5 --yes

Exit codes: 0 measured, 1 nothing moved during the window, 2 refused (no --yes).

Smoke test: none that is safe. Running it at all opens the capture window, so it
is deliberately excluded from scripts/smoke.ps1. `--help` is the safe check.
"""

from __future__ import annotations

import argparse
import ctypes
import sys
import time
from ctypes import wintypes

if sys.platform != "win32":
    raise SystemExit("error: Windows only")

user32 = ctypes.WinDLL("user32", use_last_error=True)

WM_INPUT = 0x00FF
WM_QUIT = 0x0012
RIDEV_INPUTSINK = 0x00000100
RID_INPUT = 0x10000003
RIM_TYPEMOUSE = 0
MOUSE_MOVE_ABSOLUTE = 0x01
HWND_MESSAGE = wintypes.HWND(-3)
PM_REMOVE = 0x0001

LRESULT = ctypes.c_ssize_t
WNDPROC = ctypes.WINFUNCTYPE(LRESULT, wintypes.HWND, wintypes.UINT,
                             wintypes.WPARAM, wintypes.LPARAM)


class WNDCLASSW(ctypes.Structure):
    _fields_ = [("style", wintypes.UINT), ("lpfnWndProc", WNDPROC),
                ("cbClsExtra", ctypes.c_int), ("cbWndExtra", ctypes.c_int),
                ("hInstance", wintypes.HINSTANCE), ("hIcon", wintypes.HICON),
                ("hCursor", wintypes.HANDLE), ("hbrBackground", wintypes.HBRUSH),
                ("lpszMenuName", wintypes.LPCWSTR), ("lpszClassName", wintypes.LPCWSTR)]


class RAWINPUTDEVICE(ctypes.Structure):
    _fields_ = [("usUsagePage", wintypes.USHORT), ("usUsage", wintypes.USHORT),
                ("dwFlags", wintypes.DWORD), ("hwndTarget", wintypes.HWND)]


class RAWINPUTHEADER(ctypes.Structure):
    _fields_ = [("dwType", wintypes.DWORD), ("dwSize", wintypes.DWORD),
                ("hDevice", wintypes.HANDLE), ("wParam", wintypes.WPARAM)]


class _BUTTONS(ctypes.Structure):
    _fields_ = [("usButtonFlags", wintypes.USHORT), ("usButtonData", wintypes.USHORT)]


class _BUTTONUNION(ctypes.Union):
    _fields_ = [("ulButtons", wintypes.ULONG), ("b", _BUTTONS)]


class RAWMOUSE(ctypes.Structure):
    _anonymous_ = ("u",)
    _fields_ = [("usFlags", wintypes.USHORT), ("u", _BUTTONUNION),
                ("ulRawButtons", wintypes.ULONG), ("lLastX", wintypes.LONG),
                ("lLastY", wintypes.LONG), ("ulExtraInformation", wintypes.ULONG)]


class RAWINPUT(ctypes.Structure):
    _fields_ = [("header", RAWINPUTHEADER), ("mouse", RAWMOUSE)]


# --------------------------------------------------------------------------
# Win32 prototypes. ctypes defaults an undeclared function to restype c_int with
# no argtypes, and both halves of that default are wrong here:
#   * a 64-bit HMODULE / HWND returned as c_int is TRUNCATED to 32 bits, so the
#     handle can be silently wrong on x64;
#   * GetRawInputData returns (UINT)-1 on failure, which as a c_int is -1, so
#     the `n != 0xFFFFFFFF` check below could never fire and a failed read would
#     be parsed as if it were data.
# Everything this script calls is therefore declared. (It uses PeekMessageW, not
# GetMessageW - a blocking GetMessageW would sit past the capture window.)
# --------------------------------------------------------------------------
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

kernel32.GetModuleHandleW.argtypes = [wintypes.LPCWSTR]
kernel32.GetModuleHandleW.restype = wintypes.HMODULE

user32.DefWindowProcW.argtypes = [wintypes.HWND, wintypes.UINT,
                                  wintypes.WPARAM, wintypes.LPARAM]
user32.DefWindowProcW.restype = LRESULT

user32.RegisterClassW.argtypes = [ctypes.POINTER(WNDCLASSW)]
user32.RegisterClassW.restype = wintypes.ATOM

user32.CreateWindowExW.argtypes = [
    wintypes.DWORD, wintypes.LPCWSTR, wintypes.LPCWSTR, wintypes.DWORD,
    ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int,
    wintypes.HWND, wintypes.HMENU, wintypes.HINSTANCE, wintypes.LPVOID,
]
user32.CreateWindowExW.restype = wintypes.HWND

user32.RegisterRawInputDevices.argtypes = [ctypes.POINTER(RAWINPUTDEVICE),
                                           wintypes.UINT, wintypes.UINT]
user32.RegisterRawInputDevices.restype = wintypes.BOOL

user32.GetRawInputData.argtypes = [wintypes.HANDLE, wintypes.UINT,
                                   wintypes.LPVOID,
                                   ctypes.POINTER(wintypes.UINT), wintypes.UINT]
user32.GetRawInputData.restype = wintypes.UINT  # (UINT)-1 == 0xFFFFFFFF on error

user32.PeekMessageW.argtypes = [wintypes.LPMSG, wintypes.HWND,
                                wintypes.UINT, wintypes.UINT, wintypes.UINT]
user32.PeekMessageW.restype = wintypes.BOOL

user32.TranslateMessage.argtypes = [wintypes.LPMSG]
user32.TranslateMessage.restype = wintypes.BOOL

user32.DispatchMessageW.argtypes = [wintypes.LPMSG]
user32.DispatchMessageW.restype = LRESULT


def make_window() -> wintypes.HWND:
    hinst = kernel32.GetModuleHandleW(None)
    wc = WNDCLASSW()
    wc.lpfnWndProc = ctypes.cast(user32.DefWindowProcW, WNDPROC)
    wc.hInstance = hinst
    wc.lpszClassName = "RawInputDpiProbe"
    if not user32.RegisterClassW(ctypes.byref(wc)):
        err = ctypes.get_last_error()
        if err != 1410:  # ERROR_CLASS_ALREADY_EXISTS
            raise ctypes.WinError(err)
    hwnd = user32.CreateWindowExW(0, "RawInputDpiProbe", "RawInputDpiProbe",
                                  0, 0, 0, 0, 0, HWND_MESSAGE, None, hinst, None)
    if not hwnd:
        raise ctypes.WinError(ctypes.get_last_error())
    # Keep the class object alive; ctypes would otherwise free the WNDPROC.
    make_window._keep = wc  # type: ignore[attr-defined]
    return wintypes.HWND(hwnd)


def register_raw_mouse(hwnd) -> None:
    rid = RAWINPUTDEVICE(0x01, 0x02, RIDEV_INPUTSINK, hwnd)
    if not user32.RegisterRawInputDevices(ctypes.byref(rid), 1,
                                          ctypes.sizeof(RAWINPUTDEVICE)):
        raise ctypes.WinError(ctypes.get_last_error())


def collect(hwnd, seconds: float) -> dict:
    msg = wintypes.MSG()
    buf = ctypes.create_string_buffer(ctypes.sizeof(RAWINPUT) + 64)
    size = wintypes.UINT(ctypes.sizeof(buf))
    hdr_size = ctypes.sizeof(RAWINPUTHEADER)

    per_device: dict[int, dict] = {}
    absolute_seen = False
    end = time.monotonic() + seconds

    while time.monotonic() < end:
        got = user32.PeekMessageW(ctypes.byref(msg), None, 0, 0, PM_REMOVE)
        if not got:
            time.sleep(0.001)
            continue
        if msg.message == WM_QUIT:
            break
        if msg.message == WM_INPUT:
            size.value = ctypes.sizeof(buf)
            n = user32.GetRawInputData(wintypes.HANDLE(msg.lParam), RID_INPUT,
                                       buf, ctypes.byref(size), hdr_size)
            if n != 0xFFFFFFFF and n > 0:
                ri = ctypes.cast(buf, ctypes.POINTER(RAWINPUT)).contents
                if ri.header.dwType == RIM_TYPEMOUSE:
                    dev = int(ri.header.hDevice or 0)
                    d = per_device.setdefault(
                        dev, {"x": 0, "y": 0, "abs_x": 0, "packets": 0})
                    d["packets"] += 1
                    if ri.mouse.usFlags & MOUSE_MOVE_ABSOLUTE:
                        absolute_seen = True
                        d["abs_x"] = ri.mouse.lLastX
                    else:
                        d["x"] += ri.mouse.lLastX
                        d["y"] += ri.mouse.lLastY
        user32.TranslateMessage(ctypes.byref(msg))
        user32.DispatchMessageW(ctypes.byref(msg))

    return {"per_device": per_device, "absolute_seen": absolute_seen}


def main(argv=None) -> int:
    p = argparse.ArgumentParser(
        prog="rawinput_dpi_test.py",
        description=__doc__.splitlines()[0],
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__[__doc__.index("CONSENT-GATED"):],
    )
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("--distance-cm", type=float, help="distance you will slide, cm")
    g.add_argument("--distance-in", type=float, help="distance you will slide, inches")
    p.add_argument("--seconds", type=float, default=8.0, help="capture window")
    p.add_argument("--countdown", type=float, default=3.0, help="pause before capture")
    p.add_argument("--yes", action="store_true",
                   help="required: the owner approved THIS run (it captures all "
                        "mouse movement system-wide)")
    a = p.parse_args(argv)

    if not a.yes:
        print("  This captures EVERY mouse movement system-wide for the capture")
        print("  window. Re-run with --yes only after the owner has explicitly")
        print("  approved it in the current conversation, and only when nothing")
        print("  that matters is in the foreground.")
        print("VERDICT: refusing to run without --yes")
        return 2

    inches = a.distance_in if a.distance_in else a.distance_cm / 2.54
    hwnd = make_window()
    register_raw_mouse(hwnd)

    for i in range(int(a.countdown), 0, -1):
        print(f"starting in {i}...", flush=True)
        time.sleep(1)
    print(f"GO - slide {inches * 2.54:.1f} cm ({inches:.2f} in) in one straight "
          f"stroke. Capturing {a.seconds:.0f}s.", flush=True)

    res = collect(hwnd, a.seconds)
    devices = res["per_device"]
    if not devices:
        print("VERDICT: FAIL - no mouse packets captured. Nothing moved during the "
              "window, or the raw-input sink never armed.")
        return 1

    print()
    total = 0
    for dev, d in sorted(devices.items(), key=lambda kv: -abs(kv[1]["x"])):
        print(f"device 0x{dev:x}: dx={d['x']:+d} counts  dy={d['y']:+d} counts  "
              f"packets={d['packets']}")
        total = max(total, abs(d["x"]))
    if len(devices) > 1:
        print("more than one pointing device reported - the biggest dx is used below; "
              "confirm that is the mouse you measured.")
    if res["absolute_seen"]:
        print("WARNING: absolute-coordinate packets seen (tablet, RDP, or a VM). "
              "Counts from those are not comparable and were excluded.")

    dpi = total / inches if inches else 0
    print()
    print(f"counts       {total} horizontal counts over {inches:.3f} in "
          f"({inches * 2.54:.2f} cm)")
    print(f"implied DPI  {dpi:.0f}")
    common = [400, 800, 1000, 1200, 1600, 1800, 2000, 2400, 3200]
    near = min(common, key=lambda c: abs(c - dpi)) if dpi else None
    if near:
        err = abs(near - dpi) / near * 100
        agrees = "consistent with" if err < 5 else "NOT close to"
        print(f"VERDICT: about {dpi:.0f} DPI - {agrees} the stock step {near} "
              f"({err:.1f}% away). One run is not a measurement: repeat the "
              "stroke twice more and compare before quoting it.")
    else:
        print("VERDICT: FAIL - no horizontal movement to divide by.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
