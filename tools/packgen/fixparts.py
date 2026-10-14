"""Post-fixes for finished custom parts (texture + mask in place; originals backed up to ~/packgen_work/_backup).

    python3 fixparts.py <pack dir> "<Part name>" <fix> [<fix> ...]

fixes:
  unskin       skin drawn into the part (bare thigh between garter straps...) -> transparent, so the body shows
  fill_feet    white socks whose foot was cut away with the white background -> fill the foot back in
  rear_strap   strap(s) rising above the neckline on the back (left) side -> removed
  white_holes  flat white areas enclosed by the drawing (between straps, inside rings) -> transparent
  down<N> / up<N> / left<N> / right<N>   move the whole part by N px (e.g. down110: a visor sitting too high)
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


def fill_feet(T, M, p, cat):
    n = 0
    for name, v in p['sprites'].items():
        if not name.startswith('Boots Foot'):
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


FIXES = {'drop1': drop(0), 'drop2': drop(1), 'drop3': drop(2), 'unskin': unskin, 'fill_feet': fill_feet, 'rear_strap': rear_strap, 'white_holes': white_holes}


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
