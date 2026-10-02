"""Draws the DMG window background as a retina TIFF. Run from the repo root: python3 installer/make-background.py"""
import os
import subprocess

from PIL import Image, ImageDraw, ImageFont

W, H = 660, 400


def font(path, size):
    try:
        return ImageFont.truetype(path, size)
    except OSError:
        return ImageFont.load_default()


def draw(scale):
    im = Image.new("RGB", (W * scale, H * scale), (11, 11, 13))
    d = ImageDraw.Draw(im)
    mono = font("/System/Library/Fonts/Menlo.ttc", 11 * scale)
    sans = font("/System/Library/Fonts/HelveticaNeue.ttc", 13 * scale)
    # Faint slash grid, same texture as the website hero.
    cw, rh = 9 * scale, 16 * scale
    for y in range(0, H * scale, rh):
        for x in range(0, W * scale, cw):
            h = ((x // cw) * 374761393 + (y // rh) * 668265263) & 0xFFFFFFFF
            h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
            if (h >> 16) % 100 > 55:
                d.text((x, y), "/", fill=(31, 31, 36), font=mono)
    # Arrow from the app slot (165, 190) to Applications (495, 190).
    y = 190 * scale
    d.line([(250 * scale, y), (405 * scale, y)], fill=(10, 132, 255), width=2 * scale)
    d.polygon([(410 * scale, y), (398 * scale, y - 7 * scale), (398 * scale, y + 7 * scale)], fill=(10, 132, 255))
    text = "Drag Jerox into Applications"
    tw = d.textlength(text, font=sans)
    d.text(((W * scale - tw) / 2, 318 * scale), text, fill=(161, 161, 170), font=sans)
    return im


draw(1).save("installer/bg.png")
draw(2).save("installer/bg@2x.png")
subprocess.run(["tiffutil", "-cathidpicheck", "installer/bg.png", "installer/bg@2x.png", "-out", "installer/dmg-background.tiff"], check=True)
os.remove("installer/bg.png")
os.remove("installer/bg@2x.png")
