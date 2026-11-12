#!/usr/bin/env python3
"""Makes lib/edit/web/faces.bin – the face detector of the image editor's Face Blur tab – from YuNet's ONNX file.

    python3 scripts/make-face-model.py <face_detection_yunet_2023mar.onnx>

YuNet (Shiqi Yu and others, MIT license) is a face detector of 53,000 numbers. Its file comes from OpenCV's model zoo:
https://github.com/opencv/opencv_zoo/tree/main/models/face_detection_yunet (the file is checked against SHA256 below).

The editor runs the model in the page, in plain JavaScript (lib/edit/web/faces.js) – on every system, with nothing to install.
For that the ONNX file (a protocol buffer of a graph) becomes a file a few lines of JavaScript can read:

    "LFACE1\\n\\0"  ·  the length of the header (uint32, little endian)  ·  the header (JSON)  ·  zeros up to a multiple of 4
    ·  the numbers (float32, little endian)

The header lists the steps in the order they run. A step works on numbered slots (pictures of numbers, channel after channel):
    ["c3s2", out, in, cin, cout, w, b]   a 3×3 convolution with stride 2 and a border of 1 (the first step)
    ["pw",   out, in, cin, cout, w, b]   a 1×1 convolution
    ["dw",   out, in, c, w, b]           a 3×3 convolution of each channel by itself, border 1
    ["relu", slot] · ["sig", slot]       in place
    ["pool", out, in]                    the biggest of 2×2
    ["up",   out, in]                    twice as wide and high (every number four times)
    ["add",  out, a, b]
    ["free", slot, …]                    these slots are not needed any more
w and b are where a step's weights and biases start in the numbers.

Only Python's standard library: the protocol buffer is read by hand (reader below), so anyone can make the file again.
"""
import hashlib
import json
import os
import struct
import sys

SHA256 = "8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4"      # face_detection_yunet_2023mar.onnx
SOURCE = "https://github.com/opencv/opencv_zoo/tree/main/models/face_detection_yunet"
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lib", "edit", "web", "faces.bin")
MAGIC = b"LFACE1\n\0"


# ── A protocol buffer, read by hand ────────────────────────────

def varint(buf, i):
    n = shift = 0
    while True:
        b = buf[i]
        i += 1
        n |= (b & 0x7F) << shift
        if not b & 0x80:
            return n, i
        shift += 7


def fields(buf):
    """(field number, wire type, value) of a message: value is an int (varint, fixed) or bytes (length-delimited)."""
    i, end = 0, len(buf)
    while i < end:
        key, i = varint(buf, i)
        num, wire = key >> 3, key & 7
        if wire == 0:
            val, i = varint(buf, i)
        elif wire == 1:
            val, i = buf[i:i + 8], i + 8
        elif wire == 2:
            n, i = varint(buf, i)
            val, i = buf[i:i + n], i + n
        elif wire == 5:
            val, i = buf[i:i + 4], i + 4
        else:
            raise ValueError("a wire type this reader does not know: %d" % wire)
        yield num, wire, val


def ints(wire, val):
    """A repeated int64 field: one number, or many packed into bytes."""
    if wire == 0:
        return [val]
    out, i = [], 0
    while i < len(val):
        n, i = varint(val, i)
        out.append(n)
    return out


