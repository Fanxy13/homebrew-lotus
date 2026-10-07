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

## Methods

- Guided filter: K. He, J. Sun, X. Tang, *Guided Image Filtering* (ECCV 2010); fast variant: K. He, J. Sun, *Fast Guided Filter* (2015)
- Foreground estimation: M. Forte, F. Pitié, *Approximate Fast Foreground Colour Estimation* (ICIP 2021), as also used in BiRefNet's examples
- GrabCut via OpenCV: C. Rother, V. Kolmogorov, A. Blake (SIGGRAPH 2004)
