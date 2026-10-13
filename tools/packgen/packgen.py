"""Batch generator for custom CC2D part packs.

    python3 packgen.py run specs/gangster.json [more specs...] [--budget 150] [--only ID] [--redo ID]
    python3 packgen.py list specs/*.json
    python3 packgen.py reconvert specs/x.json [--only ID]   (redo fitting/colours from the saved image, no API call)

A spec file: {"pack_dir": "custom/gangster", "package": "Gangster", "parts": [
   {"id": "jacket_m", "category": "Armor", "name": "Gangster 01 Male", "template": "Daily 09 Male",
    "desc": "a 1950s ... suit jacket", "mode": "identity"|"fit", "model": "google/nano-banana-pro"}, ...]}

For each part not yet done: template sheet -> canvas -> image model -> pieces cut out and placed on
the template's sprite rectangles -> CC2D grey texture + colour mask -> registered in the pack's
parts.json. Work files go to ~/packgen_work/<package>/<id>/ (outside the repo). Resumable: a part
is skipped when its done.json exists. --budget stops starting new parts after N seconds.
"""
import json, os, sys, time
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rep, mesh, recolor
from ccpack import piece_mask, bbox

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
WORK = os.path.expanduser('~/packgen_work')
ASPECTS = {'1:1': 1.0, '3:2': 1.5, '2:3': 2 / 3, '4:3': 4 / 3, '3:4': 0.75, '16:9': 16 / 9, '9:16': 9 / 16, '21:9': 21 / 9}
CATALOGUE = None

PIECE_WORDS = {
    'Armor Body': 'the torso', 'Armor Neck': 'a collar piece', 'Armor Upper Arm R': 'an upper-arm sleeve',
    'Armor Upper Arm L': 'an upper-arm sleeve', 'Armor Lower Arm R': 'a forearm sleeve', 'Armor Lower Arm L': 'a forearm sleeve',
    'Pants Hip': 'the hips / waist piece', 'Pants Upper Leg R': 'a thigh piece', 'Pants Upper Leg L': 'a thigh piece',
    'Pants Lower Leg R': 'a shin piece', 'Pants Lower Leg L': 'a shin piece', 'Pants Lower Leg F': 'a front-facing shin piece',
    'Boots Foot R': 'a shoe seen from the side', 'Boots Foot L': 'a shoe seen from the side', 'Boots Foot F': 'a shoe seen from the front',
    'Boots Lower Leg R': 'a boot shaft (lower leg)', 'Boots Lower Leg L': 'a boot shaft (lower leg)', 'Boots Lower Leg F': 'a front-facing boot shaft',
    'Hair S': 'a hairstyle (hair only, no head or face)', 'Hair B': 'the back layer of the hair (behind the head)',
    'Hair F': 'the front layer of the hair (over the forehead and ears)', 'Helmet F': 'the hat / headwear (no head)',
    'Helmet B': 'the back part of the headwear', 'Facial Hair': 'the facial hair only (no face)', 'Weapon': 'the held item',
    'Gloves Hand R 0': 'a gloved hand', 'Gloves Hand R 1': 'a gloved hand', 'Gloves Hand L 0': 'a gloved hand', 'Gloves Hand L 1': 'a gloved hand',
    'Gloves Lower Arm R': 'a glove cuff', 'Gloves Lower Arm L': 'a glove cuff',
}
KEEP = (" Keep every piece exactly where it is, at the same size, with the same silhouette and the same three-quarter angle, so it still fits "
        "the character's body. Same art style as the input: hand-drawn cartoon with bold black outlines and soft cel shading. "
        "Plain white background and nothing else: no body, no skin, no hands, no text, no labels, no logos.")


def catalogue():
    global CATALOGUE
    if CATALOGUE is None:
        CATALOGUE = json.load(open(os.path.join(ROOT, 'cc2d/parts.json')))
    return CATALOGUE


def template_part(category, name):
    for p in catalogue()['categories'][category]:
        if p['name'] == name:
            return p
    raise KeyError('%s / %s' % (category, name))


def res_path(res):
    return os.path.join(ROOT, res[len('res://'):])


def regions_of(category, tp, size):
    if category in ('Cape', 'Skirt'):
        return {'Cloth': [0, 0, size[0], size[1]]}
    return {k: v['region'] for k, v in tp['sprites'].items()}


