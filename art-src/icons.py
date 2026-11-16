"""Draws the GuildEventManager icons (own drawings, 24x24 grid) and writes
them as 64x64 TGA files with alpha to Media/Icons. White icons are tinted in
the game; the coloured ones (check, cross, roles) are used inline in text."""
import io, os, cairosvg
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "Media", "Icons")
PNG = os.path.join(HERE, "icons")

S = 'fill="none" stroke="{c}" stroke-width="{w}" stroke-linecap="round" stroke-linejoin="round"'
F = 'fill="{c}" stroke="none"'

ICONS = {
  # side bar
  "home":     ('s', '<path d="M3 11 L12 4 L21 11"/><path d="M5.5 9.5 V20 H18.5 V9.5"/><path d="M10 20 V14.5 H14 V20"/>'),
  "events":   ('s', '<rect x="3.5" y="5" width="17" height="15.5" rx="2"/><path d="M3.5 10 H20.5"/><path d="M8 3 V7"/><path d="M16 3 V7"/><path d="M7.5 14 H9.5 M11 14 H13 M14.5 14 H16.5 M7.5 17 H9.5 M11 17 H13"/>'),
  "ledger":   ('s', '<path d="M5 4.5 A1.5 1.5 0 0 1 6.5 3 H19 V18 H6.5 A1.5 1.5 0 0 0 5 19.5 Z"/><path d="M5 19.5 A1.5 1.5 0 0 0 6.5 21 H19 V18"/><path d="M9 7.5 H15 M9 11 H15"/>'),
  "ach":      ('s', '<path d="M7.5 4 H16.5 V9 A4.5 4.5 0 0 1 7.5 9 Z"/><path d="M7.5 5.5 H4.5 V7.5 A3 3 0 0 0 7.8 10.6"/><path d="M16.5 5.5 H19.5 V7.5 A3 3 0 0 1 16.2 10.6"/><path d="M12 13.5 V17.5"/><path d="M8.5 20.5 H15.5 L14.5 17.5 H9.5 Z"/>'),
  "banner":   ('s', '<path d="M5.5 21 V3"/><path d="M5.5 4 H18.5 L15.5 8.5 L18.5 13 H5.5"/>'),
  "pvp":      ('s', '<path d="M4 4 L15 15"/><path d="M20 4 L9 15"/><path d="M12.5 17.5 L17.5 12.5"/><path d="M6.5 12.5 L11.5 17.5"/><path d="M15.5 15.5 L20 20"/><path d="M8.5 15.5 L4 20"/>'),
  "raids":    ('s', '<path d="M4 21 V9 H6.5 V6 H9 V9 H11 V6 H13 V9 H15 V6 H17.5 V9 H20 V21 Z"/><path d="M10 21 V16.5 A2 2 0 0 1 14 16.5 V21"/>'),
  "holiday":  ('s', '<path d="M12 3 V21"/><path d="M4.2 7.5 L19.8 16.5"/><path d="M4.2 16.5 L19.8 7.5"/><path d="M10 4.5 L12 6.5 L14 4.5 M10 19.5 L12 17.5 L14 19.5"/>'),
  # header
  "settings": ('s', '<circle cx="12" cy="12" r="3"/><path d="M12 2.5 V5.2 M12 18.8 V21.5 M2.5 12 H5.2 M18.8 12 H21.5 M5.3 5.3 L7.2 7.2 M16.8 16.8 L18.7 18.7 M5.3 18.7 L7.2 16.8 M16.8 7.2 L18.7 5.3"/><circle cx="12" cy="12" r="6.8"/>'),
  "bell":     ('s', '<path d="M6 16.5 V11 A6 6 0 0 1 18 11 V16.5 L19.8 18.5 H4.2 Z"/><path d="M10 21 H14"/>'),
  "close":    ('s', '<path d="M6.5 6.5 L17.5 17.5 M17.5 6.5 L6.5 17.5"/>'),
  "chevron":  ('s', '<path d="M9 5.5 L15.5 12 L9 18.5"/>'),
  "back":     ('s', '<path d="M15 5.5 L8.5 12 L15 18.5"/>'),
  "dot":      ('f', '<circle cx="12" cy="12" r="7"/>'),
  # states (coloured, for text)
  "check":    ('s3#8fe0b0', '<path d="M5 12.5 L10 17.5 L19.5 6.5"/>'),
  "cross":    ('s3#f0a08f', '<path d="M6.5 6.5 L17.5 17.5 M17.5 6.5 L6.5 17.5"/>'),
  "unknown":  ('s3#e3b45b', '<path d="M8.8 9 A3.3 3.3 0 1 1 13.6 12 C12.6 12.6 12 13.3 12 14.6"/><circle cx="12" cy="18.6" r="1.4" fill="#e3b45b" stroke="none"/>'),
  "dash":     ('s3#8a8078', '<path d="M7 12 H17"/>'),
  # roles (coloured)
  "role_tank":  ('f#7fb2ff', '<path d="M12 2.5 L19.5 5.5 V11 C19.5 16 16.3 19.7 12 21.5 C7.7 19.7 4.5 16 4.5 11 V5.5 Z"/>'),
  "role_heal":  ('f#6fe0a0', '<path d="M9.6 3.5 H14.4 V9.6 H20.5 V14.4 H14.4 V20.5 H9.6 V14.4 H3.5 V9.6 H9.6 Z"/>'),
  "role_melee": ('s2.4#f08f80', '<path d="M20.5 3.5 L19.3 8 L10.3 17 L7 13.7 L16 4.7 Z" fill="#f08f80"/><path d="M5 12 L12 19"/><path d="M8 16 L4 20"/>'),
  "role_range": ('s2.2#e8c060', '<path d="M7 3 C15.5 7 15.5 17 7 21"/><path d="M7 3 V21"/><path d="M3.5 12 H20"/><path d="M17 9 L20.5 12 L17 15"/>'),
}

