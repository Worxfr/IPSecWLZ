

output "wavelength_vpc_id" {
  description = "ID of the Wavelength VPC"
  value       = aws_vpc.wavelength_vpc.id
}

output "wavelength_subnet_id" {
  description = "ID of the Wavelength subnet"
  value       = aws_subnet.wavelength_subnet.id
}

output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.ipsec_bgp_instance.id
}

output "instance_private_ip" {
  description = "Private IP of the EC2 instance"
  value       = aws_instance.ipsec_bgp_instance.private_ip
}

output "instance_public_ip" {
  description = "Public IP (EIP) of the EC2 instance"
  value       = aws_eip.wavelength_ip.carrier_ip
}

output "carrier_gateway_id" {
  description = "ID of the Carrier Gateway"
  value       = aws_ec2_carrier_gateway.wavelength_cgw.id
}