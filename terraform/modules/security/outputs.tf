output "edge_sg_id" { value = openstack_networking_secgroup_v2.edge.id }
output "control_plane_sg_id" { value = openstack_networking_secgroup_v2.control_plane.id }
output "worker_sg_id" { value = openstack_networking_secgroup_v2.worker.id }
