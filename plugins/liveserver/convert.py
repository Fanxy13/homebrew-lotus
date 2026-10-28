"""The converter behind /html (html.zsh) – Python's standard library only (3.9 and newer), see lotusdoc/.

    convert.py scan <folder>                   the files it can convert, the newest first: kind, time, path
    convert.py open <folder>                   the page a Live Server of this folder shows in the browser right now
    convert.py convert --to <format> [--page] [--all] --root <folder> [--result <file>] [<file> …]

Formats: txt, md, docx, odt, rtf, pdf. Code (the default) is the file as it is written – colored like VS Code, with
the number of each line; txt is the file itself, byte for byte. --page makes HTML pages what a visitor reads
(headings, text, lists, tables, links, images) – style sheets and scripts stay code. --all converts every page,
style sheet and script of the folder into a folder of its own (Word/, PDF/ …) inside it; single files get their
document next to them. Nothing is ever written over: a file of the same name gets "(2)" – unless it is one this
converter made and nobody changed since (made.tsv in the plugin's data folder), which is made again.
"""
import sys

sys.dont_write_bytecode = True          # no __pycache__ in the plugin's folder: Lotus would take it for a change

import datetime
import os
import re
import shutil
import subprocess

from lotusdoc import highlight, page, writers
from lotusdoc.model import Document, Code

FORMATS = {"txt": "Text", "md": "Markdown", "docx": "Word", "odt": "OpenDocument", "rtf": "RTF", "pdf": "PDF"}
KINDS = {
    "page": (".html", ".htm", ".xhtml"),
    "style": (".css", ".scss", ".sass", ".less"),
    "script": (".js", ".mjs", ".cjs", ".jsx", ".ts", ".tsx", ".mts", ".vue", ".svelte"),
    "data": (".json", ".xml", ".webmanifest", ".php"),
    "text": (".md", ".markdown", ".txt", ".csv"),
}
WORDS = {"page": ("page", "pages"), "style": ("style sheet", "style sheets"), "script": ("script", "scripts"),
         "data": ("data file", "data files"), "text": ("text", "texts")}
IMAGES = (".png", ".jpg", ".jpeg", ".gif", ".webp", ".avif", ".svg", ".ico", ".bmp", ".heic", ".tif", ".tiff")
SKIP_DIRS = {"node_modules", "__pycache__", "venv", ".venv", "bower_components", "vendor", "dist", "build", ".next"}
MARKER = ".lotus-html"                  # in a folder this converter made: never converted again
MAX_SIZE = 5 * 1024 * 1024
MAX_FILES = 2000
HOME = os.path.realpath(os.path.expanduser("~"))
TTY = sys.stdout.isatty()


def color(name, fallback):
    code = os.environ.get("LOTUS_COLOR_" + name, "")
    return code if re.fullmatch(r"[0-9;]+", code) else fallback


KEY, ACCENT, DIM = color("KEY", "38;5;150"), color("ACCENT", "38;5;149"), color("DIM", "38;5;245")


def paint(code, text, bold=False):
    return f"\033[{'1;' if bold else ''}{code}m{text}\033[0m" if TTY else text


def say(text=""):
    print(text, flush=True)


def tilde(path):
    return "~" + path[len(HOME):] if path == HOME or path.startswith(HOME + os.sep) else path


def kind_of(name):
    ext = os.path.splitext(name)[1].lower()
    for kind, exts in KINDS.items():
        if ext in exts:
            return kind
    return "image" if ext in IMAGES else ""


def minified(name):
    return bool(re.search(r"[.-]min\.(js|css|mjs)$", name, re.I))


def size_text(n):
    return f"{n} B" if n < 1024 else f"{n / 1024:.1f} KB" if n < 1024 * 1024 else f"{n / 1048576:.1f} MB"


def plural(n, kind):
    one, many = WORDS.get(kind, (kind, kind + "s"))
    return f"{n} {one if n == 1 else many}"


# ── What is in a folder ───────────────────────────────────────

