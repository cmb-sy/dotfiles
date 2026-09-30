#!/usr/bin/env python3
"""Stand-in for the Jev API in bats tests.

  jev-fake-server.py <responses.json> <requests.log> <port-file>

responses.json is a list of [status, body, delay?] served in order; the last
one repeats. Every request is appended to requests.log as one JSON line.
The chosen port is written to port-file once the server is listening.
"""
import http.server
import json
import sys
import time

responses_path, log_path, port_path = sys.argv[1:4]
with open(responses_path, encoding="utf-8") as f:
    responses = json.load(f)
served = 0


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        global served
        body = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode()
        with open(log_path, "a", encoding="utf-8") as f:
            f.write(json.dumps({"auth": self.headers.get("Authorization"), "body": body},
                               ensure_ascii=False) + "\n")
        status, payload, *rest = responses[min(served, len(responses) - 1)]
        served += 1
        if rest:
            time.sleep(rest[0])
        data = payload.encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass


server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
with open(port_path, "w") as f:
    f.write(str(server.server_address[1]))
server.serve_forever()
