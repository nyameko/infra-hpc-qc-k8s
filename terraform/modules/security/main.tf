locals {
  groups = toset([
    "edge",
    "hermes-orchestrator",
    "slurm-controller",
    "slurm-login",
    "slurm-compute",
    "api-lb",
    "k8s-control-plane",
    "k8s-worker",
  ])
}

resource "openstack_networking_secgroup_v2" "this" {
  for_each    = local.groups
  name        = "${var.name_prefix}-${each.key}"
  description = "${var.name_prefix} ${each.key}"
}

resource "openstack_networking_secgroup_rule_v2" "edge_ssh_bootstrap" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.bootstrap_ssh_cidr
  security_group_id = openstack_networking_secgroup_v2.this["edge"].id
}

resource "openstack_networking_secgroup_rule_v2" "edge_wireguard" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 51820
  port_range_max    = 51820
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.this["edge"].id
}

resource "openstack_networking_secgroup_rule_v2" "internal_all" {
  for_each = {
    edge             = "edge"
    hermes           = "hermes-orchestrator"
    slurm_controller = "slurm-controller"
    slurm_login      = "slurm-login"
    slurm_compute    = "slurm-compute"
    api_lb           = "api-lb"
    k8s_control      = "k8s-control-plane"
    k8s_worker       = "k8s-worker"
  }
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = null
  remote_ip_prefix  = each.value == "edge" ? var.mgmt_cidr : var.mgmt_cidr
  security_group_id = openstack_networking_secgroup_v2.this[each.value].id
}

resource "openstack_networking_secgroup_rule_v2" "api_lb" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6443
  port_range_max    = 6443
  remote_ip_prefix  = var.mgmt_cidr
  security_group_id = openstack_networking_secgroup_v2.this["api_lb"].id
}


resource "openstack_networking_secgroup_rule_v2" "k8s_api" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6443
  port_range_max    = 6443
  remote_ip_prefix  = var.api_lb_cidr
  security_group_id = openstack_networking_secgroup_v2.this["k8s-control-plane"].id
}

resource "openstack_networking_secgroup_rule_v2" "k8s_api_k8s" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6443
  port_range_max    = 6443
  remote_ip_prefix  = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.this["k8s-control-plane"].id
}

resource "openstack_networking_secgroup_rule_v2" "k8s_kubelet" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 10250
  port_range_max    = 10250
  remote_ip_prefix  = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.this["k8s-worker"].id
}

resource "openstack_networking_secgroup_rule_v2" "slurm_compute_6817" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6817
  port_range_max    = 6818
  remote_ip_prefix  = var.mgmt_cidr
  security_group_id = openstack_networking_secgroup_v2.this["slurm-compute"].id
}
