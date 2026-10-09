#!/usr/bin/env python3
"""Local, synthetic two-page fixture for testing the embedded browser."""
import argparse
import base64
import http.server
import sys
import json
import os
import pathlib
import tempfile

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/auth' and self.headers.get('Authorization') != 'Basic ' + base64.b64encode(b'fixture:fixture').decode():
            self.send_response(401)
            self.send_header('WWW-Authenticate', 'Basic realm="TermGPT synthetic test"')
            self.end_headers()
            return
        page = 'Second page' if self.path == '/second' else 'TermGPT WebView fixture'
        body = f'<!doctype html><html><head><title>{page}</title></head><body><h1>{page}</h1><input placeholder="Spelling test"><a href="/auth">Basic Auth test</a><a href="/second">Next page</a><a href="/" target="_blank">Open in browser tab</a><form action="/second" method="post"><input name="username" autocomplete="username" placeholder="Username"><input type="password" name="password" autocomplete="current-password" placeholder="Password"><button type="submit">Login</button></form><button onclick="prompt(\'Password Required:\')">noVNC prompt test</button></body></html>'.encode()
        if self.path == '/legacy':
            body = '''<!doctype html><html><head><title>Legacy login fixture</title></head><body>
            <h1>Legacy login fixture</h1><div style="display:none"><input type="password" name="old_password"><input type="password" name="new_password"></div>
            <input type="text" id="txt_Username" placeholder="Username"><input type="password" id="txt_Password" autocomplete="off" placeholder="Password">
            <input type="button" id="loginbutton" value="登  录" onclick="document.getElementById('result').textContent='Synthetic login clicked'">
            <p id="result">Not submitted</p></body></html>'''.encode()
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", "0")))
        self.send_response(303)
        self.send_header("Location", "/second")
        self.end_headers()
    def log_message(self, *_):
        pass

if __name__ == '__main__':
    if sys.version_info < (3, 8):
        sys.exit('Python 3.8 or newer is required.')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=8765)
    parser.add_argument('--clear-saved-auth', type=pathlib.Path, help='Remove only fixture/fixture credentials for this loopback port from a credentials.json file, then exit.')
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error('port must be in 1..65535')
    if args.clear_saved_auth:
        path = args.clear_saved_auth
        if path.is_symlink() or not path.is_file():
            parser.error('Configuration must be a regular file.')
        data = json.loads(path.read_text())
        passwords = data.get('webPasswords', {})
        for key, value in list(passwords.items()):
            origin = f'http://127.0.0.1:{args.port}'
            if (key == 'form:' + origin and value == {'username': 'fixture', 'password': 'fixture'}
                    or key == 'prompt:' + origin + ':Password Required:' and value == {'username': '', 'password': 'fixture'}):
                del passwords[key]
                continue
            try:
                scope = json.loads(key)
            except (ValueError, TypeError):
                continue
            if (isinstance(scope, list) and len(scope) == 5 and scope[:4] == ['http', '127.0.0.1', str(args.port), 'TermGPT synthetic test']
                    and value == {'username': 'fixture', 'password': 'fixture'}):
                del passwords[key]
        descriptor, temporary = tempfile.mkstemp(dir=path.parent, prefix='.fixture-cleanup-')
        try:
            with os.fdopen(descriptor, 'w') as output:
                json.dump(data, output, ensure_ascii=False, indent=2)
            os.replace(temporary, path)
        finally:
            if os.path.exists(temporary): os.unlink(temporary)
        print('Synthetic fixture credential cleanup complete.')
        sys.exit(0)
    server = http.server.HTTPServer(('127.0.0.1', args.port), Handler)
    print(f'WEB fixture: http://127.0.0.1:{args.port}/', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
