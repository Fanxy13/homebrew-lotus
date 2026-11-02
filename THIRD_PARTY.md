# Third-party software

Lotus itself is MIT licensed (see [LICENSE](LICENSE)). It does not bundle the software below.
Remove BG downloads it on first use, after asking, into `~/.local/share/lotus` on your Mac.

## Models

| Model | Project | License | Files Lotus downloads |
|---|---|---|---|
| BiRefNet, BiRefNet Lite | [ZhengPeng7/BiRefNet](https://github.com/ZhengPeng7/BiRefNet) – Peng Zheng et al., *Bilateral Reference for High-Resolution Dichotomous Image Segmentation* (CAAI AIR 2024) | MIT, © 2024 ZhengPeng | `birefnet.py`, `BiRefNet_config.py`, `model.safetensors` from [huggingface.co/ZhengPeng7](https://huggingface.co/ZhengPeng7), pinned to one revision |
| InSPyReNet | [plemeri/InSPyReNet](https://github.com/plemeri/InSPyReNet) – Taehun Kim et al., *Revisiting Image Pyramid Structure for High Resolution Salient Object Detection* (ACCV 2022) | MIT, © 2021 Taehun Kim | `ckpt_base.pth` from the [transparent-background](https://github.com/plemeri/transparent-background) release 1.2.12 |

The exact URLs, sizes and SHA-256 checksums are in [`data/bg-models.tsv`](data/bg-models.tsv).
BiRefNet's model code needs two base classes from Hugging Face `transformers`; Lotus provides
small stand-ins for them instead of installing that library.

## Python packages

Installed with pip into Lotus' own environment (versions in `lib/bg/requirements-*.txt`):

| Package | License |
|---|---|
| [PyTorch](https://pytorch.org), torchvision | BSD-3-Clause |
| [NumPy](https://numpy.org) | BSD-3-Clause |
| [Pillow](https://python-pillow.org) | MIT-CMU (HPND) |
| [OpenCV](https://opencv.org) (opencv-python-headless) | Apache-2.0 |
| [timm](https://github.com/huggingface/pytorch-image-models) | Apache-2.0 |
| [kornia](https://github.com/kornia/kornia) | Apache-2.0 |
| [einops](https://github.com/arogozhnikov/einops) | MIT |
| [safetensors](https://github.com/huggingface/safetensors) | Apache-2.0 |
| [transparent-background](https://github.com/plemeri/transparent-background) (InSPyReNet model code, installed without extras) | MIT |

## Programs Lotus downloads or uses on Linux and Windows

Nothing here is bundled in the repository. Each is fetched from the project that makes it, after asking, and checked against a sha256 where Lotus pins one (`data/vendor.tsv`).

| Program | What it is for | License |
|---|---|---|
| [fastfetch](https://github.com/fastfetch-cli/fastfetch) | the system information next to the logo (pinned release, Linux and Windows) | MIT |
| [yt-dlp](https://github.com/yt-dlp/yt-dlp) | `/convert` (the official build of the release, checked against its SHA2-256SUMS) | Unlicense |
| [Swift](https://www.swift.org) runtime and Foundation | linked statically into the AI program for Linux (built with Swift's Static Linux SDK) | Apache-2.0 with the Runtime Library Exception |
| [musl libc](https://musl.libc.org), [libcurl](https://curl.se), [zlib](https://zlib.net), [libxml2](https://gitlab.gnome.org/GNOME/libxml2), [ICU](https://icu.unicode.org) | parts of that static program (they come with the Static Linux SDK) | MIT, curl license, zlib license, MIT, Unicode license |
| [bubblewrap](https://github.com/containers/bubblewrap) | the sandbox of limited plugins on Linux (from your package manager) | LGPL-2.0-or-later |
| [ImageMagick](https://imagemagick.org) | `/img convert` and covers on Linux (from your package manager) | ImageMagick License |
| [Chromium](https://www.chromium.org), Chrome, Edge | the AI looks at the pages it builds, in headless mode (the one you installed) | BSD-3-Clause and others |
| [Pester](https://pester.dev) | the tests of the Windows module (not part of an install) | Apache-2.0 |

## Methods

- Guided filter: K. He, J. Sun, X. Tang, *Guided Image Filtering* (ECCV 2010); fast variant: K. He, J. Sun, *Fast Guided Filter* (2015)
- Foreground estimation: M. Forte, F. Pitié, *Approximate Fast Foreground Colour Estimation* (ICIP 2021), as also used in BiRefNet's examples
- GrabCut via OpenCV: C. Rother, V. Kolmogorov, A. Blake (SIGGRAPH 2004)

## MeshChat for Windows

`meshchat.exe` (built from `win/meshchat` by the CI) is one file with these inside. The repository holds only the
sources; NuGet supplies the rest when it is built.

| Software | What it is for | License |
|---|---|---|
| [.NET 8 runtime](https://github.com/dotnet/runtime) | the program runs on it – nothing to install | MIT |
| [BouncyCastle.Cryptography](https://github.com/bcgit/bc-csharp) 2.4.0 | Ed25519 signatures (RFC 8032) – the Mac uses Apple's CryptoKit for the same | MIT |
| Windows SDK projection (Microsoft.Windows.SDK.NET.Ref) | the calls into Windows' Bluetooth (WinRT) | [Windows SDK license terms](https://aka.ms/WinSDKLicenseURL) |
