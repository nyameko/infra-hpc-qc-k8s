variable "name_prefix" { type = string }
variable "k8s_cidr" { type = string }
variable "bootstrap_ssh_cidr" { type = string }
variable "internal_cidrs" { type = list(string) }
