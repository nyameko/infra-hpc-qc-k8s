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

locals {
  cloudflare_ipv4_cidrs = toset([
    "173.245.48.0/20",
    "103.21.244.0/22",
    "103.22.200.0/22",
    "103.31.4.0/22",
    "141.101.64.0/18",
    "108.162.192.0/18",
    "190.93.240.0/20",
    "188.114.96.0/20",
    "197.234.240.0/22",
    "198.41.128.0/17",
    "162.158.0.0/15",
    "104.16.0.0/13",
    "104.24.0.0/14",
    "172.64.0.0/13",
    "131.0.72.0/22",
  ])
}

resource "openstack_networking_secgroup_rule_v2" "edge_http_cloudflare" {
  for_each = local.cloudflare_ipv4_cidrs

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = each.value
  security_group_id = openstack_networking_secgroup_v2.this["edge"].id
}

resource "openstack_networking_secgroup_rule_v2" "edge_https_cloudflare" {
  for_each = local.cloudflare_ipv4_cidrs

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = each.value
  security_group_id = openstack_networking_secgroup_v2.this["edge"].id
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

resource "openstack_networking_secgroup_rule_v2" "api_lb_http_vpn" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = var.vpn_cidr
  security_group_id = openstack_networking_secgroup_v2.this["api-lb"].id
}

resource "openstack_networking_secgroup_rule_v2" "edge_wazuh_agent" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 1514
  port_range_max    = 1515
  remote_ip_prefix  = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.this["edge"].id
}

resource "openstack_networking_secgroup_rule_v2" "edge_wazuh_agent_mgmt" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 1514
  port_range_max    = 1515
  remote_ip_prefix  = var.mgmt_cidr
  security_group_id = openstack_networking_secgroup_v2.this["edge"].id
}

resource "openstack_networking_secgroup_rule_v2" "edge_wazuh_agent_vpn" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 1514
  port_range_max    = 1515
  remote_ip_prefix  = var.vpn_cidr
  security_group_id = openstack_networking_secgroup_v2.this["edge"].id
}

resource "openstack_networking_secgroup_rule_v2" "edge_wazuh_api" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 55000
  port_range_max    = 55000
  remote_ip_prefix  = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.this["edge"].id
}

resource "openstack_networking_secgroup_rule_v2" "edge_wazuh_api_mgmt" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 55000
  port_range_max    = 55000
  remote_ip_prefix  = var.mgmt_cidr
  security_group_id = openstack_networking_secgroup_v2.this["edge"].id
}

resource "openstack_networking_secgroup_rule_v2" "edge_wazuh_api_vpn" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 55000
  port_range_max    = 55000
  remote_ip_prefix  = var.vpn_cidr
  security_group_id = openstack_networking_secgroup_v2.this["edge"].id
}

resource "openstack_networking_secgroup_rule_v2" "api_lb_wazuh_indexer_from_edge" {
  direction = "ingress"
  ethertype = "IPv4"
  protocol  = "tcp"

  port_range_min = 9200
  port_range_max = 9200

  remote_group_id = openstack_networking_secgroup_v2.this["edge"].id

  security_group_id = openstack_networking_secgroup_v2.this["api-lb"].id
}

resource "openstack_networking_secgroup_rule_v2" "k8s_worker_wazuh_indexer_from_api_lb" {
  direction = "ingress"
  ethertype = "IPv4"
  protocol  = "tcp"

  port_range_min = 9200
  port_range_max = 9200

  remote_group_id = openstack_networking_secgroup_v2.this["api-lb"].id

  security_group_id = openstack_networking_secgroup_v2.this["k8s-worker"].id
}

resource "openstack_networking_secgroup_rule_v2" "api_lb_https_vpn" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = var.vpn_cidr
  security_group_id = openstack_networking_secgroup_v2.this["api-lb"].id
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

resource "openstack_networking_secgroup_rule_v2" "k8s_api_from_k8s" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6443
  port_range_max    = 6443
  remote_ip_prefix  = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.this["k8s-control-plane"].id
}

resource "openstack_networking_secgroup_rule_v2" "api_lb_http_from_k8s" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.this["api-lb"].id
}

resource "openstack_networking_secgroup_rule_v2" "api_lb_https_from_k8s" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.this["api-lb"].id
}

resource "openstack_networking_secgroup_rule_v2" "api_lb_http_mgmt" {
  direction = "ingress"
  ethertype = "IPv4"
  protocol  = "tcp"

  port_range_min = 80
  port_range_max = 80

  remote_ip_prefix = var.mgmt_cidr

  security_group_id = openstack_networking_secgroup_v2.this["api-lb"].id
}

