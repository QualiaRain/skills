#!/usr/bin/env python3
"""Read (and optionally set) the CURRENT DPI of a Logitech HID++ 2.0 mouse.

Talks straight to the mouse over the LIGHTSPEED receiver's vendor-defined HID
interface. Does NOT need G HUB, LGS, or any Logitech background agent running --
which is the whole point: G HUB's settings DB is only "software intent", while
the mouse itself reports what it is actually running right now.

Run it with an ephemeral env so nothing is installed into an existing venv:

    uv run --with hidapi python logi_dpi.py
    uv run --with hidapi python logi_dpi.py --verbose
    uv run --with hidapi python logi_dpi.py --set 1600 --yes    # NOT read-only

If the `hidapi` wheel will not build/install, `--with hid` is the fallback, but
that package is only ctypes bindings: it needs a hidapi.dll on PATH (or next to
the script). Both module layouts are supported by the shim below.

LOGITECH ONLY. HID++ is Logitech's vendor protocol; a Razer/SteelSeries/Corsair
mouse has no equivalent open protocol here. On non-Logitech hardware this script
exits non-zero and says what to do instead - the rest of the skill (the pointer
check, the game ledger, the calculator, the spin test and the raw-input DPI
test) is vendor neutral and still works.

Tested against a LIGHTSPEED receiver only. Nothing in here is LIGHTSPEED
specific - it enumerates any Logitech interface on usage page 0xFF00 or 0xFF43
(the two vendor pages Solaar and libratbag both enumerate for HID++) and speaks
plain HID++ 2.0 - so a Unifying receiver or a wired Logitech mouse should work
the same way, but that is UNTESTED. If it does work on other Logitech hardware,
record it in README.md's "Logitech-only vs works-on-anything" section rather
than assuming it next time.

--set is a WRITE to the mouse and is refused without --yes. It prints the DPI it
read BEFORE and the DPI it reads back AFTER, so the reported number is always
one that came off the device, never the one that was sent.

Usage
-----
  uv run --with hidapi python logi_dpi.py read        # the answer
  uv run --with hidapi python logi_dpi.py --verbose   # every probe attempt
  uv run --with hidapi python logi_dpi.py --set 1600 --yes   # WRITE

Exit codes: 0 read a DPI, 2 no HID++ device answered (or the DPI features did
not reply), 3 a --set was refused or out of range.

Smoke test (read-only):
  uv run --with hidapi python logi_dpi.py read

--------------------------------------------------------------------------
HID++ 2.0 wire format (documented here so the next reader can verify the bytes)
--------------------------------------------------------------------------
Everything is a HID *output* report on the vendor collection (usage page 0xFF00,
or 0xFF43 on the devices that use that page) and the reply comes back as an
*input* report on the same collection.

  report 0x10 "short" = 7 bytes total: [0x10, dev_idx, feat_idx, fn_sw, p0,p1,p2]
  report 0x11 "long"  = 20 bytes total: [0x11, dev_idx, feat_idx, fn_sw, p0..p15]

  dev_idx  0x01 = first device paired to the receiver, 0xFF = the receiver itself
  feat_idx index of the feature IN THIS DEVICE's feature table (NOT the 16-bit
           feature ID) -- you look it up first via the Root feature
  fn_sw    (function_id << 4) | software_id ; software_id must be non-zero,
           we use 0x1, and the device echoes it back so replies can be matched

  Root feature is ALWAYS at feature index 0x00.
    Root fn 0 = getFeature(featID_hi, featID_lo) -> [featIdx, featType, featVer]
                featIdx == 0 means "device does not support that feature"
    Root fn 1 = getProtocolVersion(0,0,ping) -> [verMaj, verMin, ping] (our ping)

  Error replies:
    HID++ 1.0 style: report 0x10, [0x10, dev, 0x8F, feat_idx, fn_sw, err, 0]
    HID++ 2.0 style: report 0x11, [0x11, dev, 0xFF, feat_idx, fn_sw, err, ...]

Features used:
  0x2201 ADJUSTABLE_DPI
    fn 2 getSensorDpi(sensorIdx)
         -> [sensorIdx, dpi_hi, dpi_lo, default_hi, default_lo]
    fn 3 setSensorDpi(sensorIdx, dpi_hi, dpi_lo)            <-- write
  0x2202 EXTENDED_ADJUSTABLE_DPI (newer sensors, per-axis, sub-1ms capable)
    Function numbering here is NOT the same as 0x2201 -- verified live
    2026-09-01, Logitech G PRO-series wireless mouse via LIGHTSPEED receiver,
    feature 0x2202 -- because the naive guess (fn 3 = getSensorDpiParameters)
    returns the DPI *list* instead and decodes into nonsense:
        req  10 01 09 31 00 00 00
        rply 11 01 09 31 00 00 03 20 04 B0 01 90 09 60 0C 80 00 00 00 00
             sensor=00 direction=00 then 16-bit DPI stages 800/1200/400/2400/3200
    fn 3 getSensorDpiList(sensorIdx, direction)
         -> [sensorIdx, direction, dpi0_hi, dpi0_lo, dpi1_hi, dpi1_lo, ...]
            the selectable DPI stages, zero-terminated
    fn 5 getSensorDpiParameters(sensorIdx)                  <-- CURRENT DPI
         -> [sensorIdx, dpiX_hi, dpiX_lo, defX_hi, defX_lo,
             dpiY_hi, dpiY_lo, defY_hi, defY_lo, lod, ...]
         Verified live 2026-09-01, Logitech G PRO-series wireless mouse via
         LIGHTSPEED receiver, feature 0x2202 -- the reply is four consecutive
         16-bit DPI values then the lift-off distance, e.g.
             rply 11 01 09 51 00 01 90 01 90 01 90 01 90 01 00 ...
                  sensor=00  dpiX=0190  defX=0190  dpiY=0190  defY=0190  lod=01
         i.e. 400 dpi on both axes. There is no "direction" request parameter:
         passing one changes nothing in the reply, both axes always come back.
    fn 6 setSensorDpiParameters(sensorIdx, dpiX_hi, dpiX_lo,
                                dpiY_hi, dpiY_lo, lod)      <-- write
    (read fn 5 / write fn 6 matches Solaar's read_fnid=0x50 / write_fnid=0x60.)
  0x8060 ADJUSTABLE_REPORT_RATE
    fn 1 getReportRate() -> [period_ms]      Hz = 1000 / period_ms
  0x8061 EXTENDED_ADJUSTABLE_REPORT_RATE
    fn 2 getReportRate(connectionType) -> [rateIdx]
         rateIdx 0..6 = 125/250/500/1000/2000/4000/8000 Hz
         connectionType 0 = wired, 1 = wireless (we try both, print raw)

Report-rate decoding is best-effort and is labelled "inferred" in the output;
DPI decoding is the load-bearing part and is verified against the default-DPI
fields that come back in the same packet.
"""

