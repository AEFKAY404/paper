#!/usr/bin/env python3
"""Signed-out, nonpersistent WebKit smoke checks with a Safari-compatible UA."""

import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit, urlunsplit


SITES = {
    "Google Search": "https://www.google.com/search?q=yt",
    "YouTube": "https://www.youtube.com/",
    "GitHub": "https://github.com/",
    "Reddit": "https://www.reddit.com/",
    "Gmail": "https://mail.google.com/",
    "Google Docs": "https://docs.google.com/",
    "Microsoft": "https://www.microsoft.com/",
    "Wikipedia": "https://www.wikipedia.org/",
}
EXPRESSION = """JSON.stringify({title:document.title,readyState:document.readyState,
  bodyLength:document.body?.innerText.length ?? 0,
  excerpt:document.body?.innerText.slice(0,220) ?? '',
  videoElements:document.querySelectorAll('video').length,
  inputElements:document.querySelectorAll('input').length,
  jsExecuted:21*2})"""


def run_probe(binary: Path, url: str, expression: str, ua: str | None = None) -> dict:
    env = os.environ.copy()
    env.update(PAPER_IDENTITY_URL=url, PAPER_IDENTITY_EXPR=expression,
               PAPER_IDENTITY_DELAY="2")
    if ua:
        env["PAPER_CUSTOM_UA"] = ua
    try:
        process = subprocess.run([str(binary)], env=env, capture_output=True,
                                 text=True, timeout=22)
        output = process.stdout
        result = {"exitCode": process.returncode}
    except subprocess.TimeoutExpired as error:
        output = (error.stdout or b"").decode("utf-8", "replace")
        result = {"timedOut": True}
    for line in output.splitlines():
        if line.startswith("PAGE_URL="):
            result["finalURL"] = line.removeprefix("PAGE_URL=")
        elif line.startswith("JS_RESULT="):
            value = line.removeprefix("JS_RESULT=")
            try:
                result["page"] = json.loads(value)
            except json.JSONDecodeError:
                result["page"] = value
        elif line.startswith("NAVIGATION_ERROR="):
            result["navigationError"] = line.removeprefix("NAVIGATION_ERROR=")
        elif line.startswith("JS_ERROR="):
            result["javascriptError"] = line.removeprefix("JS_ERROR=")
    return result


def main() -> None:
    binary = Path(tempfile.gettempdir()) / "paper-identity-probe"
    if not binary.exists():
        subprocess.run(["xcrun", "swiftc", "tools/identity_probe.swift", "-o", str(binary)],
                       check=True)
    base = run_probe(binary, "data:text/html,<title>UA</title>", "navigator.userAgent")
    default_ua = base.get("page")
    safari_info = Path("/Applications/Safari.app/Contents/Info.plist")
    with safari_info.open("rb") as stream:
        safari_version = plistlib.load(stream)["CFBundleShortVersionString"]
    engine = re.search(r"AppleWebKit/([\d.]+)", default_ua or "")
    if not engine or not re.fullmatch(r"\d+(?:\.\d+){0,2}", safari_version):
        raise SystemExit("Could not derive a truthful desktop WebKit identity")
    ua = f"{default_ua} Version/{safari_version} Safari/{engine.group(1)} Paper/1.0"
    rows = []
    for name, url in SITES.items():
        result = run_probe(binary, url, EXPRESSION, ua)
        # Keep opaque server tokens and challenge query strings out of saved output.
        if "finalURL" in result:
            parts = urlsplit(result["finalURL"])
            result["finalURL"] = urlunsplit((parts.scheme, parts.netloc, parts.path, "", ""))
        rows.append({"site": name, "requestedURL": url, **result})
        print(name, result.get("page", {}).get("title") if isinstance(result.get("page"), dict)
              else result.get("navigationError", "timed out"), flush=True)
    output = Path(sys.argv[1] if len(sys.argv) > 1 else "/private/tmp/paper-web-compatibility.json")
    output.write_text(json.dumps({"userAgent": ua, "sites": rows}, indent=2) + "\n")
    print(f"saved {output}")


if __name__ == "__main__":
    main()