def tensor(buf):
    """TensorProto → (name, dims, numbers)."""
    name, dims, kind, raw, floats, longs = "", [], 0, None, [], []
    for num, wire, val in fields(buf):
        if num == 1:
            dims += ints(wire, val)
        elif num == 2:
            kind = val
        elif num == 4:
            floats += list(struct.unpack("<%df" % (len(val) // 4), val)) if wire == 2 else [struct.unpack("<f", val)[0]]
        elif num == 7:
            longs += ints(wire, val)
        elif num == 8:
            name = val.decode("utf-8")
        elif num == 9:
            raw = val
    if kind == 1:                                       # FLOAT
        data = list(struct.unpack("<%df" % (len(raw) // 4), raw)) if raw is not None else floats
    elif kind == 7:                                     # INT64
        data = list(struct.unpack("<%dq" % (len(raw) // 8), raw)) if raw is not None else longs
    else:
        raise ValueError("tensor %s has a type this reader does not know: %d" % (name, kind))
    return name, dims, data


def attribute(buf):
    name, value = "", None
    for num, wire, val in fields(buf):
        if num == 1:
            name = val.decode("utf-8")
        elif num == 2:
            value = struct.unpack("<f", val)[0]
        elif num == 3:
            value = val
        elif num == 4:
            value = val.decode("utf-8", "replace")
        elif num == 5:
            value = tensor(val)
        elif num == 7:
            value = (value or []) + (list(struct.unpack("<%df" % (len(val) // 4), val)) if wire == 2 else [struct.unpack("<f", val)[0]])
        elif num == 8:
            value = (value or []) + ints(wire, val)
    return name, value


def node(buf):
    n = {"in": [], "out": [], "op": "", "attr": {}}
    for num, _wire, val in fields(buf):
        if num == 1:
            n["in"].append(val.decode("utf-8"))
        elif num == 2:
            n["out"].append(val.decode("utf-8"))
        elif num == 4:
            n["op"] = val.decode("utf-8")
        elif num == 5:
            k, v = attribute(val)
            n["attr"][k] = v
    return n


def graph(model):
    nodes, init, outputs = [], {}, []
    for num, _wire, val in fields(model):
        if num != 7:                                    # ModelProto.graph
            continue
        for gnum, _gwire, gval in fields(val):
            if gnum == 1:
                nodes.append(node(gval))
            elif gnum == 5:
                name, dims, data = tensor(gval)
                init[name] = (dims, data)
            elif gnum == 12:                            # ValueInfoProto: its name is field 1
                outputs.append([v for n, _w, v in fields(gval) if n == 1][0].decode("utf-8"))
    return nodes, init, outputs


# ── The graph as steps ─────────────────────────────────────────

def convert(nodes, init, outputs):
    slot, steps, numbers = {"input": 0}, [], []
    uses = {}
    for n in nodes:
        for name in n["in"]:
            uses[name] = uses.get(name, 0) + 1

    def new(name):
        slot[name] = len(set(slot.values()))
        return slot[name]

    def put(values):
        at = len(numbers)
        numbers.extend(values)
        return at

    for n in nodes:
        op, a = n["op"], n["attr"]
        if op == "Conv":
            dims, w = init[n["in"][1]]
            bdims, b = init[n["in"][2]]
            co, cig, kh, kw = dims
            group, stride, pads = a.get("group", 1), a.get("strides", [1, 1]), a.get("pads", [0, 0, 0, 0])
            if a.get("dilations", [1, 1]) != [1, 1] or bdims != [co]:
                raise ValueError("a convolution this converter does not know")
            src = slot[n["in"][0]]
            if (kh, kw) == (3, 3) and stride == [2, 2] and pads == [1, 1, 1, 1] and group == 1:
                steps.append(["c3s2", new(n["out"][0]), src, cig, co, put(w), put(b)])
            elif (kh, kw) == (1, 1) and stride == [1, 1] and pads == [0, 0, 0, 0] and group == 1:
                steps.append(["pw", new(n["out"][0]), src, cig, co, put(w), put(b)])
            elif (kh, kw) == (3, 3) and stride == [1, 1] and pads == [1, 1, 1, 1] and group == co and cig == 1:
                steps.append(["dw", new(n["out"][0]), src, co, put(w), put(b)])
            else:
                raise ValueError("a convolution this converter does not know: %r %r" % (dims, a))
        elif op in ("Relu", "Sigmoid"):
            if uses.get(n["in"][0], 0) != 1:
                raise ValueError("%s of a value that is used elsewhere too" % op)
            slot[n["out"][0]] = slot[n["in"][0]]                        # in place
            steps.append(["relu" if op == "Relu" else "sig", slot[n["in"][0]]])
        elif op == "MaxPool":
            if a.get("kernel_shape") != [2, 2] or a.get("strides") != [2, 2] or a.get("pads", [0, 0, 0, 0]) != [0, 0, 0, 0] or a.get("ceil_mode", 0):
                raise ValueError("a pooling this converter does not know")
            steps.append(["pool", new(n["out"][0]), slot[n["in"][0]]])
        elif op == "Resize":
            scales = init[n["in"][2]][1]
            if a.get("mode") != "nearest" or scales != [1.0, 1.0, 2.0, 2.0]:
                raise ValueError("a resize this converter does not know")
            steps.append(["up", new(n["out"][0]), slot[n["in"][0]]])
        elif op == "Add":
            steps.append(["add", new(n["out"][0]), slot[n["in"][0]], slot[n["in"][1]]])
        elif op in ("Transpose", "Reshape"):
            # the end of the graph only puts the numbers in another order (rows of pixels) – the page reads the pictures as they are
            if uses.get(n["in"][0], 0) != 1:
                raise ValueError("%s of a value that is used elsewhere too" % op)
            slot[n["out"][0]] = slot[n["in"][0]]
        else:
            raise ValueError("a step this converter does not know: %s" % op)

    out = {}
    for name in outputs:
        kind, stride = name.split("_")
        out.setdefault(kind, {})[int(stride)] = slot[name]
    strides = sorted(out["cls"])
    result = dict((k, [out[k][s] for s in strides]) for k in ("cls", "obj", "bbox", "kps"))

    # a slot is free after the last step that reads it (the results stay)
    keep, last = set(s for v in result.values() for s in v), {}
    for i, st in enumerate(steps):
        for s in st[1:4] if st[0] == "add" else st[1:3] if st[0] in ("c3s2", "pw", "dw", "pool", "up") else st[1:2]:
            last[s] = i
    with_free = []
    for i, st in enumerate(steps):
        with_free.append(st)
        gone = sorted(s for s, at in last.items() if at == i and s not in keep)
        if gone:
            with_free.append(["free"] + gone)
    return with_free, result, strides, numbers, len(set(slot.values()))


def main(argv):
    if len(argv) != 1:
        print(__doc__.strip().split("\n\n")[0])
        return 2
    with open(argv[0], "rb") as f:
        data = f.read()
    digest = hashlib.sha256(data).hexdigest()
    if digest != SHA256:
        print("This is not the file this script knows (SHA256 %s)." % digest)
        return 1
    nodes, init, outputs = graph(data)
    steps, result, strides, numbers, slots = convert(nodes, init, outputs)
    header = {
        "format": "lotus-faces-1",
        "model": "YuNet – face_detection_yunet_2023mar.onnx",
        "source": SOURCE,
        "sha256": SHA256,
        "license": "MIT License, Copyright (c) 2020 Shiqi Yu",
        "input": "blue, green, red (0 to 255), a width and height that are multiples of 32",
        "strides": strides,
        "slots": slots,
        "numbers": len(numbers),
        "steps": steps,
        "outputs": result,
    }
    head = json.dumps(header, separators=(",", ":"), sort_keys=True).encode("utf-8")
    pad = b"\0" * (-(len(MAGIC) + 4 + len(head)) % 4)
    blob = MAGIC + struct.pack("<I", len(head)) + head + pad + struct.pack("<%df" % len(numbers), *numbers)
    with open(OUT, "wb") as f:
        f.write(blob)
    print("%s: %d steps, %d numbers, %d bytes, SHA256 %s" % (os.path.relpath(OUT), len([s for s in steps if s[0] != "free"]),
                                                              len(numbers), len(blob), hashlib.sha256(blob).hexdigest()))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
