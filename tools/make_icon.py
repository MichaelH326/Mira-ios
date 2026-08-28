#!/usr/bin/env python3
"""Draw Mira as the app icon.

The icon is a picture of the mascot, so it has to be the *same* mascot — the
same three-harmonic silhouette, the same soft-spike hair, the same eyes. This
redraws it from the same constants rather than tracing a screenshot, so
changing `MiraFace.swift` and re-running this keeps them in step. Anything you
change in one is worth changing in the other.

Everything is drawn at 4x and downsampled at the end: PIL has no
anti-aliasing, and a supersample is both the simplest fix and the one that
handles the fur strands as well as it handles the outline.

    python3 tools/make_icon.py

Writes ios/Mira/Assets.xcassets/AppIcon.appiconset/icon-1024.png. iOS 17 wants
one 1024x1024 image and derives the rest, and the corner radius and mask come
from the system — so this draws full-bleed and square.
"""

import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SS = 4                      # supersample factor
W = SIZE * SS

OUT = os.path.join(os.path.dirname(__file__), "..", "ios", "Mira",
                   "Assets.xcassets", "AppIcon.appiconset", "icon-1024.png")

# The butter theme, which is the app's default. One hue: the field is the
# accent, she is the pale end of it, her hair the deep end.
FIELD = (109, 172, 224)
FUR_LIGHT = (250, 253, 255)
FUR_MID = (188, 221, 246)
FUR_DEEP = (82, 150, 210)
FUR_BACK = (66, 120, 168)   # the hair behind her: furDeep darkened, not faded
EYE = (37, 47, 62)
CHEEK = (255, 156, 157)

# She fills more of the tile than she does of the screen. An icon is looked at
# for a fraction of a second at 40 points across, so the shape has to be
# unmistakable before any detail registers.
CENTRE = (W / 2, W * 0.560)
RADIUS = W * 0.315
CHURN = 1.35                # a fixed moment of the animation, chosen for shape


def deviation(angle):
    """The same three harmonics `MiraFace.deviation` uses."""
    return (0.072 * math.sin(2 * angle + CHURN)
            + 0.046 * math.sin(3 * angle - CHURN * 1.3)
            + 0.021 * math.sin(5 * angle + CHURN * 0.7))


def rim(angle, wobble=0.55):
    return RADIUS * (1 + wobble * deviation(angle))


def at(angle, r):
    return (CENTRE[0] + math.cos(angle) * r, CENTRE[1] + math.sin(angle) * r)


def blob_points(scale=1.0, samples=240):
    return [at(a, rim(a) * scale)
            for a in (i / samples * 2 * math.pi for i in range(samples))]


# Tuft(turn, length, width, lean) — turns clockwise from straight up, matching
# `MiraFace.Tuft`. The back set shows past her sides; the front set rises out
# of the hairline.
BACK_TUFTS = [
    (-0.105, 0.17, 0.018, -0.010),
    (-0.045, 0.19, 0.017, -0.004),
    (0.045, 0.19, 0.017, 0.004),
    (0.105, 0.17, 0.018, 0.010),
]
FRONT_TUFTS = [
    (-0.125, 0.12, 0.016, -0.008),
    (-0.094, 0.22, 0.015, -0.006),
    (-0.063, 0.17, 0.015, -0.004),
    (-0.031, 0.30, 0.016, -0.002),
    (0.000, 0.20, 0.015, 0.001),
    (0.031, 0.27, 0.016, 0.003),
    (0.063, 0.16, 0.015, 0.005),
    (0.094, 0.24, 0.015, 0.008),
    (0.125, 0.11, 0.016, 0.012),
]
HAIRLINE_REACH = 0.135

TAU = 2 * math.pi


def quad(p0, p1, p2, steps=24):
    """A quadratic bezier as points; PIL only draws polygons."""
    out = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        out.append((u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0],
                    u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1]))
    return out


