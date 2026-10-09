#!/usr/bin/env python3
"""Local, synthetic two-page fixture for testing the embedded browser."""
import argparse
import base64
import http.server
import sys

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/auth' and self.headers.get('Authorization') != 'Basic ' + base64.b64encode(b'fixture:fixture').decode():
            self.send_response(401)
            self.send_header('WWW-Authenticate', 'Basic realm="TermGPT synthetic test"')
            self.end_headers()
            return
        page = 'Second page' if self.path == '/second' else 'TermGPT WebView fixture'
        body = f'<!doctype html><html><head><title>{page}</title></head><body><h1>{page}</h1><input placeholder="Spelling test"><a href="/auth">Basic Auth test</a><a href="/second">Next page</a><a href="/" target="_blank">Open in browser tab</a></body></html>'.encode()
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *_):
        pass

if __name__ == '__main__':
    if sys.version_info < (3, 8):
        sys.exit('Python 3.8 or newer is required.')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=8765)
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error('port must be in 1..65535')
    server = http.server.HTTPServer(('127.0.0.1', args.port), Handler)
    print(f'WEB fixture: http://127.0.0.1:{args.port}/', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
