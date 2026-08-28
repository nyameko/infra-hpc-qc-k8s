resource "openstack_networking_port_v2" "this" {
  for_each           = var.nodes
  name               = "${each.value.name}-port"
  network_id         = each.value.network_id
  security_group_ids = each.value.security_groups

  fixed_ip {
    subnet_id  = each.value.subnet_id
    ip_address = each.value.fixed_ip
  }
}

resource "openstack_compute_instance_v2" "this" {
  for_each    = var.nodes
  name        = each.value.name
  image_id    = each.value.image_id
  flavor_name = each.value.flavor_name
  key_pair    = each.value.key_pair
  config_drive = true

  network {
    port = openstack_networking_port_v2.this[each.key].id
  }

  user_data = try(each.value.user_data, null)
}
