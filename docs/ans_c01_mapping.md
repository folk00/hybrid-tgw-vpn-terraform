# ANS-C01 Concept Mapping

| ANS-C01 Area | Project Evidence |
|---|---|
| VPC design | Isolated private subnets across two AZs |
| Routing | Dedicated route table plus gateway endpoint route injection |
| Hybrid connectivity | Optional real TGW, Customer Gateway and Site-to-Site VPN connections |
| Private access to AWS services | S3 and DynamoDB Gateway VPC Endpoints |
| Security | IAM least privilege, S3 public access block, SSE-S3, security group |
| Observability | CloudWatch log group, structured JSON logs, metric filter |
| Automation | Terraform IaC, PowerShell deploy/destroy helpers |
| DNS | Documented future Route 53 Resolver pattern |
| SD-WAN/cloud integration | Samples and analyzer detect SD-WAN, OMP, VPN, TGW and route table risks |
| Operations | MOP risk checks, rollback/pre-check/post-check validation |

## Design Highlights

- The Lambda is private and does not require NAT for AWS service access.
- S3 and DynamoDB access is through Gateway VPC Endpoints.
- Tenant isolation is enforced via S3 prefixes and DynamoDB partition keys.
- CloudWatch receives structured JSON events, and a metric filter turns risk
  scores into a metric.
- Optional TGW/VPN is disabled by default to control cost. When `vpn_sites` is
  populated, Terraform creates the TGW, VPN, attachments, associations,
  propagation and route-table entries.
