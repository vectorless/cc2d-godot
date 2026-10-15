"""Post-fixes for finished custom parts (texture + mask in place; originals backed up to ~/packgen_work/_backup).

    python3 fixparts.py <pack dir> "<Part name>" <fix> [<fix> ...]

fixes:
  unskin       skin drawn into the part (bare thigh between garter straps...) -> transparent, so the body shows
  fill_feet    white socks whose foot was cut away with the white background -> fill the foot back in
  rear_strap   strap(s) rising above the neckline on the back (left) side -> removed
  white_holes  flat white areas enclosed by the drawing (between straps, inside rings) -> transparent
  down<N> / up<N> / left<N> / right<N>   move the whole part by N px (e.g. down110: a visor sitting too high)
  fill_sleeves white sleeves cut away with the background -> filled
  unface       a blank face drawn inside a hairstyle -> removed
  back_legs    straps drawn as an upside-down V over the shoulder: the leg going down the back -> removed
  fill_template  template area left bare (skin shows through) -> filled with the part's nearest cloth
  fill_shoulders the same, only the top of the torso piece (bare shoulders beside the collar)
  grow_feet    side-view foot pieces a little small -> scaled up 12% around the sole
  strays       separate specks / stray lines beside a piece -> removed
  blank_shins  clear the lower-leg pieces (shorts drawn full length)
  drop1 / drop2 / drop3   everything on colour channel N -> transparent (e.g. the channel that is bare skin)
"""
import json, os, sys, shutil
import numpy as np
from PIL import Image
from scipy import ndimage
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
BACK = os.path.expanduser('~/packgen_work/_backup')


