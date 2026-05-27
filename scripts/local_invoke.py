from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "app"))

from lambda_function import handler  # noqa: E402


class LocalContext:
    aws_request_id = "local-request"


def main() -> int:
    sample = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "samples" / "mop_risky_change.md"
    content = sample.read_text(encoding="utf-8")
    event = {
        "rawPath": "/analyze",
        "requestContext": {"http": {"method": "POST"}},
        "body": json.dumps(
            {
                "tenant_id": "retail-co",
                "artifact_name": sample.name,
                "content": content,
            }
        ),
    }
    response = handler(event, LocalContext())
    print(json.dumps(json.loads(response["body"]), indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
