"""The graphics cards of this PC that DirectML can use (Windows): DXGI's list of adapters, each asked whether it can
make a Direct3D 12 device – what DirectML needs. Windows' software adapter (Microsoft Basic Render Driver) is left
out: DirectML refuses it, and it would only be the processor in disguise. Plain ctypes, no package needed.
"""
import ctypes
import sys

_SOFTWARE = 0x2                 # DXGI_ADAPTER_FLAG_SOFTWARE
_FEATURE_LEVEL_11_0 = 0xB000    # the lowest Direct3D 12 feature level


class _GUID(ctypes.Structure):
    _fields_ = [("d1", ctypes.c_uint32), ("d2", ctypes.c_uint16), ("d3", ctypes.c_uint16), ("d4", ctypes.c_ubyte * 8)]

    def __init__(self, text):
        h = text.replace("-", "")
        super().__init__(int(h[:8], 16), int(h[8:12], 16), int(h[12:16], 16),
                         (ctypes.c_ubyte * 8)(*bytes.fromhex(h[16:])))


class _DESC1(ctypes.Structure):   # DXGI_ADAPTER_DESC1
    _fields_ = [("Description", ctypes.c_wchar * 128), ("VendorId", ctypes.c_uint), ("DeviceId", ctypes.c_uint),
                ("SubSysId", ctypes.c_uint), ("Revision", ctypes.c_uint), ("DedicatedVideoMemory", ctypes.c_size_t),
                ("DedicatedSystemMemory", ctypes.c_size_t), ("SharedSystemMemory", ctypes.c_size_t),
                ("LuidLow", ctypes.c_uint32), ("LuidHigh", ctypes.c_int32), ("Flags", ctypes.c_uint)]


def _method(obj, slot, *argtypes):
    """A method of a COM object by its place in the vtable"""
    vtbl = ctypes.cast(obj, ctypes.POINTER(ctypes.POINTER(ctypes.c_void_p))).contents
    return ctypes.WINFUNCTYPE(ctypes.c_long, ctypes.c_void_p, *argtypes)(vtbl[slot])


def adapters():
    """Every adapter DXGI lists → [{index, name, vendor, mb, software, d3d12}] (index: DirectML's device_id);
    [] off Windows or when DXGI is not there"""
    if sys.platform != "win32":
        return []
    try:
        dxgi = ctypes.WinDLL("dxgi")
        d3d12 = ctypes.WinDLL("d3d12")
    except OSError:
        return []
    create = d3d12.D3D12CreateDevice
    create.restype = ctypes.c_long
    create.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(_GUID), ctypes.c_void_p]
    factory = ctypes.c_void_p()
    if dxgi.CreateDXGIFactory1(ctypes.byref(_GUID("770aae78-f26f-4dba-a829-253c83d1b387")), ctypes.byref(factory)) != 0:
        return []
    found = []
    try:
        # IUnknown 0–2 · IDXGIObject 3–6 · IDXGIFactory 7–11 · IDXGIFactory1: EnumAdapters1 = 12
        enum = _method(factory, 12, ctypes.c_uint, ctypes.POINTER(ctypes.c_void_p))
        i = 0
        while i < 64:
            adapter = ctypes.c_void_p()
            if enum(factory, i, ctypes.byref(adapter)) != 0:      # DXGI_ERROR_NOT_FOUND after the last one
                break
            try:
                desc = _DESC1()
                # IDXGIAdapter 7–9 · IDXGIAdapter1: GetDesc1 = 10
                if _method(adapter, 10, ctypes.POINTER(_DESC1))(adapter, ctypes.byref(desc)) == 0:
                    software = bool(desc.Flags & _SOFTWARE) or (desc.VendorId == 0x1414 and desc.DeviceId == 0x8C)
                    # no device is made: with a null pointer for it, D3D12CreateDevice only says whether it could
                    hr = create(adapter, _FEATURE_LEVEL_11_0, ctypes.byref(_GUID("189819f1-1db6-4b57-be54-1821339b85f7")), None)
                    found.append({"index": i, "name": desc.Description.strip(), "vendor": desc.VendorId,
                                  "mb": desc.DedicatedVideoMemory // (1 << 20), "software": software, "d3d12": hr in (0, 1)})
            finally:
                _method(adapter, 2)(adapter)                       # Release
            i += 1
    finally:
        _method(factory, 2)(factory)
    return found


def cards():
    """The adapters DirectML would use, the one with the most memory of its own first (on a laptop: the dedicated
    card before the one built into the processor)"""
    usable = [a for a in adapters() if a["d3d12"] and not a["software"]]
    return sorted(usable, key=lambda a: (-a["mb"], a["index"]))


if __name__ == "__main__":
    # For Lotus on Windows before its environment exists (any Python 3 will do): one line per card,
    # "gpu <device id> <name> <MB>", tab separated – the same as the worker's probe
    for c in cards():
        print("gpu", c["index"], c["name"].replace("\t", " "), c["mb"], sep="\t")
