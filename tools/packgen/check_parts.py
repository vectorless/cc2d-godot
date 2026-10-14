"""Quality check for custom part packs: flags the problems found while adding AI-generated clothing.

    python3 check_parts.py [pack dir or parts.json ...] [--only "Part name"] [--sheet out.png]

With no arguments it checks every custom/*/parts.json. Each part is compared with the template it was
drawn on (its "template", or the "template_texture" guide in its spec). Prints one line per problem and,
with --sheet, writes a contact sheet of the flagged parts: template | part | overlay, where red = template
area the part leaves uncovered (skin shows) and blue = part outside the template's outline.

Checks (name: what it catches, e.g.)
  format        wrong texture/mask size or mode, missing file / .import, not 3 colours
  white_fill    white background kept inside the drawing (between harness straps, inside cuff rings)
  flat_fill     a large flat, unshaded area (a blank face drawn inside a hairstyle)
  white_main    the main colour is near white: usually background kept as cloth
  skin_channel  a colour channel is skin-toned: exposed skin drawn into the part recolours with it (garters)
  uncovered     body-covering piece leaves template area bare (pencil skirt, thighs, shoulders)
  overflow      piece reaches well outside the template (straps behind the neck drawn in front, flares, offset tops)
  fragments     separate bits besides the main piece (slivers, specks)
  thin_lines    stray thin lines not attached to the drawing (a leftover body or jaw outline)
  prop_size     held item much smaller/bigger than the template item
  prop_grip     held item doesn't reach the hand (grip point)
"""
import json, os, sys, glob
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
COVER = ('Armor Body', 'Pants Hip', 'Pants Upper Leg', 'Pants Lower Leg', 'Cloth', 'Boots Lower Leg')
NO_OVERFLOW = ('Hair', 'Helmet', 'Weapon', 'FacialHair', 'Cape', 'Mouth')


def rp(res):
    return os.path.join(ROOT, res[len('res://'):]) if res.startswith('res://') else res


def rgba(path):
    return np.asarray(Image.open(path).convert('RGBA')).astype(np.float32)


def spec_index():
    idx = {}
    for f in glob.glob(os.path.join(HERE, 'specs', '*.json')):
        s = json.load(open(f))
        for p in s['parts']:
            idx[(s['package'], p['name'])] = p
    return idx


def regions(cat, part, size):
    if cat in ('Cape', 'Skirt'):
        return {'Cloth': [0, 0, size[0], size[1]]}
    return {k: v['region'] for k, v in part['sprites'].items()}


