# Cost Estimate

Region used by the lab: `us-east-1`.

## Current Emulated CGW Lab

Approximate hourly cost with light/no traffic:

| Item | Qty | Approx hourly |
| --- | ---: | ---: |
| AWS Site-to-Site VPN connection | 1 | $0.05 |
| Transit Gateway attachments: app VPC + VPN | 2 | $0.10 |
| EC2 Ubuntu t3.micro router appliance | 1 | $0.0104 |
| Public IPv4: appliance EIP + two AWS VPN tunnel endpoints | 3 | $0.015 |
| API Gateway/Lambda/S3/DynamoDB/CloudWatch low usage | small | usually pennies |

Estimated subtotal before data transfer and taxes: about `$0.1754/hour`.

Useful rough numbers:

- 4 hours: about `$0.70`
- 8 hours: about `$1.40`
- 24 hours: about `$4.21`
- 30 days always on: about `$126`

Traffic through Transit Gateway can add data processing charges. Internet data
transfer out can also add cost.

## Cisco C8000V PAYG Note

Cisco Catalyst 8000V PAYG is much more expensive for a lab. The AWS Marketplace
listing for DNA Essentials shows software usage starting around `$2.13/hour`
for `c5.large`, before EC2 compute, TGW, VPN, IPv4, storage, and data transfer.
That makes it useful for a Cisco-specific demo, but not for the first low-cost
reference lab.

## Stop Cost

Destroy the lab when finished:

```powershell
cd "C:\Users\davidgo2\Downloads\New`Project\terraform"
terraform destroy -var-file .\emulated-cgw.tfvars
```

Important resources to confirm gone: `vpn-03b5f780fe72ee12a`,
`tgw-010787c106f32f71c`, `i-0459c78a89215be27`, and the Elastic IP
`54.85.251.230`.
