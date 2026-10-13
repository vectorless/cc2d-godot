"""Tiny Replicate client: python3 rep.py <model> <input.json> <out_prefix>
input.json values that are local file paths under key 'files:<field>' get data-URI'd."""
import json, sys, time, base64, urllib.request, os, mimetypes
TOKEN = open(os.path.expanduser('~/.secrets/replicate')).read().strip()
API = 'https://api.replicate.com/v1'

def req(method, url, body=None, headers=None):
    h = {'Authorization': 'Bearer ' + TOKEN, 'Content-Type': 'application/json'}
    h.update(headers or {})
    for attempt in range(12):
        r = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None, headers=h, method=method)
        try:
            with urllib.request.urlopen(r, timeout=300) as f:
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
    inp = dict(inp)
    for k in list(inp):
        if k.startswith('files:'):
            inp[k[6:]] = [data_uri(p) for p in inp.pop(k)]
    t0 = time.time()
    p = req('POST', '%s/models/%s/predictions' % (API, model), {'input': inp}, {'Prefer': 'wait=60'})
    while p['status'] not in ('succeeded', 'failed', 'canceled'):
        time.sleep(3)
        p = req('GET', p['urls']['get'])
    if p['status'] != 'succeeded':
        print('FAILED', model, p.get('error'))
        return []
    out = p['output'] if isinstance(p['output'], list) else [p['output']]
    files = []
    for i, u in enumerate(out):
        ext = os.path.splitext(u.split('?')[0])[1] or '.png'
        fn = '%s_%d%s' % (out_prefix, i, ext)
        urllib.request.urlretrieve(u, fn)
        files.append(fn)
    print('ok', model, '%.0fs' % (time.time() - t0), files, 'metrics', p.get('metrics'))
    return files

if __name__ == '__main__':
    run(sys.argv[1], json.load(open(sys.argv[2])), sys.argv[3])
