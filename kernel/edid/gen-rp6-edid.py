#!/usr/bin/env python3
# gen-rp6-edid.py — generate a synthetic EDID 1.3 for the Retroid Pocket 6 DSI panel.
#
# WHY: the RP6 panel is DSI (no hardware EDID); /sys/class/drm/card0-DSI-1/edid is 0 bytes.
# gamescope's *dynamic* refresh control (Steam QAM refresh slider) populates its
# ValidDynamicRefreshRates list ONLY from the connector EDID (DRMBackend.cpp ParseEDID); with an
# empty EDID the QAM slider is inert. Launch-time `-r` doesn't need the EDID, which is why that
# works. This EDID exposes the panel's two real modes so gamescope offers 60/120 Hz live-switching,
# matching ROCKNIX. Loaded via CONFIG_DRM_LOAD_EDID_FIRMWARE (drm.edid_firmware=DSI-1:edid/rp6.bin)
# or, for a no-reboot test, the connector's debugfs edid_override.
#
# Timings are the panel's actual DRM modes (from on-device `modetest -c`, connector DSI-1):
#   #0 1080x1920 @120.00  clk 263424  h:1080 1096 1098 1120  v:1920 1940 1944 1960  (preferred)
#   #1 1080x1920 @ 60.00  clk 262886  h:1080 1096 1098 1120  v:1920 1936 1940 3912  (VFP-stretched)

import struct

def dtd(clock_khz, hact, hsync_start, hsync_end, htot, vact, vsync_start, vsync_end, vtot,
        hsize_mm, vsize_mm):
    """18-byte Detailed Timing Descriptor."""
    pixclk = round(clock_khz / 10)          # 10 kHz units
    hblank = htot - hact
    vblank = vtot - vact
    hso = hsync_start - hact                 # h front porch
    hsw = hsync_end - hsync_start            # h sync width
    vso = vsync_start - vact                 # v front porch
    vsw = vsync_end - vsync_start            # v sync width
    b = bytearray(18)
    b[0] = pixclk & 0xFF
    b[1] = (pixclk >> 8) & 0xFF
    b[2] = hact & 0xFF
    b[3] = hblank & 0xFF
    b[4] = ((hact >> 8) << 4) | ((hblank >> 8) & 0x0F)
    b[5] = vact & 0xFF
    b[6] = vblank & 0xFF
    b[7] = ((vact >> 8) << 4) | ((vblank >> 8) & 0x0F)
    b[8] = hso & 0xFF
    b[9] = hsw & 0xFF
    b[10] = ((vso & 0x0F) << 4) | (vsw & 0x0F)
    b[11] = (((hso >> 8) & 0x3) << 6) | (((hsw >> 8) & 0x3) << 4) | \
            (((vso >> 4) & 0x3) << 2) | ((vsw >> 4) & 0x3)
    b[12] = hsize_mm & 0xFF
    b[13] = vsize_mm & 0xFF
    b[14] = ((hsize_mm >> 8) << 4) | ((vsize_mm >> 8) & 0x0F)
    b[15] = 0                                 # h border
    b[16] = 0                                 # v border
    b[17] = 0x1E                              # digital separate sync, +H +V
    return bytes(b)

def descriptor_string(tag, text):
    """18-byte monitor descriptor (0xFC name / 0xFE etc.). Body is exactly 13 bytes:
    text, then 0x0A terminator (if room), then 0x20 padding."""
    body = text.encode("ascii")[:13]
    if len(body) < 13:
        body = body + b"\x0a" + b"\x20" * (12 - len(body))
    return bytes([0, 0, 0, tag, 0]) + body

def descriptor_range(vmin, vmax, hmin, hmax, max_pixclk_mhz):
    """18-byte Monitor Range Limits descriptor (0xFD)."""
    return bytes([0, 0, 0, 0xFD, 0, vmin, vmax, hmin, hmax,
                  round(max_pixclk_mhz / 10), 0x00, 0x0A]) + b"\x20" * 6

def srgb_chromaticity():
    """10 bytes encoding standard sRGB chromaticity coords."""
    coords = [(0.640, 0.330), (0.300, 0.600), (0.150, 0.060), (0.3127, 0.3290)]  # R G B W
    q = [(round(x * 1024), round(y * 1024)) for x, y in coords]
    (rx, ry), (gx, gy), (bx, by), (wx, wy) = q
    b = bytearray(10)
    b[0] = ((rx & 3) << 6) | ((ry & 3) << 4) | ((gx & 3) << 2) | (gy & 3)
    b[1] = ((bx & 3) << 6) | ((by & 3) << 4) | ((wx & 3) << 2) | (wy & 3)
    b[2], b[3], b[4], b[5] = rx >> 2, ry >> 2, gx >> 2, gy >> 2
    b[6], b[7], b[8], b[9] = bx >> 2, by >> 2, wx >> 2, wy >> 2
    return bytes(b)

e = bytearray(128)
e[0:8] = b"\x00\xff\xff\xff\xff\xff\xff\x00"   # header
# Manufacturer "RTP" (Retroid Pocket; 5-bit A=1..Z=26, packed big-endian)
mfr = ((ord('R')-64) << 10) | ((ord('T')-64) << 5) | (ord('P')-64)
e[8], e[9] = (mfr >> 8) & 0xFF, mfr & 0xFF
e[10], e[11] = 0x06, 0x00                       # product code 0x0006
e[12:16] = b"\x00\x00\x00\x00"                  # serial
e[16] = 0                                        # week
e[17] = 2026 - 1990                              # year
e[18], e[19] = 1, 3                              # EDID 1.3
e[20] = 0x80                                     # digital input
e[21], e[22] = 7, 12                             # image size cm (portrait ~68x120 mm)
e[23] = 0x78                                     # gamma 2.2
e[24] = 0x0A                                     # active off + preferred-timing-is-native
e[25:35] = srgb_chromaticity()
e[35:38] = b"\x00\x00\x00"                       # no established timings
e[38:54] = b"\x01\x01" * 8                       # no standard timings

# 4 detailed descriptors: DTD@120 (preferred) | DTD@60 | range limits | name
e[54:72]  = dtd(263424, 1080, 1096, 1098, 1120, 1920, 1940, 1944, 1960, 68, 120)
e[72:90]  = dtd(262886, 1080, 1096, 1098, 1120, 1920, 1936, 1940, 3912, 68, 120)
e[90:108] = descriptor_range(55, 125, 150, 250, 270)
e[108:126] = descriptor_string(0xFC, "RP6")

e[126] = 0                                       # extensions
e[127] = (-sum(e[0:127])) & 0xFF                 # checksum

import sys, os
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "rp6.bin")
with open(out, "wb") as f:
    f.write(e)
print(f"wrote {out} ({len(e)} bytes), checksum byte 0x{e[127]:02x}")
print("hex:", e.hex())
