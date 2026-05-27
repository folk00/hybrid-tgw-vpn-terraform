# Architecture Notes

## Purpose

HybridNet ANS-C01 Lab is a deployable AWS networking reference that maps cloud
networking concepts to a network operations workflow.

The app is intentionally small. The value is the AWS architecture around it:
private subnets, VPC endpoints, S3, DynamoDB, CloudWatch, IAM, API Gateway and
Lambda.

## Request Flow

1. A user sends a network artifact to `POST /analyze`.
2. API Gateway invokes Lambda.
3. Lambda runs in private subnets.
4. Lambda analyzes the text for AWS/network concepts and change risk.
5. Lambda writes the artifact to S3 through a Gateway VPC Endpoint.
6. Lambda writes an audit row to DynamoDB through a Gateway VPC Endpoint.
7. Lambda logs a structured event to CloudWatch.
8. CloudWatch metric filters extract `risk_score` for visibility.

## Tenant Pattern

This project uses a simple tenant-aware key strategy:

```text
s3://bucket/tenants/{tenant_id}/YYYY/MM/DD/{uuid}-{artifact_name}
DynamoDB partition key: tenant_id
DynamoDB sort key: created_at#request_id
```

It is not full SaaS auth. It demonstrates the isolation pattern in a way that is
easy to explain in an interview.

## Why No NAT Gateway By Default

The Lambda does not need Internet access for the first demo. It reaches S3 and
DynamoDB privately through VPC endpoints. This keeps cost down and demonstrates
private AWS service access, a core AWS networking topic.

## Future Additions

- Optional Bedrock agent path with a private Bedrock interface endpoint
- Transit Gateway multi-VPC route table lab
- Additional Site-to-Site VPN examples for Fortinet, Cisco IOS-XE and Meraki MX
- VPC Flow Logs enabled on demand
- Route 53 Resolver inbound/outbound endpoint module
