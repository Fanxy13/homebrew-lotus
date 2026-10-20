# A tiny Modrinth for tests/test-minecraft.zsh: python3 fake-modrinth.py <port>
# /v2/search answers with two plugins (and remembers the query in FAKE_LOG when set),
# /v2/project/<id>/version gives one version with one file, /files/<name> serves it.
# The project "broken" gives a file whose checksum does not match; "needsdep" requires "dep".
import hashlib, json, os, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs

PORT = int(sys.argv[1])
FILES = {name: ("jar of " + name).encode() for name in ("good.jar", "broken.jar", "needsdep.jar", "dep.jar")}

class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, code, body, kind="application/json"):
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        if os.environ.get("FAKE_LOG"):
            with open(os.environ["FAKE_LOG"], "a") as f:
                f.write(json.dumps({"path": u.path, "query": q, "ua": self.headers.get("User-Agent")}) + "\n")
        if u.path == "/v2/search":
            hits = [
                {"project_id": "good", "slug": "good-plugin", "title": "Good Plugin", "downloads": 1234567,
                 "author": "someone", "description": "Does good\tthings\nwell"},
                {"project_id": "needsdep", "slug": "needs-dep", "title": "Needs Dep", "downloads": 999,
                 "author": "other", "description": "Needs another plugin"},
            ]
            return self.send(200, {"hits": hits, "offset": 0, "limit": 30, "total_hits": 42})
        if u.path.startswith("/v2/project/") and u.path.endswith("/version"):
            pid = u.path.split("/")[3]
            if pid not in ("good", "broken", "needsdep", "dep"):
                return self.send(404, {"error": "not found"})
            name = pid + ".jar"
            sha = hashlib.sha512(FILES[name]).hexdigest()
            if pid == "broken":
                sha = "0" * 128
            deps = [{"project_id": "dep", "dependency_type": "required"}] if pid == "needsdep" else []
            base = "http://127.0.0.1:%d/files/" % PORT
            versions = [
                {"version_number": "2.0-beta", "version_type": "beta",
                 "files": [{"url": base + name, "filename": name, "primary": True, "hashes": {"sha512": sha}}],
                 "dependencies": []},
                {"version_number": "1.5", "version_type": "release",
                 "files": [{"url": base + name, "filename": name, "primary": True, "hashes": {"sha512": sha}}],
                 "dependencies": deps},
            ]
            return self.send(200, versions)
        if u.path.startswith("/files/") and u.path[7:] in FILES:
            return self.send(200, FILES[u.path[7:]], "application/java-archive")
        self.send(404, {"error": "not found"})

HTTPServer(("127.0.0.1", PORT), H).serve_forever()
