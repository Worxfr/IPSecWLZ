
> [!CAUTION]
> Project in progress

> [!WARNING]  
> ## ⚠️ Important Disclaimer
>
> **This project is for testing and demonstration purposes only.**
>
>Please be aware of the following:
>
>- The infrastructure deployed by this project is not intended for production use.
>- Security measures may not be comprehensive or up to date.
>- Performance and reliability have not been thoroughly tested at scale.
>- The project may not comply with all best practices or organizational standards.
>
>Before using any part of this project in a production environment:
>
>1. Thoroughly review and understand all code and configurations.
>2. Conduct a comprehensive security audit.
>3. Test extensively in a safe, isolated environment.
>4. Adapt and modify the code to meet your specific requirements and security standards.
>5. Ensure compliance with your organization's policies and any relevant regulations.
>
>The maintainers of this project are not responsible for any issues that may arise from the use of this code in production environments.

---

# IPSec BGP Terraform Module

This Terraform module sets up an EC2 instance configured for IPSec tunneling and BGP routing, designed for creating secure, high-performance network connections between AWS and external networks.

## Features

- Deploys an EC2 instance with the latest Ubuntu 22.04 AMI
- Configures IPSec tunneling using StrongSwan
- Sets up BGP routing with FRR (Free Range Routing)
- Supports multiple VPCs with secondary ENIs
- Implements AWS Systems Manager Session Manager for secure instance access
- Configures necessary security groups and IAM roles

## Prerequisites

- Terraform v0.14+
- AWS CLI configured with appropriate permissions
- A VPC and subnet in your AWS account
- An Elastic IP allocated for the VPN instance

## Usage

```hcl
module "ipsec_bgp" {
  source = "path/to/module"

  vpc_id         = "vpc-xxxxxxxx"
  subnet_id      = "subnet-xxxxxxxx"
  key_pair_name  = "your-key-pair"
  ipsec_psk      = "your-pre-shared-key"
  bgp_asn_local  = "65000"
  bgp_asn_remote = "65001"
  elastic_ip     = "eipalloc-xxxxxxxx"
  remote_public_ip  = "203.0.113.1"
  remote_private_ip = "10.0.0.1"
  local_private_ip  = "10.0.0.2"

  secondary_vpcs = [
    {
      vpc_id    = "vpc-yyyyyyyy"
      subnet_id = "subnet-yyyyyyyy"
    }
  ]
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| vpc_id | ID of the VPC where the instance will be created | `string` | n/a | yes |
| subnet_id | ID of the subnet where the instance will be created | `string` | n/a | yes |
| key_pair_name | Name of the SSH key pair | `string` | n/a | yes |
| ipsec_psk | Pre-shared key for IPSec | `string` | n/a | yes |
| bgp_asn_local | Local BGP ASN number | `string` | n/a | yes |
| bgp_asn_remote | Remote BGP ASN number | `string` | n/a | yes |
| elastic_ip | Elastic IP address for the VPN instance | `string` | n/a | yes |
| remote_public_ip | IPSEC public IP address for the remote endpoint | `string` | n/a | yes |
| remote_private_ip | IPSEC Private IP address for the remote endpoint in the IPSEC tunnel | `string` | n/a | yes |
| local_private_ip | IPSEC Private IP address for the local endpoint in the IPSEC tunnel | `string` | n/a | yes |
| is_wlz | Boolean flag to indicate if this is a WaveLength Zone deployment | `bool` | `false` | no |
| secondary_vpcs | List of secondary VPCs configurations for cross-VPC ENIs | `list(object)` | `[]` | no |

## Outputs

Certainly! I'll add an "Outputs" section to the README file to include the output information you've provided. Here's how the updated README would look with the new Outputs section:

# IPSec BGP Terraform Module

## Outputs

| Name | Description |
|------|-------------|
| instance_id | ID of the created EC2 instance |
| instance_private_ip | Private IP of the EC2 instance |
| instance_public_ip | Public IP (EIP) of the EC2 instance |
| security_group_id | ID of the security group |
| is_wlz | Flag indicating if deployment is in WLZ |
| secondary_enis | Map of secondary ENI details |

### secondary_enis Output Structure

The `secondary_enis` output provides a map with the following structure for each secondary ENI:

```hcl
{
  eni_id      = <ENI ID>
  private_ip  = <Private IP of the ENI>
  vpc_id      = <VPC ID where the ENI is located>
  subnet_id   = <Subnet ID where the ENI is located>
  description = <Description of the ENI>
}
```

## Usage Example with Outputs

```hcl
module "ipsec_bgp" {
  source = "path/to/module"
  
  # ... [input variables] ...
}

output "instance_id" {
  value = module.ipsec_bgp.instance_id
}

output "instance_private_ip" {
  value = module.ipsec_bgp.instance_private_ip
}

output "secondary_enis" {
  value = module.ipsec_bgp.secondary_enis
}
```



## Security Considerations

- The module uses a pre-shared key for IPSec authentication. Ensure this key is stored securely and rotated regularly.
- The security group allows inbound traffic on UDP ports 500 and 4500 from any source (0.0.0.0/0). Consider restricting this to known IP ranges if possible.
- Ensure that the IAM role permissions are reviewed and follow the principle of least privilege.

## Limitations

- The module currently supports up to 3 secondary VPCs due to ENI limits on t3.medium instances.
- The BGP configuration does not include authentication. Consider implementing MD5 authentication for production use.

## Contributing

Contributions to improve the module are welcome. Please follow the standard fork, branch, and pull request workflow.

## License

Specify your license here.

