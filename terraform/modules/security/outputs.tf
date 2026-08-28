output "group_ids" {
  value = { for k, v in openstack_networking_secgroup_v2.this : k => v.id }
}
