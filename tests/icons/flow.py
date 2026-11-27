#!/usr/bin/env python3
"""A conversation with a program in a pseudo terminal: wait for a text, then type something.

    python3 tests/icons/flow.py <steps.json> <command> [arguments…]

steps.json is a list of [text to wait for, keys to type afterwards]; the keys may be empty (only wait). Each text is looked
for after the one before it, in what the program printed with its colors and cursor movements taken out. Waiting is for as
long as the machine needs (60 seconds at most for one text), so a slow computer is no reason for a test to fail. What the
program printed goes to stdout; the exit status is the program's, or 99 when a text never came (then it says which).
Python's standard library only – the same on macOS and Linux (the tests of Lotus already need python3 for their terminals).
"""
import fcntl
import json
import os
import pty
import re
import select
import signal
import struct
import sys
import termios
import time

SEQUENCE = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]|\x1b[=>]|\r")


def main():
    steps = json.load(open(sys.argv[1], encoding="utf-8"))
    command = sys.argv[2:]
    pid, fd = pty.fork()
    if pid == 0:
        os.execvp(command[0], command)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 50, 100, 0, 0))
    seen = {"text": "", "eof": False}

    def pump(wait):
        """Reads what the program printed; False when it has nothing more to say (it ended)."""
        if seen["eof"]:
            return False
        ready, _, _ = select.select([fd], [], [], wait)
        if not ready:
            return True
        try:
            data = os.read(fd, 65536)
        except OSError:
            data = b""
        if not data:
            seen["eof"] = True
            return False
        seen["text"] += SEQUENCE.sub("", data.decode("utf-8", "replace"))
        return True

    position = 0
    for want, keys in steps:
        deadline = time.time() + 60
        while True:
            found = seen["text"].find(want, position)
            if found >= 0:
                position = found + len(want)
                break
            if time.time() > deadline or not pump(0.1):
                if seen["text"].find(want, position) >= 0:
                    continue
                print(seen["text"])
                print("flow.py: this text never came: " + want)
                try:
                    os.kill(pid, signal.SIGKILL)
                except OSError:
                    pass
                os.waitpid(pid, 0)
                return 99
        if keys:
            time.sleep(0.15)          # the program has printed its question – give it the moment to start reading
            os.write(fd, keys.encode("utf-8"))

    end = time.time() + 30
    while time.time() < end and pump(0.1):
        pass
    print(seen["text"])
    try:
        _, status = os.waitpid(pid, 0)
    except ChildProcessError:
        return 0
    return os.waitstatus_to_exitcode(status)


if __name__ == "__main__":
    sys.exit(main())
