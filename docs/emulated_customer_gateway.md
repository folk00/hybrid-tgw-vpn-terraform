# Emulated Customer Gateway Lab

This mode creates a realistic AWS hybrid networking lab without needing a
physical router or a home public IP.

Terraform creates:

- Transit Gateway
- App VPC attachment
- Site-to-Site VPN attachment
- Customer Gateway
- An Ubuntu EC2 instance with Elastic IP acting as the branch router
- strongSwan IPsec configuration generated from the AWS VPN tunnel attributes
- A dummy branch LAN interface, default `172.16.10.1/24`

The EC2 instance pulls the generated VPN config from SSM Parameter Store during
boot. The parameter is `SecureString`, but remember Terraform state still stores
generated values locally for this lab.

## Plan

```powershell
cd .\terraform
terraform plan -var-file .\emulated-cgw.tfvars -out emulated-cgw.tfplan
```

## Apply

```powershell
terraform apply .\emulated-cgw.tfplan
```

## Check The Appliance

After apply, get the instance id:

```powershell
terraform output emulated_customer_gateway
```

Then use SSM Run Command or Session Manager. Useful commands:

```bash
sudo tail -n 100 /var/log/hybridnet-cgw-bootstrap.log
sudo ipsec statusall
sudo ip addr show branch0
sudo cat /opt/hybridnet/ipsec-status.txt
```

## Destroy

```powershell
terraform destroy -var-file .\emulated-cgw.tfvars
```
