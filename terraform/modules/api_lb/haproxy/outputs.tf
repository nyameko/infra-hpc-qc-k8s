output "address" {
  description = "Kubernetes API load-balancer address."
  value       = var.vip_address
}

output "port" {
  description = "Kubernetes API load-balancer listener port."
  value       = var.listener_port
}

output "endpoint" {
  description = "Kubernetes API load-balancer endpoint."
  value       = "${var.vip_address}:${var.listener_port}"
}

output "instance_id" {
  description = "HAProxy VM ID."
  value       = openstack_compute_instance_v2.api_lb.id
}

output "port_id" {
  description = "Neutron port ID."
  value       = openstack_networking_port_v2.api_lb.id
}
