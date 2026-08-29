output "edge_floating_ip" { value = openstack_networking_floatingip_v2.edge.address }
output "k8s_api_vip" { value = module.api_lb.vip_address }
output "node_ips" { value = module.compute.ips }
