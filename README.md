# HybridNet ANS-C01 Lab

Terraform-deployable AWS networking lab plus a small Network Change Intelligence API.

This project is designed to show AWS Advanced Networking concepts in a practical
network-automation context: private VPC design, gateway endpoints, S3, DynamoDB,
CloudWatch observability, IAM least privilege, API Gateway, Lambda, optional
Transit Gateway scaffolding, and network/MOP artifact analysis.

## What This Demonstrates

- AWS VPC design with isolated private subnets across two AZs
- S3 Gateway Endpoint and DynamoDB Gateway Endpoint
- API Gateway front door invoking Lambda
- Lambda attached to private subnets with no NAT Gateway by default
- S3 artifact storage with encryption, versioning, lifecycle policy, and public access block
- DynamoDB audit table for request history
- CloudWatch log group, structured JSON logs, and metric filter for risk score
- Optional real Transit Gateway and Site-to-Site VPN lab, disabled by default to avoid cost
- A small app that analyzes Cisco, SD-WAN, MOP, and AWS hybrid networking text

## Why This Fits My Profile

This is not a generic SaaS demo. It is a hybrid network operations lab that
connects AWS Advanced Networking concepts with real enterprise network change
workflows:

- Cisco SD-WAN, Meraki, Nexus, Catalyst, BGP, OSPF, VRF, VPN
- AWS TGW, Direct Connect, Site-to-Site VPN, VPC endpoints, DNS and routing
- MOP review, rollback checks, pre/post validation, auditability
- Infrastructure as Code with Terraform

## Architecture

```text
Client / Browser / curl
        |
        v
Amazon API Gateway HTTP API
        |
        v
AWS Lambda - Network Analyzer
        |
        |-- writes uploaded artifact to S3
        |-- writes audit event to DynamoDB
        |-- writes structured JSON logs to CloudWatch Logs
        |
        v
Private VPC subnets
        |
        |-- S3 Gateway VPC Endpoint
        |-- DynamoDB Gateway VPC Endpoint
```

No NAT Gateway is created by default. The Lambda function reaches S3 and
DynamoDB through VPC Gateway Endpoints, which is a key ANS-C01 concept.

## Folder Layout

```text
app/
  lambda_function.py        # deployable app
samples/
  iosxe_sdwan_edge.txt      # network sample
  aws_tgw_plan.md           # AWS hybrid networking sample
  mop_risky_change.md       # MOP/risk sample
scripts/
  local_invoke.py           # local test without AWS
  deploy.ps1                # Terraform helper
  destroy.ps1               # Terraform helper
terraform/
  versions.tf
  variables.tf
  main.tf
  outputs.tf
docs/
  ans_c01_mapping.md
  architecture.md
```

## Local Test

```powershell
cd "C:\Users\davidgo2\Downloads\New`Project"
python .\scripts\local_invoke.py .\samples\mop_risky_change.md
```

The local test does not call AWS. It imports the Lambda handler and prints the
same JSON response the cloud API would return.

## Deploy

Prereqs:

- AWS CLI configured with a profile that can create VPC, Lambda, API Gateway,
  S3, DynamoDB, IAM, and CloudWatch resources
- Terraform installed

```powershell
cd "C:\Users\davidgo2\Downloads\New`Project\terraform"
terraform init
terraform plan -out tfplan
terraform apply tfplan
```

Or use:

```powershell
.\scripts\deploy.ps1
```

The default region is `us-east-1`. Override it with:

```powershell
terraform plan -var "aws_region=us-east-2"
```

## Plan TGW/VPN Without Applying

There is also a reproducible plan-only demo for the hybrid path:

```powershell
cd "C:\Users\davidgo2\Downloads\New`Project\terraform"
terraform plan -var-file .\vpn.demo.tfvars -out hybrid-demo.tfplan
```

That file uses a documentation IP address so Terraform can show the TGW and
VPN resources in the plan. Do not apply it as-is. Replace
`customer_gateway_ip`, `bgp_asn`, and `remote_cidrs` with real branch values
before creating a live VPN.

## Enable Real TGW Site-to-Site VPN

By default, no TGW or VPN resources are created. To create a real hybrid
connectivity lab, copy the example variables file:

```powershell
cd "C:\Users\davidgo2\Downloads\New`Project\terraform"
Copy-Item .\terraform.tfvars.example .\terraform.tfvars
```

Edit `terraform.tfvars` and replace:

```hcl
customer_gateway_ip = "REPLACE_WITH_BRANCH_PUBLIC_IP"
```

with the public IP of your router, firewall, or SD-WAN edge.

When `vpn_sites` is non-empty, Terraform creates:

- Transit Gateway
- TGW route table
- App VPC attachment
- Customer Gateway
- Site-to-Site VPN connection
- TGW association and propagation
- VPC route-table routes toward remote branch CIDRs
- Static VPN/TGW routes when `static_routes_only = true`

More details:

```text
docs/tgw_vpn_lab.md
```

## Emulated Customer Gateway

For a realistic lab without a physical router, use the included emulated CGW
mode:

```powershell
cd "C:\Users\davidgo2\Downloads\New`Project\terraform"
terraform plan -var-file .\emulated-cgw.tfvars -out emulated-cgw.tfplan
terraform apply .\emulated-cgw.tfplan
```

This creates an EC2-based branch appliance with an Elastic IP, then uses that
Elastic IP as the AWS Customer Gateway. See:

```text
docs/emulated_customer_gateway.md
```

## Cisco Customer Gateway Variant

For a Cisco IOS XE version, use the optional C8000V/CSR1000V-style Customer
Gateway variant. It keeps the same AWS TGW and Site-to-Site VPN flow, but uses
BGP over the two AWS VPN tunnels instead of the Linux strongSwan static-route
example. It is disabled by default because it requires a subscribed Cisco
Marketplace AMI and higher hourly cost.

```text
docs/cisco_c8000v_customer_gateway.md
```

## Test The Deployed API

After `terraform apply`, copy the `api_endpoint` output and run:

```powershell
$api = "<api_endpoint>"
$body = @{
  tenant_id = "retail-co"
  artifact_name = "mop_risky_change.md"
  content = Get-Content "..\samples\mop_risky_change.md" -Raw
} | ConvertTo-Json -Depth 5

Invoke-RestMethod -Method Post -Uri "$api/analyze" -ContentType "application/json" -Body $body
```

## Cost Notes

Defaults are intentionally cost-aware:

- No NAT Gateway
- No Transit Gateway unless `enable_tgw_lab = true`
- No VPN unless `vpn_sites` is non-empty
- No VPC Flow Logs unless `enable_vpc_flow_logs = true`
- DynamoDB uses on-demand billing
- Lambda/API Gateway usage stays tiny for a demo

Destroy when done:

```powershell
cd "C:\Users\davidgo2\Downloads\New`Project\terraform"
terraform destroy
```

## CV Bullet

Built a Terraform-deployable AWS Advanced Networking lab with private VPC
subnets, S3/DynamoDB gateway endpoints, API Gateway, Lambda, CloudWatch logs,
metric filters, optional Transit Gateway and real Site-to-Site VPN connections,
plus a network change intelligence API for Cisco SD-WAN, MOP and hybrid cloud
artifact analysis.
