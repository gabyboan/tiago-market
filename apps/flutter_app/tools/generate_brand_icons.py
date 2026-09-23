#!/usr/bin/env python3
"""Export the app bar's Material shopping_basket_rounded to launcher icons.

Run: uv run --with fonttools --with cairosvg --with pillow tools/generate_brand_icons.py
Requires Flutter on PATH. Material Icons are distributed under Apache 2.0.
"""
from io import BytesIO
from pathlib import Path
import shutil

import cairosvg
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SDK = Path(shutil.which('flutter')).resolve().parents[1]
FONT_DIR = SDK / 'bin/cache/artifacts/material_fonts'
font = TTFont(FONT_DIR / 'MaterialIcons-Regular.otf')
glyphs = font.getGlyphSet()
units = font['head'].unitsPerEm
# Same proportion as the 20px glyph in the app bar's 36px green circle.
scale = (512 * 20 / 36) / units
offset = (512 - units * scale) / 2
pen = SVGPathPen(glyphs)
glyphs[font.getBestCmap()[0xF0170]].draw(
    TransformPen(pen, (scale, 0, 0, -scale, offset, 512 - offset)))
path = pen.getCommands()


def svg(circle=False):
    background = ('<circle cx="256" cy="256" r="256" fill="#006C51"/>'
                  if circle else '<rect width="512" height="512" fill="#006C51"/>')
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" '
            f'role="img" aria-label="Tiago Market">{background}'
            f'<path fill="#fff" d="{path}"/></svg>\n')


def png(destination, size, circle=False):
    destination.write_bytes(cairosvg.svg2png(bytestring=svg(circle).encode(),
                                          output_width=size, output_height=size))


assets = ROOT / 'assets/branding'
assets.mkdir(parents=True, exist_ok=True)
(assets / 'tiago-market-launcher.svg').write_text(svg(True))
(assets / 'tiago-market-launcher-full-bleed.svg').write_text(svg())
shutil.copyfile(FONT_DIR / 'MaterialIcons_LICENSE.txt', assets / 'MaterialIcons-LICENSE.txt')
for density, size in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
    png(ROOT / f'android/app/src/main/res/mipmap-{density}/ic_launcher.png', size, True)
(ROOT / 'android/app/src/main/res/drawable/ic_launcher_foreground.xml').write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<vector xmlns:android="http://schemas.android.com/apk/res/android" '
    'android:width="108dp" android:height="108dp" '
    'android:viewportWidth="512" android:viewportHeight="512">\n'
    f'    <path android:fillColor="#FFFFFFFF" android:pathData="{path}" />\n</vector>\n')
for icon in (ROOT / 'ios/Runner/Assets.xcassets/AppIcon.appiconset').glob('*.png'):
    with Image.open(icon) as current:
        size = current.width
    png(icon, size)
for icon in (ROOT / 'web/icons').glob('*.png'):
    size = 192 if '192' in icon.name else 512
    png(icon, size, 'maskable' not in icon.name)
png(ROOT / 'web/favicon.png', 64, True)
public = ROOT.parent / 'price_web/public'
for name in ('tiago-market-logo.svg', 'tiago-market-navbar.svg'):
    (public / name).write_text(svg(True))
Image.open(BytesIO(cairosvg.svg2png(bytestring=svg(True).encode(), output_width=256,
                                  output_height=256))).save(public / 'favicon.ico')
print('Updated Android, iOS and web icons from the app bar glyph.')
