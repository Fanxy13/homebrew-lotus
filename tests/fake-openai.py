# A tiny OpenAI-compatible model for tests/test-aiserver.zsh: python3 fake-openai.py <port>
# Streams like a real one. A message with "run" calls run_command (echo lotus-test-ok); after the tool
# result it says what the command printed; anything else gets a short Markdown answer.
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Model(BaseHTTPRequestHandler):
    def do_POST(self):
        size = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(size) or b"{}")
        last = (body.get("messages") or [{}])[-1]
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()

        def chunk(delta, finish=None):
            data = {"choices": [{"index": 0, "delta": delta, "finish_reason": finish}]}
            self.wfile.write(b"data: " + json.dumps(data).encode() + b"\n\n")
            self.wfile.flush()

        if last.get("role") == "user" and "run" in str(last.get("content", "")):
            call = {"index": 0, "id": "call_1", "type": "function",
                    "function": {"name": "run_command", "arguments": json.dumps({"command": "echo lotus-test-ok"})}}
            chunk({"tool_calls": [call]})
            chunk({}, "tool_calls")
        elif last.get("role") == "tool":
            chunk({"content": "The command said: "})
            chunk({"content": str(last.get("content", ""))[:200]})
            chunk({}, "stop")
        else:
            chunk({"content": "Hello **from** the test model."})
            chunk({}, "stop")
        self.wfile.write(b"data: [DONE]\n\n")

    def log_message(self, *args):
        pass


ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), Model).serve_forever()