from __future__ import annotations

import argparse
import json
import sys
import time

LOGITECH_VID = 0x046D
# Vendor-defined usage pages that carry HID++. 0xFF00 is what the LIGHTSPEED /
# Unifying receivers expose; 0xFF43 is the second page Solaar and libratbag both
# enumerate for HID++, used by some newer and wired Logitech devices. Accepting
# both only WIDENS enumeration - a candidate is still only used if it answers a
# HID++ ping, so a non-HID++ interface on either page is discarded exactly as
# before.
HIDPP_USAGE_PAGES = (0xFF00, 0xFF43)

# Windows splits the receiver's vendor interface into TWO HID collections that
# get TWO separate device paths: usage 0x0001 carries the 7-byte short report
# 0x10, usage 0x0002 carries the 20-byte long report 0x11. A reply can come
# back on either one regardless of which one the request went out on, so a
# handle on only one collection silently misses half the traffic. (Measured:
# 2026-09-01, Logitech G PRO-series wireless mouse via LIGHTSPEED receiver, the
# same run that verified feature 0x2202 above -- pinging device index 1 on the
# short collection alone times out, while the receiver's own "unknown device"
# errors for indices 2-6 arrive fine.)
USAGE_SHORT = 0x0001
USAGE_LONG = 0x0002

# Logitech devices that are definitely not the mouse and must not be opened.
EXCLUDED_PIDS = {0x0893}  # StreamCam

REPORT_SHORT = 0x10
REPORT_LONG = 0x11
LEN_SHORT = 7
LEN_LONG = 20

