#!/usr/bin/env python3
"""Turns the spinning-folder video into a transparent spritesheet for Godot.

Run from the project root:
    python3 tools/build_file_spin.py path/to/file-spin.mp4

Writes art/copy/file_spin.png (a grid of frames) and prints the grid size.
Needs ffmpeg, numpy, scipy and Pillow. The video has a pure black background,
which is turned into transparency (the folder's own edge colors are pushed out
into the soft edge so there is no dark fringe).
"""
import glob
import os
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image
from scipy import ndimage

OUT = "art/copy/file_spin.png"
COLS = 10
MAX_W = 320            # width of the widest frame in the sheet, in pixels
THRESH = 28            # brightness (max of R, G, B) above this counts as folder
PAD = 6


def cut_out(frame: np.ndarray) -> np.ndarray:
    mx = frame.max(axis=2)
    solid = ndimage.binary_fill_holes(mx > THRESH)
    solid = ndimage.binary_opening(solid, iterations=1)
    core = ndimage.binary_erosion(solid, iterations=4)
    # Soft edge: blur the mask a little, but never let the core go see-through.
    alpha = ndimage.gaussian_filter(solid.astype(float), 1.2)
    alpha = np.where(core, 1.0, np.clip(alpha * 1.15, 0, 1))
    alpha[~ndimage.binary_dilation(solid, iterations=3)] = 0.0
    # Edge colors come from the nearest solid pixel, not from the black edge.
    idx = ndimage.distance_transform_edt(~core, return_distances=False, return_indices=True)
    rgb = frame[idx[0], idx[1]]
    return np.dstack([rgb, (alpha * 255).astype(np.uint8)])


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", sys.argv[1],
                        os.path.join(tmp, "f_%03d.png")], check=True)
        files = sorted(glob.glob(os.path.join(tmp, "f_*.png")))
        cut = [cut_out(np.array(Image.open(f).convert("RGB"))) for f in files]
    # One crop box for every frame keeps the folder steady while it spins.
    ys, xs = np.where(np.any([c[..., 3] > 0 for c in cut], axis=0))
    x0, x1 = max(xs.min() - PAD, 0), xs.max() + PAD + 1
    y0, y1 = max(ys.min() - PAD, 0), ys.max() + PAD + 1
    scale = MAX_W / (x1 - x0)
    fw, fh = MAX_W, int(round((y1 - y0) * scale))
    rows = -(-len(cut) // COLS)
    sheet = Image.new("RGBA", (fw * COLS, fh * rows), (0, 0, 0, 0))
    for i, c in enumerate(cut):
        im = Image.fromarray(c[y0:y1, x0:x1], "RGBA").resize((fw, fh), Image.LANCZOS)
        sheet.paste(im, ((i % COLS) * fw, (i // COLS) * fh))
    sheet.save(OUT, optimize=True)
    print(f"{len(cut)} frames, {COLS} x {rows} grid, each {fw} x {fh}px -> {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
