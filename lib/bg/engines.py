"""The two model families behind Remove BG, behind one small interface:

    engine = load(model_id, models_dir, backend)  →  engine.predict(rgb) → alpha (0…1) at model resolution

BiRefNet  (https://github.com/ZhengPeng7/BiRefNet, MIT)  – its official model code and weights from
          Hugging Face, pinned and checked. The code only needs two small base classes from
          `transformers`; Lotus provides them instead of installing the whole library.
InSPyReNet (https://github.com/plemeri/InSPyReNet, MIT) – the model code of its official package
          `transparent-background`, without the package's GUI, webcam and download helpers.
"""
import hashlib
import importlib
import importlib.util
import os
import sys
import types

from events import BgError, log

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MEAN = (0.485, 0.456, 0.406)
STD = (0.229, 0.224, 0.225)


def registry():
    """data/bg-models.tsv → {id: {...}}"""
    models = {}
    with open(os.path.join(ROOT, "data", "bg-models.tsv"), encoding="utf-8") as f:
        for line in f:
            if line.startswith("#") or not line.strip():
                continue
            mid, engine, label, mb, size, lic, home, files = line.rstrip("\n").split("\t")
            models[mid] = {
                "id": mid, "engine": engine, "label": label, "mb": int(mb), "input": int(size),
                "license": lic, "home": home,
                "files": [dict(zip(("name", "url", "sha256", "bytes"), f.split("|"))) for f in files.split(";")],
            }
    return models


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def check_files(model, folder, full=False):
    """Missing or damaged files → list of names. Code files are always hashed (they are small and
    get imported); the weights are checked by size, or hashed too with full=True."""
    bad = []
    for f in model["files"]:
        p = os.path.join(folder, f["name"])
        if not os.path.isfile(p) or os.path.getsize(p) != int(f["bytes"]):
            bad.append(f["name"])
        elif (full or f["name"].endswith(".py")) and sha256(p) != f["sha256"]:
            bad.append(f["name"])
    return bad


def pick_device(backend):
    """auto → MPS on Apple silicon when PyTorch can use it, otherwise the CPU."""
    import torch
    mps = getattr(torch.backends, "mps", None)
    has_mps = bool(mps and mps.is_built() and mps.is_available())
    if backend == "mps" and not has_mps:
        raise BgError("BG-013", "The Apple GPU (MPS) is not available to PyTorch on this Mac.")
    if backend in ("auto", "mps") and has_mps:
        return "mps"
    return "cpu"


class Engine:
    def __init__(self, model, net, device):
        self.model = model
        self.net = net
        self.device = device
        self.label = model["label"]

    def input_size(self, h, w):
        """Model resolution for an image of h × w. InSPyReNet keeps the aspect ratio on large images
        when it runs on the GPU (more detail for high resolutions), everything else is square."""
        n = self.model["input"]
        if self.model["engine"] == "inspyrenet" and self.device == "mps" and min(h, w) > 1280:
            s = 1280 / min(h, w)
            return max(32, round(h * s / 32) * 32), max(32, round(w * s / 32) * 32)
        return n, n

    def predict(self, rgb):
        """rgb: uint8 H × W × 3 → float32 alpha at model resolution (0 background … 1 foreground)."""
        import cv2
        import numpy as np
        import torch
        h, w = rgb.shape[:2]
        mh, mw = self.input_size(h, w)
        interp = cv2.INTER_AREA if mh * mw < h * w else cv2.INTER_LINEAR
        x = cv2.resize(rgb, (mw, mh), interpolation=interp).astype(np.float32) / 255.0
        x = (x - np.array(MEAN, np.float32)) / np.array(STD, np.float32)
        t = torch.from_numpy(x.transpose(2, 0, 1).copy())[None].to(self.device)
        try:
            with torch.inference_mode():
                out = self.net(t)
                pred = out[-1].sigmoid() if self.model["engine"] == "birefnet" else out
                pred = pred[0, 0].float().cpu().numpy()
        except KeyboardInterrupt:
            raise
        except BaseException as e:
            raise translate(e, self.device) from e
        return np.nan_to_num(pred, nan=0.0).clip(0, 1)

    def close(self):
        """Frees the model (several hundred MB) once all images are done."""
        import torch
        self.net = None
        if self.device == "mps" and hasattr(torch, "mps"):
            torch.mps.empty_cache()


