from __future__ import annotations

import argparse
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "app"))

from lambda_function import handler  # noqa: E402


class LocalContext:
    aws_request_id = "local-http-request"


HTML = """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Hybrid TGW + VPN Lab</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 0; background: #f6f8fb; color: #172033; }
    header { background: #172033; color: white; padding: 18px 24px; }
    main { max-width: 1100px; margin: 24px auto; padding: 0 18px; }
    .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 18px; }
    label { display: block; font-weight: 700; margin: 12px 0 6px; }
    input, textarea, button { width: 100%; box-sizing: border-box; font: inherit; }
    input, textarea { border: 1px solid #c8d1dc; border-radius: 6px; padding: 10px; background: white; }
    textarea { min-height: 420px; resize: vertical; }
    button { border: 0; border-radius: 6px; padding: 12px 14px; background: #0f766e; color: white; font-weight: 700; cursor: pointer; margin-top: 12px; }
    pre { background: #0b1020; color: #d8e7ff; padding: 14px; border-radius: 6px; min-height: 420px; overflow: auto; white-space: pre-wrap; }
    .hint { color: #526173; font-size: 14px; }
  </style>
</head>
<body>
  <header>
    <h1>Hybrid TGW + VPN Lab</h1>
    <div>Network change intelligence API - local Lambda simulation</div>
  </header>
  <main>
    <p class="hint">Paste Cisco, SD-WAN, MOP, or AWS hybrid networking text. The local server calls the same handler used by Lambda.</p>
    <div class="grid">
      <section>
        <label for="tenant">Tenant</label>
        <input id="tenant" value="retail-co" />
        <label for="artifact">Artifact name</label>
        <input id="artifact" value="mop_risky_change.md" />
        <label for="content">Artifact content</label>
        <textarea id="content"># MOP - Add SD-WAN Branch To AWS Hybrid Network

Add a new SD-WAN branch and advertise prefixes into AWS through TGW VPN.
Customer gateway IP is &lt;IP_TO_REPLACE&gt;.

Steps:
1. Create VPN attachment.
2. Add route table entry 0.0.0.0/0 toward Internet Gateway.
3. Update BGP neighbor.
4. Push SD-WAN template.
5. Confirm user traffic.

Notes:
- IPsec tunnel will be created.
- Terraform code will be updated.
- No CloudWatch requirement has been documented yet.</textarea>
        <button onclick="analyze()">Analyze</button>
      </section>
      <section>
        <label>Result</label>
        <pre id="result">Click Analyze.</pre>
      </section>
    </div>
  </main>
  <script>
    async function analyze() {
      const body = {
        tenant_id: document.getElementById('tenant').value,
        artifact_name: document.getElementById('artifact').value,
        content: document.getElementById('content').value
      };
      const res = await fetch('/analyze', {
        method: 'POST',
        headers: {'content-type': 'application/json'},
        body: JSON.stringify(body)
      });
      const data = await res.json();
      document.getElementById('result').textContent = JSON.stringify(data, null, 2);
    }
  </script>
</body>
</html>
"""


class Handler(BaseHTTPRequestHandler):
    def _send(self, status: int, body: str, content_type: str = "application/json") -> None:
        data = body.encode("utf-8")
        self.send_response(status)
        self.send_header("content-type", content_type)
        self.send_header("content-length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self) -> None:
        if self.path == "/":
            self._send(200, HTML, "text/html; charset=utf-8")
            return
        event = {
            "rawPath": self.path,
            "requestContext": {"http": {"method": "GET"}},
        }
        response = handler(event, LocalContext())
        self._send(response["statusCode"], response["body"])

    def do_POST(self) -> None:
        length = int(self.headers.get("content-length") or "0")
        raw = self.rfile.read(length).decode("utf-8", errors="replace")
        event = {
            "rawPath": self.path,
            "requestContext": {"http": {"method": "POST"}},
            "body": raw,
        }
        response = handler(event, LocalContext())
        self._send(response["statusCode"], response["body"])

    def log_message(self, fmt: str, *args) -> None:
        sys.stdout.write("%s - %s\n" % (self.address_string(), fmt % args))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8008)
    args = parser.parse_args()
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"Serving http://{args.host}:{args.port}")
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
