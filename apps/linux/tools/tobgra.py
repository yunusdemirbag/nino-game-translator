#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Nino contributors
# BMP (24/32 bit, sips çıktısı) → ham BGRA; boyutu yazdırır.
import struct, sys
src, dst = sys.argv[1], sys.argv[2]
d = open(src, 'rb').read()
off = struct.unpack_from('<I', d, 10)[0]
w, h = struct.unpack_from('<ii', d, 18)
bpp = struct.unpack_from('<H', d, 28)[0]
bottom_up = h > 0; h = abs(h)
row = ((w * bpp + 31) // 32) * 4
out = bytearray(w * h * 4)
for y in range(h):
    sy = h - 1 - y if bottom_up else y
    base = off + sy * row
    for x in range(w):
        p = base + x * (bpp // 8)
        o = (y * w + x) * 4
        out[o:o+3] = d[p:p+3]
        out[o+3] = 255
open(dst, 'wb').write(out)
print(w, h)
