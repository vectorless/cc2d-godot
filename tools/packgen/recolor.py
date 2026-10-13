"""Split a full-colour part texture into CC2D's form: a grey shading texture plus an RGB colour
mask, with three default colours, so the part can be recoloured like CC2D's own parts.

CC2D's armour shader (linear space): out = 2 * colour_k * tex   where mask channel k is set,
                                      out = 2 * 0.5   * tex   where the mask is black.
So for a pixel of colour C in channel k we store tex = lum(C) / (2 * lum(colour_k)) as grey,
and outlines / near-black pixels stay unmasked with tex = C / (2 * lin(0.5)).
python3 recolor.py in.png out_tex.png out_mask.png  -> prints the 3 default colours (sRGB)"""
import sys, json
import numpy as np
from PIL import Image

def to_lin(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)

def to_srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)

def lum(lin):
    return lin[..., 0] * 0.2126 + lin[..., 1] * 0.7152 + lin[..., 2] * 0.0722

def kmeans(x, k, iters=30, seed=0):
    rng = np.random.default_rng(seed)
    # k-means++ init
    c = [x[rng.integers(len(x))]]
    for _ in range(1, k):
        d = np.min(((x[:, None, :] - np.array(c)[None]) ** 2).sum(-1), axis=1)
        c.append(x[rng.choice(len(x), p=d / d.sum())])
    c = np.array(c)
    for _ in range(iters):
        lab = np.argmin(((x[:, None, :] - c[None]) ** 2).sum(-1), axis=1)
        c = np.array([x[lab == i].mean(0) if np.any(lab == i) else c[i] for i in range(k)])
    return c, lab

def split(src, out_tex, out_mask, k=3, outline=0.035):
    im = np.asarray(Image.open(src).convert('RGBA')).astype(np.float32) / 255.0
    rgb, a = im[..., :3], im[..., 3]
    lin = to_lin(rgb)
    L = lum(lin)
    solid = a > 0.5
    ink = solid & (L < outline)               # black outlines and deep shadow: leave unmasked
    paint = solid & ~ink
    # cluster on a perceptual-ish feature: sRGB colour (sampled for speed)
    feats = rgb[paint]
    sample = feats[np.random.default_rng(1).choice(len(feats), min(len(feats), 40000), replace=False)]
    centers, _ = kmeans(sample, k)
    # order: most common first (channel R = main fabric)
    lab_all = np.argmin(((feats[:, None, :] - centers[None]) ** 2).sum(-1), axis=1)
    order = np.argsort(-np.bincount(lab_all, minlength=k))
    centers = centers[order]
    lab_all = np.argsort(order)[lab_all]
    # default colours: a bright-ish version of each cluster (so shading has headroom)
    defaults = []
    tex = np.zeros_like(lin)
    mask = np.zeros_like(lin)
    idx = np.nonzero(paint)
    for i in range(k):
        sel = lab_all == i
        px = lin[idx[0][sel], idx[1][sel]]
        if len(px) == 0:
            defaults.append([0.5, 0.5, 0.5])
            continue
        # colour = the 85th-percentile-luminance pixels' mean, so most shading lands below it
        l = lum(px)
        hi = px[l >= np.percentile(l, 85)].mean(0)
        col_lin = np.clip(hi, 1e-4, 1)
        defaults.append(to_srgb(col_lin).tolist())
        g = np.clip(l / (2 * lum(col_lin[None])[0]), 0, 1)
        tex[idx[0][sel], idx[1][sel]] = g[:, None]
        mask[idx[0][sel], idx[1][sel], i] = 1.0
    # unmasked ink: tex = C / (2 * lin(0.5))
    tex[ink] = np.clip(lin[ink] / (2 * to_lin(np.array(0.5))), 0, 1)
    tex_srgb = to_srgb(tex)
    out = np.dstack([tex_srgb, a])
    Image.fromarray((out * 255 + 0.5).astype(np.uint8), 'RGBA').save(out_tex)
    m = np.dstack([mask, solid.astype(np.float32)])
    Image.fromarray((m * 255 + 0.5).astype(np.uint8), 'RGBA').save(out_mask)
    return [[round(v, 4) for v in c] + [1.0] for c in defaults]

if __name__ == '__main__':
    print(json.dumps(split(sys.argv[1], sys.argv[2], sys.argv[3])))
