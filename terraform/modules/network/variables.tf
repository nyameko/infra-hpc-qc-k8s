variable "name_prefix" { type = string }
variable "external_network_id" { type = string }
variable "mgmt_cidr" { type = string }
variable "mgmt_pool_start" { type = string }
variable "mgmt_pool_end" { type = string }
variable "k8s_cidr" { type = string }
variable "k8s_pool_start" { type = string }
variable "k8s_pool_end" { type = string }
variable "dns_nameservers" { type = list(string) }
variable "create_wireguard_route" { type = bool default = true }
variable "wireguard_cidr" { type = string default = "10.60.0.0/24" }
variable "edge_admin_ip" { type = string default = "10.50.0.10" }
