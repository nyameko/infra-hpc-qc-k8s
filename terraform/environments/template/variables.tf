variable "openstack_cloud" { type = string }
variable "openstack_region" { type = string }
variable "external_network_name" { type = string }
#variable "external_name_id" { type = string }
variable "image_id" { type = string }
variable "ssh_key_name" { type = string }
variable "bootstrap_ssh_cidr" { type = string }
variable "edge_flavor" { type = string }
variable "hermes_flavor" { type = string }
variable "slurm_controller_flavor" { type = string }
variable "login_flavor" { type = string }
variable "compute_12c_flavor" { type = string }
variable "compute_64c_flavor" {
  description = "OpenStack flavor for 64-vCPU / 256-GiB Slurm compute nodes (C64.xlarge in the reference cloud)."
  type        = string
}
variable "k8s_control_plane_flavor" { type = string }
variable "k8s_worker_flavor" { type = string }
variable "api_lb_type" {
  description = "Implementation used for the Kubernetes API load balancer."
  type        = string

  validation {
    condition = contains(
      ["haproxy", "octavia"],
      var.api_lb_type
    )

    error_message = "api_lb_type must be either 'haproxy' or 'octavia'."
  }
}


# Network topology is environment-private. The public template intentionally
# declares variables without production defaults.
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

variable "edge_fixed_ip" { type = string }
variable "agent_oob_fixed_ip" { type = string }
variable "slurm_controller_fixed_ip" { type = string }
variable "slurm_login_1_fixed_ip" { type = string }
variable "slurm_login_2_fixed_ip" { type = string }
variable "slurm_compute_1_fixed_ip" { type = string }
variable "slurm_compute_2_fixed_ip" { type = string }
variable "slurm_compute_3_fixed_ip" { type = string }
variable "slurm_compute_4_fixed_ip" { type = string }
variable "storage_fixed_ip" { type = string }
variable "k8s_cp_1_fixed_ip" { type = string }
variable "k8s_cp_2_fixed_ip" { type = string }
variable "k8s_cp_3_fixed_ip" { type = string }
variable "k8s_worker_1_fixed_ip" { type = string }
variable "k8s_worker_2_fixed_ip" { type = string }
variable "k8s_worker_3_fixed_ip" { type = string }