def make_canvas(tex_path, out_path, long_side=2048):
    t = Image.open(tex_path).convert('RGBA')
    W, H = t.size
    r = W / H
    aspect = min(ASPECTS, key=lambda k: abs(np.log(ASPECTS[k] / r)))
    ar = ASPECTS[aspect]
    cw, ch = (long_side, round(long_side / ar)) if ar >= 1 else (round(long_side * ar), long_side)
    s = min(cw / W, ch / H)
    pw, ph = round(W * s), round(H * s)
    box = [(cw - pw) // 2, (ch - ph) // 2, pw, ph]
    bg = Image.new('RGBA', t.size, (255, 255, 255, 255))
    bg.alpha_composite(t)
    c = Image.new('RGB', (cw, ch), 'white')
    c.paste(bg.convert('RGB').resize((pw, ph), Image.LANCZOS), (box[0], box[1]))
    c.save(out_path)
    return {'aspect': aspect, 'canvas': [cw, ch], 'box': box, 'size': [W, H]}


def describe(category, tp):
    names = list(tp['sprites'].keys()) if category not in ('Cape', 'Skirt') else []
    if category == 'Cape':
        return "This image is the texture of a cape for a 2D cut-out game character: one long cloth panel hanging from the shoulders, top edge at the top."
    if category == 'Skirt':
        return "This image is the texture of a skirt for a 2D cut-out game character: one piece, waistband at the top."
    words = [PIECE_WORDS.get(n, n.lower()) for n in names]
    uniq = []
    for w in words:
        if w not in uniq:
            uniq.append(w)
    counts = {w: words.count(w) for w in uniq}
    parts = [(('two ' + w.split(' ', 1)[1] + 's') if counts[w] == 2 and w.startswith(('a ', 'an ')) else
              (('%d %ss' % (counts[w], w.split(' ', 1)[1])) if counts[w] > 2 else w)) for w in uniq]
    lst = ', '.join(parts[:-1]) + (' and ' if len(parts) > 1 else '') + parts[-1]
    n = len(names)
    if n == 1:
        return "This image is a sprite for a 2D cut-out game character: %s, on a white background." % lst
    return ("This image is a sprite sheet for a 2D cut-out game character: %d separate pieces of one item on a white background - %s." % (n, lst))


def fit_rule(sprite):
    """How a generated piece is placed on the template's piece (see convert)."""
    if sprite in ('Armor Body', 'Armor Neck', 'Pants Hip', 'Cloth') or sprite.startswith('Gloves'):
        return 'box'
    if 'Arm' in sprite or 'Leg' in sprite:
        return 'length'
    if sprite.startswith('Boots Foot'):
        return 'foot'
    if sprite.startswith(('Helmet', 'Hair')):
        return 'head'
    if sprite in ('Facial Hair', 'Weapon') or sprite.startswith(('Bow', 'Shield')):
        return 'width'
    return 'none'


def convert(gen_path, meta, tex_path, regions, out_path, mode='auto'):
    tmpl = Image.open(tex_path).convert('RGBA')
    W, H = tmpl.size
    talpha = np.asarray(tmpl)[:, :, 3]
    g = Image.open(gen_path).convert('RGB').resize(tuple(meta['canvas']), Image.LANCZOS)
    x, y, pw, ph = meta['box']
    g = g.crop((x, y, x + pw, y + ph)).resize((2 * W, 2 * H), Image.LANCZOS)
    g2 = np.asarray(g).astype(np.float32)
    out = np.zeros((H * 2, W * 2, 4), np.float32)
    report = {}
    for name, (rx, ry, rw, rh) in regions.items():
        X, Y, Wr, Hr = 2 * rx, 2 * ry, 2 * rw, 2 * rh
        rect = g2[Y:Y + Hr, X:X + Wr]
        fg = piece_mask(rect)
        gb = bbox(fg)
        if gb is None:
            report[name] = 'empty'
            continue
        tb = bbox(talpha[ry:ry + rh, rx:rx + rw] > 20)
        canvas_rgb = rect.copy()
        canvas_a = fg.astype(np.float32)
        rule = fit_rule(name) if mode != 'identity' else 'none'
        if rule != 'none' and tb is not None:
            tb = [2 * v for v in tb]
            gx0, gy0, gx1, gy1 = gb
            tx0, ty0, tx1, ty1 = tb
            gw, gh, tw, th = gx1 - gx0, gy1 - gy0, tx1 - tx0, ty1 - ty0
            sx = sy = 1.0
            if rule == 'box':        # covers the body: fill the template's box (bounded stretch)
                sx, sy = tw / gw, th / gh
                if abs(np.log(sx / sy)) > 0.25:
                    sx = sy = np.sqrt(sx * sy)
                ax, ay = 'c', 't'
            elif rule == 'length':   # limbs: same length so the joints line up; keep its own width
                sx = sy = th / gh
                ax, ay = 'c', 't'
            elif rule == 'foot':     # shoes: same length, sole on the template's sole
                sx = sy = tw / gw
                ax, ay = 'c', 'b'
            elif rule == 'head':     # hats / hair: no bigger than ~1.4x the template, sitting on the same spot
                sx = sy = min(1.0, 1.45 * tw / gw, 1.3 * th / gh)
                ax, ay = 'c', 'b'
            elif rule == 'width':    # facial hair, weapons: same overall size
                sx = sy = min(tw / gw, th / gh) if gw / gh > 0 else 1.0
                ax, ay = 'c', 'c'
            nw, nh = max(1, round(gw * sx)), max(1, round(gh * sy))
            pim = Image.fromarray(rect[gy0:gy1, gx0:gx1].astype(np.uint8)).resize((nw, nh), Image.LANCZOS)
            mim = Image.fromarray((fg[gy0:gy1, gx0:gx1] * 255).astype(np.uint8)).resize((nw, nh), Image.LANCZOS)
            px = int(round((tx0 + tx1) / 2 - nw / 2))
            py = int(round(ty0 if ay == 't' else (ty1 - nh if ay == 'b' else (ty0 + ty1) / 2 - nh / 2)))
            canvas_rgb = np.full((Hr, Wr, 3), 255, np.float32)
            canvas_a = np.zeros((Hr, Wr), np.float32)
            sx0, sy0, dx0, dy0 = max(0, -px), max(0, -py), max(0, px), max(0, py)
            cw, chh = min(nw - sx0, Wr - dx0), min(nh - sy0, Hr - dy0)
            canvas_rgb[dy0:dy0 + chh, dx0:dx0 + cw] = np.asarray(pim).astype(np.float32)[sy0:sy0 + chh, sx0:sx0 + cw]
            canvas_a[dy0:dy0 + chh, dx0:dx0 + cw] = np.asarray(mim).astype(np.float32)[sy0:sy0 + chh, sx0:sx0 + cw] / 255.0
            report[name] = '%s %.2fx%.2f' % (rule, sx, sy)
        else:
            report[name] = 'as drawn'
        # soften the cut edge and un-blend the anti-aliasing from the white background
        soft = np.asarray(Image.fromarray((canvas_a * 255).astype(np.uint8)).filter(__import__('PIL.ImageFilter', fromlist=['x']).GaussianBlur(1.2))).astype(np.float32) / 255.0
        lum = canvas_rgb.mean(axis=2) / 255.0
        edge = (soft > 0.02) & (soft < 0.98)
        a = np.where(edge, np.clip(np.maximum(soft * 0.5, (1.0 - lum) * 1.2), 0, 1) * (soft > 0.02), canvas_a)
        a = np.where(canvas_a > 0.98, 1.0, a)
        safe = np.maximum(a, 1e-3)[..., None]
        unblend = np.clip((canvas_rgb - 255.0 * (1 - a[..., None])) / safe, 0, 255)
        rgb = np.where(edge[..., None], unblend, canvas_rgb)
        out[Y:Y + Hr, X:X + Wr, :3] = rgb
        out[Y:Y + Hr, X:X + Wr, 3] = a * 255
    img = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), 'RGBA').resize((W, H), Image.LANCZOS)
    img.save(out_path)
    return report


