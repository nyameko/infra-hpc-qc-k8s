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
