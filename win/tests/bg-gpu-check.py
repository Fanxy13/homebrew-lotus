"""Remove BG for the graphics card, checked on real Windows with the real models (windows.yml, job bg-gpu – after
/bg setup and `worker.py prepare` for each BiRefNet model):

1. onnxprep.deform_conv2d gives torchvision's numbers (random inputs, the kernel sizes BiRefNet has: 1, 3 and 7)
2. each converted model gives PyTorch's alpha on the same pictures. ONNX Runtime runs it on the processor here:
   GitHub's machine has no graphics card, and DirectML refuses Windows' software adapter – so this checks the
   conversion, which is what a card would run, not the card itself
3. without a card, auto works on the processor and --backend gpu says why it cannot
   (with a card – should a runner ever have one – the model runs on it and is compared with PyTorch too)

python bg-gpu-check.py <models dir>      (the runtime's Python; status 1 when something does not hold)
"""
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "lib", "bg"))
import numpy as np
import torch
from torchvision.ops import deform_conv2d

import engines
import gpu
import onnxprep
from events import BgError

models_dir = sys.argv[1]
failed = []


def check(ok, what):
    print(("  ok    " if ok else "  FAIL  ") + what, flush=True)
    if not ok:
        failed.append(what)


# 1 · the deformable convolution in plain operations
torch.manual_seed(3)
worst = 0.0
for k in (1, 3, 7):
    for c_in, c_out, h, w in ((64, 32, 32, 32), (5, 7, 13, 9)):
        for scale in (0.0, 1.5, 20.0):
            x = torch.randn(1, c_in, h, w)
            weight = torch.randn(c_out, c_in, k, k)
            offset = torch.randn(1, 2 * k * k, h, w) * scale
            mask = 2 * torch.sigmoid(torch.randn(1, k * k, h, w))
            want = deform_conv2d(x, offset, weight, None, padding=k // 2, mask=mask)
            got = onnxprep.deform_conv2d(x, offset, weight, None, padding=k // 2, mask=mask)
            worst = max(worst, ((want - got).abs().max() / want.abs().max().clamp(min=1)).item())
check(worst < 1e-4, f"deform_conv2d in plain operations = torchvision's (largest relative difference {worst:.1e})")


# 2 · the converted models against PyTorch
def pictures():
    """An orange disc on a grey gradient (the self-test's), and a busier one: shapes, a texture, a thin bar"""
    yy, xx = np.mgrid[0:480, 0:640]
    disc = np.dstack([40 + yy * 0.2, 60 + xx * 0.1, 90 + 0 * xx]).astype(np.uint8)
    disc[(yy - 240) ** 2 + (xx - 320) ** 2 < 120 ** 2] = (230, 120, 60)
    rng = np.random.default_rng(7)
    yy, xx = np.mgrid[0:720, 0:960]
    busy = np.dstack([90 + 60 * np.sin(xx / 37.0), 120 + 50 * np.cos(yy / 23.0), 140 + 0 * xx]) + rng.normal(0, 12, (720, 960, 3))
    busy[((yy - 380) / 260.0) ** 2 + ((xx - 470) / 170.0) ** 2 < 1] = (200, 160, 120)
    busy[((yy - 190) / 90.0) ** 2 + ((xx - 470) / 80.0) ** 2 < 1] = (215, 175, 140)
    busy[100:650, 700:712] = (30, 30, 30)
    return [("disc", disc), ("busy", np.clip(busy, 0, 255).astype(np.uint8))]


import onnxruntime as ort

print(f"ONNX Runtime {ort.__version__}, providers {ort.get_available_providers()}", flush=True)
so = ort.SessionOptions()
so.enable_mem_pattern = False                    # as Lotus makes its sessions (DirectML needs both)
so.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
registry = engines.registry()
for mid in ("birefnet-lite", "birefnet"):
    m = registry[mid]
    path = onnxprep.onnx_path(models_dir, m)
    if not os.path.isfile(path):
        check(False, f"{m['label']}: converted ({os.path.basename(path)})")
        continue
    try:
        import onnx
        graph = onnx.load(path, load_external_data=False)
        opset = max([o.version for o in graph.opset_import if o.domain in ("", "ai.onnx")] or [0])
        ops = {}
        for n in graph.graph.node:
            ops[n.op_type] = ops.get(n.op_type, 0) + 1
        check("DeformConv" not in ops and ops.get("GridSample", 0) > 0,
              f"{m['label']}: {os.path.getsize(path) / 1e6:.0f} MB, {sum(ops.values())} operations, "
              f"{ops.get('GridSample', 0)} GridSample, no DeformConv")

        def since(op):
            try:
                return onnx.defs.get_schema(op, opset).since_version
            except Exception:
                return "?"
        # every operator with the version of its definition: a card runs those DirectML has a kernel for (for the log)
        print(f"  {m['label']}: opset {opset} · " + ", ".join(f"{op}-{since(op)} ×{c}" for op, c in sorted(ops.items(), key=lambda t: (-t[1], t[0]))), flush=True)
        del graph
    except ImportError:
        print("  (no onnx package: the operators are not listed)")
    cpu = engines.load(mid, models_dir, "cpu")
    t0 = time.time()
    onnx_cpu = engines.OnnxEngine(m, ort.InferenceSession(path, so, providers=["CPUExecutionProvider"]), {"name": "CPU"})
    print(f"  {m['label']}: ONNX Runtime loaded it in {time.time() - t0:.1f}s", flush=True)
    for name, img in pictures()[: 2 if mid == "birefnet-lite" else 1]:
        t0 = time.time()
        want = cpu.predict(img)
        t_torch = time.time() - t0
        t0 = time.time()
        got = onnx_cpu.predict(img)
        t_onnx = time.time() - t0
        d = np.abs(want - got)
        print(f"  {m['label']} · {name}: PyTorch {t_torch:.1f}s, ONNX Runtime {t_onnx:.1f}s · kept {want.mean() * 100:.1f}% · "
              f"difference max {d.max():.1e}, mean {d.mean():.1e}, pixels off by more than 0.05: {(d > 0.05).mean() * 100:.3f}%", flush=True)
        check(d.max() < 0.02 and d.mean() < 1e-3, f"{m['label']} · {name}: the converted model gives PyTorch's alpha")
        if name == "disc":
            check(got[512, 512] > 0.5 and got[16, 16] < 0.5, f"{m['label']} · disc: kept in the middle, gone in the corner")
    # the plain-ops convolution on the processor too: the same numbers – and how long it takes there
    patched = onnxprep.plain_deform_conv(cpu.net)
    try:
        t0 = time.time()
        plain = cpu.predict(pictures()[0][1])
        t_plain = time.time() - t0
    finally:
        onnxprep.restore_deform_conv(patched)
    t0 = time.time()
    want = cpu.predict(pictures()[0][1])
    t_tv = time.time() - t0
    print(f"  {m['label']} on the processor: torchvision's deform_conv2d {t_tv:.1f}s, plain operations {t_plain:.1f}s, "
          f"difference {np.abs(want - plain).max():.1e}", flush=True)
    cpu.close()
    onnx_cpu.close()


# 3 · with or without a graphics card
adapters = gpu.adapters()
for a in adapters:
    print(f"  adapter {a['index']}: {a['name']} · vendor {a['vendor']:04x} · {a['mb']} MB"
          f"{' · software' if a['software'] else ''}{' · Direct3D 12' if a['d3d12'] else ''}", flush=True)
check(bool(adapters), "DXGI lists the adapters (Windows always has its software one)")
check(all(not c["software"] for c in gpu.cards()), "Windows' software adapter is never a card")
lite = registry["birefnet-lite"]
if not gpu.cards():
    e = engines.load("birefnet-lite", models_dir, "auto")
    check(e.device == "cpu", "no card: auto works on the processor")
    try:
        engines.load("birefnet-lite", models_dir, "gpu")
        check(False, "no card: --backend gpu refuses")
    except BgError as err:
        check(err.code == "BG-013" and "graphics card" in err.reason, f"no card: --backend gpu refuses – {err.code} {err.reason}")
    # what DirectML itself does here (for the log): Lotus never asks it without a card
    try:
        s = ort.InferenceSession(onnxprep.onnx_path(models_dir, lite), so, providers=[("DmlExecutionProvider", {"device_id": "0"}), "CPUExecutionProvider"])
        print(f"  DirectML on adapter 0: the session runs on {s.get_providers()}", flush=True)
    except Exception as err:
        print(f"  DirectML on adapter 0: {type(err).__name__}: {str(err)[:200]}", flush=True)
else:
    e = engines.load("birefnet-lite", models_dir, "gpu")
    check(e.device == "gpu", f"a card: BiRefNet Lite runs on {e.card['name']}")
    img = pictures()[0][1]
    want = engines.load("birefnet-lite", models_dir, "cpu").predict(img)
    d = np.abs(want - e.predict(img))
    check(d.max() < 0.02, f"a card: the same alpha as PyTorch (max {d.max():.1e})")

print(f"\n{len(failed)} failed" if failed else "\nall held", flush=True)
sys.exit(1 if failed else 0)