def translate(e, device):
    """PyTorch exceptions → Lotus errors with a code"""
    if isinstance(e, BgError):
        return e
    text = f"{type(e).__name__}: {e}"
    if isinstance(e, MemoryError) or "out of memory" in text.lower():
        return BgError("BG-007", "Not enough memory for this image.", text)
    if isinstance(e, KeyboardInterrupt):
        return e
    if device == "mps":
        return BgError("BG-013", "PyTorch could not run the model on the Apple GPU (MPS).", text)
    return BgError("BG-011", "The model stopped with an error.", text)


def _birefnet(model, folder):
    import torch
    # The official code imports two base classes from `transformers` – these stand-ins do the same
    # job for inference, so the large library is not needed.
    shim = types.ModuleType("transformers")

    class PretrainedConfig:
        def __init__(self, **kwargs):
            for k, v in kwargs.items():
                setattr(self, k, v)

    class PreTrainedModel(torch.nn.Module):
        def __init__(self, config, *args, **kwargs):
            super().__init__()
            self.config = config

        def post_init(self):
            pass

    shim.PretrainedConfig, shim.PreTrainedModel = PretrainedConfig, PreTrainedModel
    package = "lotus_birefnet_" + model["id"].replace("-", "_")
    pkg = types.ModuleType(package)
    pkg.__path__ = [folder]
    saved = sys.modules.get("transformers")
    sys.modules["transformers"] = shim
    sys.modules[package] = pkg
    try:
        config = importlib.import_module(package + ".BiRefNet_config")
        code = importlib.import_module(package + ".birefnet")
    finally:
        if saved is not None:
            sys.modules["transformers"] = saved
        else:
            sys.modules.pop("transformers", None)
    net = code.BiRefNet(config=config.BiRefNetConfig(bb_pretrained=False))
    from safetensors.torch import load_file
    state = load_file(os.path.join(folder, "model.safetensors"))
    missing, unexpected = net.load_state_dict(state, strict=False)
    if missing or unexpected:
        raise BgError("BG-009", "The BiRefNet weights do not match its code.",
                      f"missing {len(missing)}, unexpected {len(unexpected)}")
    return net


def _inspyrenet(model, folder):
    import torch
    spec = importlib.util.find_spec("transparent_background")
    if spec is None:
        raise BgError("BG-004", "The InSPyReNet code (transparent-background) is not installed.")
    # Import the model modules without the package's __init__ (GUI, webcam and download helpers)
    if "transparent_background" not in sys.modules:
        pkg = types.ModuleType("transparent_background")
        pkg.__path__ = list(spec.submodule_search_locations)
        sys.modules["transparent_background"] = pkg
    from transparent_background.InSPyReNet import InSPyReNet_SwinB
    net = InSPyReNet_SwinB(depth=64, pretrained=False, threshold=None, base_size=[1024, 1024])
    state = torch.load(os.path.join(folder, "ckpt_base.pth"), map_location="cpu", weights_only=True)
    net.load_state_dict(state, strict=True)
    return net


def load(model_id, models_dir, backend):
    models = registry()
    if model_id not in models:
        raise BgError("BG-004", f"Unknown model: {model_id}")
    model = models[model_id]
    folder = os.path.join(models_dir, model_id)
    bad = check_files(model, folder)
    if bad:
        raise BgError("BG-009", f"{model['label']} is incomplete or damaged: {', '.join(bad)}")
    device = pick_device(backend)
    log("info", f"Loading {model['label']} on {device.upper()}")
    import torch
    torch.set_grad_enabled(False)
    try:
        net = _birefnet(model, folder) if model["engine"] == "birefnet" else _inspyrenet(model, folder)
        net.eval()
        net = net.to(device)
    except (BgError, KeyboardInterrupt):
        raise
    except BaseException as e:
        err = translate(e, device)
        if err.code == "BG-011":
            err = BgError("BG-004", f"{model['label']} could not be loaded.", err.detail)
        raise err from e
    return Engine(model, net, device)
