"""A stand-in for lib/bg/worker.py in the tests of /bg on Windows: the same commands and events, no PyTorch.

run      copies each image to <stem>_no_bg.png (next to it, or into --out) – an image called broken.* fails with
         BG-005 as a real unreadable file would; a batch skips it, one image alone ends with the error
selftest a model that loads and answers in 0.42 s
check    every model ok – "ready" for the graphics card when its folder has a gpu-*.onnx
probe    a Python and a PyTorch; with FAKE_BG_GPU="<name>|<MB>" a graphics card, with FAKE_BG_DML=1 DirectML too
prepare  writes gpu-1-fake.onnx into the model's folder (what the conversion would make)
The backend: auto and gpu run on the "GPU" when the model's folder has a gpu-*.onnx (gpu without one: BG-013, as
the real worker says it); FAKE_BG_GPU_FAIL=1 makes the card fail with BG-013. The file named by LOTUS_BG_CANCEL stops
it like the real one: status 130.
"""
import argparse
import glob
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


def backend(a):
    """CPU or GPU, as the real worker picks it – None after the error it would give"""
    prepared = bool(glob.glob(os.path.join(a.models_dir, a.model, "gpu-*.onnx")))
    if a.backend == "cpu" or (a.backend == "auto" and not prepared):
        return "CPU"
    if not prepared:
        emit("error", "BG-013", "Fake Lite is not prepared for the graphics card yet.", "gpu-1-fake.onnx")
        return None
    if os.environ.get("FAKE_BG_GPU_FAIL"):
        emit("info", "backend", "GPU")
        emit("error", "BG-013", "The graphics card could not run the model (DirectML).", "fake failure")
        return None
    return "GPU"


def run(a):
    emit("stage", "load_model")
    emit("info", "model", "Fake Lite")
    b = backend(a)
    if not b:
        return 2
    emit("info", "backend", b)
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
    c.add_argument("--model")
    c.add_argument("--models-dir")
    c.add_argument("--full", action="store_true")
    g = sub.add_parser("prepare")
    g.add_argument("--model", required=True)
    g.add_argument("--models-dir", required=True)
    for name in ("run", "selftest"):
        r = sub.add_parser(name)
        r.add_argument("--model", required=True)
        r.add_argument("--models-dir", required=True)
        r.add_argument("--backend", default="auto", choices=["auto", "gpu", "mps", "cpu"])
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
        if os.environ.get("FAKE_BG_GPU"):
            name, mb = os.environ["FAKE_BG_GPU"].split("|")
            emit("gpu", 0, name, mb)
            emit("info", "directml", 1 if os.environ.get("FAKE_BG_DML") else 0)
        return 0
    if a.cmd == "check":
        for mid in [a.model] if a.model else ["birefnet-lite"]:
            ready = glob.glob(os.path.join(a.models_dir or ".", mid, "gpu-*.onnx"))
            emit("model", mid, "ok", "", "ready" if ready else "-")
        return 0
    if a.cmd == "prepare":
        emit("info", "model", "Fake Lite")
        emit("stage", "prepare")
        out = os.path.join(a.models_dir, a.model, "gpu-1-fake.onnx")
        with open(out, "w") as f:
            f.write("not really a model")
        emit("info", "seconds", "0.5")
        emit("info", "peak_mb", "321")
        emit("done", "prepare", out, "0.5")
        return 0
    if a.cmd == "selftest":
        emit("stage", "load_model")
        emit("info", "model", "Fake Lite")
        b = backend(a)
        if not b:
            return 2
        emit("info", "backend", b)
        emit("stage", "segment")
        emit("info", "seconds", "0.42")
        emit("done", "selftest", "", "0.42")
        return 0
    return run(a)


if __name__ == "__main__":
    rc = main()
    emit("end", rc)
    sys.exit(rc)
