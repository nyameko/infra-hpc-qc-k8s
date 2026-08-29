variable "name" {
  description = "Name of the API load-balancer VM."
  type        = string
}

variable "network_id" {
  description = "Neutron network ID for the API LB."
  type        = string
}

variable "subnet_id" {
  description = "Neutron subnet ID for the API LB."
  type        = string
}

variable "vip_address" {
  description = "Private address presented as the Kubernetes API endpoint."
  type        = string
}

variable "security_group_ids" {
  description = "Security groups attached to the API LB port."
  type        = list(string)
}

variable "image_id" {
  description = "Image ID for the HAProxy VM."
  type        = string
}

variable "flavor_id" {
  description = "Flavor ID for the HAProxy VM."
  type        = string
}

variable "key_pair" {
  description = "OpenStack keypair name."
  type        = string
}

variable "backend_addresses" {
  description = "Kubernetes control-plane backend IP addresses."
  type        = list(string)
}

variable "backend_port" {
  description = "Kubernetes API backend port."
  type        = number
  default     = 6443
}

variable "listener_port" {
  description = "Port exposed by the API LB."
  type        = number
  default     = 6443
}

variable "user_data" {
  description = "Cloud-init bootstrap data for the HAProxy VM."
  type        = string
  default     = null
}
