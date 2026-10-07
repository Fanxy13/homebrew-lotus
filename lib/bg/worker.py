"""Lotus Remove BG worker. Runs inside Lotus' own Python environment, one command per process:

  probe                               what this Mac and the runtime can do
  check    [--model ID] [--full]      are the model files complete and unchanged?
  run      --model ID --backend B (--out DIR | --next-to-source) --session DIR [--keep MASK] IMAGE…
  refine   --session DIR --keep MASK  apply your KEEP marks to the last result (no model needed)
  selftest --model ID --backend B     load the model and cut out a small generated picture

Events for the Lotus screen go to stdout, one per line, tab separated:
  stage <name> · info <key> <value> · image <n> <total> <path> · done <input> <output> <seconds>
  warn <code> <text> · error <code> <reason> <detail>
Details and tracebacks go to the Lotus log only. Images are read from and written to local files –
nothing is uploaded, nothing is sent anywhere.
"""
import os
import sys

os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")   # a few BiRefNet layers run on the CPU
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import argparse
import json
import signal
import time
import traceback
import warnings

from events import BgError, Stage, emit, log

warnings.filterwarnings("ignore")


def _interrupt(*_):
    raise KeyboardInterrupt


signal.signal(signal.SIGTERM, _interrupt)


def cmd_probe(a):
    import platform
    emit("info", "python", platform.python_version())
    emit("info", "machine", platform.machine())
    emit("info", "memory", os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES"))
    try:
        import torch
    except Exception as e:
        raise BgError("BG-002", "PyTorch cannot be loaded.", f"{type(e).__name__}: {e}")
    mps = getattr(torch.backends, "mps", None)
    emit("info", "torch", torch.__version__)
    emit("info", "mps", int(bool(mps and mps.is_built() and mps.is_available())))
    import importlib.util
    for name in ("numpy", "cv2", "PIL", "timm", "kornia", "einops", "safetensors", "transparent_background"):
        ok = importlib.util.find_spec(name) is not None
        emit("info", "module", name, "ok" if ok else "missing")
    return 0


def cmd_check(a):
    import engines
    models = engines.registry()
    for mid in ([a.model] if a.model else models):
        m = models[mid]
        folder = os.path.join(a.models_dir, mid)
        if not os.path.isdir(folder) or not any(os.path.exists(os.path.join(folder, f["name"])) for f in m["files"]):
            emit("model", mid, "missing", "")
            continue
        bad = engines.check_files(m, folder, full=a.full)
        emit("model", mid, "damaged" if bad else "ok", ",".join(bad))
    return 0


def _memory_check(h, w):
    total = os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES")
    need = h * w * 28 + 2_500_000_000
    if need > total * 0.8:
        raise BgError("BG-007", "This image needs more memory than this Mac has.",
                      f"{w}×{h} needs about {need / 1e9:.1f} GB, the Mac has {total / 1e9:.0f} GB")


def _save_session(session, meta, rgb_w, alpha_w):
    import images
    from PIL import Image
    Image.fromarray(rgb_w).save(os.path.join(session, "work.png"), "PNG", compress_level=1)
    images.save_gray(os.path.join(session, "alpha.png"), alpha_w, 16)
    with open(os.path.join(session, "meta.json"), "w") as f:
        json.dump(meta, f)


def _finish(rgb, rgb_w, alpha_w, keep, src_alpha):
    """Keep marks, clean-up and full size → final alpha"""
    import numpy as np
    import matting
    if keep is not None:
        alpha_w = matting.apply_keep(alpha_w, keep, rgb_w)
    alpha_w = matting.tidy(alpha_w, keep)
    alpha = matting.to_full(alpha_w, rgb_w, rgb)
    if src_alpha is not None:
        alpha = np.minimum(alpha, src_alpha.astype(np.float32) / 255.0)
    return alpha


def _write(out, rgb, alpha, icc):
    import matting
    import images
    rgb_out = matting.foreground(rgb, alpha)
    images.save_png(out, rgb_out, alpha, icc)
    kept = float(alpha.mean()) * 100
    emit("info", "kept", f"{kept:.1f}")
    if kept < 0.5:
        emit("warn", "BG-W01", "Almost nothing was kept – the model found no clear subject.")


def _load_keep(path, hw):
    if not path:
        return None
    import cv2
    import images
    import matting
    keep = images.load_gray(path)
    return matting.resize(keep, hw, cv2.INTER_LINEAR) > 0.5


def process(engine, path, folder, session, keep_path, remember):
    import images
    import matting
    t0 = time.time()
    out = None
    try:
        with Stage("load_image", "Reading the image"):
            rgb, src_alpha, icc = images.load(path, session)
        h, w = rgb.shape[:2]
        emit("info", "resolution", f"{w} × {h}")
        log("debug", f"Image {w}×{h}{', has transparency' if src_alpha is not None else ''}")
        _memory_check(h, w)
        hw = matting.work_size(h, w)
        rgb_w = matting.resize(rgb, hw)
        with Stage("segment", "Segmenting the foreground"):
            raw = engine.predict(rgb_w)
        with Stage("refine", "Refining edges"):
            alpha_w = matting.refine_edges(raw, rgb_w)
            keep = _load_keep(keep_path, hw)
            alpha = _finish(rgb, rgb_w, alpha_w, keep, src_alpha)
        with Stage("write", "Writing the PNG"):
            out = images.output_path(folder or os.path.dirname(os.path.abspath(path)), path)
            _write(out, rgb, alpha, icc)
        if remember:
            _save_session(session, {"input": os.path.abspath(path), "output": out, "model": engine.model["id"],
                                    "device": engine.device, "work": list(hw)}, rgb_w, alpha_w)
    except BaseException:
        if out and os.path.exists(out) and os.path.getsize(out) == 0:
            os.unlink(out)   # the reserved name, never written
        raise
    secs = time.time() - t0
    log("info", f"Done in {secs:.2f}s: {out}")
    emit("done", path, out, f"{secs:.2f}")


def cmd_run(a):
    import engines
    os.makedirs(a.session, exist_ok=True)
    folder = None if a.next_to_source else os.path.expanduser(a.out)
    with Stage("load_model", "Loading the model"):
        t0 = time.time()
        engine = engines.load(a.model, a.models_dir, a.backend)
        emit("info", "model", engine.label)
        emit("info", "backend", engine.device.upper())
        log("info", f"{engine.label} ready on {engine.device.upper()} in {time.time() - t0:.1f}s")
    failed = 0
    for n, path in enumerate(a.images, 1):
        emit("image", n, len(a.images), path)
        log("info", f"Removing the background ({n}/{len(a.images)}): {path}")
        try:
            process(engine, path, folder, a.session, a.keep, remember=len(a.images) == 1)
        except BgError as e:
            if e.code != "BG-005" or len(a.images) == 1:
                raise
            failed += 1
            log("warn", f"Skipped {path}: {e.reason} {e.detail}")
            emit("skip", path, e.code, e.reason)
    engine.close()
    return 0 if failed < len(a.images) else 2


def cmd_refine(a):
    import images
    import matting
    with open(os.path.join(a.session, "meta.json")) as f:
        meta = json.load(f)
    t0 = time.time()
    emit("image", 1, 1, meta["input"])
    with Stage("load_image", "Reading the image"):
        rgb, src_alpha, icc = images.load(meta["input"], a.session)
    h, w = rgb.shape[:2]
    emit("info", "resolution", f"{w} × {h}")
    hw = tuple(meta["work"])
    rgb_w = matting.resize(rgb, hw)
    alpha_w = matting.resize(images.load_gray(os.path.join(a.session, "alpha.png")), hw)
    with Stage("refine", "Applying your marks"):
        keep = _load_keep(a.keep, hw)
        alpha = _finish(rgb, rgb_w, alpha_w, keep, src_alpha)
    out = meta["output"]
    with Stage("write", "Writing the PNG"):
        if not os.path.exists(out):
            out = images.output_path(os.path.dirname(out), meta["input"])
        _write(out, rgb, alpha, icc)
    secs = time.time() - t0
    log("info", f"Refined with KEEP marks in {secs:.2f}s: {out}")
    emit("done", meta["input"], out, f"{secs:.2f}")
    return 0


def cmd_selftest(a):
    import numpy as np
    import engines
    with Stage("load_model", "Loading the model"):
        engine = engines.load(a.model, a.models_dir, a.backend)
        emit("info", "model", engine.label)
        emit("info", "backend", engine.device.upper())
    with Stage("segment", "Test picture"):
        yy, xx = np.mgrid[0:480, 0:640]
        img = np.dstack([40 + yy * 0.2, 60 + xx * 0.1, 90 + 0 * xx]).astype(np.uint8)
        disk = (yy - 240) ** 2 + (xx - 320) ** 2 < 120 ** 2
        img[disk] = (230, 120, 60)
        t0 = time.time()
        alpha = engine.predict(img)
        secs = time.time() - t0
    if not np.isfinite(alpha).all() or alpha.max() <= 0:
        raise BgError("BG-004", f"{engine.label} gave an empty result in the test.")
    emit("info", "seconds", f"{secs:.2f}")
    log("info", f"Self-test of {engine.label} on {engine.device.upper()}: {secs:.2f}s")
    emit("done", "selftest", "", f"{secs:.2f}")
    return 0


def main():
    rc = 2
    try:
        rc = _main()
    finally:
        emit("end", rc)   # the last event, so Lotus never has to guess
    return rc


def _main():
    p = argparse.ArgumentParser(prog="lotus-bg")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("probe")
    c = sub.add_parser("check")
    c.add_argument("--model")
    c.add_argument("--models-dir", required=True)
    c.add_argument("--full", action="store_true")
    for name in ("run", "selftest"):
        r = sub.add_parser(name)
        r.add_argument("--model", required=True)
        r.add_argument("--models-dir", required=True)
        r.add_argument("--backend", default="auto", choices=["auto", "mps", "cpu"])
        if name == "run":
            r.add_argument("--out", default="")
            r.add_argument("--next-to-source", action="store_true")
            r.add_argument("--session", required=True)
            r.add_argument("--keep", default="")
            r.add_argument("images", nargs="+")
    f = sub.add_parser("refine")
    f.add_argument("--session", required=True)
    f.add_argument("--keep", required=True)
    a = p.parse_args()
    try:
        return {"probe": cmd_probe, "check": cmd_check, "run": cmd_run,
                "refine": cmd_refine, "selftest": cmd_selftest}[a.cmd](a)
    except BgError as e:
        log("error", f"{e.code} {e.reason}" + (f" – {e.detail}" if e.detail else ""))
        emit("error", e.code, e.reason, (e.detail or "")[:400])
        return 2
    except KeyboardInterrupt:
        log("info", "Worker stopped: cancelled")
        return 130
    except Exception as e:
        log("error", "BG-011 " + traceback.format_exc())
        emit("error", "BG-011", "Something unexpected went wrong.", f"{type(e).__name__}: {e}"[:400])
        return 2


if __name__ == "__main__":
    sys.exit(main())
