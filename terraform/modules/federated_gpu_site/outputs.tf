output "private_network_id" {
  value = openstack_networking_network_v2.private.id
}

output "private_subnet_id" {
  value = openstack_networking_subnet_v2.private.id
}

output "router_id" {
  value = openstack_networking_router_v2.site.id
}

output "edge_instance_id" {
  value = openstack_compute_instance_v2.edge.id
}

output "edge_fixed_ip" {
  value = var.edge_fixed_ip
}

output "edge_floating_ip" {
  value = var.edge_floating_ip_address
}

output "gpu_instance_id" {
  value = openstack_compute_instance_v2.gpu.id
}

output "gpu_fixed_ip" {
  value = var.gpu_fixed_ip
}

output "model_cache_volume_id" {
  value = openstack_blockstorage_volume_v3.model_cache.id
}

output "edge_security_group_id" {
  value = openstack_networking_secgroup_v2.edge.id
}

output "gpu_security_group_id" {
  value = openstack_networking_secgroup_v2.gpu_inference.id
}

output "gpu2_instance_id" {
  value = var.gpu2_enabled ? openstack_compute_instance_v2.gpu2[0].id : null
}

output "gpu2_fixed_ip" {
  value = var.gpu2_enabled ? var.gpu2_fixed_ip : null
}

output "gpu2_data_volume_id" {
  value = var.gpu2_enabled ? openstack_blockstorage_volume_v3.gpu2_data[0].id : null
}
