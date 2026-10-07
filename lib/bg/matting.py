"""From the model's rough alpha to a clean, full-resolution cut-out.

    model alpha ─▶ edge refinement (work size) ─▶ your KEEP marks ─▶ clean-up ─▶ full size ─▶ edge colors

Work size: the image at most 2048 px on its long side – large enough for hair and fine edges,
small enough to stay fast. The last two steps run on the original resolution.
"""
import cv2
import numpy as np

WORK = 2048


def work_size(h, w, limit=WORK):
    s = min(1.0, limit / max(h, w))
    return max(1, round(h * s)), max(1, round(w * s))


def resize(img, hw, interp=None):
    h, w = hw
    if img.shape[:2] == (h, w):
        return img
    if interp is None:
        interp = cv2.INTER_AREA if h * w < img.shape[0] * img.shape[1] else cv2.INTER_LINEAR
    return cv2.resize(img, (w, h), interpolation=interp)


def _box(x, r):
    return cv2.boxFilter(x, -1, (2 * r + 1, 2 * r + 1), normalize=True, borderType=cv2.BORDER_REFLECT)


def guided_color(img, p, r, eps):
    """Guided filter with a color guide (He et al.): the alpha follows the edges of the photo.
    img float32 H×W×3 in 0…1, p float32 H×W."""
    m = [_box(img[..., c], r) for c in range(3)]
    mp = _box(p, r)
    cov = [_box(img[..., c] * p, r) - m[c] * mp for c in range(3)]
    v = {}
    for i in range(3):
        for j in range(i, 3):
            v[i, j] = _box(img[..., i] * img[..., j], r) - m[i] * m[j] + (eps if i == j else 0)
    # Inverse of the symmetric 3×3 covariance per pixel (adjugate / determinant)
    a00 = v[1, 1] * v[2, 2] - v[1, 2] * v[1, 2]
    a01 = v[0, 2] * v[1, 2] - v[0, 1] * v[2, 2]
    a02 = v[0, 1] * v[1, 2] - v[0, 2] * v[1, 1]
    a11 = v[0, 0] * v[2, 2] - v[0, 2] * v[0, 2]
    a12 = v[0, 2] * v[0, 1] - v[0, 0] * v[1, 2]
    a22 = v[0, 0] * v[1, 1] - v[0, 1] * v[0, 1]
    det = v[0, 0] * a00 + v[0, 1] * a01 + v[0, 2] * a02
    det[np.abs(det) < 1e-12] = 1e-12
    ka = (a00 * cov[0] + a01 * cov[1] + a02 * cov[2]) / det
    kb = (a01 * cov[0] + a11 * cov[1] + a12 * cov[2]) / det
    kc = (a02 * cov[0] + a12 * cov[1] + a22 * cov[2]) / det
    b = mp - ka * m[0] - kb * m[1] - kc * m[2]
    return _box(ka, r) * img[..., 0] + _box(kb, r) * img[..., 1] + _box(kc, r) * img[..., 2] + _box(b, r)


def _band(alpha, lo=0.02, hi=0.98, grow=3):
    """Where the edge is: neither clearly in nor clearly out, a few pixels wider."""
    band = ((alpha > lo) & (alpha < hi)).astype(np.uint8)
    if grow:
        band = cv2.dilate(band, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * grow + 1, 2 * grow + 1)))
    return band.astype(bool)


def refine_edges(alpha, rgb):
    """Model alpha (any size) → alpha at the size of rgb (the work image) with edges that follow
    the photo. Solid areas keep the model's value; only the edge band is filtered."""
    h, w = rgb.shape[:2]
    up = resize(alpha.astype(np.float32), (h, w), cv2.INTER_LINEAR)
    img = rgb.astype(np.float32) / 255.0
    r = max(2, round(max(h, w) / 512 * 2))
    q = np.clip(guided_color(img, up, r, 1e-4), 0, 1)
    band = _band(up, grow=r)
    return np.where(band, q, up).astype(np.float32)


def _stroke_core(keep):
    """The middle part of each painted stroke (always kept). Its outer part may be background the
    brush went over, so the photo decides there."""
    k = keep.astype(np.uint8)
    dist = cv2.distanceTransform(k, cv2.DIST_L2, 3)
    n, labels = cv2.connectedComponents(k, connectivity=8)
    if n <= 1:
        return keep
    peak = np.zeros(n, np.float32)
    np.maximum.at(peak, labels.ravel(), dist.ravel())
    limit = np.minimum(peak * 0.6, max(4.0, max(keep.shape) * 0.012))
    return keep & (dist >= limit[labels])


