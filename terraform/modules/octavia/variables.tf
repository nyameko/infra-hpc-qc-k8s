variable "name_prefix" { type = string }
variable "k8s_subnet_id" { type = string }
variable "control_plane_ips" { type = map(string) }

variable "vip_address" { type = string }
