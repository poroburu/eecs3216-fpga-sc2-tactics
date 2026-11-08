#!/usr/bin/env python3
"""Convert the testbench's 4-bit-per-channel PPM (P3, max 15) to PNG. usage: ppm2png.py in.ppm out.png"""
import struct, sys, zlib
tok = open(sys.argv[1]).read().split()
w, h, mx = int(tok[1]), int(tok[2]), int(tok[3]); v = list(map(int, tok[4:]))
rows = b"".join(b"\0" + bytes(c * 255 // mx for c in v[y * w * 3:(y + 1) * w * 3]) for y in range(h))
chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
open(sys.argv[2], "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                              + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b""))
