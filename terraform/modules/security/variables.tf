variable "name_prefix" { type = string }
variable "bootstrap_ssh_cidr" { type = string }
variable "vpn_cidr" { type = string }
variable "mgmt_cidr" { type = string }
variable "k8s_cidr" { type = string }
variable "api_lb_address" { type = string }

variable "fabric_wireguard_port" {
  description = "UDP port for the infrastructure federation WireGuard interface."
  type        = number
  default     = 51821
}

variable "fabric_wireguard_ingress_cidrs" {
  description = "Public source CIDRs allowed to reach the infrastructure WireGuard endpoint."
  type        = list(string)
  default     = []
}

variable "federated_site_cidrs" {
  description = "Remote private site CIDRs allowed to reach central host services such as Wazuh."
  type        = list(string)
  default     = []
}
