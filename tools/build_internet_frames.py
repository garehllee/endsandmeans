#!/usr/bin/env python3
"""Splits the internet minigame spritesheet into per-phase frames for Godot.

Run from the project root:  python3 tools/build_internet_frames.py
The big source images live in art_source/ (it has a .gdignore so Godot skips it).

Why: the sheet is 9246x32768, far too big to load as one texture (web builds
usually cap textures at 8192-16384 px). This writes small per-frame PNGs to
art/internet/frames/ plus a manifest the game reads.

Sheet layout (8 columns x 30 rows, read left to right, top to bottom). A red
"<- label" cell ends each section:
    0-55     loop 1            (56 frames)
    56       marker
    57-112   loop 1 hover      (56 frames; stored in a shuffled order, matched
                                back to loop 1 by image similarity)
    113      marker
    114-149  transition        (36 frames)
    150      marker
    151-199  click frames      (49 frames)
    200      marker
    201-236  outro             (36 frames)
    237      marker
"""
import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

Image.MAX_IMAGE_PIXELS = None

SHEET = "art_source/internet/internet-spritesheet.png"
OUT = "art/internet/frames"
COLS, ROWS = 8, 30
OUT_W, OUT_H = 800, 756          # output frame size (the sheet's frames are ~1156x1092)
SECTIONS = {"loop": (0, 56), "hover": (57, 56), "transition": (114, 36),
            "click": (151, 49), "outro": (201, 36)}
MARKERS = [56, 113, 150, 200, 237]
HOVER_THRESHOLD = 60             # summed RGB difference that counts as "highlighted"
HOVER_MARGIN = 6


def main() -> int:
    os.makedirs(OUT, exist_ok=True)
    sheet = Image.open(SHEET).convert("RGB")
    W, H = sheet.size
    fw, fh = W / COLS, H / ROWS

    def cell(i: int) -> Image.Image:
        r, c = divmod(i, COLS)
        box = (round(c * fw), round(r * fh), round((c + 1) * fw), round((r + 1) * fh))
        return sheet.crop(box).resize((OUT_W, OUT_H), Image.LANCZOS)

    # Sanity check: the markers should sit where we think they do.
    for m in MARKERS:
        a = np.array(cell(m))
        if not ((a[..., 0] > 240).mean() > 0.5 and (a[..., 1] < 30).mean() > 0.5):
            print(f"warning: cell {m} does not look like a red marker; the sheet layout may have changed")

    manifest = {"frame": [OUT_W, OUT_H]}
    for name in ("loop", "transition", "click", "outro"):
        start, n = SECTIONS[name]
        manifest[name] = n
        for k in range(n):
            cell(start + k).save(f"{OUT}/{name}_{k:03d}.png", optimize=True)
        print(name, n, "frames")

    # Hover frames come in a different order from the loop, so match each one to
    # the loop frame it belongs with, then keep only the highlighted computer.
    loop = [np.array(cell(i)).astype(int) for i in range(SECTIONS["loop"][1])]
    hover_start, hover_n = SECTIONS["hover"]
    small = lambda a: a[::4, ::4]
    loop_small = [small(a) for a in loop]
    match = {}
    for k in range(hover_n):
        h = np.array(cell(hover_start + k)).astype(int)
        d = [np.abs(small(h) - ls).mean() for ls in loop_small]
        j = int(np.argmin(d))
        if j in match:
            print(f"error: loop frame {j} matched by two hover frames; check the sheet")
            return 1
        match[j] = (k, h)
    print("hover frames matched:", len(match))

    hover = {}
    for j, (k, h) in sorted(match.items()):
        diff = np.abs(h - loop[j]).sum(2) > HOVER_THRESHOLD
        labels, n = ndimage.label(ndimage.binary_closing(diff, iterations=3))
        if n == 0:
            continue
        sizes = ndimage.sum(diff, labels, range(1, n + 1))
        best = int(np.argmax(sizes)) + 1
        if sizes[best - 1] < 150:
            continue                       # the computer is hidden behind the globe in this frame
        ys, xs = np.where(labels == best)
        if ys.max() - ys.min() < 60:
            continue                       # a thin sliver along the globe's edge, not the computer
        x0, x1 = max(xs.min() - HOVER_MARGIN, 0), min(xs.max() + HOVER_MARGIN + 1, OUT_W)
        y0, y1 = max(ys.min() - HOVER_MARGIN, 0), min(ys.max() + HOVER_MARGIN + 1, OUT_H)
        crop = Image.fromarray(h[y0:y1, x0:x1].astype("uint8"))
        crop.save(f"{OUT}/hover_{j:03d}.png", optimize=True)
        hover[str(j)] = {"x": int(x0), "y": int(y0), "w": int(x1 - x0), "h": int(y1 - y0),
                         "cx": float((xs.min() + xs.max()) / 2), "cy": float((ys.min() + ys.max()) / 2)}
    manifest["hover"] = hover
    print("loop frames with a visible computer:", len(hover))

    with open(f"{OUT}/frames.json", "w") as f:
        json.dump(manifest, f, indent=1)

    # Instructions: the @2x art halved (exactly 2:1) to save memory.
    for tag in ("a", "b"):
        src = Image.open(f"art_source/internet/internet-instructions-{tag}@2x.png").convert("RGBA")
        src.resize((src.width // 2, src.height // 2), Image.BOX).save(
            f"art/internet/instructions_{tag}.png", optimize=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
