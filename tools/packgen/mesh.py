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
    if inp.get('aspect_ratio') in ('1:1', '16:9', '9:16', '4:3', '3:4', '3:2', '2:3'):
        body['aspect_ratio'] = inp['aspect_ratio']
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
        Image.open(tmp).convert('RGB').save(fn)   # whatever format Meshy returns -> png
        os.remove(tmp)
        files.append(fn)
    print('ok', model, '%.0fs' % (time.time() - t0), files, 'credits', t.get('consumed_credits'), 'task', tid)
    return files


if __name__ == '__main__':
    run(sys.argv[1], json.load(open(sys.argv[2])), sys.argv[3])
