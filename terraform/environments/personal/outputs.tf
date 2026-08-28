output "edge_admin_floating_ip" { value = module.compute.edge_admin_floating_ip }
output "edge_admin_private_ip" { value = module.compute.edge_admin_ip }
output "k8s_api_vip" { value = module.octavia.vip_address }
output "control_plane_ips" { value = module.compute.control_plane_ips }
output "worker_ips" { value = module.compute.worker_ips }
output "mgmt_network_id" { value = module.network.mgmt_network_id }
output "k8s_network_id" { value = module.network.k8s_network_id }