def lin(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def srgb(c):
    c = np.clip(c, 0, 1); return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def shaded(T, M, cols):
    """The part as the shader draws it with its default colours: out = 2*tex*colour_k (linear), unmasked = tex*2*0.5."""
    t = lin(T[..., :3] / 255); out = t.copy()
    for k in range(3):
        w = (M[..., k] / 255)[..., None]
        out = out * (1 - w) + 2 * t * lin(np.array(cols[k][:3]))[None, None] * w
    return srgb(out)


def unskin(T, M, p, cat):
    rgb = shaded(T, M, p['colors']); r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx, mn = rgb.max(-1), rgb.min(-1); sat = (mx - mn) / np.maximum(mx, 1e-3)
    hue = np.where(mx == mn, 0, (60 * (g - b) / np.maximum(mx - mn, 1e-3)) % 360)
    skin = (mx == r) & (hue >= 8) & (hue <= 42) & (sat > 0.12) & (sat < 0.6) & (mx > 0.42) & (T[..., 3] > 0)
    skin = ndimage.binary_opening(skin, iterations=2)
    lab, n = ndimage.label(skin)
    if n:
        sz = ndimage.sum(skin, lab, range(1, n + 1)); skin = np.isin(lab, 1 + np.nonzero(sz >= 120)[0])
    rim = ndimage.binary_dilation(skin, iterations=1) & (T[..., :3].mean(-1) > 90)
    kill = skin | rim
    T[..., 3] = np.where(kill, 0, T[..., 3]); M[kill] = 0
    return int(kill.sum())


def fill_feet(T, M, p, cat, which=('Boots Foot',)):
    n = 0
    for name, v in p['sprites'].items():
        if not name.startswith(which):
            continue
        x, y, w, h = v['region']; sl = (slice(y, y + h), slice(x, x + w))
        a = T[sl][..., 3] > 60
        if not a.any():
            continue
        closed = ndimage.binary_closing(a, structure=np.ones((3, 3)), iterations=6)
        # the sock outline is open at the ankle: close it across its top rows before filling
        ys = np.nonzero(closed.any(1))[0]
        for yy in range(ys[0], min(ys[0] + 6, ys[-1])):
            xs = np.nonzero(closed[yy])[0]
            if len(xs) > 1:
                closed[yy, xs[0]:xs[-1] + 1] = True
        filled = ndimage.binary_fill_holes(closed)
        if filled.sum() < 1.6 * a.sum():
            # still open (outline with gaps): fill the outline's convex hull instead
            from scipy.spatial import ConvexHull
            from PIL import ImageDraw
            yy, xx = np.nonzero(a)
            hull = ConvexHull(np.c_[xx, yy])
            poly = Image.new('L', (a.shape[1], a.shape[0]), 0)
            ImageDraw.Draw(poly).polygon([(float(xx[i]), float(yy[i])) for i in hull.vertices], fill=255)
            filled = filled | (np.asarray(poly) > 0)
        add = filled & ~a
        if not add.any():
            continue
        # fill with the sock's own light shading (median of its lighter pixels) on the main channel
        lt = T[sl][..., :3][a & (T[sl][..., :3].mean(-1) > 120)]
        val = np.median(lt, axis=0) if len(lt) else np.array([200, 200, 200])
        Ts, Ms = T[sl], M[sl]
        Ts[add, :3] = val; Ts[add, 3] = 255
        Ms[add] = (255, 0, 0, 255)
        n += int(add.sum())
    return n


def rear_strap(T, M, p, cat):
    a = T[..., 3] > 60
    widths = a.sum(1); top = np.nonzero(widths > 0.45 * widths.max())[0][0]
    cols = np.nonzero(a[top])[0]; mid = (cols.min() + cols.max()) / 2
    kill = np.zeros_like(a); kill[:top + 2, :int(mid)] = True; kill &= T[..., 3] > 0
    fade = np.clip((np.arange(T.shape[0])[:, None] - (top - 2)) / 4.0, 0, 1)
    T[..., 3] = np.where(kill, T[..., 3] * np.broadcast_to(fade, a.shape), T[..., 3])
    M[T[..., 3] == 0] = 0
    return int(kill.sum())


def white_holes(T, M, p, cat):
    rgb, a = T[..., :3], T[..., 3]
    white = (a > 128) & (rgb.min(-1) > 215) & (np.ptp(rgb, axis=-1) < 20)
    lab, n = ndimage.label(white)
    if not n:
        return 0
    sz = ndimage.sum(white, lab, range(1, n + 1)); holes = np.isin(lab, 1 + np.nonzero(sz >= 150)[0])
    holes = ndimage.binary_dilation(holes, iterations=2) & (rgb.mean(-1) > 150)
    T[..., 3] = np.where(holes, 0, a); M[holes] = 0
    return int(holes.sum())


def drop(k):
    def f(T, M, p, cat):
        ch = (M[..., k] > 128) & (M[..., k] >= M[..., :3].max(-1)) & (T[..., 3] > 0)
        rim = ndimage.binary_dilation(ch, iterations=1) & (M[..., :3].max(-1) < 60) & (T[..., :3].mean(-1) > 110)
        kill = ch | rim
        T[..., 3] = np.where(kill, 0, T[..., 3]); M[kill] = 0
        return int(kill.sum())
    return f


def blank_shins(T, M, p, cat):
    """shorts drawn full-length: clear the lower-leg (shin) pieces"""
    n = 0
    for name, v in p['sprites'].items():
        if 'Lower Leg' in name:
            x, y, w, h = v['region']; n += int((T[y:y + h, x:x + w, 3] > 0).sum())
            T[y:y + h, x:x + w] = 0; M[y:y + h, x:x + w] = 0
    return n


def fill_sleeves(T, M, p, cat):
    """white sleeves whose inside was cut away with the background -> fill them back in"""
    return fill_feet(T, M, p, cat, which=('Armor Upper Arm', 'Armor Lower Arm'))


def unface(T, M, p, cat):
    """hair drawn with a blank face inside it: remove the big flat (unshaded) area in the front hair
    piece and the stray outline left around it, so the character's own face shows"""
    n = 0
    for name, v in p['sprites'].items():
        if not name.startswith('Hair F'):
            continue
        x, y, w, h = v['region']; sl = (slice(y, y + h), slice(x, x + w))
        tt = T[sl].astype(np.float32); L = tt[..., :3].mean(-1); a = tt[..., 3]
        mu = ndimage.uniform_filter(L, 7); sd = np.sqrt(np.maximum(ndimage.uniform_filter(L * L, 7) - mu * mu, 0))
        flat = (sd < 3.0) & (a > 200)
        lab, k = ndimage.label(flat)
        if not k:
            continue
        sizes = ndimage.sum(flat, lab, range(1, k + 1))
        keep = [i + 1 for i in np.argsort(sizes)[::-1][:2] if sizes[i] > 0.04 * (a > 0).sum()]
        if not keep:
            continue
        region = ndimage.binary_fill_holes(ndimage.binary_closing(np.isin(lab, keep), iterations=6))
        region = ndimage.binary_dilation(region, iterations=2) & (a > 0) & (L > 60)
        a2 = np.where(region, 0, a)
        body = ndimage.binary_opening(a2 > 128, structure=np.ones((5, 5)))
        a2 = np.where(ndimage.binary_dilation(body, iterations=3), a2, 0)
        n += int(((a > 0) & (a2 == 0)).sum())
        Ts = T[sl]; Ts[..., 3] = a2; Ms = M[sl]; Ms[a2 == 0] = 0
    return n


def back_legs(T, M, p, cat):
    """camisole / bra straps drawn as an upside-down V over each shoulder: keep the leg rising from
    the neckline to the top of the shoulder, remove the leg coming back down behind (it would show in
    front of the shoulder). Works on everything above the garment's top edge."""
    a = T[..., 3] > 60
    widths = a.sum(1); top = int(np.nonzero(widths > 0.45 * widths.max())[0][0])
    cols = np.nonzero(a[top])[0]; mid = (cols.min() + cols.max()) / 2
    above = np.zeros_like(a); above[:top - 2] = a[:top - 2]   # straps only (not the neckline that joins them)
    lab, n = ndimage.label(above)
    kill = np.zeros_like(a)
    for i in range(1, n + 1):
        comp = lab == i
        if comp.sum() < 30:
            continue
        ys, xs = np.nonzero(comp)
        ay = ys.min(); ax = xs[ys == ay].mean()
        outer = (np.arange(a.shape[1])[None, :] < ax - 2) if ax < mid else (np.arange(a.shape[1])[None, :] > ax + 2)
        k = comp & outer & (np.arange(a.shape[0])[:, None] > ay + 3) & (np.arange(a.shape[0])[:, None] < top - 1)
        kill |= k
    kill = ndimage.binary_dilation(kill, iterations=1) & (np.arange(a.shape[0])[:, None] < top - 1)
    T[..., 3] = np.where(kill, 0, T[..., 3]); M[kill] = 0
    return int(kill.sum())


def _template_alpha(p, cat, shape):
    """alpha of the template the part was fitted to (the spec's guide texture if it has one)"""
    import glob
    guide = None
    for f in glob.glob(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'specs', '*.json')):
        sp = json.load(open(f))
        for q in sp['parts']:
            if q['name'] == p['name'] and sp['package'] == p['package'] and q.get('template_texture'):
                guide = os.path.join(os.path.dirname(os.path.abspath(__file__)), q['template_texture'])
    if guide is None:
        cat_all = json.load(open(os.path.join(ROOT, 'cc2d', 'parts.json')))['categories'][cat]
        tp = next(q for q in cat_all if q['name'] == p['template'])
        guide = os.path.join(ROOT, tp['texture'][len('res://'):])
    t = Image.open(guide).convert('RGBA')
    if t.size != (shape[1], shape[0]):
        t = t.resize((shape[1], shape[0]))
    return np.asarray(t)[..., 3] > 128