def tuft_polygon(turn, length, width, lean):
    """One soft spike: curved sides, blunt tip. See `MiraFace.hair`."""
    axis = turn * TAU - math.pi / 2
    left_base, right_base = axis - width * TAU, axis + width * TAU
    tip_axis = axis + lean * TAU

    root = 0.86
    left_r, right_r = rim(left_base) * root, rim(right_base) * root
    tip_r = rim(tip_axis) * (1 + length)

    left, right = at(left_base, left_r), at(right_base, right_r)
    spread = width * 0.30 * TAU
    tip_a, tip_b = at(tip_axis - spread, tip_r), at(tip_axis + spread, tip_r)
    bow = 0.55
    ctrl_a = at(left_base - width * 0.6 * TAU, left_r + (tip_r - left_r) * bow)
    ctrl_b = at(right_base + width * 0.6 * TAU, right_r + (tip_r - right_r) * bow)

    return (quad(left, ctrl_a, tip_a)
            + quad(tip_a, at(tip_axis, tip_r * 1.03), tip_b)
            + quad(tip_b, ctrl_b, right))


def hairline_polygon(samples=80):
    """The solid mass the spikes grow out of. See `MiraFace.hairline`."""
    reach = HAIRLINE_REACH
    outer, inner = [], []
    for i in range(samples + 1):
        turn = -reach + i / samples * reach * 2
        angle = turn * TAU - math.pi / 2
        outer.append(at(angle, rim(angle) * 1.035))
        # Tapers to nothing at both ends; a constant thickness leaves blunt
        # stubs that read as a hat brim. See `MiraFace.hairline`.
        centreness = math.cos(turn / reach * math.pi / 2) ** 0.6
        inner.append(at(angle, rim(angle) * (1.035 - centreness * 0.335)))
    return outer + inner[::-1]


def hashed(value):
    """The deterministic 0..1 `MiraFace.noise` uses, so the fluff matches."""
    x = math.sin(value * 12.9898) * 43758.5453
    return x - math.floor(x)


