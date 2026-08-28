data "openstack_networking_network_v2" "external" {
  name = var.external_network_name
}

resource "openstack_networking_network_v2" "mgmt" {
  name = "${var.name_prefix}-mgmt"
}

resource "openstack_networking_subnet_v2" "mgmt" {
  name       = "${var.name_prefix}-mgmt-subnet"
  network_id = openstack_networking_network_v2.mgmt.id
  cidr       = var.mgmt_cidr
  ip_version = 4
  gateway_ip = var.mgmt_gateway_ip
  allocation_pool {
    start = var.mgmt_pool_start
    end   = var.mgmt_pool_end
  }
}

resource "openstack_networking_network_v2" "k8s" {
  name = "${var.name_prefix}-k8s"
}

resource "openstack_networking_subnet_v2" "k8s" {
  name       = "${var.name_prefix}-k8s-subnet"
  network_id = openstack_networking_network_v2.k8s.id
  cidr       = var.k8s_cidr
  ip_version = 4
  gateway_ip = var.k8s_gateway_ip
  allocation_pool {
    start = var.k8s_pool_start
    end   = var.k8s_pool_end
  }
}

resource "openstack_networking_router_v2" "main" {
  name                = "${var.name_prefix}-router"
  admin_state_up      = true
  external_network_id = data.openstack_networking_network_v2.external.id
}

resource "openstack_networking_router_interface_v2" "mgmt" {
  router_id = openstack_networking_router_v2.main.id
  subnet_id = openstack_networking_subnet_v2.mgmt.id
}

resource "openstack_networking_router_interface_v2" "k8s" {
  router_id = openstack_networking_router_v2.main.id
  subnet_id = openstack_networking_subnet_v2.k8s.id
}
