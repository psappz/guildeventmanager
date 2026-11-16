"""Turns the layered banner art (art-src/banner, 1024x2048 PNG, made with
ChatGPT from our prompt) into WoW textures: 256x512 TGA with straight alpha
in Media/Banner. The layers are stacked and tinted in UI_GuildBanner.lua."""
import glob, os
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "banner")
OUT = os.path.join(HERE, "..", "Media", "Banner")
os.makedirs(OUT, exist_ok=True)
n = 0
for f in sorted(glob.glob(os.path.join(SRC, "*.png"))):
    im = Image.open(f).convert("RGBA")
    small = im.convert("RGBa").resize((256, 512), Image.LANCZOS).convert("RGBA")
    small.save(os.path.join(OUT, os.path.basename(f)[:-4] + ".tga"))
    n += 1
print(n, "textures")
