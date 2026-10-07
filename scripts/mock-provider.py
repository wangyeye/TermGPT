#!/usr/bin/env python3
"""Local-only OpenAI-compatible test fixture; no external API credentials needed."""
import argparse
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != '/v1/chat/completions':
            self.send_error(404)
            return
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        if not body.get('stream') or not body.get('messages'):
            self.send_error(400)
            return
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.end_headers()
        for text in ['本地接口测试通过。\n', '```bash\n', 'printf TermGPT_OK', '\n```']:
            self.wfile.write(('data: ' + json.dumps({'choices': [{'delta': {'content': text}}]}) + '\n\n').encode())
            self.wfile.flush()
        self.wfile.write(b'data: [DONE]\n\n')

    def log_message(self, fmt, *args):
        pass

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=18765)
    args = parser.parse_args()
    print(f'Test fixture listening on http://127.0.0.1:{args.port}/v1', flush=True)
    HTTPServer(('127.0.0.1', args.port), Handler).serve_forever()
