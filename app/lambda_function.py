from __future__ import annotations

import base64
import datetime as dt
import hashlib
import json
import os
import re
import uuid
from typing import Any

try:
    import boto3  # type: ignore
except Exception:  # Local mode can run without boto3 installed.
    boto3 = None


S3_BUCKET = os.getenv("S3_BUCKET", "")
AUDIT_TABLE = os.getenv("AUDIT_TABLE", "")
PROJECT_NAME = os.getenv("PROJECT_NAME", "hybridnet-ansc01-lab")

_s3 = boto3.client("s3") if boto3 and S3_BUCKET else None
_ddb = boto3.resource("dynamodb").Table(AUDIT_TABLE) if boto3 and AUDIT_TABLE else None


CONCEPT_PATTERNS: dict[str, list[str]] = {
    "AWS Transit Gateway": ["transit gateway", "tgw", "route propagation", "route association"],
    "Direct Connect": ["direct connect", "dxgw", "direct connect gateway", "private vif"],
    "Site-to-Site VPN": ["site-to-site", "ipsec", "ikev2", "customer gateway", "virtual private gateway"],
    "VPC Routing": ["route table", "0.0.0.0/0", "igw", "internet gateway", "nat gateway"],
    "VPC Endpoints": ["vpc endpoint", "gateway endpoint", "interface endpoint", "privatelink"],
    "Hybrid DNS": ["route 53 resolver", "inbound resolver", "outbound resolver", "conditional forwarder"],
    "Observability": ["cloudwatch", "flow logs", "vpc flow logs", "metric filter", "logs insights"],
    "Network Security": ["security group", "nacl", "network firewall", "waf", "firewall", "palo alto"],
    "Cisco SD-WAN": ["sd-wan", "sdwan", "vmanage", "viptela", "omp", "app-route", "tloc"],
    "Enterprise Routing": ["bgp", "ospf", "eigrp", "mpls", "vrf", "l3vpn", "route-map"],
    "Cisco Switching": ["nexus", "catalyst", "vpc", "lacp", "port-channel", "vlan", "trunk"],
    "Automation": ["terraform", "ansible", "netmiko", "netconf", "restconf", "api", "ci/cd", "gitops"],
}


def _json_response(status_code: int, payload: dict[str, Any]) -> dict[str, Any]:
    return {
        "statusCode": status_code,
        "headers": {
            "content-type": "application/json",
            "access-control-allow-origin": "*",
            "access-control-allow-methods": "GET,POST,OPTIONS",
            "access-control-allow-headers": "content-type,authorization",
        },
        "body": json.dumps(payload, default=str),
    }


def _now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")


def _safe_name(value: str, default: str) -> str:
    value = (value or "").strip()
    value = re.sub(r"[^A-Za-z0-9_.=-]+", "-", value)
    return value.strip("-")[:120] or default


def _decode_body(event: dict[str, Any]) -> dict[str, Any]:
    raw = event.get("body") or "{}"
    if event.get("isBase64Encoded"):
        raw = base64.b64decode(raw).decode("utf-8", errors="replace")
    if isinstance(raw, dict):
        return raw
    try:
        return json.loads(raw)
    except Exception:
        return {"content": str(raw)}


def _hits(content_l: str, patterns: dict[str, list[str]]) -> list[str]:
    found: list[str] = []
    for concept, terms in patterns.items():
        if any(term in content_l for term in terms):
            found.append(concept)
    return found


def _risk_findings(content: str) -> list[str]:
    text = content.lower()
    findings: list[str] = []

    if "rollback" not in text:
        findings.append("Missing rollback plan or rollback trigger.")
    if "pre-check" not in text and "pre check" not in text and "precheck" not in text:
        findings.append("Missing explicit pre-check section.")
    if "post-check" not in text and "post check" not in text and "postcheck" not in text:
        findings.append("Missing explicit post-check validation section.")
    if any(token in text for token in ["tbd", "placeholder", "x.x.x.x", "<ip", "replace-me"]):
        findings.append("Contains placeholders that must be resolved before implementation.")
    if "0.0.0.0/0" in text and not any(token in text for token in ["firewall", "nacl", "security group", "inspection"]):
        findings.append("Default route present without an obvious inspection/security control.")
    if any(token in text for token in ["bgp", "direct connect", "vpn", "tgw"]) and "route table" not in text:
        findings.append("Hybrid routing mentioned without route-table validation details.")
    if "ipsec" in text and "ike" not in text:
        findings.append("IPsec mentioned without IKE/IKEv2 parameter validation.")
    if "sd-wan" in text and "omp" not in text and "vmanage" not in text:
        findings.append("SD-WAN mentioned without OMP/vManage control-plane validation.")
    if "terraform" in text and "plan" not in text:
        findings.append("Terraform mentioned without an explicit plan/review step.")
    if "cloudwatch" not in text and "log" not in text:
        findings.append("No observability/logging validation found.")

    return findings


