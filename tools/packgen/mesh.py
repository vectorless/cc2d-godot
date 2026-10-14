"""Tiny Meshy image-to-image client, same interface as rep.py:
    python3 mesh.py <model> <input.json> <out_prefix>
model is 'meshy/<ai_model>' (e.g. meshy/nano-banana-pro, 9 credits; meshy/nano-banana-2, 6 credits).
Takes the same input dict packgen builds for Replicate: prompt, files:image_input (local paths), aspect_ratio.
The API key is read from ~/.secrets/meshy. Never commit it."""
import json, sys, time, base64, urllib.request, urllib.error, os, mimetypes
API = 'https://api.meshy.ai/openapi/v1/image-to-image'


def _key():
    return open(os.path.expanduser('~/.secrets/meshy')).read().strip()


def req(method, url, body=None):
    h = {'Authorization': 'Bearer ' + _key(), 'Content-Type': 'application/json'}
    for attempt in range(12):
        r = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None, headers=h, method=method)
        try:
            with urllib.request.urlopen(r, timeout=120) as f:
                return json.load(f)
        except urllib.error.HTTPError as e:
            if e.code != 429 or attempt == 11:
                print('HTTP', e.code, e.read()[:300])
                raise
            time.sleep(float(e.headers.get('Retry-After') or 10))


def data_uri(path):
    mt = mimetypes.guess_type(path)[0] or 'image/png'
    return 'data:%s;base64,%s' % (mt, base64.b64encode(open(path, 'rb').read()).decode())


def run(model, inp, out_prefix):
    ai_model = model.split('/', 1)[1] if model.startswith('meshy/') else model
    refs = []
    for k in list(inp):
        if k.startswith('files:'):
            refs += [data_uri(p) for p in inp[k]]
    body = {'ai_model': ai_model, 'prompt': inp['prompt'], 'reference_image_urls': refs[:5]}
    allowed = ['1:1', '16:9', '9:16', '4:3', '3:4'] + (['3:2', '2:3'] if 'gpt-image' in ai_model else [])
    ar = inp.get('aspect_ratio')
    pad = None
    if ar and ar not in allowed:
        # pad the reference image with white to the nearest supported shape, crop the result back afterwards
        from PIL import Image
        src = [v for k in inp if k.startswith('files:') for v in inp[k]][0]
        im = Image.open(src).convert('RGB'); w, h = im.size
        ratio = lambda r: float(r.split(':')[0]) / float(r.split(':')[1])
        best = min((r for r in allowed if ratio(r) >= w / h - 1e-6 or ratio(r) <= w / h + 1e-6),
                   key=lambda r: (abs(ratio(r) - w / h) if (ratio(r) >= w / h) == (w >= h) else 9))
        R = ratio(best); W2, H2 = (max(w, round(h * R)), max(h, round(w / R)))
        canvas = Image.new('RGB', (W2, H2), 'white'); canvas.paste(im, ((W2 - w) // 2, (H2 - h) // 2))
        tmp = out_prefix + '_padded.png'; canvas.save(tmp)
        refs = [data_uri(tmp)] + refs[1:]
        body['reference_image_urls'] = refs[:5]
        pad = (W2, H2, w, h); ar = best
    if ar in allowed:
        body['aspect_ratio'] = ar
    t0 = time.time()
    tid = req('POST', API, body)['result']
    while True:
        time.sleep(4)
        t = req('GET', '%s/%s' % (API, tid))
        if t['status'] in ('SUCCEEDED', 'FAILED', 'CANCELED'):
            break
    if t['status'] != 'SUCCEEDED':
        print('FAILED', model, t.get('task_error'))
        return []
    files = []
    for i, u in enumerate(t.get('image_urls') or []):
        fn = '%s_%d.png' % (out_prefix, i)
        tmp = fn + '.dl'
        urllib.request.urlretrieve(u, tmp)
        from PIL import Image
        im = Image.open(tmp).convert('RGB')         # whatever format Meshy returns -> png
        if pad:                                     # undo the padding: crop the original area back out
            W2, H2, w, h = pad; sx, sy = im.width / W2, im.height / H2
            x0, y0 = (W2 - w) // 2 * sx, (H2 - h) // 2 * sy
            im = im.crop((round(x0), round(y0), round(x0 + w * sx), round(y0 + h * sy)))
        im.save(fn)
        os.remove(tmp)
        files.append(fn)
    print('ok', model, '%.0fs' % (time.time() - t0), files, 'credits', t.get('consumed_credits'), 'task', tid)
    return files


if __name__ == '__main__':
    run(sys.argv[1], json.load(open(sys.argv[2])), sys.argv[3])
