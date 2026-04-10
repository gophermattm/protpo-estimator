#!/usr/bin/env python3
"""Local CORS proxy for QXO/Beacon API.

Runs on localhost:8182, forwards requests to api.qxo.com,
and relays cookies so the Flutter web app can authenticate.

Usage:  python3 tools/qxo_proxy.py
"""

import http.server
import json
import ssl
import urllib.request
import urllib.error
from http.cookies import SimpleCookie

PORT = 8182
QXO_BASE = 'https://api.qxo.com'

# Stored cookies from QXO login
stored_cookies: dict[str, str] = {}


class QxoProxyHandler(http.server.BaseHTTPRequestHandler):
    def do_OPTIONS(self):
        self._send_cors_headers(200)
        self.end_headers()

    def do_GET(self):
        self._proxy('GET')

    def do_POST(self):
        self._proxy('POST')

    def _proxy(self, method):
        target_url = QXO_BASE + self.path
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length) if content_length > 0 else None

        # Build request to QXO
        req = urllib.request.Request(target_url, data=body, method=method)
        req.add_header('Content-Type', 'application/json')

        # Send stored cookies
        if stored_cookies:
            cookie_str = '; '.join(f'{k}={v}' for k, v in stored_cookies.items())
            req.add_header('Cookie', cookie_str)

        # Disable SSL verification for simplicity in dev
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE

        try:
            resp = urllib.request.urlopen(req, context=ctx)
            resp_body = resp.read()

            # Store any Set-Cookie headers from QXO
            for header_line in resp.headers.get_all('Set-Cookie') or []:
                cookie = SimpleCookie(header_line)
                for key, morsel in cookie.items():
                    stored_cookies[key] = morsel.value
                    if key == 'access_token':
                        print(f'  [proxy] Stored access_token ({len(morsel.value)} chars)')

            # Send response back to Flutter
            self._send_cors_headers(resp.status)
            self.send_header('Content-Type', 'application/json; charset=utf-8')
            self.end_headers()
            self.wfile.write(resp_body)

        except urllib.error.HTTPError as e:
            error_body = e.read()
            self._send_cors_headers(e.code)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(error_body)

        except Exception as e:
            self._send_cors_headers(502)
            self.end_headers()
            self.wfile.write(json.dumps({'error': str(e)}).encode())

    def _send_cors_headers(self, status_code):
        self.send_response(status_code)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')

    def log_message(self, format, *args):
        print(f'  [proxy] {args[0]}')


if __name__ == '__main__':
    server = http.server.HTTPServer(('127.0.0.1', PORT), QxoProxyHandler)
    print(f'QXO proxy listening on http://127.0.0.1:{PORT}')
    print(f'Forwarding to {QXO_BASE}')
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print('\nProxy stopped.')
