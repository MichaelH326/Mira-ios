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

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SIZE = 1024
SS = 4                      # supersample factor
W = SIZE * SS

OUT = os.path.join(os.path.dirname(__file__), "..", "ios", "Mira",
                   "Assets.xcassets", "AppIcon.appiconset", "icon-1024.png")

# The butter theme, which is the app's default. One hue: the field is the
# accent, she is the pale end of it, her hair the deep end.
FIELD = (66, 134, 199)
FUR_LIGHT = (250, 253, 255)
FUR_MID = (188, 221, 246)
FUR_DEEP = (82, 150, 210)
FUR_BACK = (146, 186, 222)  # the under-ring: furMid darkened, not faded
EYE = (37, 47, 62)
CHEEK = (255, 156, 157)

# She fills more of the tile than she does of the screen. An icon is looked at
# for a fraction of a second at 40 points across, so the shape has to be
# unmistakable before any detail registers.
CENTRE = (W / 2, W * 0.560)
RADIUS = W * 0.300
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


# Hair covers her: tufts ring the whole silhouette, not a fringe on a bald
# head. Two rings offset by half a step so the under one shows between the
# tufts of the top one. Generated exactly as `MiraFace.ring` does.
def hashed(value):
    """The deterministic 0..1 `MiraFace.hashed` uses, so the rings match."""
    x = math.sin(value * 12.9898) * 43758.5453
    return x - math.floor(x)


def ring(count, seed, phase, root, length, width):
    """One layer of the coat. Mirrors `MiraFace.ring`."""
    out = []
    for index in range(count):
        step = 1 / count
        turn = (index + phase) * step - 0.5
        h1, h2 = hashed(index * 1.7 + seed), hashed(index * 4.1 + seed)
        # 1 at the crown, 0 underneath: long on top, short below, which is
        # most of what stops a ring of spikes reading as a sea urchin. The
        # hash term is the largest of the three — an evenly stepped ring of
        # equal spikes reads as a gear however soft the tips are.
        crown = (math.cos(turn * 2 * math.pi) + 1) / 2
        scale = 0.55 + crown * 0.25 + h1 * 0.60
        lean = (0.004 + h2 * 0.010) * (-1 if turn < 0 else 1)
        # Root jittered, or every tip in a ring lands on a circle and five
        # rings read as a dahlia. Width wide relative to length, or each tuft
        # is a petal rather than fur. See `MiraFace.ring`.
        out.append((turn, root, length * scale,
                    step * (width + h2 * 0.22), lean))
    return out


# She is made of hair all the way in: concentric rings from near her centre
# out past the rim, each long enough to reach across the next, so there is no
# smooth ground anywhere. (tufts, shade) — shade 0 is the pale inner colour,
# 1 the full pastel.
# Every ring is the same colour — she is one flat pastel, top to bottom. What
# tells the layers apart is shading, not hue: each drops a blurred shadow on
# the one beneath before it is filled, and one gradient over the whole mass
# gives her form.
COATS = [
    ring(12, 0, 0.00, 0.20, 0.34, 0.34),
    ring(16, 300, 0.35, 0.38, 0.34, 0.34),
    ring(20, 600, 0.15, 0.55, 0.33, 0.34),
    ring(24, 900, 0.45, 0.70, 0.33, 0.34),
    ring(28, 1200, 0.20, 0.84, 0.34, 0.34),
]
UNDER_COAT = ring(22, 1900, 0.5, 0.80, 0.32, 0.34)

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


def tuft_polygon(turn, root, length, width, lean):
    """One soft spike: curved sides, blunt tip. See `MiraFace.hair`."""
    axis = turn * TAU - math.pi / 2
    left_base, right_base = axis - width * TAU, axis + width * TAU
    tip_axis = axis + lean * TAU

    left_r, right_r = rim(left_base) * root, rim(right_base) * root
    tip_r = rim(tip_axis) * (root + length)

    left, right = at(left_base, left_r), at(right_base, right_r)
    spread = width * 0.30 * TAU
    tip_a, tip_b = at(tip_axis - spread, tip_r), at(tip_axis + spread, tip_r)
    bow = 0.55
    ctrl_a = at(left_base - width * 0.6 * TAU, left_r + (tip_r - left_r) * bow)
    ctrl_b = at(right_base + width * 0.6 * TAU, right_r + (tip_r - right_r) * bow)

    return (quad(left, ctrl_a, tip_a)
            + quad(tip_a, at(tip_axis, tip_r * 1.03), tip_b)
            + quad(tip_b, ctrl_b, right))


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


