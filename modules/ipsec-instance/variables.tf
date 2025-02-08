variable "vpc_id" {
  description = "ID of the VPC where the instance will be created"
  type        = string
}

variable "subnet_id" {
  description = "ID of the subnet where the instance will be created"
  type        = string
}

variable "key_pair_name" {
  description = "Name of the SSH key pair"
  type        = string
}

variable "peer_ip" {
  description = "IP address of the IPSec peer"
  type        = string
}

variable "ipsec_psk" {
  description = "Pre-shared key for IPSec"
  type        = string
  sensitive   = true
}

variable "bgp_asn_local" {
  description = "Local BGP ASN number"
  type        = string
}

variable "bgp_asn_remote" {
  description = "Remote BGP ASN number"
  type        = string
}

variable "remote_subnet" {
  description = "Remote subnet CIDR"
  type        = string
}

variable "network_border_group" {
  description = "Network border group for the EIP"
  type        = string
}
