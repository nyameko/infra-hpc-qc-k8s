output "mgmt_network_id" { value = openstack_networking_network_v2.mgmt.id }
output "mgmt_subnet_id" { value = openstack_networking_subnet_v2.mgmt.id }
output "k8s_network_id" { value = openstack_networking_network_v2.k8s.id }
output "k8s_subnet_id" { value = openstack_networking_subnet_v2.k8s.id }
output "router_id" { value = openstack_networking_router_v2.this.id }