def analyze_artifact(content: str) -> dict[str, Any]:
    content_l = content.lower()
    concepts = _hits(content_l, CONCEPT_PATTERNS)
    findings = _risk_findings(content)

    risk_score = min(100, 10 + len(findings) * 12)
    if "Network Security" not in concepts and any(x in content_l for x in ["vpn", "tgw", "direct connect", "0.0.0.0/0"]):
        risk_score = min(100, risk_score + 10)
    if findings and any("placeholder" in f.lower() for f in findings):
        risk_score = min(100, risk_score + 8)

    recommendations = [
        "Add explicit owner, maintenance window, rollback trigger, and success criteria.",
        "Include route-table, prefix, and BGP/OMP validation before and after the change.",
        "Confirm CloudWatch/logging or equivalent telemetry before production cutover.",
    ]
    if "VPC Endpoints" not in concepts and any(x in content_l for x in ["s3", "dynamodb", "private subnet"]):
        recommendations.append("Use VPC endpoints for private access to AWS services where possible.")
    if "Hybrid DNS" not in concepts and any(x in content_l for x in ["vpc", "hybrid", "vpn", "direct connect"]):
        recommendations.append("Document DNS/resolver behavior for hybrid connectivity.")

    return {
        "risk_score": risk_score,
        "concepts_detected": concepts,
        "findings": findings,
        "recommendations": recommendations,
    }


def _store_artifact(tenant_id: str, artifact_name: str, content: str) -> str:
    if not _s3:
        return "local-only/no-s3"
    day = dt.datetime.now(dt.timezone.utc).strftime("%Y/%m/%d")
    key = f"tenants/{tenant_id}/{day}/{uuid.uuid4()}-{artifact_name}"
    _s3.put_object(
        Bucket=S3_BUCKET,
        Key=key,
        Body=content.encode("utf-8"),
        ContentType="text/plain; charset=utf-8",
        ServerSideEncryption="AES256",
    )
    return key


def _write_audit(item: dict[str, Any]) -> None:
    if not _ddb:
        return
    _ddb.put_item(Item=item)


def _route(event: dict[str, Any]) -> tuple[str, str]:
    request_context = event.get("requestContext") or {}
    http = request_context.get("http") or {}
    method = http.get("method") or event.get("httpMethod") or "GET"
    path = event.get("rawPath") or event.get("path") or "/"
    return method.upper(), path


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    method, path = _route(event)
    if method == "OPTIONS":
        return _json_response(204, {})
    if path in {"/", "/health"} and method == "GET":
        return _json_response(200, {"ok": True, "project": PROJECT_NAME})
    if path != "/analyze" or method != "POST":
        return _json_response(404, {"error": "Use POST /analyze or GET /health"})

    body = _decode_body(event)
    tenant_id = _safe_name(str(body.get("tenant_id") or "demo-tenant"), "demo-tenant")
    artifact_name = _safe_name(str(body.get("artifact_name") or "artifact.txt"), "artifact.txt")
    content = str(body.get("content") or "")
    if not content.strip():
        return _json_response(400, {"error": "content is required"})

    analysis = analyze_artifact(content)
    request_id = getattr(context, "aws_request_id", str(uuid.uuid4()))
    artifact_sha256 = hashlib.sha256(content.encode("utf-8")).hexdigest()
    s3_key = _store_artifact(tenant_id, artifact_name, content)

    audit_item = {
        "tenant_id": tenant_id,
        "created_at": _now_iso() + f"#{request_id}",
        "request_id": request_id,
        "artifact_name": artifact_name,
        "artifact_sha256": artifact_sha256,
        "s3_key": s3_key,
        "risk_score": analysis["risk_score"],
        "concepts_detected": analysis["concepts_detected"],
        "finding_count": len(analysis["findings"]),
        "ttl_epoch": int(dt.datetime.now(dt.timezone.utc).timestamp()) + 60 * 60 * 24 * 30,
    }
    _write_audit(audit_item)

    log_event = {
        "event": "analysis_completed",
        "tenant_id": tenant_id,
        "request_id": request_id,
        "risk_score": analysis["risk_score"],
        "finding_count": len(analysis["findings"]),
        "concepts": analysis["concepts_detected"],
    }
    print(json.dumps(log_event))

    return _json_response(
        200,
        {
            "tenant_id": tenant_id,
            "artifact_name": artifact_name,
            "artifact_sha256": artifact_sha256,
            "s3_key": s3_key,
            **analysis,
        },
    )
