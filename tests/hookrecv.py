"""本地 webhook 接收器：把收到的请求原样打印出来，用于验证路由器推送。

    python tests/hookrecv.py [port]

只用来做本地联调，收到什么都不做，直接回 {"ok":true}。
"""
import sys
from datetime import datetime
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8899


class H(BaseHTTPRequestHandler):
    def _show(self, body):
        ts = datetime.now().strftime("%H:%M:%S")
        print(f"--- {ts}  {self.command} {self.path} ---", flush=True)
        if body:
            print(body.decode("utf-8", "replace"), flush=True)
        else:
            print("(空正文)", flush=True)

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        self._show(self.rfile.read(n) if n else b"")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"ok":true}')

    def do_GET(self):
        self._show(b"")
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, *a):
        pass


print(f"listening on 0.0.0.0:{PORT}", flush=True)
HTTPServer(("0.0.0.0", PORT), H).serve_forever()