def tinted(mask, colour, strength=255):
    """A solid colour worn through an alpha mask.

    Everything soft here is built this way rather than by blurring an RGBA
    layer. PIL blurs the colour channels independently of alpha, so a blurred
    transparent layer drags RGB out of the transparent-black pixels around the
    shape — which showed up as grey scratches under her. Blurring an `L` mask
    and pouring a uniform colour through it cannot do that.
    """
    layer = Image.new("RGBA", mask.size, colour + (0,))
    layer.putalpha(mask.point(lambda v: v * strength // 255))
    return layer


def soft_edge(scale, blur, strength):
    """A blurred copy of her whole silhouette, for the fluff behind her."""
    mask = Image.new("L", (W, W), 0)
    ImageDraw.Draw(mask).polygon(blob_points(scale=scale), fill=255)
    return tinted(mask.filter(ImageFilter.GaussianBlur(blur)), FUR_LIGHT, strength)


def soft_rim(width, blur, strength):
    """A blurred ring on her outline, for the fluff drawn over her.

    A ring and not a disc: a blurred filled silhouette is opaque through the
    middle, so composited on top of her it repaints her face as well as her
    edge — which is what had turned the pastel white.
    """
    mask = Image.new("L", (W, W), 0)
    ring = blob_points()
    ImageDraw.Draw(mask).line(ring + [ring[0]], fill=255,
                              width=int(width), joint="curve")
    return tinted(mask.filter(ImageFilter.GaussianBlur(blur)), FUR_LIGHT, strength)


def main():
    icon = Image.new("RGB", (W, W), FIELD)

    # A soft lift in the upper left, so the field is not a flat rectangle.
    glow_mask = Image.new("L", (W, W), 0)
    ImageDraw.Draw(glow_mask).ellipse(
        [-W * 0.25, -W * 0.35, W * 0.85, W * 0.55], fill=255)
    glow_mask = glow_mask.filter(ImageFilter.GaussianBlur(W * 0.06))
    icon = Image.alpha_composite(icon.convert("RGBA"),
                                 tinted(glow_mask, (255, 255, 255), 48))

    # Hair behind her, then fur, then the body, then hair in front.
    back = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    bd = ImageDraw.Draw(back)
    for t in BACK_TUFTS:
        bd.polygon(tuft_polygon(*t), fill=FUR_BACK + (255,))
    icon = Image.alpha_composite(icon, back)

    # Two soft fringes rather than drawn strands, widest and faintest first.
    icon = Image.alpha_composite(icon, soft_edge(1.13, RADIUS * 0.10, 70))
    icon = Image.alpha_composite(icon, soft_edge(1.06, RADIUS * 0.05, 130))

    body = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(body).polygon(blob_points(), fill=FUR_MID + (255,))
    icon = Image.alpha_composite(icon, body)

    # The lit side: a pale ellipse up and to the left, blurred and clipped to
    # the body — the radial gradient the app draws. Partial alpha, because at
    # full strength it repaints her white and the pastel is the point.
    mask = Image.new("L", (W, W), 0)
    ImageDraw.Draw(mask).polygon(blob_points(), fill=255)

    lit_mask = Image.new("L", (W, W), 0)
    lx, ly = CENTRE[0] - RADIUS * 0.30, CENTRE[1] - RADIUS * 0.38
    ImageDraw.Draw(lit_mask).ellipse(
        [lx - RADIUS * 0.62, ly - RADIUS * 0.62, lx + RADIUS * 0.62, ly + RADIUS * 0.62],
        fill=255)
    lit_mask = lit_mask.filter(ImageFilter.GaussianBlur(RADIUS * 0.32))
    lit_mask = Image.composite(lit_mask, Image.new("L", (W, W), 0), mask)
    icon = Image.alpha_composite(icon, tinted(lit_mask, FUR_LIGHT, 150))

    # And a ring on the rim itself, which is what keeps the edge from
    # resolving into a hard line.
    icon = Image.alpha_composite(icon, soft_rim(RADIUS * 0.06, RADIUS * 0.032, 85))

    front = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    fd = ImageDraw.Draw(front)
    fd.polygon(hairline_polygon(), fill=FUR_DEEP + (255,))
    for t in FRONT_TUFTS:
        fd.polygon(tuft_polygon(*t), fill=FUR_DEEP + (255,))
    icon = Image.alpha_composite(icon, front)

    # The shadow the hair casts, so it grows out of her rather than sitting on.
    shade_mask = Image.new("L", (W, W), 0)
    ImageDraw.Draw(shade_mask).ellipse(
        [CENTRE[0] - RADIUS * 0.62, CENTRE[1] - RADIUS * 0.98,
         CENTRE[0] + RADIUS * 0.62, CENTRE[1] - RADIUS * 0.58], fill=255)
    shade_mask = shade_mask.filter(ImageFilter.GaussianBlur(RADIUS * 0.11))
    shade_mask = Image.composite(shade_mask, Image.new("L", (W, W), 0), mask)
    icon = Image.alpha_composite(icon, tinted(shade_mask, FUR_DEEP, 80))

    # Blush.
    cheek_mask = Image.new("L", (W, W), 0)
    cd = ImageDraw.Draw(cheek_mask)
    for side in (-1, 1):
        cw, ch = RADIUS * 0.32, RADIUS * 0.18
        cx = CENTRE[0] + side * RADIUS * 0.52
        cy = CENTRE[1] + RADIUS * 0.35
        cd.ellipse([cx - cw / 2, cy - ch / 2, cx + cw / 2, cy + ch / 2], fill=255)
    cheek_mask = cheek_mask.filter(ImageFilter.GaussianBlur(RADIUS * 0.06))
    icon = Image.alpha_composite(icon, tinted(cheek_mask, CHEEK, 100))

    # Eyes.
    eyes = ImageDraw.Draw(icon)
    ew, eh = RADIUS * 0.30, RADIUS * 0.41
    for side in (-1, 1):
        ex = CENTRE[0] + side * RADIUS * 0.32
        ey = CENTRE[1] + RADIUS * 0.02
        eyes.rounded_rectangle([ex - ew / 2, ey - eh / 2, ex + ew / 2, ey + eh / 2],
                               radius=ew / 2, fill=EYE + (255,))
        iris = ew * 0.62
        ix, iy = ex, ey + eh * 0.10
        eyes.ellipse([ix - iris / 2, iy - iris / 2, ix + iris / 2, iy + iris / 2],
                     fill=(96, 165, 226, 255))
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
    random.seed(0)
    main()