SOFTWARE_ID = 0x01
ROOT_FEATURE_INDEX = 0x00
ROOT_FN_GET_FEATURE = 0
ROOT_FN_PING = 1

FEAT_ADJUSTABLE_DPI = 0x2201
FEAT_EXT_ADJUSTABLE_DPI = 0x2202
FEAT_REPORT_RATE = 0x8060
FEAT_EXT_REPORT_RATE = 0x8061

ERR_MARK_HIDPP10 = 0x8F
ERR_MARK_HIDPP20 = 0xFF

# 0xFF error frames use the HID++ 2.0 code space...
HIDPP20_ERRORS = {
    0x00: "no_error",
    0x01: "unknown",
    0x02: "invalid_argument",
    0x03: "out_of_range",
    0x04: "hardware_error",
    0x05: "logitech_internal",
    0x06: "invalid_feature_index",
    0x07: "invalid_function_id",
    0x08: "busy",
    0x09: "unsupported",
}
# ...but 0x8F frames are the older HID++ 1.0 error notification, and the
# receiver answers with THESE when you address an empty pairing slot.
HIDPP10_ERRORS = {
    0x01: "invalid_subid",
    0x02: "invalid_address",
    0x03: "invalid_value",
    0x04: "connect_fail",
    0x05: "too_many_devices",
    0x06: "already_exists",
    0x07: "busy",
    0x08: "unknown_device",  # i.e. nothing paired in that slot
    0x09: "resource_error",
    0x0A: "request_unavailable",
    0x0B: "invalid_param_value",
    0x0C: "wrong_pin_code",
}

# 0x8061 rate index -> Hz. Index n is 8000 >> (6 - n) in practice; spelled out
# so a wrong assumption is visible rather than hidden in arithmetic. The ladder
# direction (index 0 = SLOWEST) matches Solaar's public 0x8061 table, where
# index 0 is an 8 ms period = 125 Hz, rising to index 4 at 0.5 ms = 2000 Hz.
EXT_RATE_HZ = {0: 125, 1: 250, 2: 500, 3: 1000, 4: 2000, 5: 4000, 6: 8000}
RATE_LADDER_PROVENANCE = (
    "index 0 = slowest; corroborated by G HUB's settings.db (wireless 2000 Hz "
    "for this mouse) and Solaar's public 0x8061 table (index 0 = 8 ms = 125 Hz, "
    "index 4 = 0.5 ms = 2000 Hz). Not measured."
)


# --------------------------------------------------------------------------
# hidapi / hid compatibility shim
# --------------------------------------------------------------------------
class HidBackend:
    """Wraps either the `hidapi` (cython) or `hid` (ctypes) python package."""

    def __init__(self) -> None:
        try:
            import hid  # noqa: PLC0415
        except ImportError as exc:  # pragma: no cover - environment problem
            raise SystemExit(
                "no python hid module. run this via:\n"
                "  uv run --with hidapi python logi_dpi.py\n"
                "or, if that wheel fails, `--with hid` plus a hidapi.dll on PATH\n"
                "VERDICT: FAIL - no python hid module here; re-run through "
                "`uv run --with hidapi python logi_dpi.py`"
            ) from exc
        self.hid = hid
        # `hidapi` exposes hid.device(); `hid` exposes hid.Device().
        self.style = "cython" if hasattr(hid, "device") else "ctypes"

    def enumerate(self, vid: int = 0, pid: int = 0) -> list[dict]:
        return list(self.hid.enumerate(vid, pid))

    def open_path(self, path):
        if self.style == "cython":
            dev = self.hid.device()
            dev.open_path(path)
            return _CythonDev(dev)
        return _CtypesDev(self.hid.Device(path=path))


class _CythonDev:
    def __init__(self, dev):
        self._d = dev

    def write(self, data: bytes) -> int:
        return self._d.write(bytes(data))

    def read(self, size: int, timeout_ms: int) -> bytes:
        return bytes(self._d.read(size, timeout_ms))

    def close(self) -> None:
        self._d.close()


class _CtypesDev:
    def __init__(self, dev):
        self._d = dev

    def write(self, data: bytes) -> int:
        return self._d.write(bytes(data))

    def read(self, size: int, timeout_ms: int) -> bytes:
        return bytes(self._d.read(size, timeout_ms))

    def close(self) -> None:
        self._d.close()


