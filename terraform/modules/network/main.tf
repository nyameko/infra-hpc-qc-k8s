resource "openstack_networking_network_v2" "mgmt" {
  name           = var.name_prefix == "" ? "k8s-mgmt" : "${var.name_prefix}-mgmt"
  admin_state_up = true
}

resource "openstack_networking_subnet_v2" "mgmt" {
  name       = "${var.name_prefix}-mgmt-subnet"
  network_id = openstack_networking_network_v2.mgmt.id
  cidr       = var.mgmt_cidr
  ip_version = 4

  allocation_pool {
    start = var.mgmt_pool_start
    end   = var.mgmt_pool_end
  }

  dns_nameservers = var.dns_nameservers
}

resource "openstack_networking_network_v2" "k8s" {
  name           = "${var.name_prefix}-k8s"
  admin_state_up = true
}

resource "openstack_networking_subnet_v2" "k8s" {
  name       = "${var.name_prefix}-k8s-subnet"
  network_id = openstack_networking_network_v2.k8s.id
  cidr       = var.k8s_cidr
  ip_version = 4

  allocation_pool {
    start = var.k8s_pool_start
    end   = var.k8s_pool_end
  }

  dns_nameservers = var.dns_nameservers
}

resource "openstack_networking_router_v2" "this" {
  name                = "${var.name_prefix}-router"
  admin_state_up      = true
  external_network_id = var.external_network_id
}

resource "openstack_networking_router_interface_v2" "mgmt" {
  router_id = openstack_networking_router_v2.this.id
  subnet_id = openstack_networking_subnet_v2.mgmt.id
}

resource "openstack_networking_router_interface_v2" "k8s" {
  router_id = openstack_networking_router_v2.this.id
  subnet_id = openstack_networking_subnet_v2.k8s.id
}

resource "openstack_networking_router_route_v2" "wireguard" {
  count            = var.create_wireguard_route ? 1 : 0
  router_id        = openstack_networking_router_v2.this.id
  destination_cidr = var.wireguard_cidr
  next_hop         = var.edge_admin_ip
}
