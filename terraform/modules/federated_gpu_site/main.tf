data "openstack_networking_network_v2" "external" {
  name = var.external_network_name
}

resource "openstack_networking_network_v2" "private" {
  name = "${var.name_prefix}-private"
}

resource "openstack_networking_subnet_v2" "private" {
  name            = "${var.name_prefix}-private-subnet"
  network_id      = openstack_networking_network_v2.private.id
  cidr            = var.private_cidr
  ip_version      = 4
  gateway_ip      = var.private_gateway_ip
  dns_nameservers = var.dns_nameservers

  allocation_pool {
    start = var.private_pool_start
    end   = var.private_pool_end
  }
}

resource "openstack_networking_router_v2" "site" {
  name                = "${var.name_prefix}-router"
  admin_state_up      = true
  external_network_id = data.openstack_networking_network_v2.external.id
}

resource "openstack_networking_router_interface_v2" "private" {
  router_id = openstack_networking_router_v2.site.id
  subnet_id = openstack_networking_subnet_v2.private.id
}

resource "openstack_networking_secgroup_v2" "edge" {
  name        = "${var.name_prefix}-edge"
  description = "Federated site edge / wg-fabric gateway"
}

resource "openstack_networking_secgroup_v2" "gpu_inference" {
  name        = "${var.name_prefix}-gpu-inference"
  description = "Dedicated GPU model-serving node"
}

resource "openstack_networking_secgroup_rule_v2" "edge_ssh" {
  for_each = toset(var.bootstrap_ssh_cidrs)

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = each.value
  security_group_id = openstack_networking_secgroup_v2.edge.id
}

resource "openstack_networking_secgroup_rule_v2" "edge_wireguard" {
  for_each = toset(var.wireguard_ingress_cidrs)

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = var.wireguard_port
  port_range_max    = var.wireguard_port
  remote_ip_prefix  = each.value
  security_group_id = openstack_networking_secgroup_v2.edge.id
}

resource "openstack_networking_secgroup_rule_v2" "edge_private" {
  direction         = "ingress"
  ethertype         = "IPv4"
  remote_ip_prefix  = var.private_cidr
  security_group_id = openstack_networking_secgroup_v2.edge.id
}

resource "openstack_networking_secgroup_rule_v2" "gpu_ssh_from_edge" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_group_id   = openstack_networking_secgroup_v2.edge.id
  security_group_id = openstack_networking_secgroup_v2.gpu_inference.id
}

locals {
  gpu_service_ports = toset([
    tostring(var.vllm_port),
    tostring(var.node_exporter_port),
    tostring(var.dcgm_exporter_port),
  ])

  gpu_remote_rules = {
    for pair in setproduct(toset(var.remote_routed_cidrs), local.gpu_service_ports) :
    "${pair[0]}:${pair[1]}" => {
      cidr = pair[0]
      port = tonumber(pair[1])
    }
  }
}

resource "openstack_networking_secgroup_rule_v2" "gpu_services_from_fabric" {
  for_each = local.gpu_remote_rules

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = each.value.port
  port_range_max    = each.value.port
  remote_ip_prefix  = each.value.cidr
  security_group_id = openstack_networking_secgroup_v2.gpu_inference.id
}

resource "openstack_networking_secgroup_rule_v2" "gpu_services_from_edge" {
  for_each = local.gpu_service_ports

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = tonumber(each.value)
  port_range_max    = tonumber(each.value)
  remote_group_id   = openstack_networking_secgroup_v2.edge.id
  security_group_id = openstack_networking_secgroup_v2.gpu_inference.id
}

resource "openstack_networking_secgroup_rule_v2" "gpu_icmp_from_fabric" {
  for_each = toset(var.remote_routed_cidrs)

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = each.value
  security_group_id = openstack_networking_secgroup_v2.gpu_inference.id
}

resource "openstack_networking_port_v2" "edge" {
  name               = "${var.name_prefix}-edge-port"
  network_id         = openstack_networking_network_v2.private.id
  security_group_ids = [openstack_networking_secgroup_v2.edge.id]

  fixed_ip {
    subnet_id  = openstack_networking_subnet_v2.private.id
    ip_address = var.edge_fixed_ip
  }

  dynamic "allowed_address_pairs" {
    for_each = toset(var.remote_routed_cidrs)
    content {
      ip_address = allowed_address_pairs.value
    }
  }
}

resource "openstack_networking_port_v2" "gpu" {
  name               = "${var.gpu_name}-port"
  network_id         = openstack_networking_network_v2.private.id
  security_group_ids = [openstack_networking_secgroup_v2.gpu_inference.id]

  fixed_ip {
    subnet_id  = openstack_networking_subnet_v2.private.id
    ip_address = var.gpu_fixed_ip
  }
}

resource "openstack_compute_instance_v2" "edge" {
  name              = var.edge_name
  image_id          = var.edge_image_id
  flavor_name       = var.edge_flavor_name
  key_pair          = var.key_pair
  availability_zone = var.availability_zone
  config_drive      = true
  user_data         = var.edge_user_data

  network {
    port = openstack_networking_port_v2.edge.id
  }
}

resource "openstack_compute_instance_v2" "gpu" {
  name              = var.gpu_name
  flavor_name       = var.gpu_flavor_name
  key_pair          = var.key_pair
  availability_zone = var.availability_zone
  config_drive      = true
  user_data         = var.gpu_user_data

  block_device {
    uuid                  = var.gpu_image_id
    source_type           = "image"
    destination_type      = "volume"
    boot_index            = 0
    volume_size           = var.gpu_root_volume_size_gb
    delete_on_termination = true
  }

  network {
    port = openstack_networking_port_v2.gpu.id
  }
}

resource "openstack_networking_floatingip_associate_v2" "edge" {
  floating_ip = var.edge_floating_ip_address
  port_id     = openstack_networking_port_v2.edge.id
}

resource "openstack_blockstorage_volume_v3" "model_cache" {
  name              = "${var.gpu_name}-model-cache"
  size              = var.model_volume_size_gb
  volume_type       = var.model_volume_type
  availability_zone = var.availability_zone
}

resource "openstack_compute_volume_attach_v2" "model_cache" {
  instance_id = openstack_compute_instance_v2.gpu.id
  volume_id   = openstack_blockstorage_volume_v3.model_cache.id
}

resource "openstack_networking_router_route_v2" "fabric_remote" {
  for_each = toset(var.remote_routed_cidrs)

  router_id        = openstack_networking_router_v2.site.id
  destination_cidr = each.value
  next_hop         = var.edge_fixed_ip

  depends_on = [openstack_networking_router_interface_v2.private]
}
