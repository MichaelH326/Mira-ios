#!/usr/bin/env python3
"""Draw Mira as the app icon.

The icon is a picture of the mascot, so it has to be the *same* mascot — the
same three-harmonic silhouette, the same bands of curved fur strands, the same
eyes. This redraws it from the same constants rather than tracing a
screenshot, so changing `MiraFace.swift` and re-running this keeps them in
step. Anything you change in one is worth changing in the other.

    python3 tools/make_icon.py          # needs pillow

Writes ios/Mira/Assets.xcassets/AppIcon.appiconset/icon-1024.png. iOS 17 wants
one 1024x1024 image and derives the rest, and the corner radius and mask come
from the system — so this draws full-bleed and square.

Everything is drawn at 4x and downsampled at the end: PIL has no
anti-aliasing, and a supersample is both the simplest fix and the one that
handles the fur strands as well as it handles the outline.
"""

import math
import os

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SS = 4                      # supersample factor
W = SIZE * SS

OUT = os.path.join(os.path.dirname(__file__), "..", "ios", "Mira",
                   "Assets.xcassets", "AppIcon.appiconset", "icon-1024.png")

# Her own three creams, straight out of `MiraFace`, on a field taken from the
# butter theme's accent. Blue behind cream is the most contrast the app's own
# palette offers, which is what an icon needs.
FIELD = (120, 178, 228)
CORE = (255, 252, 248)
MID = (255, 239, 224)
EDGE = (254, 218, 196)
EYE = (37, 47, 62)
CHEEK = (255, 156, 157)
IRIS_LIGHT = (140, 192, 235)
IRIS_DEEP = (52, 122, 180)

# She fills more of the tile than she does of the screen. An icon is looked at
# for a fraction of a second at 40 points across, so the shape has to be
# unmistakable before any detail registers.
CENTRE = (W / 2, W * 0.545)
RADIUS = W * 0.285
CHURN = 1.35                # a fixed moment of the animation, chosen for shape
WOBBLE = 0.42               # her resting deviation from a circle
TAU = 2 * math.pi


def deviation(angle):
    """The same three harmonics `MiraFace.deviation` uses."""
    return (0.072 * math.sin(2 * angle + CHURN)
            + 0.046 * math.sin(3 * angle - CHURN * 1.3)
            + 0.021 * math.sin(5 * angle + CHURN * 0.7))


def rim(angle):
    return RADIUS * (1 + WOBBLE * deviation(angle))


def at(angle, r):
    return (CENTRE[0] + math.cos(angle) * r, CENTRE[1] + math.sin(angle) * r)


def blob_points(scale=1.0, samples=240):
    return [at(a, rim(a) * scale)
            for a in (i / samples * TAU for i in range(samples))]


def hashed(value):
    """The deterministic 0..1 `MiraFace.noise` uses, so the fluff matches."""
    x = math.sin(value * 12.9898) * 43758.5453
    return x - math.floor(x)


def quad(p0, p1, p2, steps=16):
    """A quadratic bezier as points; PIL draws polylines, not curves."""
    out = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        out.append((u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0],
                    u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1]))
    return out


