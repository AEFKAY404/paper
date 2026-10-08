#!/usr/bin/env python3
"""Local-only browser identity fixture. Prints selected request headers as JSON."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os


PAGE = b"""<!doctype html><meta charset=utf-8><title>Paper Identity Probe</title>
<script src=/script.js></script><img src=/pixel alt="">
<main>Local browser identity diagnostic. No data is sent off this Mac.</main>"""
SCRIPT = b"""window.paperIdentity = {
  userAgent: navigator.userAgent,
  platform: navigator.platform,
  vendor: navigator.vendor,
  language: navigator.language,
  languages: navigator.languages,
  cookieEnabled: navigator.cookieEnabled,
  maxTouchPoints: navigator.maxTouchPoints,
  hardwareConcurrency: navigator.hardwareConcurrency,
  deviceMemory: navigator.deviceMemory ?? null,
  userAgentData: navigator.userAgentData ? {
    brands: navigator.userAgentData.brands,
    mobile: navigator.userAgentData.mobile,
    platform: navigator.userAgentData.platform
  } : null,
  webdriver: navigator.webdriver,
  devicePixelRatio: window.devicePixelRatio,
  screenWidth: screen.width,
  screenHeight: screen.height,
  cssGrid: CSS.supports('display', 'grid'),
  cssContainerQueries: CSS.supports('container-type', 'inline-size'),
  serviceWorker: 'serviceWorker' in navigator,
  credentials: 'credentials' in navigator,
  share: 'share' in navigator,
  mediaCapabilities: 'mediaCapabilities' in navigator
};
document.addEventListener('DOMContentLoaded', () => {
  const result = document.createElement('pre');
  result.id = 'identity-result';
  result.textContent = JSON.stringify(window.paperIdentity);
  document.body.append(result);
});"""


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        print(json.dumps({
            "path": self.path,
            "userAgent": self.headers.get("User-Agent"),
            "acceptLanguage": self.headers.get("Accept-Language"),
            "secChUa": self.headers.get("Sec-CH-UA"),
            "secChUaPlatform": self.headers.get("Sec-CH-UA-Platform"),
        }), flush=True)
        if self.path == "/redirect":
            self.send_response(302)
            self.send_header("Location", "/landing")
            self.end_headers()
            return
        if self.path == "/script.js":
            body, kind = SCRIPT, "application/javascript"
        elif self.path == "/pixel":
            body, kind = b"", "image/png"
        else:
            body, kind = PAGE, "text/html; charset=utf-8"
        self.send_response(200)
        self.send_header("Content-Type", kind)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):
        pass


if __name__ == "__main__":
    port = int(os.environ.get("PAPER_IDENTITY_PORT", "8765"))
    print(f"identity probe: http://127.0.0.1:{port}/redirect", flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