def fill_template(T, M, p, cat, which=None, top_frac=None, maxdist=34):
    """template area the part leaves bare (skin shows through: shoulders, hips, thighs, boot shafts)
    -> filled with the part's own nearest cloth, with the outline moved out to the new edge"""
    ta_full = _template_alpha(p, cat, T.shape)
    n = 0
    for name, v in p['sprites'].items():
        if which and not name.startswith(which):
            continue
        x, y, w, h = v['region']; sl = (slice(y, y + h), slice(x, x + w))
        Ts, Ms = T[sl], M[sl]
        pa = Ts[..., 3] > 128
        ta = ta_full[sl]
        if not pa.any() or not ta.any():
            continue
        gap = ta & ~pa & (ndimage.distance_transform_edt(~pa) <= maxdist)
        if top_frac:
            ys = np.nonzero(ta.any(1))[0]
            gap &= (np.arange(h)[:, None] <= ys[0] + top_frac * (ys[-1] - ys[0]))
        gap = ndimage.binary_opening(gap, iterations=1)
        if gap.sum() < 40:
            continue
        new = pa | gap
        L = Ts[..., :3].mean(-1)
        src = pa & (L > 70) & ndimage.binary_erosion(pa, iterations=2)
        # copy from the garment's main colour (its most used mask channel), not a nearby shirt, tie or trim
        chans = [int(((Ms[..., k] > 128) & src).sum()) for k in range(3)]
        main = int(np.argmax(chans))
        if chans[main] > 0.3 * src.sum():
            src = src & (Ms[..., main] > 128)
        if not src.any():
            continue
        iy, ix = ndimage.distance_transform_edt(~src, return_distances=False, return_indices=True)
        # old outline that is now inside the garment: repaint it as cloth too
        old_line = pa & (L <= 70) & ndimage.binary_dilation(gap, iterations=3) & ndimage.binary_erosion(new, iterations=3)
        paint = gap | old_line
        Ts[paint, :3] = Ts[iy[paint], ix[paint], :3]
        Ms[paint] = Ms[iy[paint], ix[paint]]
        Ts[gap, 3] = 255
        # new outline along the filled edge
        edge = new & ~ndimage.binary_erosion(new, iterations=1) & ndimage.binary_dilation(gap, iterations=1)
        Ts[edge, :3] = 35; Ts[edge, 3] = 255; Ms[edge] = 0; Ms[edge, 3] = 255
        Ms[gap, 3] = 255
        n += int(gap.sum())
    return n


