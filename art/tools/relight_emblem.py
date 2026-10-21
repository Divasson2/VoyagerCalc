#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# relight_emblem.py (0.6.7): paint the new per-model emblems (art/icon/emblem-<m>-1024.png, made by
# `make_icon_square.py --emblems-only`) onto the faces that already exist, without re-running the colour
# correction of colour_faces.py (which is not meant to be applied twice). Only the badge square changes.
# The previous faces are kept as face_<m>[_nolcd]_oldN.png in art/faces (never in app/Resources).
#   /workspace/.venv-faces/bin/python art/tools/relight_emblem.py
import json, os, shutil, sys
import numpy as np
sys.path.insert(0, os.path.dirname(__file__))
import make_faces as mf
import colour_faces as cf

def main():
    geo = json.load(open(os.path.join(cf.FACES, 'geometry.json')))
    for m in ('12c', '15c', '16c'):
        nol_p, full_p = [os.path.join(cf.FACES, f'face_{m}{s}.png') for s in ('_nolcd', '')]
        for p in (nol_p, full_p):
            a = cf.load(p)
            new = cf.emblem(a, geo[m], m)
            changed = int((new[..., :3] != a[..., :3]).any(2).sum())
            shutil.copyfile(p, cf.next_old(p)); cf.save(new, p)
            print(os.path.basename(p), 'pixels changed:', changed)
        shutil.copyfile(nol_p, os.path.join(cf.ROOT, 'app', 'Resources', 'Faces', f'face_{m}_nolcd.png'))

if __name__ == '__main__':
    main()
