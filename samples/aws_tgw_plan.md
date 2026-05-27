# AWS Hybrid Networking Plan

Tenant: retail-co

## Scope

Connect branch SD-WAN sites into AWS through Site-to-Site VPN terminating on a
Transit Gateway. Application VPCs attach to the TGW and use route propagation.

## AWS Components

- VPC 10.42.0.0/16
- Transit Gateway
- Site-to-Site VPN with BGP
- Customer Gateway public IP x.x.x.x
- Private subnets for app workloads
- S3 Gateway VPC Endpoint
- DynamoDB Gateway VPC Endpoint
- CloudWatch log group for app telemetry
- Route 53 Resolver outbound rules for on-prem DNS

## Validation

- Confirm BGP session state up on both tunnels
- Confirm TGW route propagation for branch prefixes
- Confirm VPC route table sends branch CIDRs to TGW
- Confirm S3 access stays private through gateway endpoint
- Confirm CloudWatch receives app logs

## Open Items

- Replace customer gateway IP placeholder
- Confirm branch advertised prefixes
- Confirm rollback process