def scan(root, made=None):
    """(files, left out) – files [(kind, mtime, path)] the newest first; left out {reason: [paths]}. Not: hidden
    files, node_modules and the like, links out of the folder, and the documents this converter made."""
    files, left = [], {}
    for folder, dirs, names in os.walk(root):
        if folder != root and os.path.exists(os.path.join(folder, MARKER)):
            dirs[:] = []
            continue
        dirs[:] = sorted(d for d in dirs if not d.startswith(".") and d not in SKIP_DIRS)
        for name in sorted(names):
            if name.startswith(".") or name.endswith("~"):
                continue
            path = os.path.join(folder, name)
            kind = kind_of(name)
            real = os.path.realpath(path)
            if not real.startswith(root + os.sep) or (made and made.ours(path)):
                continue
            try:
                st = os.stat(path)
            except OSError:
                continue
            if kind == "image":
                left.setdefault("images", []).append(path)
            elif not kind:
                left.setdefault("other", []).append(path)
            elif minified(name):
                left.setdefault("minified", []).append(path)
            elif st.st_size > MAX_SIZE:
                left.setdefault("large", []).append(path)
            else:
                files.append((kind, st.st_mtime, path))
            if len(files) >= MAX_FILES:
                break
    files.sort(key=lambda f: -f[1])
    return files, left


# ── The page open in Live Server ──────────────────────────────

def data_dir():
    return os.environ.get("LOTUS_PLUGIN_DATA") or os.path.join(HOME, ".local/share/lotus/plugins/liveserver")


def live_server(pid):
    try:
        out = subprocess.run(["/bin/ps", "-p", str(pid), "-o", "command="], capture_output=True, text=True, timeout=3).stdout
    except (OSError, subprocess.SubprocessError):
        return False
    return "liveserver.py" in out


def open_page(folder):
    """The file of the page a Live Server shows in the browser right now – for this folder, or one around it."""
    running = os.path.join(data_dir(), "running")
    try:
        names = sorted(os.listdir(running))
    except OSError:
        return ""
    best = None
    for name in names:
        if not name.isdigit():
            continue
        try:
            with open(os.path.join(running, name)) as f:
                pid, root = f.read().split("\n")[:2]
            with open(os.path.join(running, name + ".page")) as f:
                rel, stamp = (f.read().split("\n") + ["", "0"])[:2]
        except (OSError, ValueError):
            continue
        root = os.path.realpath(root.strip())
        if not rel or not (folder == root or folder.startswith(root + os.sep) or root.startswith(folder + os.sep)):
            continue
        path = os.path.realpath(os.path.join(root, rel))
        if not path.startswith(root + os.sep) or not os.path.isfile(path) or not live_server(int(pid)):
            continue
        try:
            stamp = float(stamp)
        except ValueError:
            stamp = 0
        if best is None or stamp > best[0]:
            best = (stamp, path)
    return best[1] if best else ""


# ── Where the documents go ────────────────────────────────────

class Made:
    """The documents this converter made (made.tsv): one of them, unchanged since, may be made again."""

    def __init__(self):
        self.path = os.path.join(data_dir(), "made.tsv")
        self.entries = {}
        try:
            with open(self.path, encoding="utf-8") as f:
                for line in f:
                    p = line.rstrip("\n").split("\t")
                    if len(p) == 3:
                        self.entries[p[0]] = (p[1], p[2])
        except OSError:
            pass

    @staticmethod
    def stamp(path):
        st = os.stat(path)
        return str(st.st_size), str(st.st_mtime_ns)

    def ours(self, path):
        try:
            return self.entries.get(path) == self.stamp(path)
        except OSError:
            return False

    def add(self, path):
        try:
            self.entries[path] = self.stamp(path)
        except OSError:
            pass

    def save(self):
        keep = {p: v for p, v in self.entries.items() if os.path.exists(p)}
        items = list(keep.items())[-5000:]
        try:
            os.makedirs(os.path.dirname(self.path), exist_ok=True)
            tmp = self.path + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                f.writelines(f"{p}\t{a}\t{b}\n" for p, (a, b) in items)
            os.replace(tmp, self.path)
        except OSError:
            pass


def out_name(path, fmt, mode):
    """about.html as code → about.html.docx (the code of about.html), as a page → about.docx."""
    name = os.path.basename(path)
    if mode == "page" and kind_of(name) == "page":
        name = os.path.splitext(name)[0]
    return f"{name}.{fmt}"


def free(path, made, taken):
    """path, or "name (2).ext" … when something else is there – our own unchanged document may be made again."""
    n, cand = 2, path
    while cand in taken or (os.path.lexists(cand) and not made.ours(cand)):
        stem, dot, last = path.rpartition(".")
        cand = f"{stem} ({n}).{last}" if dot else f"{path} ({n})"
        n += 1
    taken.add(cand)
    return cand


