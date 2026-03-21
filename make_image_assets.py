from PIL import Image
import sys

src = sys.argv[1]
pal_out = sys.argv[2]
img_out = sys.argv[3]

im = Image.open(src).convert("RGB").resize((320, 200), Image.Resampling.LANCZOS)
qim = im.quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)

pixel_bytes = qim.tobytes()
if len(pixel_bytes) != 320 * 200:
    raise RuntimeError("Unexpected pixel byte length: {}".format(len(pixel_bytes)))

raw_pal = qim.getpalette()[:256*3]
if len(raw_pal) != 256*3:
    raise RuntimeError("Unexpected palette byte length: {}".format(len(raw_pal)))

vga_pal = bytes(min(63, max(0, c // 4)) for c in raw_pal)
with open(pal_out, "wb") as f:
    f.write(vga_pal)

with open(img_out, "wb") as f:
    f.write(pixel_bytes)

print("wrote", pal_out, len(vga_pal), "bytes")
print("wrote", img_out, len(pixel_bytes), "bytes")
