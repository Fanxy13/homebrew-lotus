"""Talking to Lotus: events on stdout for the progress screen, details in the shared Lotus log."""
import os
import re
import sys
import time

# The event channel is a copy of the original stdout. Everything else that libraries print goes to
# stderr, so a stray print can never be mistaken for an event.
_events = os.fdopen(os.dup(1), "w", buffering=1, encoding="utf-8")
os.dup2(2, 1)
sys.stdout = sys.stderr


def emit(*parts):
    """One event per line, tab separated: stage segment · info backend MPS · done in out 2.1"""
    _events.write("\t".join(str(p).replace("\t", " ").replace("\n", " ") for p in parts) + "\n")
    _events.flush()


class BgError(Exception):
    """An error with a code the Lotus screen explains (BG-004 …) and a technical reason."""

    def __init__(self, code, reason, detail=""):
        super().__init__(reason)
        self.code = code
        self.reason = reason
        self.detail = detail


_RANK = {"off": 0, "error": 1, "warn": 2, "info": 3, "debug": 4, "trace": 5}
_LOG = os.environ.get("LOTUS_LOG", "")
_MAX = _RANK.get(os.environ.get("LOTUS_LOG_LEVEL", "info"), 3)
if os.environ.get("LOTUS_VERBOSE") == "1":
    _MAX = max(_MAX, 4)
_HOME = os.path.expanduser("~")
_SECRET = re.compile(r"(sk-(?:ant-|proj-)?)[A-Za-z0-9_-]{12,}")


def log(level, message):
    """Same format as lib/log.zsh: time, level, part, message – home folder as ~, no secrets."""
    if not _LOG or _RANK.get(level.lower(), 3) > _MAX:
        return
    msg = str(message).replace("\t", " ").replace("\r", "").replace("\n", "\\n")
    if len(_HOME) > 1:
        msg = msg.replace(_HOME, "~")
    msg = _SECRET.sub(r"\1•••", msg)
    now = time.time()
    stamp = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(now)) + ".%03d" % int(now % 1 * 1000)
    try:
        fd = os.open(_LOG, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
        try:
            os.write(fd, f"{stamp}\t{level.upper()}\tbg\t{msg}\n".encode("utf-8"))
        finally:
            os.close(fd)
    except OSError:
        pass
    if os.environ.get("LOTUS_VERBOSE") == "1":
        sys.stderr.write(f"\x1b[2m{stamp[11:19]} {level.upper():5} bg: {msg}\x1b[0m\n")


class Stage:
    """with Stage("segment"): …  – announces a stage and logs how long it took."""

    def __init__(self, name, what=None):
        self.name = name
        self.what = what or name

    def __enter__(self):
        self.t0 = time.time()
        emit("stage", self.name)
        log("debug", f"{self.what} …")
        return self

    def __exit__(self, kind, value, tb):
        if kind is None:
            log("debug", f"{self.what}: {time.time() - self.t0:.2f}s")
        return False
