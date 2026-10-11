# A tiny OpenAI-compatible model for tests/test-aiserver.zsh: python3 fake-openai.py <port>
# Streams like a real one. A message with "run" calls run_command (echo lotus-test-ok); after the tool
# result it says what the command printed; anything else gets a short Markdown answer.
# "delete" asks for rm -rf ./nothing-here, "admin" for sudo ls – both must not run without the user.
# "html" gets an answer with the HTML models like to write into Markdown (<br>, <b>, &nbsp; …).
# "look at" calls view_page on site/index.html at phone width, "make a page" writes site2/index.html.
# Stopping too early, so Lotus lets it go on: "think too long" runs out of room once, "never ends"
# always, "announce" says what it will do next after a step and stops, "ask back" ends with a question.
# Asking instead of acting: "offer to build" only asks whether it should (Lotus tells it to act), "explain then
# offer" answers at length and ends with an offer (that stays the answer). "raw newline" writes a file with
# arguments that have real line breaks in a string (Lotus repairs them), "broken call" sends arguments that
# cannot be repaired and then stops without a word (Lotus lets it go on).
# "break off" ends the stream in the middle, like a model server that crashed.
# "in the background" runs a command that leaves a program running (sleep 20 &) – the step must not wait for it.
# Going wrong the way small models do: "cut the file short" writes 1 line over big.txt (50 lines), "search twice"
# makes the same search again and again, "alias" calls open_file with file_path, "paste the code" puts two files
# into the answer instead of writing them, "think in circles" thinks the same sentence over and over,
# "think then look" thinks and lists the folder (its thinking must come back with the tool call).
# With FAKE_LOG set, every request is appended to that file (one JSON per line).
# "take your time" thinks for about 3 seconds (its thoughts come in pieces), then answers "Took my time." –
# long enough to close the page in between.
# "how hard" gets back how it was asked to think (a model on this Mac gets it with every message) and
# whether the ultra instructions are there.
# Asked to improve a prompt (data/ai/system.md "## enhance"), it answers "Goal: <the request>" – or fails
# with an error when the request contains "fail-enhance".
import json
import os
import sys
import time
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
        # the user's latest request – not Lotus' "go on" messages
        asked = [str(m.get("content", "")) for m in messages if m.get("role") == "user"]
        said = next((t for t in reversed(asked) if not t.startswith(("You ran out of room", "You said what you would do next",
                                                                        "You only thought", "Continue the task"))), "")
        nudge = str(last.get("content", "")) if last.get("role") == "user" else ""
        if os.environ.get("FAKE_LOG"):
            with open(os.environ["FAKE_LOG"], "a") as f:
                f.write(json.dumps(body) + "\n")
        tools_done = sum(1 for m in messages[[i for i, m in enumerate(messages) if m.get("role") == "user"][-1]:] if m.get("role") == "tool")
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
        elif nudge.startswith("Do not ask whether you should"):
            chunk({"content": "Done without asking."})
            chunk({}, "stop")
        elif last.get("role") == "user" and "offer to build" in said:
            chunk({"content": "I can create two files for you, index.html and style.css. Would you like me to generate them in this folder?"})
            chunk({}, "stop")
        elif last.get("role") == "user" and "explain then offer" in said:
            chunk({"content": "Here is the history in detail. " + "It began in Paris and grew step by step. " * 20})
            chunk({"content": "Would you like me to build a website about it?"})
            chunk({}, "stop")
        elif body.get("tools") and last.get("role") == "user" and "raw newline" in said:
            args = '{"path": "raw.txt", "content": "line one\nline two\tend \\\' quoted"}'   # a real line break and tab, and a backslash before '
            call = {"index": 0, "id": "call_r", "type": "function", "function": {"name": "write_file", "arguments": args}}
            chunk({"tool_calls": [call]})
            chunk({}, "tool_calls")
        elif last.get("role") == "tool" and "raw newline" in said:
            chunk({"content": "Wrote it."})
            chunk({}, "stop")
        elif nudge.startswith("Continue the task") and "broken call" in said:
            chunk({"content": "Recovered after the broken call."})
            chunk({}, "stop")
        elif body.get("tools") and last.get("role") == "user" and "broken call" in said:
            call = {"index": 0, "id": "call_b", "type": "function",
                    "function": {"name": "write_file", "arguments": '{"path": "broken.txt", "content": "never closed'}}
            chunk({"tool_calls": [call]})
            chunk({}, "tool_calls")
        elif last.get("role") == "tool" and "broken call" in said:
            chunk({}, "stop")
        elif nudge.startswith(("You thought for a long time", "Your thinking went in circles")):
            chunk({"content": "Acting now."})
            chunk({}, "stop")
        elif nudge.startswith("You wrote the code into your answer"):
            chunk({"content": "Created the files now."})
            chunk({}, "stop")
        elif "think in circles" in said and last.get("role") == "user":
            for i in range(200):
                chunk({"reasoning_content": "I need to decide how to start, so let me consider the options for the page once more. "})
            chunk({"content": "This should never be reached."})
            chunk({}, "stop")
        elif "paste the code" in said and last.get("role") == "user":
            page = "\n".join("<p>line %d</p>" % i for i in range(20))
            style = "\n".join("p.l%d { color: red; }" % i for i in range(20))
            chunk({"content": "Here is the page:\n\n```html\n" + page + "\n```\n\nAnd the style:\n\n```css\n" + style + "\n```\n\nSave them as index.html and style.css."})
            chunk({}, "stop")
        elif body.get("tools") and "cut the file short" in said and last.get("role") == "user":
            call = {"index": 0, "id": "call_s", "type": "function", "function": {"name": "write_file", "arguments": json.dumps({"path": "big.txt", "content": "just one line\\n"})}}
            chunk({"tool_calls": [call]})
            chunk({}, "tool_calls")
        elif body.get("tools") and "search twice" in said and last.get("role") in ("user", "tool") and tools_done < 3:
            call = {"index": 0, "id": "call_t%d" % tools_done + "", "type": "function", "function": {"name": "search_files", "arguments": json.dumps({"pattern": "needle"})}}
            chunk({"tool_calls": [call]})
            chunk({}, "tool_calls")
        elif body.get("tools") and "alias" in said and last.get("role") == "user":
            call = {"index": 0, "id": "call_o", "type": "function", "function": {"name": "open_file", "arguments": json.dumps({"file_path": "raw.txt"})}}
            chunk({"tool_calls": [call]})
            chunk({}, "tool_calls")
        elif body.get("tools") and "think then look" in said and last.get("role") == "user":
            chunk({"reasoning_content": "I will look at the folder first."})
            call = {"index": 0, "id": "call_l", "type": "function", "function": {"name": "list_directory", "arguments": json.dumps({"path": "."})}}
            chunk({"tool_calls": [call]})
            chunk({}, "tool_calls")
        elif last.get("role") == "tool" and ("cut the file short" in said or "search twice" in said or "think then look" in said):
            chunk({"content": "Done with the steps."})
            chunk({}, "stop")
        elif "take your time" in said and last.get("role") == "user":
            for i in range(6):
                chunk({"reasoning_content": "Thinking step %d. " % i})
                time.sleep(0.5)
            chunk({"content": "Took my time."})
            chunk({}, "stop")
        elif "break off" in said:
            chunk({"reasoning_content": "Let me start …"})
            return          # no finish reason, no [DONE]: the server broke off
        elif "how hard" in said:
            kw = body.get("chat_template_kwargs") or {}
            ultra = "yes" if "The user chose ultra effort" in system else "no"
            chunk({"content": "thinking %s %s, ultra %s" % (kw.get("reasoning_effort", "-"), str(kw.get("enable_thinking", "-")).lower(), ultra)})
            chunk({}, "stop")
        elif "never ends" in said or ("think too long" in said and not nudge.startswith("You ran out of room")):
            chunk({"reasoning_content": "Let me think about this for a very long time …"})
            chunk({}, "length")
        elif nudge.startswith("You ran out of room"):
            chunk({"content": "Finished after going on."})
            chunk({}, "stop")
        elif nudge.startswith("You said what you would do next"):
            chunk({"content": "All done now."})
            chunk({}, "stop")
        elif body.get("tools") and last.get("role") == "user" and ("announce" in nudge or "ask back" in nudge):
            call = {"index": 0, "id": "call_a", "type": "function",
                    "function": {"name": "run_command", "arguments": json.dumps({"command": "echo step-one"})}}
            chunk({"tool_calls": [call]})
            chunk({}, "tool_calls")
        elif last.get("role") == "tool" and "announce" in said:
            chunk({"content": "The first step worked. Now I'll create style.css."})
            chunk({}, "stop")
        elif last.get("role") == "tool" and "ask back" in said:
            chunk({"content": "The first step worked. Shall I also add a footer?"})
            chunk({}, "stop")
        elif body.get("tools") and last.get("role") == "user" and "make a page" in str(last.get("content", "")):
            page = '<!doctype html><html lang="en"><head><title>T</title><link rel="stylesheet" href="style.css"></head><body><h1>Hi</h1></body></html>'
            call = {"index": 0, "id": "call_w", "type": "function",
                    "function": {"name": "write_file", "arguments": json.dumps({"path": "site2/index.html", "content": page})}}
            chunk({"tool_calls": [call]})
            chunk({}, "tool_calls")
        elif body.get("tools") and last.get("role") == "user" and "look at" in str(last.get("content", "")):
            call = {"index": 0, "id": "call_v", "type": "function",
                    "function": {"name": "view_page", "arguments": json.dumps({"path": "site/index.html", "view": "phone", "inspect": "h1"})}}
            chunk({"tool_calls": [call]})
            chunk({}, "tool_calls")
        elif body.get("tools") and last.get("role") == "user" and "in the background" in str(last.get("content", "")):
            call = {"index": 0, "id": "call_bg", "type": "function",
                    "function": {"name": "run_command", "arguments": json.dumps({"command": "sleep 20 & echo started-it"})}}
            chunk({"tool_calls": [call]})
            chunk({}, "tool_calls")
        elif body.get("tools") and last.get("role") == "user" and any(w in str(last.get("content", "")) for w in ("delete", "admin", "run")):
            said = str(last.get("content", ""))
            command = "rm -rf ./nothing-here" if "delete" in said else "sudo ls" if "admin" in said else "echo lotus-test-ok"
            call = {"index": 0, "id": "call_1", "type": "function",
                    "function": {"name": "run_command", "arguments": json.dumps({"command": command})}}
            chunk({"tool_calls": [call]})
            chunk({}, "tool_calls")
        elif last.get("role") == "user" and "html" in str(last.get("content", "")):
            chunk({"content": "Line one<br>line two &amp; more &rarr; x\n\nUse List<T> here and <b>bold</b> too.\n\n"})
            chunk({"content": "```html\n<p>a<br>b</p>\n```\n\n| A | B |\n|---|---|\n| 1 | x<br>y |\n"})
            chunk({}, "stop")
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
