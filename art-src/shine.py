"""Glow, shine band and sparkle for the stage-4 guild banner (own drawings)."""
import os, math
from PIL import Image, ImageDraw, ImageFilter
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "Media", "Banner")
# soft radial glow
g = Image.new("L", (256, 512), 0)
for y in range(512):
    for x in range(256):
        dx, dy = (x - 128) / 128, (y - 240) / 270
        d = math.sqrt(dx * dx + dy * dy)
        g.putpixel((x, y), int(255 * max(0, 1 - d) ** 1.8))
im = Image.new("RGBA", g.size, (255, 255, 255, 255)); im.putalpha(g); im.save(os.path.join(OUT, "glow.tga"))
# diagonal shine band (moved across the cloth by an animation)
b = Image.new("L", (256, 256), 0)
d = ImageDraw.Draw(b)
d.polygon([(70, 256), (130, 256), (186, 0), (126, 0)], fill=255)
d.polygon([(150, 256), (166, 256), (222, 0), (206, 0)], fill=150)
b = b.filter(ImageFilter.GaussianBlur(9))
# fade out at the top and the bottom so the band has no hard edge
fade = Image.new("L", (256, 256), 0)
for y in range(256):
    v = int(255 * math.sin(math.pi * y / 255) ** 1.5)
    for x in range(256): fade.putpixel((x, y), v)
from PIL import ImageChops as _C
b = _C.multiply(b, fade)
im = Image.new("RGBA", b.size, (255, 255, 255, 255)); im.putalpha(b); im.save(os.path.join(OUT, "shine.tga"))
# four-point sparkle
s = Image.new("L", (64, 64), 0)
d = ImageDraw.Draw(s)
d.polygon([(32, 0), (36, 28), (64, 32), (36, 36), (32, 64), (28, 36), (0, 32), (28, 28)], fill=255)
s = s.filter(ImageFilter.GaussianBlur(1.2))
c = Image.new("L", (64, 64), 0); ImageDraw.Draw(c).ellipse((22, 22, 42, 42), fill=200); c = c.filter(ImageFilter.GaussianBlur(5))
s = Image.composite(Image.new("L", (64, 64), 255), s, c.point(lambda v: v)) if False else Image.eval(Image.merge("L", [s]), lambda v: v)
from PIL import ImageChops
s = ImageChops.lighter(s, c)
im = Image.new("RGBA", s.size, (255, 255, 255, 255)); im.putalpha(s); im.save(os.path.join(OUT, "sparkle.tga"))
print("ok")