def fill_shoulders(T, M, p, cat):
    """tops leaving the shoulders bare next to the collar: fill the top part of the torso piece"""
    return fill_template(T, M, p, cat, which=('Armor Body',), top_frac=0.35)


def grow_feet(T, M, p, cat, k=1.12):
    """socks / shoes a little smaller than the foot (skin shows at the sole): side-view foot pieces
    scaled up around the bottom-centre of the sole"""
    n = 0
    for name, v in p['sprites'].items():
        if name not in ('Boots Foot L', 'Boots Foot R'):
            continue
        x, y, w, h = v['region']; sl = (slice(y, y + h), slice(x, x + w))
        a = T[sl][..., 3] > 0
        if not a.any():
            continue
        ys, xs = np.nonzero(a); cx, by = (xs.min() + xs.max()) / 2, ys.max()
        for A in (T, M):
            im = Image.fromarray(A[sl].astype(np.uint8), 'RGBA')
            big = im.resize((round(w * k), round(h * k)), Image.LANCZOS if A is T else Image.NEAREST)
            out = Image.new('RGBA', (w, h), (0, 0, 0, 0))
            out.paste(big, (round(cx - cx * k), round(by - by * k)))
            A[sl] = np.asarray(out).astype(np.float32)
        n += int((T[sl][..., 3] > 0).sum() - a.sum())
    return n


def strays(T, M, p, cat):
    """separate specks and stray lines next to a piece (left over from cutting it out) -> removed"""
    n = 0
    for name, v in p['sprites'].items():
        x, y, w, h = v['region']; sl = (slice(y, y + h), slice(x, x + w))
        a = T[sl][..., 3] > 30
        lab, k = ndimage.label(ndimage.binary_dilation(a, iterations=1))
        if k < 2:
            continue
        sizes = ndimage.sum(a, lab, range(1, k + 1))
        small = np.isin(lab, 1 + np.nonzero(sizes < 0.05 * sizes.max())[0]) & (T[sl][..., 3] > 0)
        Ts, Ms = T[sl], M[sl]
        Ts[small] = 0; Ms[small] = 0
        n += int(small.sum())
    return n


FIXES = {'strays': strays, 'grow_feet': grow_feet, 'fill_template': fill_template, 'fill_shoulders': fill_shoulders, 'back_legs': back_legs, 'unface': unface, 'fill_sleeves': fill_sleeves, 'blank_shins': blank_shins, 'drop1': drop(0), 'drop2': drop(1), 'drop3': drop(2), 'unskin': unskin, 'fill_feet': fill_feet, 'rear_strap': rear_strap, 'white_holes': white_holes}


def main(pack, name, fixes):
    pj = os.path.join(ROOT, pack, 'parts.json') if not pack.endswith('.json') else pack
    d = json.load(open(pj))
    for cat, lst in d['categories'].items():
        for p in lst:
            if p['name'] != name:
                continue
            tp, mp = (os.path.join(ROOT, p[k][len('res://'):]) for k in ('texture', 'mask'))
            os.makedirs(BACK, exist_ok=True)
            for f in (tp, mp):
                b = os.path.join(BACK, os.path.basename(os.path.dirname(os.path.dirname(os.path.dirname(f)))) + '__' + os.path.basename(f))
                if not os.path.exists(b):
                    shutil.copy(f, b)
            T = np.asarray(Image.open(tp).convert('RGBA')).astype(np.float32).copy()
            M = np.asarray(Image.open(mp).convert('RGBA')).astype(np.float32).copy()
            for fx in fixes:
                mv = next((k for k in ('down', 'up', 'left', 'right') if fx.startswith(k) and fx[len(k):].isdigit()), None)
                if mv:
                    n = int(fx[len(mv):]); ax = 0 if mv in ('down', 'up') else 1; n = n if mv in ('down', 'right') else -n
                    for A in (T, M):
                        A[:] = np.roll(A, n, axis=ax)
                        if ax == 0:
                            A[:n] = 0 if n > 0 else A[:n]
                            if n < 0: A[n:] = 0
                        else:
                            if n > 0: A[:, :n] = 0
                            else: A[:, n:] = 0
                    print('%s: moved %s %d px' % (name, mv, abs(n)))
                    continue
                print('%s: %s changed %d px' % (name, fx, FIXES[fx](T, M, p, cat)))
            Image.fromarray(np.clip(T, 0, 255).astype(np.uint8)).save(tp)
            Image.fromarray(np.clip(M, 0, 255).astype(np.uint8)).save(mp)
            return
    sys.exit('not found: ' + name)


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], sys.argv[3:])