def svg(kind, body, color="#ffffff"):
    if kind.startswith('f'):
        c = kind[1:] or color
        attrs = F.format(c=c)
    else:
        rest = kind[1:]
        w, c = "1.9", color
        if rest:
            if '#' in rest:
                w2, c = rest.split('#'); c = '#' + c
                w = w2 or "1.9"
            else:
                w = rest
        attrs = S.format(c=c, w=w)
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="64" height="64"><g {attrs}>{body}</g></svg>'

def write(name, svgtext, size=64):
    png = cairosvg.svg2png(bytestring=svgtext.encode(), output_width=size, output_height=size)
    im = Image.open(io.BytesIO(png)).convert("RGBA")
    os.makedirs(PNG, exist_ok=True)
    im.save(os.path.join(PNG, name + ".png"))
    im.save(os.path.join(OUT, name + ".tga"))

for name, (kind, body) in ICONS.items():
    write(name, svg(kind, body))

# guild crest per faction: shield with a rune
CREST = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48" width="128" height="128">
<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{a}"/><stop offset="1" stop-color="{b}"/></linearGradient></defs>
<path d="M24 3 L41 8 V22 C41 33 33.5 40.5 24 45 C14.5 40.5 7 33 7 22 V8 Z" fill="url(#g)" stroke="#d9b45f" stroke-width="2.2" stroke-linejoin="round"/>
<path d="M24 6.5 L38 10.6 V22 C38 31.2 31.8 37.6 24 41.5 C16.2 37.6 10 31.2 10 22 V10.6 Z" fill="none" stroke="#000" stroke-opacity="0.25" stroke-width="1"/>
<g fill="none" stroke="#f1d58a" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">{rune}</g>
</svg>'''
write("crest_horde", CREST.format(a="#a3261c", b="#5a120c", rune='<path d="M15 13 L24 23 L33 13"/><path d="M24 23 V36"/><path d="M19 30 H29"/>'), 128)
write("crest_alliance", CREST.format(a="#2a4f9a", b="#132a5a", rune='<path d="M24 12 V36"/><path d="M15 21 H33"/><path d="M19 13 L24 9 L29 13"/>'), 128)

# preview sheet
names = list(ICONS) + ["crest_horde", "crest_alliance"]
sheet = Image.new("RGBA", (len(names) * 72, 90), (28, 22, 20, 255))
for i, n in enumerate(names):
    im = Image.open(os.path.join(PNG, n + ".png")).resize((64, 64))
    sheet.alpha_composite(im, (i * 72 + 4, 4))
sheet.save(os.path.join(PNG, "_preview.png"))
print(len(names), "icons")
