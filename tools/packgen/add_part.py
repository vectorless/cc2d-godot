"""Register a generated texture as a part of a custom pack.
python3 add_part.py <pack dir> <package name> <category> <part name> <texture.png> <template part name> [mask.png] [colors json]
Copies the texture into <pack dir>/textures/<category>/ and adds/replaces the part in
<pack dir>/parts.json, taking sprite rectangles / pivots / body types from the template part in
cc2d/parts.json (the texture must follow that template's guide layout)."""
import json, os, sys, shutil
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))

def main(pack_dir, package, category, name, tex, template, mask=None, colors=None):
    cat = json.load(open(os.path.join(ROOT, 'cc2d/parts.json')))
    tp = next(p for p in cat['categories'][category] if p['name'] == template)
    dst_dir = os.path.join(pack_dir, 'textures', category)
    os.makedirs(dst_dir, exist_ok=True)
    def place(src, suffix=''):
        fn = name + suffix + '.png'
        shutil.copyfile(src, os.path.join(dst_dir, fn))
        return 'res://' + os.path.relpath(os.path.join(dst_dir, fn), ROOT)
    tex_res = place(tex)
    mask_res = place(mask, ' Mask') if mask else None
    part = {k: v for k, v in tp.items() if k not in ('name', 'package', 'texture', 'mask', 'sprites')}
    if colors:
        part['colors'] = json.loads(colors)   # the designed look; CC2D itself keeps the slot's colours
    part.update({'name': name, 'package': package, 'texture': tex_res, 'mask': mask_res, 'template': template,
                 'sprites': {k: dict(v, texture=tex_res) for k, v in tp['sprites'].items()}})
    pj = os.path.join(pack_dir, 'parts.json')
    data = json.load(open(pj)) if os.path.exists(pj) else {'format': 1, 'package': package, 'categories': {}}
    lst = data['categories'].setdefault(category, [])
    lst[:] = [p for p in lst if p['name'] != name] + [part]
    json.dump(data, open(pj, 'w'), indent=1)
    print('added', package, category, name, '->', tex_res)

if __name__ == '__main__':
    main(*sys.argv[1:])
