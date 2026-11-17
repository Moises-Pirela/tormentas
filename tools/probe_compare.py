#!/usr/bin/env python3
"""Compares two tools-probe screenshot sets, for P1a's rendering parity checks.

The probe (`bin/tormentas --tools-probe DIR`) drives the game through the editor, inspector,
brushes, anim editor and a raid, saving a PNG at fixed frames. Since P1a step 3 it uses synthetic
input, so two runs of the same build differ only by time-driven animation (clouds, flicker):
expect under ~1% of pixels and a max channel difference under ~20. A real rendering change shows
up as a much larger max channel difference, or as differences concentrated in one area.

Always compare against the *noise floor*: two runs of the same build, not one run of each.

usage:
    python3 -I tools/probe_compare.py BASE_DIR NEW_DIR [NOISE_DIR]

Pure standard library, so it runs anywhere Python does (no Pillow, no sips).
"""
import sys
import zlib
from pathlib import Path


def load_png(path):
    """Returns (width, height, rows) for an 8-bit RGB/RGBA PNG. rows are bytearrays."""
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"not a PNG: {path}")
    pos, idat, width, height, channels = 8, bytearray(), 0, 0, 0
    while pos < len(data):
        length = int.from_bytes(data[pos:pos + 4], "big")
        kind = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            width = int.from_bytes(chunk[0:4], "big")
            height = int.from_bytes(chunk[4:8], "big")
            if chunk[8] != 8:
                raise ValueError(f"{path}: only 8-bit PNGs are supported")
            channels = {0: 1, 2: 3, 4: 2, 6: 4}[chunk[9]]
            if chunk[12] != 0:
                raise ValueError(f"{path}: interlaced PNGs are not supported")
        elif kind == b"IDAT":
            idat += chunk
        elif kind == b"IEND":
            break

    raw = zlib.decompress(bytes(idat))
    stride = width * channels
    rows, prev, at = [], bytearray(stride), 0
    for _ in range(height):
        filter_type = raw[at]
        line = bytearray(raw[at + 1:at + 1 + stride])
        at += 1 + stride
        if filter_type == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif filter_type == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif filter_type == 3:
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif filter_type == 4:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                b = prev[i]
                c = prev[i - channels] if i >= channels else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 0xFF
        elif filter_type != 0:
            raise ValueError(f"{path}: bad filter {filter_type}")
        rows.append(line)
        prev = line
    return width, height, channels, rows


def compare(a_path, b_path, threshold=2):
    wa, ha, ca, ra = load_png(a_path)
    wb, hb, cb, rb = load_png(b_path)
    if (wa, ha) != (wb, hb):
        return f"size differs ({wa}x{ha} vs {wb}x{hb})", None
    differing, worst, worst_at = 0, 0, None
    for y in range(ha):
        row_a, row_b = ra[y], rb[y]
        for x in range(wa):
            ia, ib = x * ca, x * cb
            d = max(abs(row_a[ia + k] - row_b[ib + k]) for k in range(3))
            if d > threshold:
                differing += 1
            if d > worst:
                worst, worst_at = d, (x, y)
    pct = 100.0 * differing / (wa * ha)
    return f"{pct:6.2f}% px differ, max channel diff {worst:3} at {worst_at}", worst


def compare_dirs(base, new, label):
    print(f"--- {label}")
    for shot in sorted(base.glob("*.png")):
        other = new / shot.name
        if not other.exists():
            print(f"{shot.name:24} MISSING in {new}")
            continue
        summary, _ = compare(shot, other)
        print(f"{shot.name:24} {summary}")


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    base, new = Path(sys.argv[1]), Path(sys.argv[2])
    compare_dirs(base, new, f"{base} vs {new}")
    if len(sys.argv) > 3:
        compare_dirs(new, Path(sys.argv[3]), f"noise floor: {new} vs {sys.argv[3]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
