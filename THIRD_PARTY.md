# Third-party software

Lotus itself is MIT licensed (see [LICENSE](LICENSE)). It bundles only what is listed under *In the repository*; the rest
below it does not bundle – Remove BG downloads it on first use, after asking, into `~/.local/share/lotus` on your Mac.

## In the repository

### YuNet – the face detector of the image editor's Face Blur tab

`lib/edit/web/faces.bin` holds the weights of **YuNet** (Shiqi Yu et al., *YuNet: A Tiny Millisecond-level Face Detector*,
Machine Intelligence Research 2023; training code [ShiqiYu/libfacedetection.train](https://github.com/ShiqiYu/libfacedetection.train)),
53,104 numbers. They come from `face_detection_yunet_2023mar.onnx` of OpenCV's model zoo
([opencv/opencv_zoo, models/face_detection_yunet](https://github.com/opencv/opencv_zoo/tree/main/models/face_detection_yunet)),
SHA-256 `8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4`, converted by `scripts/make-face-model.py` into a file
the page reads (SHA-256 `e0cdd19406bb0a1c96cb0c1962fe67636591d34e1fd4bdea6b75e373dc14e1f3`). The network runs in the browser, in plain JavaScript (`lib/edit/web/faces.js`); nothing is downloaded.

```
MIT License

Copyright (c) 2020 Shiqi Yu <shiqi.yu@gmail.com>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### Vue 3 – .vue files in the Live Server (macOS)

`lib/live/vue/` holds **Vue 3.5.45** (Evan You and the Vue contributors, MIT) – the two files `lotus liveserver` needs to serve a project
that is made of `.vue` files without Node, npm or a build step. They are made by `scripts/vendor-vue.py` from the packages on the npm
registry (each checked against the sha512 the registry publishes for it, pinned in the script):

| File | From | SHA-256 |
|---|---|---|
| `lib/live/vue/vue.js` | `vue@3.5.45`, `dist/vue.esm-browser.js`, as it is | `47528b748162468b6a98fe6587ad4cfbe8febd504673cf28a07114dfcf4485a1` |
| `lib/live/vue/compiler-sfc.js` | `@vue/compiler-sfc@3.5.45`, `dist/compiler-sfc.esm-browser.js`; only its last line is changed (`export { … }` → `globalThis.VueCompilerSFC = { … }`, so that JavaScriptCore can run it as a script) | `ade4bd4219482c7980e5654adad7cfc0958bf7fce66ba0fd4ac24202825fe467` |
| `lib/live/vue/LICENSE` | the `LICENSE` of both packages | `1bb85cc9b13b81ef41c81c51866172fc345e0503c86726a6755b796590b70175` |

`vue.js` is what a page gets for `import { createApp } from 'vue'` (through an import map the Live Server puts into the page);
`compiler-sfc.js` compiles each `.vue` file on the Mac, in Apple's own JavaScript engine (JavaScriptCore) – nothing is sent anywhere.
The compiler file also contains, with their notices kept where they are, code of Babel's parser (`@babel/parser`), `estree-walker`,
`magic-string`, PostCSS and `postcss-selector-parser`, `source-map-js` (BSD-3-Clause, © Mozilla Foundation and contributors, and
the Closure Compiler Authors), `merge-source-map` and `hash-sum` – the packages `@vue/compiler-sfc` itself is built from.

```
The MIT License (MIT)

Copyright (c) 2018-present, Yuxi (Evan) You

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

### A portrait for the tests

`tests/edit/face.png` (SHA-256 `ae200abbe80c32a09c43e2751d3324ff64ab59547ef9d29fdc70012b309eb1e9`) is a part of the portrait of astronaut Eileen Collins by NASA – public domain, as a
work of the U.S. government; it is the `astronaut.png` of [scikit-image](https://github.com/scikit-image/scikit-image)'s sample
data. The tests of the face detector and of Face Blur use it; it is not part of an install.

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
| [ImageMagick](https://imagemagick.org) | `/img` (the editor and `/img convert`) and covers on Linux (from your package manager) | ImageMagick License |
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
| [BouncyCastle.Cryptography](https://github.com/bcgit/bc-csharp) 2.4.0 | Ed25519 signatures (RFC 8032), X25519 (RFC 7748) and ChaCha20-Poly1305 (RFC 8439) for private messages – the Mac uses Apple's CryptoKit for the same | MIT |
| Windows SDK projection (Microsoft.Windows.SDK.NET.Ref) | the calls into Windows' Bluetooth (WinRT) | [Windows SDK license terms](https://aka.ms/WinSDKLicenseURL) |
