"""A stand-in for lib/bg/worker.py in the tests of /bg on Windows: the same commands and events, no PyTorch.

run      copies each image to <stem>_no_bg.png (next to it, or into --out) – an image called broken.* fails with
         BG-005 as a real unreadable file would; a batch skips it, one image alone ends with the error
selftest a model that loads and answers in 0.42 s
check    every model ok
probe    a Python and a PyTorch
The file named by LOTUS_BG_CANCEL stops it like the real one: status 130.
"""
import argparse
import os
import shutil
import sys
import threading
import time


def emit(*parts):
    sys.stdout.write("\t".join(str(p) for p in parts) + "\n")
    sys.stdout.flush()


stopped = threading.Event()
if os.environ.get("LOTUS_BG_CANCEL"):
    def watch(path=os.environ["LOTUS_BG_CANCEL"]):
        while not os.path.exists(path):
            time.sleep(0.05)
        stopped.set()
    threading.Thread(target=watch, daemon=True).start()


def out_path(folder, src):
    stem = os.path.splitext(os.path.basename(src))[0]
    for n in range(1, 100):
        p = os.path.join(folder, f"{stem}_no_bg.png" if n == 1 else f"{stem}_no_bg_{n}.png")
        if not os.path.exists(p):
            return p
    raise SystemExit(3)


def run(a):
    emit("stage", "load_model")
    emit("info", "model", "Fake Lite")
    emit("info", "backend", "CPU")
    failed = 0
    for n, path in enumerate(a.images, 1):
        emit("image", n, len(a.images), path)
        emit("stage", "load_image")
        if os.path.basename(path).startswith("broken"):
            if len(a.images) == 1:
                emit("error", "BG-005", "This is not an image Lotus can read.", "cannot identify image file")
                return 2
            failed += 1
            emit("skip", path, "BG-005", "This is not an image Lotus can read.")
            continue
        emit("info", "resolution", "4 × 3")
        emit("stage", "segment")
        if os.environ.get("FAKE_BG_SLOW"):
            for _ in range(200):
                if stopped.is_set():
                    return 130
                time.sleep(0.05)
        emit("stage", "refine")
        emit("stage", "write")
        folder = os.path.dirname(os.path.abspath(path)) if a.next_to_source else a.out
        os.makedirs(folder, exist_ok=True)
        out = out_path(folder, path)
        shutil.copyfile(path, out)
        emit("done", path, out, "0.42")
    return 0 if failed < len(a.images) else 2


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("probe")
    c = sub.add_parser("check")
    c.add_argument("--models-dir")
    c.add_argument("--full", action="store_true")
    for name in ("run", "selftest"):
        r = sub.add_parser(name)
        r.add_argument("--model", required=True)
        r.add_argument("--models-dir", required=True)
        r.add_argument("--backend", default="auto")
        if name == "run":
            r.add_argument("--out", default="")
            r.add_argument("--next-to-source", action="store_true")
            r.add_argument("--session", required=True)
            r.add_argument("images", nargs="+")
    a = p.parse_args()
    if a.cmd == "probe":
        emit("info", "python", "3.13.1")
        emit("info", "torch", "2.14.1+cpu")
        emit("info", "module", "numpy", "ok")
        return 0
    if a.cmd == "check":
        emit("model", "birefnet-lite", "ok", "")
        return 0
    if a.cmd == "selftest":
        emit("stage", "load_model")
        emit("info", "model", "Fake Lite")
        emit("info", "backend", "CPU")
        emit("stage", "segment")
        emit("info", "seconds", "0.42")
        emit("done", "selftest", "", "0.42")
        return 0
    return run(a)


if __name__ == "__main__":
    rc = main()
    emit("end", rc)
    sys.exit(rc)