def check_part(cat, p, tp, guide):
    probs = []
    tex_p, mask_p = rp(p['texture']), rp(p['mask'] or '')
    for f in (tex_p, mask_p):
        if not os.path.exists(f):
            return [('format', 'missing ' + os.path.relpath(f, ROOT))], None
        if not os.path.exists(f + '.import'):
            probs.append(('format', 'no .import for ' + os.path.basename(f) + ' (open the project in Godot once)'))
    T = rgba(tex_p); M = rgba(mask_p)
    G = rgba(guide) if guide else rgba(rp(tp['texture']))
    if T.shape != M.shape or T.shape[:2] != rgba(rp(tp['texture'])).shape[:2]:
        probs.append(('format', 'texture %s / mask %s / template %s sizes differ' % (T.shape[:2], M.shape[:2], rgba(rp(tp['texture'])).shape[:2])))
        return probs, None
    if G.shape[:2] != T.shape[:2]:
        G = np.asarray(Image.fromarray(G.astype(np.uint8)).resize((T.shape[1], T.shape[0]))).astype(np.float32)
    cols = p.get('colors') or []
    if len(cols) != 3:
        probs.append(('format', '%d default colours (need 3)' % len(cols)))
    else:
        c0 = np.array(cols[0][:3])
        if c0.min() > 0.93:
            probs.append(('white_main', 'main colour is white %s' % np.round(c0, 2).tolist()))
        for i, c in enumerate(cols):
            r, g, b = c[:3]
            mx, mn = max(r, g, b), min(r, g, b)
            sat = (mx - mn) / max(mx, 1e-3)
            hue = 0 if mx == mn else (60 * ((g - b) / (mx - mn)) % 360 if mx == r else 0)
            ch = M[..., i] > 128
            share = (ch & (T[..., 3] > 128)).sum() / max((T[..., 3] > 128).sum(), 1)
            if mx == r and 8 <= hue <= 45 and 0.18 <= sat <= 0.6 and 0.35 <= mx <= 0.98 and share > 0.03 \
                    and cat not in ('Hair', 'Helmet', 'Weapon', 'Mouth', 'FacialHair'):
                probs.append(('skin_channel', 'colour %d %s looks like skin and covers %.0f%% of the part' % (i + 1, np.round(c[:3], 2).tolist(), share * 100)))
    ov = np.zeros(T.shape[:2] + (3,), np.uint8)
    a = T[..., 3] > 128
    for name, (x, y, w, h) in regions(cat, p, (T.shape[1], T.shape[0])).items():
        sl = (slice(y, y + h), slice(x, x + w))
        pa, ta = a[sl], G[sl][..., 3] > 128
        if not ta.any():
            continue
        if not pa.any():
            probs.append(('uncovered', '%s: empty' % name)); continue
        lum = T[sl][..., :3].mean(-1)
        # white_fill: big flat near-white blobs inside the drawing
        white = pa & (T[sl][..., :3].min(-1) > 225) & (np.ptp(T[sl][..., :3], axis=-1) < 18)
        lab, n = ndimage.label(white)
        if n:
            sz = ndimage.sum(white, lab, range(1, n + 1)); big = sz[sz >= 150].sum()
            if big > 0.04 * pa.sum():
                probs.append(('white_fill', '%s: %.0f%% is flat white' % (name, 100 * big / pa.sum())))
        # flat_fill: large unshaded areas
        mu = ndimage.uniform_filter(lum, 7); sd = np.sqrt(np.maximum(ndimage.uniform_filter(lum * lum, 7) - mu * mu, 0))
        flat = pa & (sd < 2.0) & ndimage.binary_erosion(pa, iterations=4)
        lab, n = ndimage.label(flat)
        if n:
            mx = ndimage.sum(flat, lab, range(1, n + 1)).max()
            if cat == 'Hair' and mx > 0.08 * pa.sum():
                probs.append(('flat_fill', '%s: flat unshaded area %.0f%% of the piece (blank face?)' % (name, 100 * mx / pa.sum())))
        # coverage / overflow against the template outline
        if any(name.startswith(c) for c in COVER) and cat not in NO_OVERFLOW:
            unc = ta & ~ndimage.binary_dilation(pa, iterations=2)
            unc = ndimage.binary_opening(unc, iterations=2)
            if unc.sum() > 0.08 * ta.sum():
                probs.append(('uncovered', '%s: %.0f%% of the template area left bare' % (name, 100 * unc.sum() / ta.sum())))
            ov[sl][unc] = (255, 40, 40)
        if cat not in NO_OVERFLOW:
            out = pa & ~ndimage.binary_dilation(ta, iterations=10)
            out = ndimage.binary_opening(out, iterations=1)
            if out.sum() > 0.10 * pa.sum() and out.sum() > 300:
                ys = np.nonzero(out)[0]; tys = np.nonzero(ta)[0]
                where = ' (above the template top)' if np.median(ys) < tys.min() + 0.15 * (tys.max() - tys.min()) else ''
                probs.append(('overflow', '%s: %.0f%% of it outside the template%s' % (name, 100 * out.sum() / pa.sum(), where)))
            ov[sl][out] = (60, 90, 255)
        # fragments
        lab, n = ndimage.label(pa)
        if n > 1:
            sz = np.sort(ndimage.sum(pa, lab, range(1, n + 1)))[::-1]
            extra = sz[1:][sz[1:] > max(40, 0.01 * sz[0])]
            if len(extra):
                probs.append(('fragments', '%s: %d extra bits (%d px)' % (name, len(extra), extra.sum())))
        # thin lines
        body = ndimage.binary_opening(pa, structure=np.ones((5, 5)))
        thin = pa & ~ndimage.binary_dilation(body, iterations=4)
        lab, n = ndimage.label(thin)
        if n:
            sz = ndimage.sum(thin, lab, range(1, n + 1))
            if (sz > 60).sum():
                probs.append(('thin_lines', '%s: %d stray thin lines (%d px)' % (name, (sz > 60).sum(), sz[sz > 60].sum())))
        # props
        if cat == 'Weapon' and name == 'Weapon':
            ra = pa.sum() / max(ta.sum(), 1)
            if ra < 0.35 or ra > 4:
                probs.append(('prop_size', 'area %.2fx the template item' % ra))
            off = p['sprites'][name].get('offset')
            if off:
                gx, gy = int(-off[0]) - x, int(-off[1]) - y
                yy, xx = np.nonzero(pa)
                d = np.sqrt((xx - gx) ** 2 + (yy - gy) ** 2).min()
                if d > 40:
                    probs.append(('prop_grip', 'nearest pixel %d px from the grip' % d))
    return probs, ov


