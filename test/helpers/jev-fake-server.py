#!/usr/bin/env python3
"""Stand-in for the Jev API in bats tests.

  jev-fake-server.py <responses.json> <requests.log> <port-file>

responses.json is a list of [status, body, delay?, short?] served in order;
the last one repeats. A true `short` announces a Content-Length longer than
the body, so the client sees the connection close mid-response. Every
request is appended to requests.log as one JSON line when it arrives.
The chosen port is written to port-file once the server is listening.
"""
import http.server
import json
import socketserver
import sys
import threading
import time

responses_path, log_path, port_path = sys.argv[1:4]
with open(responses_path, encoding="utf-8") as f:
    responses = json.load(f)
served = 0
lock = threading.Lock()


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        global served
        body = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode()
        with lock:
            with open(log_path, "a", encoding="utf-8") as f:
                f.write(json.dumps({"auth": self.headers.get("Authorization"), "body": body},
                                   ensure_ascii=False) + "\n")
            status, payload, *rest = responses[min(served, len(responses) - 1)]
            served += 1
        delay = rest[0] if rest else 0
        short = len(rest) > 1 and rest[1]
        if delay:
            time.sleep(delay)
        data = payload.encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data) + (100 if short else 0)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True

    def server_bind(self):
        # HTTPServer.server_bind resolves the host with socket.getfqdn, which
        # takes 35 s under Homebrew's python on GitHub's macOS runners. The
        # name is never used here, so bind without the lookup.
        socketserver.TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address[:2]

    def handle_error(self, request, client_address):
        # A client that gave up (timeout) leaves a broken pipe; that is expected.
        pass


server = Server(("127.0.0.1", 0), Handler)
with open(port_path, "w") as f:
    f.write(str(server.server_address[1]))
server.serve_forever()
