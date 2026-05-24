#!/usr/bin/env python3
"""
led-daemon — HTTP shim that wraps /usr/local/bin/led for the QML UI.

Binds 127.0.0.1:8081 (loopback only — the UI process is on the same board).

Endpoints:
  GET  /led                            — current sysfs state as JSON
  POST /led/on
  POST /led/off
  POST /led/set?v=N
  POST /led/blink?count=N&ms=M         — non-blocking (spawned)
  POST /led/timer?on_ms=N&off_ms=M
  POST /led/none
"""
import json
import os
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

LED_BIN = os.environ.get("LED_BIN", "/usr/local/bin/led")
LED_DIR = "/sys/class/leds/user-led"
LISTEN = ("127.0.0.1", 8081)


def run_led(*args, background=False):
    cmd = [LED_BIN, *args]
    if background:
        subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return 0, "spawned"
    p = subprocess.run(cmd, capture_output=True, text=True)
    return p.returncode, (p.stdout + p.stderr).strip()


def read_state():
    out = {}
    for k in ("brightness", "max_brightness", "trigger"):
        try:
            with open(f"{LED_DIR}/{k}") as f:
                out[k] = f.read().strip()
        except OSError as e:
            out[k] = f"err: {e}"
    return out


class Handler(BaseHTTPRequestHandler):
    def _reply(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):
        sys.stderr.write("[led-daemon] " + (fmt % args) + "\n")

    def _route(self, method):
        u = urlparse(self.path)
        q = {k: v[0] for k, v in parse_qs(u.query).items()}
        path = u.path.rstrip("/") or "/"

        if method == "GET" and path == "/led":
            return self._reply(200, {"ok": True, "state": read_state()})

        if method != "POST":
            return self._reply(405, {"ok": False, "err": "method not allowed"})

        try:
            if path == "/led/on":
                rc, msg = run_led("on")
            elif path == "/led/off":
                rc, msg = run_led("off")
            elif path == "/led/set":
                rc, msg = run_led("set", q.get("v", "0"))
            elif path == "/led/blink":
                rc, msg = run_led("blink", q.get("count", "10"),
                                  q.get("ms", "200"), background=True)
            elif path == "/led/timer":
                rc, msg = run_led("timer", q.get("on_ms", "500"),
                                  q.get("off_ms", "500"))
            elif path == "/led/none":
                rc, msg = run_led("none")
            else:
                return self._reply(404, {"ok": False, "err": "unknown path"})
        except FileNotFoundError:
            return self._reply(500, {"ok": False,
                                     "err": f"led binary not found at {LED_BIN}"})

        return self._reply(200 if rc == 0 else 500,
                           {"ok": rc == 0, "rc": rc, "out": msg,
                            "state": read_state()})

    def do_GET(self):
        self._route("GET")

    def do_POST(self):
        self._route("POST")


def main():
    print(f"[led-daemon] listening on {LISTEN[0]}:{LISTEN[1]}, LED_BIN={LED_BIN}",
          file=sys.stderr)
    ThreadingHTTPServer(LISTEN, Handler).serve_forever()


if __name__ == "__main__":
    main()
