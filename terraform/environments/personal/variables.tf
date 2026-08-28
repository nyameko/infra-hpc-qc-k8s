variable "external_network_name" { type = string }
variable "external_network_id" { type = string }
variable "image_id" { type = string }
variable "key_pair_name" { type = string }
variable "edge_flavor" { type = string }
variable "control_plane_flavor" { type = string }
variable "worker_flavor" { type = string }
variable "bootstrap_ssh_cidr" { type = string }
variable "dns_nameservers" { type = list(string) default = ["1.1.1.1", "9.9.9.9"] }
variable "name_prefix" { type = string default = "nyameko-k8s" }
