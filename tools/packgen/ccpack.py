"""Turn an AI-generated CC2D sprite sheet into a CC2D part texture.

The generator gets the template sheet (1024x512 on white, scaled 2x into a 2048x1152 16:9
canvas with 64 px bars top and bottom) and returns a redraw. Here we:
  1. undo the canvas (resize to 2048x1152, crop the bars, scale to the template size)
  2. find each piece inside its sprite rectangle (white background flood-filled away)
  3. fit each piece onto the template piece's bounding box, so joints still line up
  4. rebuild an anti-aliased alpha edge
Usage: python3 ccpack.py gen.png template.png regions.json out.png
regions.json: {"Armor Body": [x, y, w, h], ...} in template pixels (top-left origin).
"""
import sys, json
import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

def load_rgb(p):
    return np.asarray(Image.open(p).convert('RGB')).astype(np.float32)

def uncanvas(gen, size):
    W, H = size
    im = Image.fromarray(gen.astype(np.uint8)).resize((2 * W, int(2 * W * 9 / 16)), Image.LANCZOS)
    top = (im.height - 2 * H) // 2
    im = im.crop((0, top, 2 * W, top + 2 * H))
    return im   # still 2x: we fit at 2x and downscale at the end

def background(rgb, thresh=232):
    """Near-white pixels connected to a rectangle's border."""
    white = (rgb.min(axis=2) > thresh) & ((rgb.max(axis=2) - rgb.min(axis=2)) < 18)
    return white

def piece_mask(rgb_rect):
    white = background(rgb_rect)
    lab, n = ndimage.label(white)
    border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    bg = np.isin(lab, list(border))
    fg = ~bg
    # drop specks, fill holes that aren't real gaps
    lab2, n2 = ndimage.label(fg)
    if n2 == 0:
        return fg
    sizes = ndimage.sum(fg, lab2, range(1, n2 + 1))
    keep = [i + 1 for i, s in enumerate(sizes) if s >= max(200, 0.04 * sizes.max())]
    fg = np.isin(lab2, keep)
    return fg

def bbox(mask):
    ys, xs = np.nonzero(mask)
    if len(xs) == 0:
        return None
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1

def convert(gen_path, template_path, regions, out_path, max_stretch=0.18):
    tmpl = Image.open(template_path).convert('RGBA')
    W, H = tmpl.size
    talpha = np.asarray(tmpl)[:, :, 3]
    g2 = uncanvas(load_rgb(gen_path), (W, H))
    g2 = np.asarray(g2).astype(np.float32)
    out = np.zeros((H * 2, W * 2, 4), np.float32)
    report = {}
    for name, (x, y, w, h) in regions.items():
        X, Y, Wr, Hr = 2 * x, 2 * y, 2 * w, 2 * h
        rect = g2[Y:Y + Hr, X:X + Wr]
        fg = piece_mask(rect)
        gb = bbox(fg)
        tb = bbox(talpha[y:y + h, x:x + w] > 20)
        if gb is None or tb is None:
            report[name] = 'empty'
            continue
        tb = [2 * v for v in tb]
        gx0, gy0, gx1, gy1 = gb
        tx0, ty0, tx1, ty1 = tb
        sx = (tx1 - tx0) / (gx1 - gx0)
        sy = (ty1 - ty0) / (gy1 - gy0)
        # Keep proportions unless the two scales are close (then match the template exactly).
        if abs(sx / sy - 1) > max_stretch:
            s = sy
            sx = sy = s
        piece = rect[gy0:gy1, gx0:gx1]
        pm = fg[gy0:gy1, gx0:gx1]
        nw, nh = max(1, round((gx1 - gx0) * sx)), max(1, round((gy1 - gy0) * sy))
        pim = Image.fromarray(piece.astype(np.uint8)).resize((nw, nh), Image.LANCZOS)
        mim = Image.fromarray((pm * 255).astype(np.uint8)).resize((nw, nh), Image.LANCZOS)
        # place centred on the template piece's box
        cx, cy = (tx0 + tx1) / 2, (ty0 + ty1) / 2
        px, py = int(round(cx - nw / 2)), int(round(cy - nh / 2))
        canvas_rgb = np.zeros((Hr, Wr, 3), np.float32)
        canvas_a = np.zeros((Hr, Wr), np.float32)
        sx0, sy0 = max(0, -px), max(0, -py)
        dx0, dy0 = max(0, px), max(0, py)
        cw, ch = min(nw - sx0, Wr - dx0), min(nh - sy0, Hr - dy0)
        canvas_rgb[dy0:dy0 + ch, dx0:dx0 + cw] = np.asarray(pim).astype(np.float32)[sy0:sy0 + ch, sx0:sx0 + cw]
        canvas_a[dy0:dy0 + ch, dx0:dx0 + cw] = np.asarray(mim).astype(np.float32)[sy0:sy0 + ch, sx0:sx0 + cw] / 255.0
        # Edge: the drawing's outline is anti-aliased against white. Where the mask is soft,
        # recover alpha from darkness and darken the colour (un-blend from white).
        lum = canvas_rgb.mean(axis=2) / 255.0
        edge = (canvas_a > 0.02) & (canvas_a < 0.98)
        a = canvas_a.copy()
        a[edge] = np.clip(np.maximum(canvas_a[edge] * 0.6, 1.0 - lum[edge]), 0, 1)
        safe = np.maximum(a, 1e-3)[..., None]
        unblend = np.clip((canvas_rgb - 255.0 * (1 - a[..., None])) / safe, 0, 255)
        rgb = np.where(edge[..., None], unblend, canvas_rgb)
        out[Y:Y + Hr, X:X + Wr, :3] = rgb
        out[Y:Y + Hr, X:X + Wr, 3] = a * 255
        report[name] = 'fit %.2fx%.2f' % (sx, sy)
    img = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), 'RGBA').resize((W, H), Image.LANCZOS)
    img.save(out_path)
    return report

if __name__ == '__main__':
    print(convert(sys.argv[1], sys.argv[2], json.load(open(sys.argv[3])), sys.argv[4]))
