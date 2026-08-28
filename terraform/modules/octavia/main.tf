resource "openstack_lb_loadbalancer_v2" "api" {
  name           = var.name
  vip_subnet_id  = var.vip_subnet_id
  vip_address    = var.vip_address
}

resource "openstack_lb_listener_v2" "api" {
  name            = "${var.name}-listener"
  loadbalancer_id = openstack_lb_loadbalancer_v2.api.id
  protocol        = "TCP"
  protocol_port   = 6443
}

resource "openstack_lb_pool_v2" "api" {
  name        = "${var.name}-pool"
  protocol    = "TCP"
  lb_method   = "ROUND_ROBIN"
  listener_id = openstack_lb_listener_v2.api.id
}

resource "openstack_lb_member_v2" "api" {
  for_each      = var.control_plane_ips
  address       = each.value
  protocol_port = 6443
  pool_id       = openstack_lb_pool_v2.api.id
  subnet_id     = var.vip_subnet_id
}

resource "openstack_lb_healthmonitor_v2" "api" {
  pool_id     = openstack_lb_pool_v2.api.id
  type        = "TCP"
  delay       = 5
  timeout     = 3
  max_retries = 3
}
