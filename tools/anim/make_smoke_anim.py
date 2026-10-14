"""Writes custom/smoking/animations.json: a "Smoke" clip for CC2DCharacter.

    python3 tools/anim/make_smoke_anim.py

Built from CC2D's Idle (tiled to the clip length) with the right arm raised to the mouth and back.
The arm offsets per body (radians, Godot space) were found by tests/smoke_pose.gd, which searches for
the pose that puts the held item's "mouth_end" at the lips with the hand off the face and the lit end
pointing away. "smoke" lists the exhale windows (seconds) in which CC2DCharacter puffs smoke from the
mouth. Same format as cc2d/animations/cc2d.json; per-body tracks go under "bodies"."""
import json, math, os
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
SRC = json.load(open(os.path.join(ROOT, 'cc2d/animations/cc2d.json')))['animations']['Idle']
L, FPS = 6.0, 30
RAISE, HOLD_END, LOWER_END = (0.6, 1.3), 2.6, 3.3
POSE = {   # Bone_Upper Arm R, Bone_Lower Arm R, Bone_Hand R offsets
    'Male':   {'Upper Arm R': -1.15, 'Lower Arm R': -1.90, 'Hand R': 0.60},
    'Female': {'Upper Arm R': -0.95, 'Lower Arm R': -1.90, 'Hand R': 0.10},
}
EXHALE = [[3.2, 4.4]]


def sample(tr, t):
    ts, vs = tr['times'], tr['values']
    t = t % SRC['length']
    if t <= ts[0]:
        return vs[0]
    for i in range(1, len(ts)):
        if t <= ts[i]:
            if not isinstance(vs[i], (int, float)) or isinstance(vs[i], bool):
                return vs[i - 1]
            u = (t - ts[i - 1]) / max(ts[i] - ts[i - 1], 1e-6)
            return vs[i - 1] + (vs[i] - vs[i - 1]) * u
    return vs[-1]


def smooth(a, b, t):
    u = min(max((t - a) / (b - a), 0.0), 1.0)
    return u * u * (3 - 2 * u)


def weight(t):   # 0 = idle arm, 1 = hand at the mouth
    return smooth(*RAISE, t) * (1 - smooth(HOLD_END, LOWER_END, t))


times = [round(i / FPS, 4) for i in range(int(L * FPS) + 1)]
common = []
for tr in SRC['tracks']:
    if tr['prop'] in ('rotation', 'position:x', 'position:y', 'scale:x', 'scale:y', 'alpha'):
        common.append({'path': tr['path'], 'prop': tr['prop'], 'times': times, 'values': [round(sample(tr, t), 5) for t in times]})
    else:   # discrete keys (visible, sprite, emote): repeat Idle's keys over the clip
        ts, vs = [], []
        for k in range(int(L / SRC['length']) + 1):
            for t, v in zip(tr['times'], tr['values']):
                if k * SRC['length'] + t <= L:
                    ts.append(round(k * SRC['length'] + t, 4)); vs.append(v)
        common.append({'path': tr['path'], 'prop': tr['prop'], 'times': ts, 'values': vs})
arm = [tr for tr in common if tr['prop'] == 'rotation' and any(tr['path'].endswith('Bone_' + b) for b in POSE['Male'])]
paths = {b: next(tr['path'] for tr in common if tr['path'].endswith('Bone_' + b)) if any(tr['path'].endswith('Bone_' + b) for tr in common)
         else None for b in POSE['Male']}
common = [tr for tr in common if tr not in arm]
bodies = {}
for body, pose in POSE.items():
    tracks = []
    for bone, off in pose.items():
        base = next((tr for tr in SRC['tracks'] if tr['path'].endswith('Bone_' + bone) and tr['prop'] == 'rotation'), None)
        path = base['path'] if base else 'Root/Pos_Hip/Bone_Hip/Pos_Body/Bone_Body/Pos_Upper Arm R/Bone_Upper Arm R/Pos_Lower Arm R/Bone_Lower Arm R/Pos_Hand R/Bone_Hand R'
        vals = [round((sample(base, t) if base else 0.0) + off * weight(t), 5) for t in times]
        tracks.append({'path': path, 'prop': 'rotation', 'times': times, 'values': vals})
    bodies[body] = {'tracks': tracks}
out = {'format': 1, 'animations': {'Smoke': {'length': L, 'loop': True, 'tracks': common, 'bodies': bodies, 'smoke': EXHALE}}}
dst = os.path.join(ROOT, 'custom/smoking/animations.json')
json.dump(out, open(dst, 'w'))
print('wrote', dst, len(common), 'common tracks;', {b: len(v['tracks']) for b, v in bodies.items()}, 'per body')
