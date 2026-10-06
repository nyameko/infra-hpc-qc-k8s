variable "name_prefix" {
  description = "Prefix for site resources."
  type        = string
}

variable "external_network_name" {
  description = "OpenStack external network used by the site router and edge floating IP."
  type        = string
}

variable "private_cidr" {
  description = "Private site subnet CIDR."
  type        = string
}

variable "private_gateway_ip" {
  description = "Private site subnet gateway address."
  type        = string
}

variable "private_pool_start" {
  type = string
}

variable "private_pool_end" {
  type = string
}

variable "dns_nameservers" {
  type    = list(string)
  default = []
}

variable "availability_zone" {
  type    = string
  default = "nova"
}

variable "edge_fixed_ip" {
  description = "Private address for the site edge."
  type        = string
}

variable "gpu_fixed_ip" {
  description = "Private address for the first inference GPU node."
  type        = string
}

variable "edge_floating_ip_address" {
  description = "Existing project floating IP to associate with the edge."
  type        = string
}

variable "edge_image_id" {
  type = string
}

variable "gpu_image_id" {
  type = string
}

variable "edge_flavor_name" {
  type = string
}

variable "gpu_flavor_name" {
  type = string
}

variable "key_pair" {
  type = string
}

variable "bootstrap_ssh_cidrs" {
  description = "Temporary/admin CIDRs allowed to SSH to the edge floating IP."
  type        = list(string)
}

variable "wireguard_ingress_cidrs" {
  description = "Public source CIDRs allowed to reach the site-to-site WireGuard endpoint."
  type        = list(string)
}

variable "remote_routed_cidrs" {
  description = "Remote private networks routed over wg-fabric. These are installed as Neutron routes via the edge."
  type        = list(string)
}

variable "wireguard_port" {
  type    = number
  default = 51821
}

variable "vllm_port" {
  type    = number
  default = 8000
}

variable "node_exporter_port" {
  type    = number
  default = 9100
}

variable "dcgm_exporter_port" {
  type    = number
  default = 9400
}

variable "gpu_root_volume_size_gb" {
  description = "Boot-from-volume root size for the GPU instance."
  type        = number
  default     = 50
}

variable "model_volume_size_gb" {
  description = "Dedicated Cinder volume for Hugging Face/vLLM model cache."
  type        = number
  default     = 120
}

variable "model_volume_type" {
  description = "Optional Cinder volume type for the model cache."
  type        = string
  default     = null
}

variable "edge_user_data" {
  type    = string
  default = null
}

variable "gpu_user_data" {
  type    = string
  default = null
}
