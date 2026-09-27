variable "openstack_cloud" { type = string }
variable "openstack_region" { type = string }
variable "external_network_name" { type = string }
variable "image_id" { type = string }
variable "ssh_key_name" { type = string }
variable "bootstrap_ssh_cidr" { type = string }

variable "mgmt_cidr" { type = string }
variable "k8s_cidr" { type = string }
variable "vpn_cidr" { type = string }
variable "mgmt_gateway_ip" { type = string }
variable "k8s_gateway_ip" { type = string }
variable "mgmt_pool_start" { type = string }
variable "mgmt_pool_end" { type = string }
variable "k8s_pool_start" { type = string }
variable "k8s_pool_end" { type = string }
variable "dns_nameservers" { type = list(string) }

variable "node_fixed_ips" {
  description = "Protected environment mapping from logical node key to fixed IP."
  type        = map(string)
}

variable "edge_flavor" { type = string }
variable "hermes_flavor" { type = string }
variable "slurm_controller_flavor" { type = string }
variable "login_flavor" { type = string }
variable "compute_12c_flavor" { type = string }
variable "compute_64c_flavor" {
  description = "OpenStack flavor for the large CPU Slurm compute class."
  type        = string
}
variable "k8s_control_plane_flavor" { type = string }
variable "k8s_worker_flavor" { type = string }

variable "api_lb_type" {
  description = "Implementation used for the Kubernetes API load balancer."
  type        = string
  validation {
    condition     = contains(["haproxy", "octavia"], var.api_lb_type)
    error_message = "api_lb_type must be either 'haproxy' or 'octavia'."
  }
}
variable "api_lb_name" { type = string }
variable "api_lb_address" { type = string }
variable "api_lb_image_id" { type = string }
variable "api_lb_flavor_id" { type = string }
variable "api_lb_user_data" {
  type    = string
  default = null
}
variable "kubernetes_api_port" {
  type    = number
  default = 6443
}


variable "jupyter_workers" {
  description = "Dedicated KubeSpawner workbench workers. Keep live names/IPs in private tfvars."
  type = map(object({
    name        = string
    fixed_ip    = string
    flavor_name = optional(string)
  }))
  default = {}
}
