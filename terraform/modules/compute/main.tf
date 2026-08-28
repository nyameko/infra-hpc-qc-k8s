resource "openstack_networking_port_v2" "edge" {
  name = "${var.name_prefix}-edge-port"
  network_id = var.mgmt_network_id
  security_group_ids = [var.edge_sg_id]
  fixed_ip {
    subnet_id = var.mgmt_subnet_id
    ip_address = var.edge_ip
  }
}

resource "openstack_compute_instance_v2" "edge" {
  name = "${var.name_prefix}-edge-admin"
  image_id = var.image_id
  flavor_name = var.edge_flavor
  key_pair = var.key_pair_name
  config_drive = true
  network { port = openstack_networking_port_v2.edge.id }
  user_data = var.edge_cloud_init
}

resource "openstack_networking_floatingip_v2" "edge" {
  pool = var.external_network_name
}

resource "openstack_networking_floatingip_associate_v2" "edge" {
  floating_ip = openstack_networking_floatingip_v2.edge.address
  port_id = openstack_networking_port_v2.edge.id
}

locals {
  control_planes = {
    cp01 = "10.51.0.11"
    cp02 = "10.51.0.12"
    cp03 = "10.51.0.13"
  }
  workers = {
    worker01 = "10.51.0.21"
    worker02 = "10.51.0.22"
    worker03 = "10.51.0.23"
  }
}

resource "openstack_networking_port_v2" "control_plane" {
  for_each = local.control_planes
  name = "${var.name_prefix}-${each.key}-port"
  network_id = var.k8s_network_id
  security_group_ids = [var.control_plane_sg_id]
  fixed_ip {
    subnet_id = var.k8s_subnet_id
    ip_address = each.value
  }
}

resource "openstack_compute_instance_v2" "control_plane" {
  for_each = local.control_planes
  name = "${var.name_prefix}-${each.key}"
  image_id = var.image_id
  flavor_name = var.control_plane_flavor
  key_pair = var.key_pair_name
  config_drive = true
  network { port = openstack_networking_port_v2.control_plane[each.key].id }
  user_data = templatefile(var.node_cloud_init_template, {
    hostname = "${var.name_prefix}-${each.key}"
  })
}

resource "openstack_networking_port_v2" "worker" {
  for_each = local.workers
  name = "${var.name_prefix}-${each.key}-port"
  network_id = var.k8s_network_id
  security_group_ids = [var.worker_sg_id]
  fixed_ip {
    subnet_id = var.k8s_subnet_id
    ip_address = each.value
  }
}

resource "openstack_compute_instance_v2" "worker" {
  for_each = local.workers
  name = "${var.name_prefix}-${each.key}"
  image_id = var.image_id
  flavor_name = var.worker_flavor
  key_pair = var.key_pair_name
  config_drive = true
  network { port = openstack_networking_port_v2.worker[each.key].id }
  user_data = templatefile(var.node_cloud_init_template, {
    hostname = "${var.name_prefix}-${each.key}"
  })
}