def apply_keep(alpha, keep, rgb):
    """Adds what you painted. alpha, keep (bool) and rgb all at work size.
    Painted areas never get removed; their outer edge snaps to the object (GrabCut + guided filter).
    Nothing the model already kept is taken away – marks only add."""
    if keep is None or not keep.any():
        return alpha
    h, w = alpha.shape
    core = _stroke_core(keep)
    # GrabCut on a smaller copy: what belongs to the marked object?
    sh, sw = work_size(h, w, 1024)
    a_s = resize(alpha, (sh, sw))
    k_s = resize(keep.astype(np.uint8), (sh, sw), cv2.INTER_NEAREST).astype(bool)
    c_s = resize(core.astype(np.uint8), (sh, sw), cv2.INTER_NEAREST).astype(bool)
    img_s = resize(rgb, (sh, sw))
    reach = max(9, int(np.hypot(sh, sw) * 0.06)) | 1
    near = cv2.dilate(k_s.astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (reach, reach))).astype(bool)
    mask = np.full((sh, sw), cv2.GC_PR_BGD, np.uint8)
    mask[a_s >= 0.5] = cv2.GC_PR_FGD
    mask[(a_s < 0.05) & ~near] = cv2.GC_BGD
    mask[k_s] = cv2.GC_PR_FGD
    mask[c_s] = cv2.GC_FGD
    seg = k_s | (a_s >= 0.5)
    has_bg = np.any((mask == cv2.GC_BGD) | (mask == cv2.GC_PR_BGD))
    if has_bg and np.any(mask == cv2.GC_FGD):
        bgd, fgd = np.zeros((1, 65), np.float64), np.zeros((1, 65), np.float64)
        cv2.grabCut(cv2.cvtColor(img_s, cv2.COLOR_RGB2BGR), mask, None, bgd, fgd, 5, cv2.GC_INIT_WITH_MASK)
        seg = (mask == cv2.GC_FGD) | (mask == cv2.GC_PR_FGD)
    # Only what is connected to a mark, and close to it
    n, labels = cv2.connectedComponents(seg.astype(np.uint8), connectivity=8)
    touched = np.unique(labels[k_s])
    added = np.isin(labels, touched[touched != 0]) & near
    soft = resize(added.astype(np.float32), (h, w), cv2.INTER_LINEAR)
    img = rgb.astype(np.float32) / 255.0
    r = max(2, round(max(h, w) / 512))
    soft = np.clip(guided_color(img, soft, r, 2e-4), 0, 1)
    out = np.maximum(alpha, soft)
    out[core] = 1.0
    return out.astype(np.float32)


def tidy(alpha, keep=None):
    """Removes faint specks (nothing above 30 % opacity) and snaps almost-solid values,
    so backgrounds do not leave a haze. Small solid objects stay."""
    a = alpha.copy()
    n, labels = cv2.connectedComponents((a > 0.05).astype(np.uint8), connectivity=8)
    if n > 1:
        peak = np.zeros(n, np.float32)
        np.maximum.at(peak, labels.ravel(), a.ravel())
        faint = (peak < 0.3)
        faint[0] = False
        if keep is not None:
            faint[np.unique(labels[keep])] = False
        a[faint[labels]] = 0
    a[a < 0.012] = 0
    a[a > 0.988] = 1
    return a


def to_full(alpha, rgb_work, rgb_full):
    """Work-size alpha → original size. The edges are rebuilt from the full-resolution photo with a
    fast guided filter (coefficients from the work image, applied at full size)."""
    H, W = rgb_full.shape[:2]
    h, w = alpha.shape
    if (h, w) == (H, W):
        return alpha
    up = resize(alpha, (H, W), cv2.INTER_LINEAR)
    g_low = cv2.cvtColor(rgb_work, cv2.COLOR_RGB2GRAY).astype(np.float32) / 255.0
    r = 2
    mi, mp = _box(g_low, r), _box(alpha, r)
    var = _box(g_low * g_low, r) - mi * mi
    cov = _box(g_low * alpha, r) - mi * mp
    a = cov / (var + 1e-4)
    b = mp - a * mi
    a, b = _box(a, r), _box(b, r)
    g_full = cv2.cvtColor(rgb_full, cv2.COLOR_RGB2GRAY).astype(np.float32)
    g_full *= 1.0 / 255.0
    q = resize(a, (H, W), cv2.INTER_LINEAR)
    q *= g_full
    q += resize(b, (H, W), cv2.INTER_LINEAR)
    del g_full
    band = _band(up, grow=max(2, round(H / h)))
    np.clip(q, 0, 1, out=q)
    return np.where(band, q, up).astype(np.float32)


def _blur(x, r):
    return cv2.blur(x, (r, r))


def foreground(rgb, alpha):
    """Edge colors without the old background (blur-fusion estimate, Forte & Pitié 2021): a
    see-through edge that picked up e.g. a green wall becomes the color of the object again.
    The smooth maps are computed small; the result is applied at full size on the edge pixels only.
    Fully transparent pixels get the nearby object color, which keeps resized copies halo-free."""
    H, W = alpha.shape
    sh, sw = work_size(H, W, 1024)
    i_s = resize(rgb, (sh, sw)).astype(np.float32) / 255.0
    a2 = resize(alpha, (sh, sw))
    a_s = a2[..., None]
    r1 = max(3, round(90 * max(sh, sw) / 1024))
    r2 = max(2, round(6 * max(sh, sw) / 1024))
    ba = _blur(a2, r1)[..., None]
    bf = _blur(i_s * a_s, r1) / (ba + 1e-5)
    bb = _blur(i_s * (1 - a_s), r1) / ((1 - ba) + 1e-5)
    f1 = np.clip(bf + a_s * (i_s - a_s * bf - (1 - a_s) * bb), 0, 1)
    ba2 = _blur(a2, r2)[..., None]
    bf2 = _blur(f1 * a_s, r2) / (ba2 + 1e-5)
    bb2 = _blur(bb * (1 - a_s), r2) / ((1 - ba2) + 1e-5)
    bf_full = resize((np.clip(bf2, 0, 1) * 255).astype(np.uint8), (H, W), cv2.INTER_LINEAR)
    bb_full = resize((np.clip(bb2, 0, 1) * 255).astype(np.uint8), (H, W), cv2.INTER_LINEAR)
    out = rgb.copy()
    edge = (alpha > 0) & (alpha < 1)
    if edge.any():
        a = alpha[edge][:, None]
        i = rgb[edge].astype(np.float32) / 255.0
        f = bf_full[edge].astype(np.float32) / 255.0
        b = bb_full[edge].astype(np.float32) / 255.0
        out[edge] = (np.clip(f + a * (i - a * f - (1 - a) * b), 0, 1) * 255 + 0.5).astype(np.uint8)
    clear = alpha <= 0
    out[clear] = bf_full[clear]
    return out
