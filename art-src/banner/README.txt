GUILD BANNER ART — LAYERED PNG ASSETS

25 production textures, each 1024 x 2048 pixels, 8-bit RGBA PNG.
Canvas origin is top left. Every texture uses the full shared canvas.
Do not trim transparent margins or position layers by visible bounds.

CONTENTS
cloth_horde_1.png through cloth_horde_4.png
border_horde_1.png through border_horde_4.png
pole_horde.png, trim_horde.png, tassels_horde.png, finial_horde.png
cloth_alliance_1.png through cloth_alliance_4.png
border_alliance_1.png through border_alliance_4.png
pole_alliance.png, trim_alliance.png, tassels_alliance.png, finial_alliance.png
sheen.png

TINTING
Only cloth_* and border_* receive guild colours. Their visible RGB channels
are identical, with values from 140 (#8C8C8C) to 255 (#FFFFFF).
Apply the background colour to cloth and the border colour to border:
  tintedRGB = textureRGB * guildRGB / 255
Preserve the original alpha. These are straight-alpha textures.
Composite tinted layers using normal alpha blending. Border is an opaque
painted band over the cloth edge, not a multiply-blended shadow layer.
Keep pole, trim, tassels, finial and sheen untinted at white vertex colour.

RECOMMENDED STACK — BACK TO FRONT
1. pole_<faction>.png
2. cloth_<faction>_<stage>.png, background-colour tint
3. border_<faction>_<stage>.png, border-colour tint
4. sheen.png, stage 4 only
5. game-provided guild emblem, stages 2-4
6. trim_<faction>.png, stages 3-4
7. tassels_<faction>.png, stages 3-4
8. finial_<faction>.png, stage 4 only

REGISTRATION
Main shaft runs approximately x130-190, y130-2020.
Crossbar spans approximately x95-950 around y165.
Cloth is contained within x220-899 and y180-1749.
Stage 1 is a short swallow-tail pennant ending by y589, above the emblem
circle. The fixed emblem circle therefore contains no stage-1 cloth;
hide the game-provided emblem at stage 1 unless your UI handles it otherwise.
Stages 2, 3 and 4 share exactly the same cloth and border alpha masks within
each faction. Their internal painted folds differ. Trim and tassels remain
registered when switching stages.
The border band is approximately 52 pixels wide, measured inward from the
edge. Coloured trim lies within this band.
The emblem reserve is centred at (560,820), radius 210 pixels. In stages
2-4 it contains only plain cloth shading. All other layers are transparent
throughout the reserve. The circle is not visibly drawn in any asset.
The shared sheen is pure white with low alpha (maximum 11/255, about 4.3%),
confined to the common cloth interior and clear of the emblem reserve.

QUALITY CHECKS
All 25 production filenames, dimensions and RGBA formats verified.
All visible tintable pixels have R=G=B and are within 140..255.
No decorative layer intrudes into the emblem reserve.
Stages 2-4 share exact cloth and border alpha masks.
All eight cloth+border pairs were previewed with each requested sample:
  Dark grey  (36,36,36)
  Deep red   (150,20,20)
  Royal blue (30,60,160)
  White      (255,255,255)
  Yellow     (230,190,40)
All 40 previews preserve fold shading and contain zero visible pure-black
pixels. At the darkest sample, the visible tonal range is 20..36.
The previews use arithmetic RGB multiplication matching the supplied rule.
This is an offline asset/compositing check; the addon itself was not run.

PREVIEWS AND RECORDS
banner-preview.jpg: all eight assembled faction/stage combinations.
quality-check/tint-check-horde.jpg: twenty Horde tint previews.
quality-check/tint-check-alliance.jpg: twenty Alliance tint previews.
quality-check/assembled-*-stage-4.jpg: full-size assembled examples.
quality-check/validation.json: per-file and per-colour numeric results.
manifest.json: filenames, draw order, stage selection and checksums.
prompts.json: built-in image_gen prompt set and final refinement.
Preview JPGs are reference sheets; only the 25 PNGs are production layers.

AUTHORING
Artwork generated with built-in image_gen, followed by deterministic canvas
registration, silhouette fitting, alpha cleanup and neutral-value export.
