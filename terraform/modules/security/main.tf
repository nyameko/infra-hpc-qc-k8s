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
  for_each = local.groups

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

resource "openstack_networking_secgroup_rule_v2" "edge_ssh_vpn" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.vpn_cidr
  security_group_id = openstack_networking_secgroup_v2.this["edge"].id
}

resource "openstack_networking_secgroup_rule_v2" "ssh_from_mgmt" {
  for_each = setsubtract(local.groups, ["edge"])

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.mgmt_cidr
  security_group_id = openstack_networking_secgroup_v2.this[each.key].id
}

resource "openstack_networking_secgroup_rule_v2" "api_lb_ingress" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6443
  port_range_max    = 6443
  remote_ip_prefix  = var.vpn_cidr
  security_group_id = openstack_networking_secgroup_v2.this["api-lb"].id
}

resource "openstack_networking_secgroup_rule_v2" "api_lb" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6443
  port_range_max    = 6443
  remote_ip_prefix  = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.this["api-lb"].id
}

resource "openstack_networking_secgroup_rule_v2" "k8s_api_vpn" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6443
  port_range_max    = 6443
  remote_ip_prefix  = var.vpn_cidr
  security_group_id = openstack_networking_secgroup_v2.this["k8s-control-plane"].id
}

resource "openstack_networking_secgroup_rule_v2" "k8s_api_from_k8s" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6443
  port_range_max    = 6443
  remote_ip_prefix  = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.this["k8s-control-plane"].id
}

resource "openstack_networking_secgroup_rule_v2" "k8s_etcd" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 2379
  port_range_max    = 2380
  remote_ip_prefix  = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.this["k8s-control-plane"].id
}

resource "openstack_networking_secgroup_rule_v2" "k8s_kubelet_control_plane" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 10250
  port_range_max    = 10250
  remote_ip_prefix  = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.this["k8s-control-plane"].id
}

resource "openstack_networking_secgroup_rule_v2" "k8s_kubelet_worker" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 10250
  port_range_max    = 10250
  remote_ip_prefix  = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.this["k8s-worker"].id
}

resource "openstack_networking_secgroup_rule_v2" "slurm_controller" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6817
  port_range_max    = 6817
  remote_ip_prefix  = var.mgmt_cidr
  security_group_id = openstack_networking_secgroup_v2.this["slurm-controller"].id
}

resource "openstack_networking_secgroup_rule_v2" "slurm_compute" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6818
  port_range_max    = 6818
  remote_ip_prefix  = var.mgmt_cidr
  security_group_id = openstack_networking_secgroup_v2.this["slurm-compute"].id
}

resource "openstack_networking_secgroup_rule_v2" "slurm_login_ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.vpn_cidr
  security_group_id = openstack_networking_secgroup_v2.this["slurm-login"].id
}

resource "openstack_networking_secgroup_rule_v2" "hermes_ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.vpn_cidr
  security_group_id = openstack_networking_secgroup_v2.this["hermes-orchestrator"].id
}

resource "openstack_networking_secgroup_rule_v2" "edge_dns_mgmt" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 53
  port_range_max    = 53
  remote_ip_prefix  = var.mgmt_cidr
  security_group_id = openstack_networking_secgroup_v2.this["edge"].id
}

resource "openstack_networking_secgroup_rule_v2" "edge_dns_mgmt_tcp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 53
  port_range_max    = 53
  remote_ip_prefix  = var.mgmt_cidr
  security_group_id = openstack_networking_secgroup_v2.this["edge"].id
}

resource "openstack_networking_secgroup_rule_v2" "edge_dns_k8s" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 53
  port_range_max    = 53
  remote_ip_prefix  = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.this["edge"].id
}

resource "openstack_networking_secgroup_rule_v2" "edge_dns_k8s_tcp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 53
  port_range_max    = 53
  remote_ip_prefix  = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.this["edge"].id
}
