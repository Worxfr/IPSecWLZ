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

variable "elastic_ip" {
  description = "Elastic IP address for the VPN instance"
  type        = string
}

variable "remote_public_ip" {
  description = "IPSEC public IP address for the remote endpoint"
  type        = string
}

variable "remote_private_ip" {
  description = "IPSEC Private IP address for the remote endpoint in the IPSEC tunnel"
  type        = string
}

variable "local_private_ip" {
  description = "IPSEC Private IP address for the local endpoint in the IPSEC tunnel" 
  type        = string
}

variable "is_wlz" {
  description = "Boolean flag to indicate if this is a WaveLength Zone deployment"
  type        = bool
  default     = false
}

variable "is_remote_in_region" {
  description = "Boolean flag to indicate if the remote device is in the AWS Region"
  type        = bool
  default     = false
}

variable "secondary_vpcs" {
  description = "List of secondary VPCs configurations for cross-VPC ENIs"
  type = list(object({
    vpc_id              = string
    subnet_id           = string
    description         = optional(string, "Cross-VPC ENI")
    security_group_rules = optional(list(object({
      from_port   = number
      to_port     = number
      protocol    = string
      cidr_blocks = list(string)
    })), [])
  }))
  default = []
}

variable "mark" {
  description = "Integer value for mark"
  type        = number
} 


variable "bgp_password" {
  description = "Password for BGP authentication"
  type        = string
  sensitive   = true
}