def register(pack_dir, package, category, name, tp, tex_src, mask_src, colors, extra):
    pack_abs = os.path.join(ROOT, pack_dir)
    dst_dir = os.path.join(pack_abs, 'textures', category)
    os.makedirs(dst_dir, exist_ok=True)
    tex_dst = os.path.join(dst_dir, name + '.png')
    mask_dst = os.path.join(dst_dir, name + ' Mask.png')
    Image.open(tex_src).save(tex_dst)
    Image.open(mask_src).save(mask_dst)
    tex_res = 'res://' + os.path.relpath(tex_dst, ROOT)
    mask_res = 'res://' + os.path.relpath(mask_dst, ROOT)
    part = {k: v for k, v in tp.items() if k not in ('name', 'package', 'texture', 'mask', 'sprites')}
    part.update({'name': name, 'package': package, 'texture': tex_res, 'mask': mask_res,
                 'sprites': {k: dict(v, texture=tex_res) for k, v in tp['sprites'].items()},
                 'colors': colors})
    part.update(extra)
    pj = os.path.join(pack_abs, 'parts.json')
    data = json.load(open(pj)) if os.path.exists(pj) else {'format': 1, 'package': package, 'categories': {}}
    lst = data['categories'].setdefault(category, [])
    lst[:] = [p for p in lst if p['name'] != name] + [part]
    json.dump(data, open(pj, 'w'), indent=1)


