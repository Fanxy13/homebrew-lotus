"""The test of /bg setup, run by the real worker on engines that give what they are told: what a graphics card makes of
the test picture has to be the disc, a processor's cut-out is not judged this way. Needs numpy.

python selftest-judges-the-card.py <lib/bg> <answer file>
the answer, one line per case: "<device> ok", or "<device> <the code of the error>"
"""
import argparse
import sys

sys.path.insert(0, sys.argv[1])
import numpy as np

import engines
import worker

yy, xx = np.mgrid[0:1024, 0:1024]
inside = (yy - 512) ** 2 + (xx - 512) ** 2 < 300 ** 2


class Fake:
    label = "Fake"

    def __init__(self, device, alpha):
        self.device, self.alpha = device, alpha

    def predict(self, rgb):
        return self.alpha


cases = [
    ("gpu", inside.astype(np.float32)),                  # the disc, as it should be
    ("gpu", np.full((1024, 1024), 0.9, np.float32)),     # everything kept
    ("gpu", (~inside).astype(np.float32)),               # the other way round
    ("gpu", np.zeros((1024, 1024), np.float32)),         # nothing at all
    ("cpu", np.full((1024, 1024), 0.9, np.float32)),     # a processor is not judged by the disc
]
answer = []
for device, alpha in cases:
    engines.load = lambda *args, d=device, a=alpha: Fake(d, a)
    try:
        worker.cmd_selftest(argparse.Namespace(model="x", models_dir="y", backend="auto"))
        answer.append(f"{device} ok")
    except worker.BgError as e:
        answer.append(f"{device} {e.code}")
open(sys.argv[2], "w", encoding="utf-8").write("\n".join(answer))
