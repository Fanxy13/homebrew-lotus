# A tiny OpenAI-compatible model for tests/test-aiserver.zsh: python3 fake-openai.py <port>
# Streams like a real one. A message with "run" calls run_command (echo lotus-test-ok); after the tool
# result it says what the command printed; anything else gets a short Markdown answer.
# "delete" asks for rm -rf ./nothing-here, "admin" for sudo ls – both must not run without the user.
# Asked to improve a prompt (data/ai/system.md "## enhance"), it answers "Goal: <the request>" – or fails
# with an error when the request contains "fail-enhance".
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Model(BaseHTTPRequestHandler):
    def do_POST(self):
        size = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(size) or b"{}")
        messages = body.get("messages") or [{}]
        last = messages[-1]
        system = str(messages[0].get("content", "")) if messages[0].get("role") == "system" else ""
        improving = system.startswith("You improve a request")
        request = str(last.get("content", "")).split("The request to improve:\n")[-1]
        if improving and "fail-enhance" in request:
            self.send_response(500)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"error": {"message": "the test model fails on purpose"}}')
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()

        def chunk(delta, finish=None):
            data = {"choices": [{"index": 0, "delta": delta, "finish_reason": finish}]}
            self.wfile.write(b"data: " + json.dumps(data).encode() + b"\n\n")
            self.wfile.flush()

        if improving:
            chunk({"content": "Goal: " + request})
            chunk({}, "stop")
        elif body.get("tools") and last.get("role") == "user" and any(w in str(last.get("content", "")) for w in ("delete", "admin", "run")):
            said = str(last.get("content", ""))
            command = "rm -rf ./nothing-here" if "delete" in said else "sudo ls" if "admin" in said else "echo lotus-test-ok"
            call = {"index": 0, "id": "call_1", "type": "function",
                    "function": {"name": "run_command", "arguments": json.dumps({"command": command})}}
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
