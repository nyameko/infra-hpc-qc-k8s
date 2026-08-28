variable "name" { type = string }
variable "vip_subnet_id" { type = string }
variable "vip_address" { type = string }
variable "control_plane_ips" { type = map(string) }
