resource "openstack_networking_secgroup_v2" "edge" {
  name        = "${var.name_prefix}-edge-admin"
  description = "Edge/admin VM security group"
}

resource "openstack_networking_secgroup_v2" "control_plane" {
  name        = "${var.name_prefix}-control-plane"
  description = "Kubernetes control-plane nodes"
}

resource "openstack_networking_secgroup_v2" "worker" {
  name        = "${var.name_prefix}-worker"
  description = "Kubernetes worker nodes"
}

resource "openstack_networking_secgroup_rule_v2" "edge_wireguard" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 51820
  port_range_max    = 51820
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.edge.id
}

resource "openstack_networking_secgroup_rule_v2" "edge_ssh_bootstrap" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.bootstrap_ssh_cidr
  security_group_id = openstack_networking_secgroup_v2.edge.id
}

resource "openstack_networking_secgroup_rule_v2" "edge_dns_tcp" {
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
  port_range_min = 53
  port_range_max = 53
  remote_ip_prefix = var.internal_cidrs[0]
  security_group_id = openstack_networking_secgroup_v2.edge.id
}

resource "openstack_networking_secgroup_rule_v2" "edge_dns_udp" {
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "udp"
  port_range_min = 53
  port_range_max = 53
  remote_ip_prefix = var.internal_cidrs[0]
  security_group_id = openstack_networking_secgroup_v2.edge.id
}

resource "openstack_networking_secgroup_rule_v2" "k8s_api" {
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
  port_range_min = 6443
  port_range_max = 6443
  remote_group_id = openstack_networking_secgroup_v2.control_plane.id
  security_group_id = openstack_networking_secgroup_v2.control_plane.id
}

resource "openstack_networking_secgroup_rule_v2" "k8s_api_internal" {
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
  port_range_min = 6443
  port_range_max = 6443
  remote_ip_prefix = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.control_plane.id
}

resource "openstack_networking_secgroup_rule_v2" "etcd" {
  for_each = toset(["2379", "2380"])
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
  port_range_min = each.value
  port_range_max = each.value
  remote_group_id = openstack_networking_secgroup_v2.control_plane.id
  security_group_id = openstack_networking_secgroup_v2.control_plane.id
}

resource "openstack_networking_secgroup_rule_v2" "kubelet_cp" {
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
  port_range_min = 10250
  port_range_max = 10250
  remote_ip_prefix = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.control_plane.id
}

resource "openstack_networking_secgroup_rule_v2" "kubelet_worker" {
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
  port_range_min = 10250
  port_range_max = 10250
  remote_ip_prefix = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.worker.id
}

resource "openstack_networking_secgroup_rule_v2" "vxlan_cp" {
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "udp"
  port_range_min = 8472
  port_range_max = 8472
  remote_ip_prefix = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.control_plane.id
}

resource "openstack_networking_secgroup_rule_v2" "vxlan_worker" {
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "udp"
  port_range_min = 8472
  port_range_max = 8472
  remote_ip_prefix = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.worker.id
}

resource "openstack_networking_secgroup_rule_v2" "worker_all_internal" {
  direction = "ingress"
  ethertype = "IPv4"
  remote_ip_prefix = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.worker.id
}

resource "openstack_networking_secgroup_rule_v2" "cp_to_worker" {
  direction = "egress"
  ethertype = "IPv4"
  remote_ip_prefix = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.control_plane.id
}
