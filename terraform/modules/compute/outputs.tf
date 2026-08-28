output "ips" {
  value = { for k, v in var.nodes : k => v.fixed_ip }
}
output "instance_ids" {
  value = { for k, v in openstack_compute_instance_v2.this : k => v.id }
}
output "port_ids" {
  value = { for k, v in openstack_networking_port_v2.this : k => v.id }
}
