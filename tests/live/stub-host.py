#!/usr/bin/env python3
"""A stand-in for the compile host of the Live Server's Vue support, for the tests of the server (it has nothing of Vue in it): it
speaks the same lines – one JSON request on stdin, one JSON answer on stdout – and makes a .vue file into a module that says what it
was given, so that what the server does around the compiler can be tested without one.

    stub-host.py [<script>…]       (the scripts the real host loads are named too and ignored)

What it does with a request {"id", "file", "source"}:
    a source with the word BREAK in it       → {"id", "errors": [{"message": "BREAK in <file>", "line": 2, "column": 3}]}
    a source with the word CRASH in it       → the program ends without an answer
    a source with the word SLOW in it        → answers after two seconds
    any other                                → {"id", "code": "export default { stub: <file>, size: <bytes>, source: <the source> };"}
and {"op": "version"} → {"id", "vue": "stub"}. It counts the requests it got in the file named by LOTUS_STUB_COUNT (one line each).
"""
import json
import os
import sys
import time

count = os.environ.get("LOTUS_STUB_COUNT")
for line in sys.stdin:
    req = json.loads(line)
    if count:
        with open(count, "a") as f:
            f.write("%s\n" % req.get("file", req.get("op")))
    if req.get("op") == "version":
        out = {"id": req["id"], "vue": "stub"}
    elif "CRASH" in req["source"]:
        sys.exit(3)
    elif "BREAK" in req["source"]:
        out = {"id": req["id"], "errors": [{"message": "BREAK in %s" % req["file"], "line": 2, "column": 3}]}
    else:
        if "SLOW" in req["source"]:
            time.sleep(2)
        out = {"id": req["id"], "code": "export default { stub: %s, size: %d, source: %s };\n" % (
            json.dumps(req["file"]), len(req["source"].encode("utf-8")), json.dumps(req["source"]))}
    sys.stdout.write(json.dumps(out) + "\n")
    sys.stdout.flush()