def tile(p, tp, guide, ov, h=220):
    ims = []
    for src in (guide or rp(tp['texture']), rp(p['texture'])):
        x = Image.open(src).convert('RGBA'); bg = Image.new('RGBA', x.size, (255, 0, 255, 255)); bg.alpha_composite(x); ims.append(bg.convert('RGB'))
    if ov is not None:
        base = Image.open(rp(p['texture'])).convert('RGBA'); g = Image.new('RGBA', base.size, (40, 40, 40, 255)); g.alpha_composite(base)
        o = Image.fromarray(ov); m = Image.fromarray(((ov.max(-1) > 0) * 200).astype(np.uint8))
        g = g.convert('RGB'); g.paste(o, (0, 0), m); ims.append(g)
    ims = [i.resize((max(1, round(i.width * h / i.height)), h)) for i in ims]
    t = Image.new('RGB', (sum(i.width + 6 for i in ims), h + 18), (90, 90, 90)); x0 = 0
    for i in ims:
        t.paste(i, (x0, 18)); x0 += i.width + 6
    return t


def main(argv):
    sheet, only, packs = None, None, []
    i = 0
    while i < len(argv):
        if argv[i] == '--sheet':
            sheet = argv[i + 1]; i += 2
        elif argv[i] == '--only':
            only = argv[i + 1]; i += 2
        else:
            packs.append(argv[i]); i += 1
    files = [os.path.join(x, 'parts.json') if os.path.isdir(x) else x for x in packs] or sorted(glob.glob(os.path.join(ROOT, 'custom', '*', 'parts.json')))
    cat_all = json.load(open(os.path.join(ROOT, 'cc2d', 'parts.json')))['categories']
    specs = spec_index()
    tiles, total, nparts = [], 0, 0
    for pj in files:
        d = json.load(open(pj))
        for cat, lst in d['categories'].items():
            for p in lst:
                if only and p['name'] != only:
                    continue
                nparts += 1
                tname = p.get('template')
                tp = next((x for x in cat_all.get(cat, []) if x['name'] == tname), None)
                if tp is None or cat == 'SkinDetails':
                    continue
                sp = specs.get((p['package'], p['name']), {})
                guide = os.path.join(HERE, sp['template_texture']) if sp.get('template_texture') else None
                probs, ov = check_part(cat, p, tp, guide)
                for k, msg in probs:
                    print('%-14s %-12s %-34s %-12s %s' % (p['package'], cat, p['name'], k, msg))
                total += len(probs)
                if probs and sheet:
                    t = tile(p, tp, guide, ov)
                    ImageDraw.Draw(t).text((4, 3), '%s / %s: %s' % (p['package'], p['name'], ', '.join(sorted({k for k, _ in probs}))), fill='white')
                    tiles.append(t)
    print('== %d problems in %d parts' % (total, nparts))
    if sheet and tiles:
        w = max(t.width for t in tiles); s = Image.new('RGB', (w, sum(t.height + 4 for t in tiles)), (60, 60, 60)); y = 0
        for t in tiles:
            s.paste(t, (0, y)); y += t.height + 4
        s.save(sheet); print('sheet:', sheet)
    return total


if __name__ == '__main__':
    sys.exit(1 if main(sys.argv[1:]) else 0)
