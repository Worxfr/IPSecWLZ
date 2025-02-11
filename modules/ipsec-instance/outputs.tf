output "instance_id" {
  description = "ID of the created EC2 instance"
  value       = aws_instance.ipsec_bgp_instance.id
}

output "instance_private_ip" {
  description = "Private IP of the EC2 instance"
  value       = aws_instance.ipsec_bgp_instance.private_ip
}

output "instance_public_ip" {
  description = "Public IP (EIP) of the EC2 instance"
  value       = var.remote_public_ip
}

output "security_group_id" {
  description = "ID of the security group"
  value       = aws_security_group.ipsec_bgp_sg.id
}

output "is_wlz" {
  description = "Flag indicating if deployment is in WLZ"
  value       = var.is_wlz
}

output "main_eni" {
  description = "Map of secondary ENI details"
  value = aws_instance.ipsec_bgp_instance.primary_network_interface_id
}

output "secondary_enis" {
  description = "Map of secondary ENI details"
  value = {
    for idx, eni in aws_network_interface.secondary_eni : idx => {
      eni_id      = eni.id
      private_ip  = eni.private_ip
      vpc_id      = var.secondary_vpcs[idx].vpc_id
      subnet_id   = var.secondary_vpcs[idx].subnet_id
      description = var.secondary_vpcs[idx].description
    }
  }
}

