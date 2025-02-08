
output "region_vpc_id" {
  description = "ID of the Region VPC"
  value       = aws_vpc.region_vpc.id
}

output "region_subnet_id" {
  description = "ID of the Region subnet"
  value       = aws_subnet.region_subnet.id
}


output "region_instance_id" {
  description = "ID of the EC2 instance"
  value       = module.ipsec-region.instance_id
}

output "region_instance_private_ip" {
  description = "Private IP of the region EC2 instance"
  value       = module.ipsec-region.instance_private_ip
}

output "region_instance_public_ip" {
  description = "Public IP (EIP) of the region EC2 instance"
  value       = module.ipsec-region.instance_public_ip
}


output "wavelength_vpc_id" {
  description = "ID of the Wavelength VPC"
  value       = aws_vpc.wavelength_vpc.id
}

output "wavelength_subnet_id" {
  description = "ID of the Wavelength subnet"
  value       = aws_subnet.wavelength_subnet.id
}

output "wavelength_instance_id" {
  description = "ID of the wavelength EC2 instance"
  value       = module.ipsec-wlz.instance_id
}

output "wavelength_instance_private_ip" {
  description = "Private IP of the wavelength EC2 instance"
  value       = module.ipsec-wlz.instance_private_ip
}

output "wavelength_instance_public_ip" {
  description = "Public IP (EIP) of the wavelength EC2 instance"
  value       = module.ipsec-wlz.instance_public_ip
}

output "region_instance_is_wlz" {
  description = "Whether the region EC2 instance is in Wavelength Zone"
  value       = module.ipsec-region.is_wlz
}

output "wavelength_instance_is_wlz" {
  description = "Whether the wavelength EC2 instance is in Wavelength Zone" 
  value       = module.ipsec-wlz.is_wlz
}

output "secondary_eni_details" {
  value = module.ipsec-wlz.secondary_enis
}