# --------------------------------------------------------------------------
# HID++ transport
# --------------------------------------------------------------------------
class HidppError(Exception):
    def __init__(self, code: int, raw: bytes, legacy: bool = False):
        self.code = code
        self.raw = raw
        self.legacy = legacy
        table = HIDPP10_ERRORS if legacy else HIDPP20_ERRORS
        name = table.get(code, "unknown_code")
        era = "1.0" if legacy else "2.0"
        super().__init__(f"HID++ {era} error 0x{code:02X} ({name})")


class Transport:
    """One logical HID++ endpoint spanning both vendor collections."""

    def __init__(self, handles: list[tuple[int, object]]):
        # handles: list of (usage, opened device)
        self.handles = handles
        self.by_usage = {usage: dev for usage, dev in handles}

    def write(self, frame: bytes) -> None:
        want = USAGE_LONG if frame[0] == REPORT_LONG else USAGE_SHORT
        order = [self.by_usage[want]] if want in self.by_usage else []
        order += [d for _, d in self.handles if d not in order]
        last = None
        for dev in order:
            try:
                dev.write(frame)
                return
            except Exception as exc:  # wrong collection for this report length
                last = exc
        raise OSError(f"write failed on every collection: {last}")

    def read(self, timeout_ms: int) -> bytes:
        """Poll every collection until one yields a report or time runs out."""
        deadline = time.monotonic() + timeout_ms / 1000.0
        slice_ms = max(20, timeout_ms // (4 * max(1, len(self.handles))))
        while time.monotonic() < deadline:
            for _, dev in self.handles:
                try:
                    data = dev.read(LEN_LONG, slice_ms)
                except Exception:
                    continue
                if data:
                    return bytes(data)
        return b""

    def close(self) -> None:
        for _, dev in self.handles:
            try:
                dev.close()
            except Exception:
                pass


class HidppChannel:
    def __init__(self, dev, device_index: int, timeout_ms: int = 500):
        self.dev = dev  # a Transport
        self.device_index = device_index
        self.timeout_ms = timeout_ms
        self.last_raw = b""

    def _frame(self, feature_index: int, function_id: int, params: bytes, long: bool):
        rid = REPORT_LONG if long else REPORT_SHORT
        size = LEN_LONG if long else LEN_SHORT
        head = bytes(
            [
                rid,
                self.device_index,
                feature_index,
                ((function_id & 0x0F) << 4) | SOFTWARE_ID,
            ]
        )
        body = bytes(params)[: size - len(head)]
        return head + body + b"\x00" * (size - len(head) - len(body))

    def request(
        self,
        feature_index: int,
        function_id: int,
        params: bytes = b"",
        long: bool = False,
    ) -> bytes:
        """Send one HID++ request, return the parameter bytes of the reply.

        Raises HidppError on a device-reported error, TimeoutError on silence.
        Unrelated input reports (button/battery/wheel notifications) are skipped.
        """
        fn_sw = ((function_id & 0x0F) << 4) | SOFTWARE_ID
        # a request needing >3 param bytes cannot fit a short report
        if len(params) > 3:
            long = True
        out = self._frame(feature_index, function_id, params, long)
        self.dev.write(out)

        deadline = time.monotonic() + self.timeout_ms / 1000.0
        while time.monotonic() < deadline:
            remaining = int((deadline - time.monotonic()) * 1000)
            reply = self.dev.read(max(20, remaining))
            if not reply:
                break
            self.last_raw = reply
            if len(reply) < 5:
                continue
            if reply[0] not in (REPORT_SHORT, REPORT_LONG):
                continue
            if reply[1] != self.device_index:
                continue
            # error frames name the ORIGINAL feature/function in bytes 3/4
            if reply[2] in (ERR_MARK_HIDPP10, ERR_MARK_HIDPP20):
                if reply[3] == feature_index and reply[4] == fn_sw:
                    raise HidppError(
                        reply[5], reply, legacy=(reply[2] == ERR_MARK_HIDPP10)
                    )
                continue
            if reply[2] == feature_index and reply[3] == fn_sw:
                return reply[4:]
        raise TimeoutError(
            f"no reply for feature_index=0x{feature_index:02X} fn={function_id}"
        )

    def ping(self) -> bytes:
        """Root getProtocolVersion; the 3rd param byte is echoed back."""
        return self.request(ROOT_FEATURE_INDEX, ROOT_FN_PING, bytes([0x00, 0x00, 0x5A]))

    def get_feature_index(self, feature_id: int) -> int:
        """Root getFeature. Returns 0 when the device lacks the feature."""
        params = bytes([(feature_id >> 8) & 0xFF, feature_id & 0xFF, 0x00])
        try:
            res = self.request(ROOT_FEATURE_INDEX, ROOT_FN_GET_FEATURE, params)
        except (HidppError, TimeoutError):
            return 0
        return res[0] if res else 0


def hexs(b: bytes) -> str:
    return " ".join(f"{x:02X}" for x in b)


# --------------------------------------------------------------------------
# Enumeration / connection
# --------------------------------------------------------------------------
def list_candidates(backend: HidBackend) -> list[dict]:
    """Vendor-defined (0xFF00 / 0xFF43) HID interfaces on Logitech devices.

    Deliberately returns no serial numbers and no device paths to the printer --
    the caller only ever surfaces product string / usage page / usage.
    """
    out = []
    for info in backend.enumerate(LOGITECH_VID, 0):
        if info.get("product_id") in EXCLUDED_PIDS:
            continue
        if info.get("usage_page") in HIDPP_USAGE_PAGES:
            out.append(info)
    return out


def describe(info: dict) -> dict:
    return {
        "product": (info.get("product_string") or "").strip(),
        "manufacturer": (info.get("manufacturer_string") or "").strip(),
        "pid": f"0x{info.get('product_id', 0):04X}",
        "interface": info.get("interface_number"),
        "usage_page": f"0x{info.get('usage_page', 0):04X}",
        "usage": f"0x{info.get('usage', 0):04X}",
    }


def open_channel(backend: HidBackend, verbose: bool, max_index: int = 6):
    """Find the vendor interface that a paired device actually answers on.

    Both 0xFF00 collections of one physical interface are opened together and
    treated as a single endpoint (see USAGE_SHORT/USAGE_LONG note above).
    """
    groups: dict[tuple, list[dict]] = {}
    for info in list_candidates(backend):
        # usage_page is part of the key so the short/long collection pair of ONE
        # vendor page is opened together, and 0xFF00 and 0xFF43 are tried as
        # separate endpoints rather than mixed into one transport.
        key = (info.get("product_id"), info.get("interface_number"),
               info.get("usage_page"))
        groups.setdefault(key, []).append(info)

    tried = []
    for key, infos in groups.items():
        desc = describe(infos[0])
        desc["collections"] = [f"0x{i.get('usage', 0):04X}" for i in infos]
        handles = []
        for info in infos:
            try:
                handles.append((info.get("usage"), backend.open_path(info["path"])))
            except Exception as exc:  # busy / access denied / gone
                tried.append({**desc, "result": f"open failed: {exc}"})
        if not handles:
            continue
        transport = Transport(handles)
        for dev_index in range(1, max_index + 1):
            ch = HidppChannel(transport, dev_index)
            try:
                pong = ch.ping()
            except (HidppError, TimeoutError) as exc:
                if verbose:
                    tried.append({**desc, "device_index": dev_index, "result": str(exc)})
                continue
            tried.append(
                {
                    **desc,
                    "device_index": dev_index,
                    "result": f"HID++ {pong[0]}.{pong[1]}",
                }
            )
            return ch, desc, pong, tried
        transport.close()
        if not verbose:
            tried.append({**desc, "result": "no device answered"})
    return None, None, None, tried


# --------------------------------------------------------------------------
# DPI read / write
# --------------------------------------------------------------------------
def read_dpi(ch: HidppChannel) -> dict:
    """Try 0x2201 first, then 0x2202. Returns a dict incl. the raw reply."""
    idx_2201 = ch.get_feature_index(FEAT_ADJUSTABLE_DPI)
    idx_2202 = ch.get_feature_index(FEAT_EXT_ADJUSTABLE_DPI)

    result = {
        "feature_0x2201_index": idx_2201,
        "feature_0x2202_index": idx_2202,
        "dpi": None,
        "dpi_x": None,
        "dpi_y": None,
        "default_dpi": None,
        "answered_by": None,
        "raw": None,
        "errors": [],
    }

    if idx_2201:
        try:
            # 0x2201 fn2 getSensorDpi(sensorIdx=0)
            #   -> [sensor, dpi_hi, dpi_lo, default_hi, default_lo]
            res = ch.request(idx_2201, 2, bytes([0x00]))
            result.update(
                answered_by="0x2201",
                raw=hexs(ch.last_raw),
                dpi=(res[1] << 8) | res[2],
                dpi_x=(res[1] << 8) | res[2],
                dpi_y=(res[1] << 8) | res[2],
                default_dpi=(res[3] << 8) | res[4],
            )
            return result
        except (HidppError, TimeoutError, IndexError) as exc:
            result["errors"].append(f"0x2201 fn2: {exc}")

    if idx_2202:
        try:
            # fn5 getSensorDpiParameters(sensorIdx=0)
            #  -> [sensor, dpiX(2), defX(2), dpiY(2), defY(2), lod, ...]
            res = ch.request(idx_2202, 5, bytes([0x00]))
            dpi_x = (res[1] << 8) | res[2]
            dpi_y = (res[5] << 8) | res[6]
            result.update(
                answered_by="0x2202",
                raw=hexs(ch.last_raw),
                dpi=dpi_x,
                dpi_x=dpi_x,
                dpi_y=dpi_y,
                dpi_y_independent=dpi_y != dpi_x,
                default_dpi=(res[3] << 8) | res[4],
                default_dpi_y=(res[7] << 8) | res[8],
                lift_off_distance=res[9],
            )
        except (HidppError, TimeoutError, IndexError) as exc:
            result["errors"].append(f"0x2202 fn5: {exc}")

        # fn3 getSensorDpiList -- the selectable stages. Read-only, informative.
        try:
            res = ch.request(idx_2202, 3, bytes([0x00, 0x00]))
            stages = []
            for i in range(2, len(res) - 1, 2):
                val = (res[i] << 8) | res[i + 1]
                if val:
                    stages.append(val)
            result["dpi_stages"] = stages
            result["dpi_stages_raw"] = hexs(ch.last_raw)
        except (HidppError, TimeoutError, IndexError) as exc:
            result["errors"].append(f"0x2202 fn3 (list): {exc}")

    return result


def read_report_rate(ch: HidppChannel) -> dict:
    """Best-effort; optional. Never fatal."""
    out = {
        "report_rate_hz": None,
        "report_rate_source": None,
        "raw": None,
        "report_rate_supported_hz": None,
        "report_rate_list_raw": None,
    }

    idx_ext = ch.get_feature_index(FEAT_EXT_REPORT_RATE)
    if idx_ext:
        # fn1 getReportRateList(connectionType) -> [connectionType, bitmap]
        # (the connection type IS echoed in the first byte -- the bitmap is the
        # SECOND byte, confirmed live 2026-09-01, Logitech G PRO-series wireless
        # mouse via LIGHTSPEED receiver, feature 0x8061, in the same run as the
        # feature 0x2202 checks: 11 01 0C 11 00 7F ... = wired, 7 rates)
        #
        # This bitmap is what pins the direction of the rate ladder, which the
        # rate value alone cannot do: index 4 reads as 2000 Hz if index 0 is the
        # SLOWEST rate, or 500 Hz if index 0 is the fastest. A wireless list
        # that is contiguous from bit 0 and shorter than the wired list means
        # index 0 = slowest, because a LIGHTSPEED link drops the FAST rates.
        for conn_type in (0x00, 0x01):  # 0 = wired, 1 = wireless
            try:
                res = ch.request(idx_ext, 1, bytes([conn_type]))
            except (HidppError, TimeoutError, IndexError):
                continue
            bitmap = res[1] if len(res) > 1 else 0
            key = "wired" if conn_type == 0 else "wireless"
            out[f"rate_list_{key}_bitmap"] = f"0x{bitmap:02X}"
            out[f"rate_list_{key}_raw"] = hexs(ch.last_raw)
            if bitmap:
                out["report_rate_supported_hz"] = [
                    EXT_RATE_HZ[b] for b in sorted(EXT_RATE_HZ) if bitmap & (1 << b)
                ]
                out["report_rate_list_raw"] = hexs(ch.last_raw)

        for conn_type in (0x01, 0x00):  # wireless first, then wired
            try:
                res = ch.request(idx_ext, 2, bytes([conn_type]))
            except (HidppError, TimeoutError):
                continue
            idx = res[0]
            hz = EXT_RATE_HZ.get(idx)
            if hz:
                out.update(
                    report_rate_hz=hz,
                    report_rate_index=idx,
                    # the other reading of the same byte, kept visible so a
                    # reader can see the assumption rather than inherit it
                    report_rate_hz_if_ladder_reversed=EXT_RATE_HZ.get(6 - idx),
                    report_rate_ladder_direction=RATE_LADDER_PROVENANCE,
                    report_rate_source=f"0x8061 fn2 (connType={conn_type}, inferred)",
                    raw=hexs(ch.last_raw),
                )
                return out

    idx_std = ch.get_feature_index(FEAT_REPORT_RATE)
    if idx_std:
        try:
            res = ch.request(idx_std, 1, b"")
            period = res[0]
            if period:
                out.update(
                    report_rate_hz=round(1000 / period),
                    report_rate_source="0x8060 fn1 (period_ms, inferred)",
                    raw=hexs(ch.last_raw),
                )
        except (HidppError, TimeoutError, ZeroDivisionError, IndexError):
            pass
    return out


def set_dpi(ch: HidppChannel, dpi: int, info: dict) -> dict:
    """WRITE. Only reachable behind --set plus --yes."""
    hi, lo = (dpi >> 8) & 0xFF, dpi & 0xFF
    if info.get("answered_by") == "0x2201":
        # 0x2201 fn3 setSensorDpi(sensorIdx, dpi_hi, dpi_lo)
        ch.request(info["feature_0x2201_index"], 3, bytes([0x00, hi, lo]), long=True)
        return {"wrote_via": "0x2201 fn3"}
    if info.get("answered_by") == "0x2202":
        # 0x2202 fn6 setSensorDpiParameters(sensorIdx, X_hi, X_lo, Y_hi, Y_lo, lod)
        # Mirrors the fn5 reply layout. The lift-off distance read back a moment
        # ago is echoed straight back so a DPI change cannot silently alter it.
        lod = info.get("lift_off_distance") or 0x01
        ch.request(
            info["feature_0x2202_index"],
            6,
            bytes([0x00, hi, lo, hi, lo, lod]),
            long=True,
        )
        return {"wrote_via": "0x2202 fn6", "lod_preserved": lod}
    raise SystemExit("cannot set: no DPI feature answered on the read")


# --------------------------------------------------------------------------
def main() -> int:
    ap = argparse.ArgumentParser(
        prog="logi_dpi.py",
        description=__doc__.split("\n")[0],
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__[
            __doc__.index("LOGITECH ONLY"):__doc__.index("HID++ 2.0 wire format")
        ].rstrip("-\n "),
    )
    ap.add_argument(
        "action", nargs="?", default="read", choices=["read"], help="default: read"
    )
    ap.add_argument("--set", type=int, metavar="DPI", help="WRITE a new DPI (needs --yes)")
    ap.add_argument("--yes", action="store_true", help="required confirmation for --set")
    ap.add_argument("--verbose", action="store_true", help="show every probe attempt")
    args = ap.parse_args()

    backend = HidBackend()
    ch, desc, pong, tried = open_channel(backend, args.verbose)

    if ch is None:
        payload = {
            "ok": False,
            "error": "no HID++ device answered on any 0xFF00 / 0xFF43 interface",
            "interfaces": tried,
        }
        print(json.dumps(payload))
        print("Interfaces probed:")
        for t in tried:
            print(f"  {t}")
        print("\nIf this is not a Logitech mouse, that is the expected result:")
        print("  HID++ is Logitech's vendor protocol and has no equivalent on")
        print("  Razer / SteelSeries / Corsair / generic mice. Instead:")
        print("    1. read the DPI out of the vendor's own software, and treat it")
        print("       as intent - the same caveat as G HUB's settings.db;")
        print("    2. confirm it with scripts/rawinput_dpi_test.py, which measures")
        print("       the sensor on any mouse (needs an explicit yes);")
        print("    3. everything else in this skill is vendor neutral.")
        print("If it IS a Logitech mouse: check the receiver is plugged in, that")
        print("the mouse is powered on and paired, and re-run with --verbose.")
        print("VERDICT: SKIP - no HID++ device answered on any 0xFF00 / 0xFF43 "
              "interface (probe list above)")
        return 2

    try:
        dpi_info = read_dpi(ch)
        rate_info = read_report_rate(ch)

        wrote = None
        if args.set is not None:
            if not args.yes:
                print(json.dumps({"ok": False, "error": "--set requires --yes"}))
                print("  A --set writes a new DPI to the mouse and lands the")
                print("  instant it is sent, mid-game included. Re-run with --yes")
                print("  only after the owner has said go in the current chat.")
                print("VERDICT: refusing to write - --set needs --yes")
                return 3
            if not 50 <= args.set <= 32000:
                print(json.dumps({"ok": False, "error": "dpi out of sane range"}))
                print(f"VERDICT: refusing to write - {args.set} DPI is outside "
                      "the sane range 50-32000")
                return 3
            print(f"BEFORE: dpi={dpi_info['dpi']} raw=[{dpi_info['raw']}]")
            wrote = set_dpi(ch, args.set, dpi_info)
            after = read_dpi(ch)
            print(f"AFTER:  dpi={after['dpi']} raw=[{after['raw']}]")
            if after["dpi"] != args.set:
                print(f"WARNING: asked for {args.set} but the mouse reports "
                      f"{after['dpi']}. The value above is what the device says "
                      "and is the one to believe. If G HUB's agent is running it "
                      "can push its own profile back over this within seconds - "
                      "re-read to check whether the change stuck.")
            wrote["after"] = after
            dpi_info = after

        payload = {
            "ok": dpi_info["dpi"] is not None,
            "device": desc,
            "hidpp_version": f"{pong[0]}.{pong[1]}",
            "device_index": ch.device_index,
            **dpi_info,
            **{k: v for k, v in rate_info.items() if k != "raw"},
            "report_rate_raw": rate_info["raw"],
        }
        if wrote:
            payload["write"] = wrote
        print(json.dumps(payload))

        if dpi_info["dpi"] is None:
            print("VERDICT: FAIL - a HID++ device answered but no DPI feature "
                  "replied. Errors: " + "; ".join(dpi_info["errors"]))
            return 2

        xy = ""
        if dpi_info["dpi_x"] != dpi_info["dpi_y"]:
            print_x, print_y = dpi_info["dpi_x"], dpi_info["dpi_y"]
            xy = f" (X={print_x}, Y={print_y})"
        if rate_info["report_rate_hz"]:
            rate = f", report rate {rate_info['report_rate_hz']} Hz"
            alt = rate_info.get("report_rate_hz_if_ladder_reversed")
            if alt and alt != rate_info["report_rate_hz"]:
                # 0x8061 returns a bare index, and this device advertises the
                # same 7 rates on wired and wireless, so the index alone cannot
                # pin the ladder direction. Two independent sources agree it
                # runs slowest-first: G HUB's settings.db reports wireless
                # 2000 Hz for this mouse, and Solaar's public 0x8061 table has
                # index 0 = 8 ms (125 Hz) rising to index 4 = 0.5 ms (2000 Hz).
                # Corroborated, not measured. The DPI above does not depend on
                # it either way.
                rate += (f" (index {rate_info['report_rate_index']}; ladder"
                         " direction corroborated by G HUB and Solaar's public"
                         f" 0x8061 table, not measured - reversed it would read"
                         f" {alt} Hz)")
        else:
            rate = ", report rate unavailable"
        stages = dpi_info.get("dpi_stages")
        stage_txt = f", stages {'/'.join(str(s) for s in stages)}" if stages else ""
        # Verbose detail goes BEFORE the verdict: the last line printed is always
        # the VERDICT, on every path through this script.
        if args.verbose:
            print(f"raw DPI reply: {dpi_info['raw']}")
            for t in tried:
                print(f"  probe: {t}")
        print(
            f"VERDICT: {dpi_info['dpi']} DPI{xy} - read from the mouse, this is "
            f"ground truth [via feature {dpi_info['answered_by']}, "
            f"default {dpi_info['default_dpi']}]{rate}{stage_txt}"
        )
        return 0
    finally:
        ch.dev.close()


if __name__ == "__main__":
    sys.exit(main())
