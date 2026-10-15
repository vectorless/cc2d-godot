"""Re-cut a held prop from its generated image at a chosen size, its bottom at the hand.

    python3 recut_prop.py specs/<pack>.json <part id> <height px> [bottom y px] [--tip] [--top] [--flip] [--widen=1.5]

The item is cut out of gen_0.png (background and enclosed flat white made transparent), scaled to
<height> px tall (the character is ~1100 px tall, so ~6 px per cm), centred on the grip column and
placed with its bottom at <bottom y> in the 512x1024 one-handed weapon sheet (the grip is at y 758).
Re-registers the part (texture, mask, colours). --tip also stores "smoke_tip": the top-centre of the
item in weapon-local pixels, where CC2DCharacter puts a smoke wisp."""
import sys, os, json
import numpy as np
from PIL import Image
from scipy import ndimage
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
os.chdir(os.path.join(HERE, '..', '..'))
import packgen, recolor

args = [a for a in sys.argv[1:] if not a.startswith('--')]
spec_path, pid, H = args[0], args[1], int(args[2])
bottom = int(args[3]) if len(args) > 3 else 790   # with --top: the item's TOP goes here instead (a pipe hangs from its mouthpiece)
spec = json.load(open(os.path.join(HERE, spec_path) if not os.path.exists(spec_path) else spec_path))
p = [x for x in spec['parts'] if x['id'] == pid][0]
wd = os.path.expanduser('~/packgen_work/%s/%s' % (spec['package'].replace(' ', '_'), pid))
g = np.asarray(Image.open(wd + '/gen_0.png').convert('RGB')).astype(np.float32)
whiteish = (g.min(-1) > 232) & (np.ptp(g, axis=-1) < 16)
obj = ~whiteish
lab, n = ndimage.label(obj); sizes = ndimage.sum(obj, lab, range(1, n + 1))
obj = lab == 1 + int(np.argmax(sizes))          # the item only (drops drawn smoke wisps and specks)
filled = ndimage.binary_fill_holes(obj)
hl, hn = ndimage.label(filled & whiteish); hs = ndimage.sum(filled & whiteish, hl, range(1, hn + 1))
fg = filled & ~np.isin(hl, 1 + np.nonzero(hs >= 150)[0])
ys, xs = np.nonzero(fg); x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
inner = ndimage.binary_erosion(fg, iterations=1)
edge = ndimage.binary_dilation(fg, iterations=1) & ~inner
a = np.where(inner, 1.0, np.where(edge, np.clip((255 - g.min(-1)) / 120, 0, 1), 0.0))
rgb = np.where(edge[..., None], np.clip((g - 255 * (1 - a[..., None])) / np.maximum(a, 1e-3)[..., None], 0, 255), g)
rgba = np.dstack([rgb, a * 255])[y0:y1, x0:x1]
s = H / (y1 - y0); w = max(1, round((x1 - x0) * s))
for a_ in sys.argv:
    if a_.startswith('--widen='):   # thicker than drawn (e.g. a cigarette that would vanish at game size)
        w = max(1, round(w * float(a_.split('=')[1])))
piece = Image.fromarray(rgba.astype(np.uint8), 'RGBA').resize((w, H), Image.LANCZOS)
if '--flip' in sys.argv:          # upside down: e.g. a cigarette held with the filter up and the lit end down
    piece = piece.transpose(Image.FLIP_TOP_BOTTOM)
tp = packgen.template_part(p['category'], p['template'])
W0, H0 = Image.open(packgen.res_path(tp['texture'])).size
out = Image.new('RGBA', (W0, H0), (0, 0, 0, 0))
left, top = W0 // 2 - w // 2, (bottom if '--top' in sys.argv else bottom - H)
if '--top' in sys.argv:
    left = W0 // 2 - int(np.nonzero(np.asarray(piece)[..., 3][:8].max(0) > 60)[0].mean())   # mouthpiece over the grip
out.alpha_composite(piece, (left, top))
out.save(wd + '/part.png')
colors = recolor.split(wd + '/part.png', wd + '/tex.png', wd + '/mask.png')
extra = {'template': p['template'], 'desc': p['desc']}
if '--tip' in sys.argv:
    off = list(tp['sprites'].values())[0].get('offset', [-W0 / 2, -H0 / 2])
    # sprite pixel (x, y) -> weapon-local (x + off.x, y + off.y). The smoke comes from the ember: the
    # brightest orange-red pixels of the original drawing (else the top-centre of the item)
    P = np.asarray(piece).astype(np.float32); r, gg, b, al = P[..., 0], P[..., 1], P[..., 2], P[..., 3]
    ember = (al > 128) & (r > 200) & (r - b > 90) & (gg < r - 30)
    if ember.sum() >= 3:
        ey, ex = np.nonzero(ember); tx, ty = left + ex.mean(), top + (ey.max() if '--flip' in sys.argv else ey.min())
    else:
        tx, ty = W0 / 2, top + 4
    extra['smoke_tip'] = [round(float(tx + off[0]), 1), round(float(ty + off[1]), 1)]
    # the end that goes in the mouth: the top-centre (filter / mouthpiece), weapon-local
    toprow = np.nonzero(np.asarray(piece)[..., 3][:4].max(0) > 60)[0]
    extra['mouth_end'] = [round(float(left + toprow.mean() + off[0]), 1), round(float(top + off[1]), 1)]
packgen.register(spec['pack_dir'], spec['package'], p['category'], p['name'], tp, wd + '/tex.png', wd + '/mask.png', colors, extra)
print(pid, 'size %dx%d bottom %d' % (w, H, bottom), extra.get('smoke_tip', ''))
