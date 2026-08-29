output "edge_floating_ip" { value = openstack_networking_floatingip_v2.edge.address }
output "k8s_api_vip" { value = module.octavia.vip_address }
output "node_ips" { value = module.compute.ips }
output "kubernetes_api_endpoint" {
  value = (
    var.api_lb_type == "haproxy"
    ? module.api_lb_haproxy[0].endpoint
    : module.api_lb_octavia[0].endpoint
  )
}
output "kubernetes_api_address" {
  value = (
    var.api_lb_type == "haproxy"
    ? module.api_lb_haproxy[0].address
    : module.api_lb_octavia[0].address
  )
}

output "kubernetes_api_port" {
  value = (
    var.api_lb_type == "haproxy"
    ? module.api_lb_haproxy[0].port
    : module.api_lb_octavia[0].port
  )
}
