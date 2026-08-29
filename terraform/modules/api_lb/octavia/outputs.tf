output "address" {
  description = "Kubernetes API load-balancer address."
  value       = openstack_lb_loadbalancer_v2.api.vip_address
}

output "port" {
  description = "Kubernetes API listener port."
  value       = var.listener_port
}

output "endpoint" {
  description = "Kubernetes API load-balancer endpoint."
  value       = "${openstack_lb_loadbalancer_v2.api.vip_address}:${var.listener_port}"
}

output "loadbalancer_id" {
  description = "Octavia load-balancer ID."
  value       = openstack_lb_loadbalancer_v2.api.id
}