def out_folder(root, fmt):
    """<folder>/Word – or "Word (2)" … when a folder of that name is there that this converter did not make."""
    label = FORMATS[fmt]
    n, cand = 2, os.path.join(root, label)
    while os.path.exists(cand) and not os.path.exists(os.path.join(cand, MARKER)):
        cand = os.path.join(root, f"{label} ({n})")
        n += 1
    return cand


# ── Converting one file ───────────────────────────────────────

def read_text(path):
    with open(path, "rb") as f:
        data = f.read()
    if b"\0" in data[:8192] and not data.startswith((b"\xff\xfe", b"\xfe\xff")):
        raise ValueError("not text")
    return data, page.decode(data)


def code_document(path, root, rel, text, data):
    lang = highlight.language(path)
    lines = highlight.lines(text, lang)
    stamp = datetime.datetime.fromtimestamp(os.path.getmtime(path)).strftime("%Y-%m-%d %H:%M")
    name = highlight.NAMES[lang] if lang != "text" else os.path.splitext(path)[1].lstrip(".").upper() or "text"
    meta = " · ".join([os.path.basename(root) or root, f"{len(lines)} line{'' if len(lines) == 1 else 's'}", name,
                       size_text(len(data)), stamp])
    return Document(rel, [Code(lines, True, lang)], "code", meta, "en")


def convert(path, out, fmt, mode, root, author):
    """One file into one document → (characters no font had)."""
    rel = os.path.relpath(path, root) if path.startswith(root + os.sep) else os.path.basename(path)
    rel = rel.replace(os.sep, "/")
    data, text = read_text(path)
    tmp = os.path.join(os.path.dirname(out), "." + os.path.basename(out) + ".lotus-tmp")     # hidden: Live Server ignores it
    try:
        if mode == "page" and kind_of(path) == "page":
            doc = page.document(path, root, rel)
        elif fmt == "txt":
            shutil.copyfile(path, tmp)          # the code as text: the file itself, byte for byte
            os.replace(tmp, out)
            return 0
        else:
            doc = code_document(path, root, rel, text, data)
        missing = 0
        if fmt == "pdf":
            from lotusdoc import pdf
            missing = pdf.write_pdf(doc, tmp, author)
        elif fmt in ("docx", "odt", "rtf"):
            getattr(writers, "write_" + fmt)(doc, tmp, author)
        else:
            getattr(writers, "write_" + fmt)(doc, tmp)
        os.replace(tmp, out)
        return missing
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)


# ── convert.py convert ────────────────────────────────────────

def main_convert(args):
    fmt, mode, all_files, root, result, files = "", "code", False, "", "", []
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--to" and i + 1 < len(args):
            fmt, i = args[i + 1], i + 1
        elif a == "--page":
            mode = "page"
        elif a == "--code":
            mode = "code"
        elif a == "--all":
            all_files = True
        elif a == "--root" and i + 1 < len(args):
            root, i = args[i + 1], i + 1
        elif a == "--result" and i + 1 < len(args):
            result, i = args[i + 1], i + 1
        else:
            files.append(a)
        i += 1
    if fmt not in FORMATS:
        say(f"  {paint('31', '✗', True)} A format: {', '.join(FORMATS)}")
        return 2
    root = os.path.realpath(root or os.getcwd())
    author = os.environ.get("LOTUS_NAME", "")
    made = Made()
    left = {}
    if all_files:
        found, left = scan(root, made)
        files = [p for _, _, p in sorted(found, key=lambda f: f[2])]
        folder = out_folder(root, fmt)
    else:
        files = [os.path.realpath(f) for f in files]
        folder = ""
    if not files:
        say(f"  {paint('31', '✗', True)} Nothing to convert here – no pages, style sheets or scripts.")
        return 1
    if folder:
        os.makedirs(folder, exist_ok=True)
        with open(os.path.join(folder, MARKER), "w") as f:
            f.write("Made by Lotus /html – documents of the files around this folder. This file keeps /html from converting them again.\n")
    taken, outputs, failed, kinds, missing = set(), [], [], {}, 0
    width = len(str(len(files)))
    for n, path in enumerate(files, 1):
        rel = os.path.relpath(path, root).replace(os.sep, "/") if path.startswith(root + os.sep) else os.path.basename(path)
        if folder:
            target = os.path.join(folder, os.path.dirname(os.path.relpath(path, root)), out_name(path, fmt, mode))
        else:
            target = os.path.join(os.path.dirname(path), out_name(path, fmt, mode))
        target = free(target, made, taken)
        if TTY and len(files) > 1:
            sys.stdout.write(f"\r\033[K  {paint(ACCENT, '◆')} {str(n).rjust(width)} / {len(files)}  {paint(DIM, rel[-60:])}")
            sys.stdout.flush()
        try:
            os.makedirs(os.path.dirname(target), exist_ok=True)
            missing += convert(path, target, fmt, mode, root, author)
            made.add(target)
            outputs.append(target)
            k = kind_of(path)
            kinds[k] = kinds.get(k, 0) + 1
            if not TTY:
                say(f"  ✓ {rel} → {os.path.relpath(target, root) if target.startswith(root + os.sep) else target}")
        except Exception as e:              # one file that fails does not stop the others
            if str(e) == "not text":
                reason = "not text"
            elif isinstance(e, OSError) and e.strerror:
                reason = e.strerror
            elif isinstance(e, RecursionError):
                reason = "nested too deeply"
            else:
                reason = f"could not be read ({type(e).__name__}: {e})"[:100]
            failed.append((rel, reason))
            if not TTY:
                say(f"  ✗ {rel} – {reason}")
    if TTY and len(files) > 1:
        sys.stdout.write("\r\033[K")
    made.save()
    summary(root, folder, fmt, mode, outputs, failed, kinds, left, missing)
    if result:                          # for html.zsh: one "key<tab>value" a line
        try:
            with open(result, "w", encoding="utf-8") as f:
                f.write(f"done\t{len(outputs)}\nfailed\t{len(failed)}\nfolder\t{folder}\nfirst\t{outputs[0] if outputs else ''}\n")
        except OSError:
            pass
    return 0 if outputs else 1