def diagonal_ramp(dx, dy, small=96):
    """0 where the light comes from, 255 opposite, along (dx, dy).

    Built small and scaled up. Rotating PIL's own linear_gradient leaves its
    corners filled with a constant, and those corners land on the icon as
    patches of flat shading.
    """
    ramp = Image.new("L", (small, small))
    pixels = ramp.load()
    length = math.hypot(dx, dy) or 1
    ux, uy = dx / length, dy / length
    for y in range(small):
        for x in range(small):
            # Projection onto the light direction, remapped to 0..1.
            t = ((x / small - 0.5) * ux + (y / small - 0.5) * uy) + 0.5
            pixels[x, y] = max(0, min(255, int((1 - t) * 255)))
    return ramp.resize((W, W), Image.BICUBIC)


def main():
    icon = Image.new("RGB", (W, W), FIELD)

    # A soft lift in the upper left, so the field is not a flat rectangle.
    glow_mask = Image.new("L", (W, W), 0)
    ImageDraw.Draw(glow_mask).ellipse(
        [-W * 0.25, -W * 0.35, W * 0.85, W * 0.55], fill=255)
    glow_mask = glow_mask.filter(ImageFilter.GaussianBlur(W * 0.06))
    icon = Image.alpha_composite(icon.convert("RGBA"),
                                 tinted(glow_mask, (255, 255, 255), 48))

    # The far side of the coat: darker, offset half a step so it shows
    # between the tufts in front.
    back = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    bd = ImageDraw.Draw(back)
    for t in UNDER_COAT:
        bd.polygon(tuft_polygon(*t), fill=FUR_BACK + (255,))
    icon = Image.alpha_composite(icon, back)

    # The ground, in the same colour as the coat. Not the body — every part
    # of it ends up under a tuft; it is only here so no field shows through.
    ground = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(ground).polygon(blob_points(scale=0.90), fill=FUR_MID + (255,))
    icon = Image.alpha_composite(icon, ground)

    # The coat, innermost ring first, every ring the same colour. What
    # separates them is the shadow each drops on the one beneath: the same
    # tufts, blurred, darkened and offset down and right, drawn just before
    # the ring itself so only the part past its own edges survives.
    for tufts in COATS:
        shadow = Image.new("L", (W, W), 0)
        sd = ImageDraw.Draw(shadow)
        for t in tufts:
            sd.polygon(tuft_polygon(*t), fill=255)
        shadow = shadow.filter(ImageFilter.GaussianBlur(RADIUS * 0.05))
        shadow = ImageChops.offset(shadow, int(RADIUS * 0.035), int(RADIUS * 0.05))
        icon = Image.alpha_composite(icon, tinted(shadow, FUR_DEEP, 140))

        layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
        ld = ImageDraw.Draw(layer)
        for t in tufts:
            ld.polygon(tuft_polygon(*t), fill=FUR_MID + (255,))
        icon = Image.alpha_composite(icon, layer)

    # One shading pass over the whole of her, and the only thing giving her
    # form: the coat is a single flat colour, so without this she is a
    # silhouette. Light from the upper left, deepening to the lower right.
    #
    # Masked to the rim and not past it. A mask wider than the fur actually
    # reaches darkens bare field around her, which reads as a smudge behind
    # her rather than shading on her — and leaving the tips beyond the rim
    # unshaded is what makes them look backlit.
    mass = Image.new("L", (W, W), 0)
    ImageDraw.Draw(mass).polygon(blob_points(), fill=255)

    ramp = Image.composite(diagonal_ramp(-0.62, -0.78),
                           Image.new("L", (W, W), 0), mass)
    icon = Image.alpha_composite(icon, tinted(ramp, FUR_DEEP, 150))

    lit_mask = Image.new("L", (W, W), 0)
    ImageDraw.Draw(lit_mask).ellipse(
        [CENTRE[0] - RADIUS * 0.98, CENTRE[1] - RADIUS * 1.05,
         CENTRE[0] + RADIUS * 0.27, CENTRE[1] + RADIUS * 0.15], fill=255)
    lit_mask = lit_mask.filter(ImageFilter.GaussianBlur(RADIUS * 0.26))
    lit_mask = Image.composite(lit_mask, Image.new("L", (W, W), 0), mass)
    icon = Image.alpha_composite(icon, tinted(lit_mask, FUR_LIGHT, 155))

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