def run_part(spec_file, spec, p, reuse=False):
    pkg = spec['package']
    wd = os.path.join(WORK, pkg.replace(' ', '_'), p['id'])
    os.makedirs(wd, exist_ok=True)
    cat = p['category']
    tp = template_part(cat, p['template'])
    tex_path = res_path(tp['texture'])
    size = Image.open(tex_path).size
    meta = make_canvas(tex_path, os.path.join(wd, 'canvas.png'))
    prompt = describe(cat, tp) + ' Redraw it as ' + p['desc'].rstrip('.') + '.' + KEEP
    model = p.get('model', spec.get('model', 'google/nano-banana-pro'))
    inp = {'prompt': prompt, 'files:image_input': [os.path.join(wd, 'canvas.png')], 'aspect_ratio': meta['aspect'],
           'resolution': '2K', 'output_format': 'png'}
    if 'gpt-image' in model:
        inp = {'prompt': prompt, 'files:input_images': [os.path.join(wd, 'canvas.png')], 'quality': 'high', 'output_format': 'png',
               'aspect_ratio': {'16:9': '2048x1152', '1:1': '1024x1024', '2:3': '1024x1536', '3:2': '1536x1024', '9:16': '1152x2048'}.get(meta['aspect'], 'auto')}
    t0 = time.time()
    if reuse and os.path.exists(os.path.join(wd, 'gen_0.png')):
        files = [os.path.join(wd, 'gen_0.png')]
    else:
        files = (mesh if model.startswith('meshy/') else rep).run(model, inp, os.path.join(wd, 'gen'))
    if not files:
        return False
    regions = regions_of(cat, tp, size)
    rgba = os.path.join(wd, 'part.png')
    rep_fit = convert(files[0], meta, tex_path, regions, rgba, p.get('mode', 'auto'))
    colors = recolor.split(rgba, os.path.join(wd, 'tex.png'), os.path.join(wd, 'mask.png'))
    extra = {'template': p['template'], 'desc': p['desc']}
    register(spec['pack_dir'], pkg, cat, p['name'], tp, os.path.join(wd, 'tex.png'), os.path.join(wd, 'mask.png'), colors, extra)
    json.dump({'model': model, 'seconds': round(time.time() - t0, 1), 'prompt': prompt, 'fit': rep_fit, 'meta': meta},
              open(os.path.join(wd, 'done.json'), 'w'), indent=1)
    print('  done %s/%s in %.0fs %s' % (pkg, p['name'], time.time() - t0, rep_fit))
    return True


def main(argv):
    cmd, rest = argv[0], argv[1:]
    budget, only, redo, files = 150.0, None, None, []
    i = 0
    while i < len(rest):
        if rest[i] == '--budget':
            budget = float(rest[i + 1]); i += 2
        elif rest[i] == '--only':
            only = rest[i + 1].split(','); i += 2
        elif rest[i] == '--redo':
            redo = rest[i + 1].split(','); i += 2
        else:
            files.append(rest[i]); i += 1
    t0 = time.time()
    pending = 0
    for f in files:
        spec = json.load(open(f))
        for p in spec['parts']:
            wd = os.path.join(WORK, spec['package'].replace(' ', '_'), p['id'])
            done = os.path.exists(os.path.join(wd, 'done.json'))
            if redo and p['id'] in redo and done:
                os.remove(os.path.join(wd, 'done.json')); done = False
            if only and p['id'] not in only:
                continue
            if cmd == 'list':
                print('%-6s %-14s %-10s %-28s %s' % ('done' if done else '-', spec['package'], p['category'], p['name'], p['template']))
                continue
            if cmd == 'reconvert':
                if os.path.exists(os.path.join(wd, 'gen_0.png')):
                    run_part(f, spec, p, reuse=True)
                continue
            if done:
                continue
            if time.time() - t0 > budget:
                pending += 1
                continue
            try:
                if not run_part(f, spec, p):
                    print('  FAILED', p['id'])
            except Exception as e:
                print('  ERROR', p['id'], repr(e)[:300])
    if cmd == 'run':
        print('pending:', pending)


if __name__ == '__main__':
    main(sys.argv[1:])