def tinted(mask, colour, strength=255):
    """A solid colour worn through an alpha mask.

    Everything soft here is built this way rather than by blurring an RGBA
    layer. PIL blurs the colour channels independently of alpha, so a blurred
    transparent layer drags RGB out of the transparent-black pixels around the
    shape — which showed up as grey scratches across her. Blurring an `L` mask
    and pouring a uniform colour through it cannot do that.
    """
    layer = Image.new("RGBA", mask.size, colour + (0,))
    layer.putalpha(mask.point(lambda v: v * strength // 255))
    return layer


# (count, min/max length, min/max width, min/max alpha, blur, curl, seed) —
# `MiraFace.furLayers` and `MiraFace.topFuzz`, unchanged. Furthest out is
# longest, widest, faintest and most blurred; closest in is short, dense and
# nearly sharp.
FUR_BANDS = [
    (90, 0.13, 0.24, 3.0, 6.0, 0.10, 0.24, 6.0, 0.34, 0),
    (130, 0.07, 0.15, 2.2, 4.2, 0.20, 0.40, 2.6, 0.24, 500),
    (150, 0.035, 0.085, 1.6, 3.0, 0.28, 0.52, 1.0, 0.16, 1000),
]
TOP_FUZZ = (110, 0.03, 0.075, 1.8, 3.4, 0.30, 0.55, 1.6, 0.20, 2000)


def fur_band(band):
    """One band of strands, as an RGBA layer.

    Two alpha masks rather than one: the strands alternate between the pale
    cream and the peach, and a mask can only carry one colour. Mirrors
    `MiraFace.fur`.
    """
    (count, min_len, max_len, min_w, max_w,
     min_a, max_a, blur, curl, seed_offset) = band

    masks = {CORE: Image.new("L", (W, W), 0), EDGE: Image.new("L", (W, W), 0)}
    draws = {tint: ImageDraw.Draw(mask) for tint, mask in masks.items()}

    for index in range(count):
        seed = index + seed_offset
        jitter = (hashed(seed) - 0.5) * 0.09
        angle = index / count * TAU + jitter
        edge = rim(angle)

        length = RADIUS * (min_len + hashed(seed * 3.1) * (max_len - min_len))
        inner = edge * (0.90 + hashed(seed * 7.7) * 0.07)
        outer = edge + length

        # The strand bends: its tip sits at a different angle from its root.
        # That curve is what separates fluff from a spine.
        bend = (hashed(seed * 4.3) - 0.5) * curl
        start = at(angle, inner)
        mid = at(angle + bend * 0.35, (inner + outer) / 2)
        tip = at(angle + bend, outer)

        tint = CORE if hashed(seed * 2.3) > 0.42 else EDGE
        alpha = int((min_a + hashed(seed * 5.9) * (max_a - min_a)) * 255)
        wide = min_w + hashed(seed * 1.7) * (max_w - min_w)
        draws[tint].line(quad(start, mid, tip), fill=alpha,
                         width=max(1, int(wide * SS)), joint="curve")

    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    for tint, mask in masks.items():
        mask = mask.filter(ImageFilter.GaussianBlur(blur * SS))
        layer = Image.alpha_composite(layer, tinted(mask, tint))
    return layer


def main():
    icon = Image.new("RGBA", (W, W), FIELD + (255,))

    # A soft lift in the upper left, so the field is not a flat rectangle.
    glow = Image.new("L", (W, W), 0)
    ImageDraw.Draw(glow).ellipse([-W * 0.25, -W * 0.35, W * 0.85, W * 0.55],
                                 fill=255)
    glow = glow.filter(ImageFilter.GaussianBlur(W * 0.06))
    icon = Image.alpha_composite(icon, tinted(glow, (255, 255, 255), 52))

    body_mask = Image.new("L", (W, W), 0)
    ImageDraw.Draw(body_mask).polygon(blob_points(), fill=255)

    # Fur behind the body, widest and faintest band first.
    for band in FUR_BANDS:
        icon = Image.alpha_composite(icon, fur_band(band))

    # The body: the app draws a radial gradient from core through mid to edge,
    # offset up and left. PIL has no radial gradient, so it is three clipped
    # layers — flat edge, then a broad mid, then a tight core.
    icon = Image.alpha_composite(icon, tinted(body_mask, EDGE))
    lx, ly = CENTRE[0] - RADIUS * 0.22, CENTRE[1] - RADIUS * 0.30
    for spread, blur, tint in ((0.95, 0.35, MID), (0.42, 0.30, CORE)):
        lit = Image.new("L", (W, W), 0)
        ImageDraw.Draw(lit).ellipse(
            [lx - RADIUS * spread, ly - RADIUS * spread,
             lx + RADIUS * spread, ly + RADIUS * spread], fill=255)
        lit = lit.filter(ImageFilter.GaussianBlur(RADIUS * blur))
        lit = Image.composite(lit, Image.new("L", (W, W), 0), body_mask)
        icon = Image.alpha_composite(icon, tinted(lit, tint))

    # The softest edge: a blurred rim inside the silhouette, which is what
    # stops it reading as a hard vector shape.
    ring = blob_points()
    soft = Image.new("L", (W, W), 0)
    ImageDraw.Draw(soft).line(ring + [ring[0]], fill=255,
                              width=int(RADIUS * 0.09), joint="curve")
    soft = soft.filter(ImageFilter.GaussianBlur(RADIUS * 0.035))
    icon = Image.alpha_composite(icon, tinted(soft, EDGE, 215))

    # A last pass over the rim. Fur behind the body alone leaves a clean arc
    # where the fill ends; these break it.
    icon = Image.alpha_composite(icon, fur_band(TOP_FUZZ))

    # Blush.
    cheeks = Image.new("L", (W, W), 0)
    cd = ImageDraw.Draw(cheeks)
    for side in (-1, 1):
        cw, ch = RADIUS * 0.32, RADIUS * 0.18
        cx, cy = CENTRE[0] + side * RADIUS * 0.56, CENTRE[1] + RADIUS * 0.41
        cd.ellipse([cx - cw / 2, cy - ch / 2, cx + cw / 2, cy + ch / 2], fill=255)
    cheeks = cheeks.filter(ImageFilter.GaussianBlur(RADIUS * 0.06))
    icon = Image.alpha_composite(icon, tinted(cheeks, CHEEK, 100))

    # Eyes.
    eyes = ImageDraw.Draw(icon)
    ew, eh = RADIUS * 0.38, RADIUS * 0.54
    for side in (-1, 1):
        ex = CENTRE[0] + side * RADIUS * 0.35
        ey = CENTRE[1] - RADIUS * 0.01
        eyes.rounded_rectangle([ex - ew / 2, ey - eh / 2, ex + ew / 2, ey + eh / 2],
                               radius=ew / 2, fill=EYE + (255,))
        # The app gives the iris a light-to-dark gradient; at icon size that
        # is a single mid tone, and faking it with two circles only made it
        # lopsided.
        iris = ew * 0.62
        iy = ey + eh * 0.10
        eyes.ellipse([ex - iris / 2, iy - iris / 2, ex + iris / 2, iy + iris / 2],
                     fill=tuple((a + b) // 2 for a, b in zip(IRIS_LIGHT, IRIS_DEEP))
                          + (255,))
        big = ew * 0.34
        bx, by = ex - ew * 0.26 + big / 2, ey - eh * 0.26 + big / 2
        eyes.ellipse([bx - big / 2, by - big / 2, bx + big / 2, by + big / 2],
                     fill=(255, 255, 255, 255))
        small = ew * 0.17
        sx, sy = ex + ew * 0.14 + small / 2, ey + eh * 0.18 + small / 2
        eyes.ellipse([sx - small / 2, sy - small / 2, sx + small / 2, sy + small / 2],
                     fill=(255, 255, 255, 190))

    icon = icon.convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    icon.save(OUT, "PNG")
    print("wrote", os.path.normpath(OUT))


if __name__ == "__main__":
    main()
