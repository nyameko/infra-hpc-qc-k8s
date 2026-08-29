resource "openstack_lb_loadbalancer_v2" "api" {
  name           = var.name
  vip_subnet_id  = var.vip_subnet_id
  vip_address    = var.vip_address
  admin_state_up = true
}
resource "openstack_lb_listener_v2" "api" {
  name            = "${var.name}-listener"
  protocol        = "TCP"
  protocol_port   = var.listener_port
  loadbalancer_id = openstack_lb_loadbalancer_v2.api.id
}
resource "openstack_lb_pool_v2" "api" {
  name        = "${var.name}-pool"
  protocol    = "TCP"
  lb_method   = var.lb_method
  listener_id = openstack_lb_listener_v2.api.id
}
resource "openstack_lb_member_v2" "api" {
  for_each = toset(var.backend_addresses)

  pool_id       = openstack_lb_pool_v2.api.id
  address       = each.value
  protocol_port = var.backend_port
}
resource "openstack_lb_monitor_v2" "api" {
  name        = "${var.name}-monitor"
  pool_id     = openstack_lb_pool_v2.api.id
  type        = "TCP"
  delay       = var.monitor_delay
  timeout     = var.monitor_timeout
  max_retries = var.monitor_max_retries
}
