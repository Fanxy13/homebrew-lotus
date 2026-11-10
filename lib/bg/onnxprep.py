"""BiRefNet for the graphics card on Windows: the PyTorch model, converted once on this PC into an ONNX file that ONNX
Runtime runs through DirectML (any DirectX 12 card – NVIDIA, AMD, Intel). The weights are the ones Lotus downloaded
and checked; nothing else is downloaded for it.

DirectML has no deformable convolution (BiRefNet's decoder has some), so for the conversion torchvision's
deform_conv2d is replaced by the same arithmetic in operations that DirectML runs: one bilinear GridSample and one
1 × 1 convolution per kernel position.
"""
import os
import sys
import time

from events import BgError, log

FORMAT = 1          # changes when the conversion changes: older files are converted again


def _pair(v):
    return tuple(v) if isinstance(v, (tuple, list)) else (v, v)


def deform_conv2d(input, offset, weight, bias=None, stride=(1, 1), padding=(0, 0), dilation=(1, 1), mask=None):
    """torchvision.ops.deform_conv2d (modulated, "DCNv2") for one group and one offset group, stride 1 and
    dilation 1 – what BiRefNet uses. The same result: each kernel position samples the input bilinearly at its
    shifted places (zero outside the picture), weighs it with the mask and adds its slice of the kernel."""
    import torch
    import torch.nn.functional as F
    if _pair(stride) != (1, 1) or _pair(dilation) != (1, 1):
        raise NotImplementedError("deform_conv2d: only stride 1 and dilation 1")
    # plain numbers: the converted model has one fixed input size, so its graph needs no shape arithmetic
    n, c, h, w = (int(v) for v in input.shape)
    oc, ic, kh, kw = (int(v) for v in weight.shape)
    ho, wo = int(offset.shape[-2]), int(offset.shape[-1])
    if ic != c or int(offset.shape[1]) != 2 * kh * kw or (mask is not None and int(mask.shape[1]) != kh * kw):
        raise NotImplementedError("deform_conv2d: only one group and one offset group")
    ph, pw = _pair(padding)
    # the input pixel where each output pixel's kernel starts
    y0 = (torch.arange(ho, dtype=input.dtype, device=input.device) - ph).view(1, ho, 1)
    x0 = (torch.arange(wo, dtype=input.dtype, device=input.device) - pw).view(1, 1, wo)
    out = None
    for ky in range(kh):
        for kx in range(kw):
            k = ky * kw + kx
            y = y0 + ky + offset[:, 2 * k]          # torchvision's order: (dy, dx) for each kernel position
            x = x0 + kx + offset[:, 2 * k + 1]
            # pixel → grid_sample's -1 … 1 (align_corners=False: -1 is the outer edge of the first pixel)
            grid = torch.stack(((2 * x + 1) / w - 1, (2 * y + 1) / h - 1), dim=-1)
            v = F.grid_sample(input, grid, mode="bilinear", padding_mode="zeros", align_corners=False)
            if mask is not None:
                v = v * mask[:, k:k + 1]
            part = F.conv2d(v, weight[:, :, ky:ky + 1, kx:kx + 1])
            out = part if out is None else out + part
    if bias is not None:
        out = out + bias.view(1, -1, 1, 1)
    return out


def plain_deform_conv(net):
    """Points the DeformableConv2d blocks of a network to deform_conv2d above (the name they call is a global of the
    module that defines them) → what restore_deform_conv puts back"""
    patched = {}
    for m in net.modules():
        if type(m).__name__ != "DeformableConv2d":
            continue
        mod = sys.modules.get(type(m).__module__)
        if mod is None or mod.__name__ in patched:
            continue
        if not hasattr(mod, "deform_conv2d"):
            raise BgError("BG-013", "This model cannot be prepared for the graphics card.",
                          f"{mod.__name__} calls no deform_conv2d of its own")
        patched[mod.__name__] = mod.deform_conv2d
        mod.deform_conv2d = deform_conv2d
    return patched


def restore_deform_conv(patched):
    for name, fn in patched.items():
        sys.modules[name].deform_conv2d = fn


def weights_file(model):
    """The weights among a model's files: the biggest one"""
    return max(model["files"], key=lambda f: int(f["bytes"]))


def onnx_path(models_dir, model):
    """Where the converted model of exactly these weights lives: in the model's folder, named after the weights'
    SHA-256 and the conversion's FORMAT – new weights or a new conversion never use an old file"""
    return os.path.join(models_dir, model["id"], f"gpu-{FORMAT}-{weights_file(model)['sha256'][:12]}.onnx")


def _head(net):
    """The network as the graphics card runs it: one picture in, the alpha of its last output (0 … 1) out"""
    import torch

    class Head(torch.nn.Module):
        def __init__(self, net):
            super().__init__()
            self.net = net

        def forward(self, x):
            return self.net(x)[-1].sigmoid()

    return Head(net).eval()


def export(model, models_dir):
    """Converts a BiRefNet model for the graphics card → (path, seconds). Written to <path>.part first, so a stopped
    conversion leaves nothing that looks finished; older conversions of the model are removed afterwards."""
    import warnings
    import torch
    import engines
    if model["engine"] != "birefnet":
        raise BgError("BG-013", f"{model['label']} runs on the processor only.")
    folder = os.path.join(models_dir, model["id"])
    out = onnx_path(models_dir, model)
    part = out + ".part"
    t0 = time.time()
    torch.set_grad_enabled(False)
    net = engines._birefnet(model, folder).eval()
    head = _head(net)
    n = model["input"]
    torch.manual_seed(0)
    x = torch.randn(1, 3, n, n)          # like a normalized picture; the values only steer the tracing
    patched = plain_deform_conv(net)
    if not patched:
        raise BgError("BG-013", "This model cannot be prepared for the graphics card.", "no DeformableConv2d found")
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            # PyTorch's TorchScript exporter: ten times faster than the torch.export one, and it writes opset 17,
            # whose GridSample DirectML runs. It needs the onnx package (requirements-windows-gpu.txt).
            torch.onnx.export(head, (x,), part, opset_version=17, input_names=["image"], output_names=["alpha"],
                              dynamo=False, do_constant_folding=True)
        os.replace(part, out)
    finally:
        restore_deform_conv(patched)
        if os.path.exists(part):
            os.unlink(part)
    for name in os.listdir(folder):
        if name.startswith("gpu-") and name.endswith(".onnx") and os.path.join(folder, name) != out:
            os.unlink(os.path.join(folder, name))
    secs = time.time() - t0
    log("info", f"{model['label']} prepared for the graphics card in {secs:.1f}s: {os.path.getsize(out) / 1e6:.0f} MB")
    return out, secs