resource "openstack_networking_secgroup_rule_v2" "api_lb_https_mgmt" {
  direction = "ingress"
  ethertype = "IPv4"
  protocol  = "tcp"

  port_range_min = 443
  port_range_max = 443

  remote_ip_prefix = var.mgmt_cidr

  security_group_id = openstack_networking_secgroup_v2.this["api-lb"].id
}

resource "openstack_networking_secgroup_rule_v2" "k8s_worker_http_from_api_lb" {
  direction = "ingress"
  ethertype = "IPv4"
  protocol  = "tcp"

  port_range_min = 80
  port_range_max = 80

  remote_ip_prefix = var.api_lb_address

  security_group_id = openstack_networking_secgroup_v2.this["k8s-worker"].id
}

resource "openstack_networking_secgroup_rule_v2" "k8s_worker_https_from_api_lb" {
  direction = "ingress"
  ethertype = "IPv4"
  protocol  = "tcp"

  port_range_min = 443
  port_range_max = 443

  remote_ip_prefix = var.api_lb_address

  security_group_id = openstack_networking_secgroup_v2.this["k8s-worker"].id
}

resource "openstack_networking_secgroup_rule_v2" "api_lb_prometheus_from_k8s" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 8404
  port_range_max    = 8404
  remote_ip_prefix  = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.this["api-lb"].id
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

resource "openstack_networking_secgroup_rule_v2" "k8s_cilium_vxlan_control_plane" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 8472
  port_range_max    = 8472
  remote_ip_prefix  = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.this["k8s-control-plane"].id
}

resource "openstack_networking_secgroup_rule_v2" "k8s_cilium_vxlan_worker" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 8472
  port_range_max    = 8472
  remote_ip_prefix  = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.this["k8s-worker"].id
}

resource "openstack_networking_secgroup_rule_v2" "k8s_cilium_health_control_plane" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 4240
  port_range_max    = 4240
  remote_ip_prefix  = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.this["k8s-control-plane"].id
}

resource "openstack_networking_secgroup_rule_v2" "k8s_cilium_health_worker" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 4240
  port_range_max    = 4240
  remote_ip_prefix  = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.this["k8s-worker"].id
}

resource "openstack_networking_secgroup_rule_v2" "k8s_nodeport_tcp_control_plane" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 30000
  port_range_max    = 32767
  remote_ip_prefix  = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.this["k8s-control-plane"].id
}

resource "openstack_networking_secgroup_rule_v2" "k8s_nodeport_tcp_worker" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 30000
  port_range_max    = 32767
  remote_ip_prefix  = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.this["k8s-worker"].id
}

resource "openstack_networking_secgroup_rule_v2" "k8s_nodeport_udp_control_plane" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 30000
  port_range_max    = 32767
  remote_ip_prefix  = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.this["k8s-control-plane"].id
}

resource "openstack_networking_secgroup_rule_v2" "k8s_nodeport_udp_worker" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 30000
  port_range_max    = 32767
  remote_ip_prefix  = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.this["k8s-worker"].id
}

resource "openstack_networking_secgroup_rule_v2" "k8s_icmp_control_plane" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.this["k8s-control-plane"].id
}

resource "openstack_networking_secgroup_rule_v2" "k8s_icmp_worker" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.this["k8s-worker"].id
}

resource "openstack_networking_secgroup_rule_v2" "k8s_control_plane_monitoring_metrics" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 9100
  port_range_max    = 9100
  remote_ip_prefix  = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.this["k8s-control-plane"].id
}

resource "openstack_networking_secgroup_rule_v2" "k8s_control_plane_cilium_metrics" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 9962
  port_range_max    = 9964
  remote_ip_prefix  = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.this["k8s-control-plane"].id
}

resource "openstack_networking_secgroup_rule_v2" "k8s_workers_monitoring_metrics" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 9100
  port_range_max    = 9100
  remote_ip_prefix  = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.this["k8s-worker"].id
}

resource "openstack_networking_secgroup_rule_v2" "k8s_workers_cilium_metrics" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 9962
  port_range_max    = 9964
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


# M1 Slurm accounting: private management network only.
resource "openstack_networking_secgroup_rule_v2" "slurmdbd_mgmt" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6819
  port_range_max    = 6819
  remote_ip_prefix  = var.mgmt_cidr
  security_group_id = openstack_networking_secgroup_v2.this["slurm-controller"].id
}

# External host exporters are scraped by Prometheus from the Kubernetes network.
resource "openstack_networking_secgroup_rule_v2" "slurm_node_exporters" {
  for_each          = toset(["slurm-controller", "slurm-login", "slurm-compute"])
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 9100
  port_range_max    = 9100
  remote_ip_prefix  = var.k8s_cidr
  security_group_id = openstack_networking_secgroup_v2.this[each.key].id
}
