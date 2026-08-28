resource "openstack_lb_loadbalancer_v2" "api" {
  name          = "${var.name_prefix}-k8s-api"
  vip_subnet_id = var.k8s_subnet_id
  vip_address   = var.vip_address
}

resource "openstack_lb_listener_v2" "api" {
  name            = "${var.name_prefix}-k8s-api-listener"
  protocol        = "TCP"
  protocol_port   = 6443
  loadbalancer_id = openstack_lb_loadbalancer_v2.api.id
}

resource "openstack_lb_pool_v2" "api" {
  name            = "${var.name_prefix}-k8s-api-pool"
  protocol        = "TCP"
  lb_method       = "ROUND_ROBIN"
  listener_id     = openstack_lb_listener_v2.api.id
}

resource "openstack_lb_member_v2" "api" {
  for_each = var.control_plane_ips
  pool_id       = openstack_lb_pool_v2.api.id
  address       = each.value
  protocol_port = 6443
  subnet_id     = var.k8s_subnet_id
}

resource "openstack_lb_monitor_v2" "api" {
  pool_id     = openstack_lb_pool_v2.api.id
  type        = "TCP"
  delay       = 5
  timeout     = 3
  max_retries = 3
}
