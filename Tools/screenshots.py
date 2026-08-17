#!/usr/bin/env python3
"""Composites simulator captures into App Store listing images.

Flat ground, one device, caption above. No gradients, no glow, no angled
devices, no badges. Output is RGB with no alpha at the exact sizes App Store
Connect requires — it rejects alpha silently, so this checks rather than trusts.

Captions never state a number. Every number a reviewer or a customer sees is
inside the screenshot, produced by the engine from the real photograph, so
swapping the source photo cannot turn a caption into a false claim.
"""
import os
import sys
from PIL import Image, ImageDraw, ImageFont

RAW = sys.argv[1]
OUT = sys.argv[2]

BG = (237, 237, 242)
INK = (13, 13, 15)
BEZEL = (16, 16, 19)
SF = "/System/Library/Fonts/SFNS.ttf"


def font(size):
    f = ImageFont.truetype(SF, size)
    try:
        f.set_variation_by_name("Bold")
    except Exception:
        pass
    return f


SPECS = {
    "iPhone-6.9-inch_1320x2868": dict(canvas=(1320, 2868), prefix="iphone", cap=94,
                                      top=150, gap=100, device_w=1044, radius=100,
                                      bezel=16, bottom=120),
    "iPad-13-inch_2064x2752": dict(canvas=(2064, 2752), prefix="ipad", cap=104,
                                   top=165, gap=110, device_w=1580, radius=64,
                                   bezel=20, bottom=130),
}

SHOTS = [
    ("01-result", "done", ["Every requirement,", "met."]),
    ("02-crop", "crop", ["You place the crop.", "Not us."]),
    ("03-destinations", "nz", ["The form's numbers,", "read off its own page."]),
    ("04-refusal", "failure", ["It tells you when", "it can't."]),
    ("05-private", "home", ["No account. No upload.", "No subscription."]),
]


def rounded_mask(size, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return m


made, missing = [], []
for folder, spec in SPECS.items():
    for name, source, lines in SHOTS:
        src = os.path.join(RAW, "%s-%s.png" % (spec["prefix"], source))
        if not os.path.exists(src):
            missing.append(os.path.join(folder, name))
            continue
        shot = Image.open(src).convert("RGB")

        W, H = spec["canvas"]
        canvas = Image.new("RGB", (W, H), BG)
        draw = ImageDraw.Draw(canvas)

        f = font(spec["cap"])
        line_h = int(spec["cap"] * 1.24)
        y = spec["top"]
        for line in lines:
            w = draw.textlength(line, font=f)
            draw.text(((W - w) / 2, y), line, font=f, fill=INK)
            y += line_h

        top = y + spec["gap"]
        avail = H - top - spec["bottom"]
        aspect = shot.width / shot.height
        dev_w = spec["device_w"]
        dev_h = int(dev_w / aspect)
        if dev_h > avail:
            dev_h = avail
            dev_w = int(dev_h * aspect)
        dx, dy = (W - dev_w) // 2, top

        draw.rounded_rectangle([dx, dy, dx + dev_w, dy + dev_h],
                               radius=spec["radius"], fill=BEZEL)
        b = spec["bezel"]
        inner = (dev_w - 2 * b, dev_h - 2 * b)
        screen = shot.resize(inner, Image.LANCZOS)
        canvas.paste(screen, (dx + b, dy + b),
                     rounded_mask(inner, max(2, spec["radius"] - b)))

        os.makedirs(os.path.join(OUT, folder), exist_ok=True)
        dest = os.path.join(OUT, folder, name + ".png")
        canvas.save(dest, "PNG")   # RGB in, so no alpha out
        made.append(dest)

for m in made:
    print("made    ", m.replace(OUT + "/", ""))
for m in missing:
    print("MISSING ", m)
