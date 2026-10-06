variable "openstack_cloud" { type = string }
variable "openstack_region" { type = string }

variable "external_network_name" { type = string }
variable "private_cidr" { type = string }
variable "private_gateway_ip" { type = string }
variable "private_pool_start" { type = string }
variable "private_pool_end" { type = string }
variable "dns_nameservers" { type = list(string) }

variable "edge_fixed_ip" { type = string }
variable "gpu_fixed_ip" { type = string }
variable "edge_floating_ip_address" { type = string }

variable "edge_image_id" { type = string }
variable "gpu_image_id" { type = string }
variable "edge_flavor_name" { type = string }
variable "gpu_flavor_name" { type = string }
variable "key_pair" { type = string }

variable "bootstrap_ssh_cidrs" { type = list(string) }
variable "wireguard_ingress_cidrs" { type = list(string) }
variable "remote_routed_cidrs" { type = list(string) }

variable "wireguard_port" {
  type    = number
  default = 51821
}

variable "model_volume_size_gb" {
  type    = number
  default = 120
}

variable "model_volume_type" {
  type    = string
  default = null
}
