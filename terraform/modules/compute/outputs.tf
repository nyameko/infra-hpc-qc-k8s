output "edge_admin_ip" { value = var.edge_ip }
output "edge_admin_floating_ip" { value = openstack_networking_floatingip_v2.edge.address }
output "control_plane_ips" { value = { for k, v in local.control_planes : k => v } }
output "worker_ips" { value = { for k, v in local.workers : k => v } }
