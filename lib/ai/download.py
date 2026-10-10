# Lotus – downloads a model from Hugging Face for lotus ai local (lib/cmd/ai.zsh, _llm_fetch) and keeps a
# progress file up to date for Lotus' own progress line:
#   <bytes received> <bytes written>
# Received is what came over the network. With Hugging Face's Xet storage the data arrives in blocks of
# up to 64 MB and is written to the model files later, so the files alone grow in jumps – a speed taken
# from them shoots up and falls to zero again and again.
#   python download.py <repo> <revision> <folder> <progress file>
# The progress is extra: if it cannot be counted (another huggingface_hub version), the model still downloads.
import os
import sys
import threading
import time

from huggingface_hub import snapshot_download

repo, revision, folder, progress = sys.argv[1:5]
bars = {}                  # "received" / "written": the byte counters of snapshot_download
lock = threading.Lock()

try:
    from tqdm import tqdm

    class Report(tqdm):
        """A progress bar that shows nothing – it only counts, for the progress file."""

        def __init__(self, *args, **kwargs):
            kwargs.pop("name", None)
            kwargs["disable"] = False
            kwargs["file"] = open(os.devnull, "w")
            super().__init__(*args, **kwargs)
            if self.unit == "B":
                kind = "received" if str(self.desc or "").lower().startswith("downloading") else "written"
                with lock:
                    bars.setdefault(kind, self)
except Exception:
    Report = None


def write():
    with lock:
        counts = [int(getattr(bars.get(k), "n", 0) or 0) for k in ("received", "written")]
    try:
        with open(progress + ".tmp", "w") as f:
            f.write("%d %d\n" % tuple(counts))
        os.replace(progress + ".tmp", progress)
    except OSError:
        pass


def keep_writing():
    while True:
        write()
        time.sleep(0.5)


threading.Thread(target=keep_writing, daemon=True).start()
args = {"repo_id": repo, "revision": revision, "local_dir": folder}
if Report is not None:
    args["tqdm_class"] = Report
try:
    snapshot_download(**args)
except TypeError as e:
    if "tqdm_class" not in str(e):
        raise
    del args["tqdm_class"]          # an older huggingface_hub: download without counting
    snapshot_download(**args)
write()
