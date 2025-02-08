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
  value       = local.remote_ip
}

output "security_group_id" {
  description = "ID of the security group"
  value       = aws_security_group.ipsec_bgp_sg.id
}

output "is_wlz" {
  description = "Flag indicating if deployment is in WLZ"
  value       = var.is_wlz
}