def summary(root, folder, fmt, mode, outputs, failed, kinds, left, missing):
    label = FORMATS[fmt]
    what = [plural(kinds[k], k) for k in KINDS if k in kinds]
    if len(outputs) == 1 and not folder:
        out = outputs[0]
        shown = "the page as a visitor reads it" if mode == "page" and kinds.get("page") else "the code"
        say(f"  {paint(KEY, '✓', True)} {os.path.basename(out)}  {paint(DIM, label + ' · ' + shown)}")
        say(f"    {paint(DIM, 'Saved next to it: ' + tilde(out))}")
    elif outputs:
        shown = "pages as a visitor reads them" if mode == "page" and kinds.get("page") else "as code"
        say(f"  {paint(KEY, '✓', True)} {len(outputs)} files → {label}  {paint(DIM, ' · '.join(what + [shown]))}")
        where = tilde(folder) if folder else tilde(os.path.dirname(outputs[0]))
        say(f"    {paint(DIM, ('Saved in ' if folder else 'Saved next to them: ') + where)}")
    if missing:
        say(f"    {paint(DIM, f'{missing} character(s) no font on this Mac has are shown as ? in the PDF (emoji, for instance).')}")
    out = []
    if left.get("images"):
        out.append(plural(len(left["images"]), "image"))
    if left.get("minified"):
        names = [os.path.basename(p) for p in left["minified"]]
        out.append(f"{len(names)} minified librar{'y' if len(names) == 1 else 'ies'} ({', '.join(names[:2])}{' …' if len(names) > 2 else ''})")
    if left.get("large"):
        out.append(f"{len(left['large'])} larger than 5 MB")
    if left.get("other"):
        out.append(f"{len(left['other'])} other file{'s' if len(left['other']) != 1 else ''}")
    if out:
        say(f"    {paint(DIM, 'Left out: ' + ' · '.join(out))}")
    for rel, reason in failed[:8]:
        say(f"  {paint('31', '✗', True)} {rel} – {reason}")
    if len(failed) > 8:
        say(f"    {paint(DIM, f'… and {len(failed) - 8} more')}")


def main(args):
    if args[:1] == ["scan"] and len(args) >= 2:
        files, left = scan(os.path.realpath(args[1]), Made())
        for kind, mtime, path in files:
            print(f"{kind}\t{int(mtime)}\t{path}")
        for reason, paths in left.items():
            print(f"left\t{reason}\t{len(paths)}")
        return 0
    if args[:1] == ["open"] and len(args) >= 2:
        path = open_page(os.path.realpath(args[1]))
        if path:
            print(path)
        return 0 if path else 1
    if args[:1] == ["convert"]:
        return main_convert(args[1:])
    print(__doc__.strip())
    return 2


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        sys.exit(130)
