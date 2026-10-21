#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Regenerate the simple vector-derived app icon. Requires Pillow; not used by CI."""
import json
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SCALE = 3
image = Image.new('RGB', (1024 * SCALE, 1024 * SCALE), '#17251e')
draw = ImageDraw.Draw(image)


def curve(start, segments):
    points = [start]
    for a, b, end in segments:
        for i in range(1, 65):
            t = i / 64
            points.append(tuple((1-t)**3*start[j] + 3*(1-t)**2*t*a[j]
                                + 3*(1-t)*t*t*b[j] + t**3*end[j] for j in (0, 1)))
        start = end
    return points


bean = curve((590, 195), [
    ((815, 188), (866, 417), (747, 524)),
    ((665, 597), (612, 537), (565, 635)),
    ((468, 844), (208, 808), (203, 600)),
    ((197, 405), (358, 203), (590, 195)),
])
draw.polygon([(x * SCALE, y * SCALE) for x, y in bean], fill='#a3de85')
crease = curve((618, 297), [
    ((443, 340), (413, 463), (479, 519)),
    ((553, 582), (422, 669), (336, 667)),
])
draw.line([(x * SCALE, y * SCALE) for x, y in crease], fill='#31523d', width=28 * SCALE)
for x, y in crease:
    draw.ellipse(((x - 14) * SCALE, (y - 14) * SCALE,
                  (x + 14) * SCALE, (y + 14) * SCALE), fill='#31523d')
draw.ellipse(tuple(n * SCALE for n in (760, 230, 807, 277)), fill='#f4ead3')
image = image.resize((1024, 1024), Image.Resampling.LANCZOS)

for platform in ('iPhone', 'Watch'):
    catalog = ROOT / 'Resources' / platform / 'Assets.xcassets'
    icon = catalog / 'AppIcon.appiconset'
    icon.mkdir(parents=True, exist_ok=True)
    image.save(icon / 'AppIcon.png')
    entry = {'filename': 'AppIcon.png', 'idiom': 'universal', 'size': '1024x1024',
             'platform': 'watchos' if platform == 'Watch' else 'ios'}
    (icon / 'Contents.json').write_text(json.dumps({'images': [entry], 'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n', newline='\n')
    (catalog / 'Contents.json').write_text(json.dumps({'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n', newline='\n')
print('Generated iPhone and Watch app icons')
