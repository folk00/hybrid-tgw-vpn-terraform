# Hybrid TGW + Site-to-Site VPN (Terraform)

[![CI](https://github.com/folk00/hybrid-tgw-vpn-terraform/actions/workflows/ci.yml/badge.svg)](https://github.com/folk00/hybrid-tgw-vpn-terraform/actions/workflows/ci.yml)

Terraform-deployable AWS Advanced Networking lab demonstrating **hybrid connectivity** between an AWS VPC and an on-prem/branch site over **Transit Gateway + Site-to-Site VPN**, with **two interchangeable Customer Gateway implementations**:

- **Linux EC2 + strongSwan + FRR** — low-cost emulated CGW for validation
- **Cisco c8000v (IOS XE)** — production-grade CGW with BGP over both tunnels

> Public lab/demo. No production data, credentials, or customer-specific logic. All sample IPs are RFC 5737 / RFC 1918.

---

## Why this exists

Most AWS networking demos stop at "click here to create a VPN." This lab shows the **full hybrid path** the way a network engineer actually has to think about it: who terminates the tunnels, how routes are exchanged, what the failure modes look like, and how to validate cost-aware before going live.

The Terraform maps 1:1 to AWS Advanced Networking reference architectures (TGW, S2S VPN, BGP/static, VPC endpoints, route tables, monitoring). See [`docs/aws_networking_mapping.md`](docs/aws_networking_mapping.md) for the detailed service mapping.

## Architecture

```text
                                  AWS region (us-east-1)
   ┌──────────────────────────────────────────────────────────────────┐
   │                                                                  │
   │   ┌─────────────────────┐         ┌───────────────────────────┐  │
   │   │     App VPC         │         │     Transit Gateway       │  │
   │   │  10.0.0.0/16        │ ──attach│   route table + assoc     │  │
   │   │                     │         └───────────┬───────────────┘  │
   │   │  private subnets    │                     │                  │
   │   │  ┌───────────────┐  │                     │                  │
   │   │  │ Lambda        │  │         ┌───────────▼───────────────┐  │
   │   │  │ (analyzer)    │  │         │   Site-to-Site VPN        │  │
   │   │  └───────────────┘  │         │   2 tunnels, IPSec/IKEv2  │  │
   │   │                     │         └───────────┬───────────────┘  │
   │   │  S3 GW endpoint     │                     │                  │
   │   │  DDB GW endpoint    │                     │                  │
   │   └─────────────────────┘                     │                  │
   │                                               │                  │
   └───────────────────────────────────────────────┼──────────────────┘
                                                   │
                          ┌────────────────────────┴────────────────────────┐
                          │                                                 │
                          │  Two interchangeable Customer Gateways          │
                          │                                                 │
       ┌──────────────────▼────────────────────┐   ┌────────────────────────▼──────────────────┐
       │  Path A: Emulated CGW (low-cost)      │   │  Path B: Cisco CGW (production-grade)     │
       │                                       │   │                                           │
       │  Linux EC2 t3.micro + EIP             │   │  Cisco c8000v IOS XE + EIP                │
       │  ├─ strongSwan (IPSec/IKEv2)          │   │  ├─ crypto ikev2 + ipsec profile          │
       │  ├─ FRR (BGP optional)                │   │  ├─ BGP over Tunnel1 + Tunnel2            │
       │  ├─ Day-0 user_data bootstrap         │   │  ├─ Day-0 IOS config via tftpl            │
       │  └─ Branch CIDR 172.16.10.0/24        │   │  └─ Marketplace AMI (subscription)        │
       │                                       │   │                                           │
       │  ~$8/mo idle, no licenses             │   │  ~hourly Cisco license + EC2              │
       └───────────────────────────────────────┘   └───────────────────────────────────────────┘
```

**Key design choices:**
- **No NAT Gateway** by default — Lambda reaches S3/DDB via **Gateway VPC Endpoints**.
- **TGW** instead of plain VPN-to-VGW — scales to multi-VPC and Direct Connect later.
- **Both CGW paths reuse the same TGW/VPN module** — swap by flipping a variable, no duplicate infra.
- **Cost-gated**: TGW, VPN, c8000v all disabled by default. Plan-only mode lets you read the resource graph before paying.

## Repo layout

```
hybrid-tgw-vpn-terraform/
├── terraform/
│   ├── main.tf                              # VPC, endpoints, Lambda, API GW, S3, DDB
│   ├── variables.tf
│   ├── outputs.tf
│   ├── versions.tf
│   ├── emulated_cgw.tf                      # Path A: Linux + strongSwan EC2 CGW
│   ├── cisco_cgw.tf                         # Path B: Cisco c8000v CGW
│   ├── templates/
│   │   ├── emulated_cgw_bootstrap.sh.tftpl  # strongSwan + FRR install + cfg
│   │   ├── emulated_cgw_config.sh.tftpl     # tunnel/BGP runtime config
│   │   └── cisco_cgw_day0_config.tftpl      # IOS XE Day-0 config
│   ├── terraform.tfvars.example             # safe template, no secrets
│   ├── cisco-cgw.tfvars.example             # safe template for Cisco path
│   └── *.tfvars                             # gitignored — real values live here
├── app/
│   └── lambda_function.py                   # Network Change Intelligence analyzer
├── scripts/
│   ├── deploy.ps1 / destroy.ps1             # Terraform wrappers
│   ├── local_invoke.py                      # test Lambda without AWS
│   └── serve_local.py                       # local HTTP front for the analyzer
├── samples/
│   ├── iosxe_sdwan_edge.txt                 # Cisco IOS XE sample
│   ├── aws_tgw_plan.md                      # AWS hybrid sample
│   └── mop_risky_change.md                  # MOP/risk sample
└── docs/
    ├── architecture.md
│   ├── aws_networking_mapping.md            # AWS networking domain ↔ resource map
    ├── tgw_vpn_lab.md
    ├── emulated_customer_gateway.md         # Linux strongSwan deep-dive
    ├── cisco_c8000v_customer_gateway.md     # c8000v deep-dive
    └── cost_estimate.md
```

## Quick start

### 1. Plan only (no AWS spend)

```powershell
cd terraform
terraform init
terraform plan -var-file .\vpn.demo.tfvars -out hybrid-demo.tfplan
```

Reads as if you were deploying. Uses RFC 5737 docs IP — safe to plan, not safe to apply.

### 2. Path A — Emulated CGW (Linux + strongSwan)

```powershell
cd terraform
terraform plan -var-file .\emulated-cgw.tfvars -out emulated-cgw.tfplan
terraform apply .\emulated-cgw.tfplan
```

Brings up an EC2 t3.micro, installs strongSwan + FRR via `user_data`, EIPs it, and registers that EIP as the AWS Customer Gateway. Two AWS VPN tunnels come up against the Linux box. Full deep-dive in [`docs/emulated_customer_gateway.md`](docs/emulated_customer_gateway.md).

### 3. Path B — Cisco c8000v CGW

```powershell
cd terraform
Copy-Item .\cisco-cgw.tfvars.example .\cisco-cgw.tfvars
# edit cisco-cgw.tfvars: set admin password, AMI, source IP
terraform plan -var-file .\cisco-cgw.tfvars -out cisco-cgw.tfplan
terraform apply .\cisco-cgw.tfplan
```

Requires Cisco Marketplace subscription for the c8000v AMI. BGP runs over both tunnels. Deep-dive in [`docs/cisco_c8000v_customer_gateway.md`](docs/cisco_c8000v_customer_gateway.md).

### 4. Tear down

```powershell
cd terraform
terraform destroy
```

## What gets deployed by default (cost-aware)

| Component                  | Default | Toggle                                |
|----------------------------|---------|---------------------------------------|
| App VPC + subnets          | ✅ on   | always                                |
| S3 / DynamoDB GW endpoints | ✅ on   | always                                |
| Lambda + API Gateway       | ✅ on   | always                                |
| CloudWatch log group       | ✅ on   | always                                |
| **NAT Gateway**            | ❌ off  | not used — endpoints replace it       |
| **Transit Gateway**        | ❌ off  | `enable_tgw_lab = true`               |
| **Site-to-Site VPN**       | ❌ off  | populate `vpn_sites = {...}`          |
| **Emulated CGW (Linux)**   | ❌ off  | `enable_emulated_customer_gateway`    |
| **Cisco c8000v CGW**       | ❌ off  | `enable_cisco_customer_gateway`       |
| VPC Flow Logs              | ❌ off  | `enable_vpc_flow_logs = true`         |

## Tech stack

- **IaC:** Terraform (AWS provider)
- **Cloud:** AWS VPC, TGW, Site-to-Site VPN, Customer Gateway, EC2, EIP, S3, DynamoDB, Lambda, API Gateway, CloudWatch, IAM
- **Network OS:** Linux (strongSwan + FRR), Cisco IOS XE (c8000v)
- **App:** Python 3.11 Lambda (network artifact analyzer)
- **Local tooling:** PowerShell deploy/destroy scripts, local invoke without AWS

## AWS service mapping

| Domain                                       | Where in this repo                                 |
|----------------------------------------------|----------------------------------------------------|
| Hybrid connectivity (S2S VPN, TGW)           | `terraform/main.tf`, `emulated_cgw.tf`, `cisco_cgw.tf` |
| BGP vs static-route VPN                      | `vpn_sites.*.static_routes_only`, `bgp_asn`        |
| VPC design + endpoints                       | `main.tf` (S3/DDB gateway endpoints, no NAT)       |
| Monitoring & logging                         | CloudWatch log group, metric filter, optional Flow Logs |
| Cost optimization                            | Default-off TGW/VPN, endpoint-only egress          |
| Security                                     | IAM least-privilege, encrypted S3, public-access block |

Full map in [`docs/aws_networking_mapping.md`](docs/aws_networking_mapping.md).

## License

MIT — see [LICENSE](LICENSE).
