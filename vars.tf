variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
}

# Variable for Wavelength Zone
variable "availabilityzone_wavelength" {
  description = "Availability Zone ID for Wavelength Zone"
  type        = string
}

# Variable for network_border_group
variable "network_border_group" {
  description = "network_border_group for Wavelength Zone (without the last letter in some case)"
  type        = string
}

# Key pair name variable - for EC2 instance SSH access
variable "key_pair_name" {
  description = "The name of the EC2 key pair to use"
  type        = string
  default     = "EC2-key-pair"
}

# BGP ASN variable - for BGP routing configuration
variable "bgp_asn_remote" {
  description = "BGP Autonomous System Number"
  type        = number
  default     = 65001
}

# BGP ASN variable - for BGP routing configuration
variable "bgp_asn_local" {
  description = "BGP Autonomous System Number"
  type        = number
  default     = 65001
}

# Peer IP variable - for IPSec tunnel configuration
variable "peer_ip" {
  description = "Peer IP"
  type        = string
  default     = "1.1.1.1"
}

# Peer PreSharedKey - for IPSec tunnel configuration
variable "ipsec_psk" {
  description = "IPSEC PSK"
  type        = string
  default     = "1234567890"
}

# Peer IP variable - for IPSec tunnel configuration
variable "remote_subnet" {
  description = "RemoteSubnet"
  type        = string
  default     = "10.1.0.0/24"
}

# Private IP 1 variable - for IPSec tunnel configuration
variable "private_ip_1" {
  description = "Private IP 1"
  type        = string
  default     = "172.16.0.1"
}

# Private IP 2 variable - for IPSec tunnel configuration
variable "private_ip_2" {
  description = "Private IP 2" 
  type        = string
  default     = "172.16.0.2"
}