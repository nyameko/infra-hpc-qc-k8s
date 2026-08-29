variable "name" { type = string }
variable "network_id" { type = string }
variable "subnet_id" { type = string }
variable "vip_address" { type = string }
variable "security_group_ids" { type = list(string) }
variable "image_id" { type = string }
variable "flavor_name" { type = string }
variable "key_pair" { type = string }
variable "backend_addresses" { type = list(string) }
variable "backend_port" {
  type    = number
  default = 6443
}
variable "listener_port" {
  type    = number
  default = 6443
}

variable "user_data" {
  description = "Cloud-init bootstrap data for the HAProxy VM."
  type        = string
  default     = null
}
