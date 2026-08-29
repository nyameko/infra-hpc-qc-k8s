variable "name" {
  description = "Name of the OpenStack load balancer."
  type        = string
}

variable "vip_subnet_id" {
  description = "Subnet in which the Octavia VIP should be created."
  type        = string
}

variable "vip_address" {
  description = "Private Kubernetes API VIP."
  type        = string
}

variable "backend_addresses" {
  description = "Kubernetes control-plane backend addresses."
  type        = list(string)
}

variable "listener_port" {
  description = "Kubernetes API listener port."
  type        = number
  default     = 6443
}

variable "backend_port" {
  description = "Kubernetes API backend port."
  type        = number
  default     = 6443
}

variable "lb_method" {
  description = "Octavia pool load-balancing method."
  type        = string
  default     = "ROUND_ROBIN"
}

variable "monitor_delay" {
  description = "Health monitor interval."
  type        = number
  default     = 10
}

variable "monitor_timeout" {
  description = "Health monitor timeout."
  type        = number
  default     = 5
}

variable "monitor_max_retries" {
  description = "Maximum health monitor retries."
  type        = number
  default     = 3
}
