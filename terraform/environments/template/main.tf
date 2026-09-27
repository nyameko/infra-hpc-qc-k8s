module "network" {
  source                = "../../modules/network"
  name_prefix           = "infra-hpc-qc-k8s"
  external_network_name = var.external_network_name
  mgmt_cidr             = var.mgmt_cidr
  k8s_cidr              = var.k8s_cidr
  api_lb_cidr           = var.k8s_cidr
  mgmt_gateway_ip       = var.mgmt_gateway_ip
  k8s_gateway_ip        = var.k8s_gateway_ip
  mgmt_pool_start       = var.mgmt_pool_start
  mgmt_pool_end         = var.mgmt_pool_end
  k8s_pool_start        = var.k8s_pool_start
  k8s_pool_end          = var.k8s_pool_end
  dns_nameservers       = var.dns_nameservers
}

module "security" {
  source             = "../../modules/security"
  name_prefix        = "infra-hpc-qc-k8s"
  bootstrap_ssh_cidr = var.bootstrap_ssh_cidr
  vpn_cidr           = var.vpn_cidr
  api_lb_cidr        = var.k8s_cidr
  mgmt_cidr          = var.mgmt_cidr
  k8s_cidr           = var.k8s_cidr
}

module "api_lb_haproxy" {
  count = var.api_lb_type == "haproxy" ? 1 : 0

  source = "../../modules/api_lb/haproxy"

  name               = var.api_lb_name
  network_id         = openstack_networking_network_v2.k8s.id
  subnet_id          = openstack_networking_subnet_v2.k8s.id
  vip_address        = var.api_lb_address
  security_group_ids = [module.security.api_lb_security_group_id]

  image_id  = var.api_lb_image_id
  flavor_id = var.api_lb_flavor_id
  key_pair  = var.ssh_key_name

  backend_addresses = [for key in ["k8s_cp_01", "k8s_cp_02", "k8s_cp_03"] : var.node_fixed_ips[key]]
  backend_port      = var.kubernetes_api_port

  user_data = var.api_lb_user_data
}

module "api_lb_octavia" {
  count = var.api_lb_type == "octavia" ? 1 : 0

  source = "../../modules/api_lb/octavia"

  name              = var.api_lb_name
  vip_subnet_id     = openstack_networking_subnet_v2.k8s.id
  vip_address       = var.api_lb_address
  backend_addresses = [for key in ["k8s_cp_01", "k8s_cp_02", "k8s_cp_03"] : var.node_fixed_ips[key]]

  listener_port = var.kubernetes_api_port
  backend_port  = var.kubernetes_api_port
}

locals {
  nodes = {
    edge = {
      name = "edge", network_id = module.network.mgmt_network_id, subnet_id = module.network.mgmt_subnet_id, fixed_ip = var.node_fixed_ips["edge"], flavor_name = var.edge_flavor, image_id = var.image_id, security_groups = [module.security.group_ids["edge"]], key_pair = var.ssh_key_name
    }
    hermes = {
      name = "hermes-orchestrator-01", network_id = module.network.mgmt_network_id, subnet_id = module.network.mgmt_subnet_id, fixed_ip = var.node_fixed_ips["hermes"], flavor_name = var.hermes_flavor, image_id = var.image_id, security_groups = [module.security.group_ids["hermes-orchestrator"]], key_pair = var.ssh_key_name
    }
    slurm_controller = {
      name = "slurm-controller-01", network_id = module.network.mgmt_network_id, subnet_id = module.network.mgmt_subnet_id, fixed_ip = var.node_fixed_ips["slurm_controller"], flavor_name = var.slurm_controller_flavor, image_id = var.image_id, security_groups = [module.security.group_ids["slurm-controller"]], key_pair = var.ssh_key_name
    }
    login1 = {
      name = "login1", network_id = module.network.mgmt_network_id, subnet_id = module.network.mgmt_subnet_id, fixed_ip = var.node_fixed_ips["login1"], flavor_name = var.login_flavor, image_id = var.image_id, security_groups = [module.security.group_ids["slurm-login"]], key_pair = var.ssh_key_name
    }
    login2 = {
      name = "login2", network_id = module.network.mgmt_network_id, subnet_id = module.network.mgmt_subnet_id, fixed_ip = var.node_fixed_ips["login2"], flavor_name = var.login_flavor, image_id = var.image_id, security_groups = [module.security.group_ids["slurm-login"]], key_pair = var.ssh_key_name
    }
    slurm_cpu_01 = {
      name = "slurm-cpu-01", network_id = module.network.mgmt_network_id, subnet_id = module.network.mgmt_subnet_id, fixed_ip = var.node_fixed_ips["slurm_cpu_01"], flavor_name = var.compute_12c_flavor, image_id = var.image_id, security_groups = [module.security.group_ids["slurm-compute"]], key_pair = var.ssh_key_name
    }
    slurm_cpu_02 = {
      name = "slurm-cpu-02", network_id = module.network.mgmt_network_id, subnet_id = module.network.mgmt_subnet_id, fixed_ip = var.node_fixed_ips["slurm_cpu_02"], flavor_name = var.compute_12c_flavor, image_id = var.image_id, security_groups = [module.security.group_ids["slurm-compute"]], key_pair = var.ssh_key_name
    }
    slurm_cpu_03 = {
      name = "slurm-cpu-03", network_id = module.network.mgmt_network_id, subnet_id = module.network.mgmt_subnet_id, fixed_ip = var.node_fixed_ips["slurm_cpu_03"], flavor_name = var.compute_64c_flavor, image_id = var.image_id, security_groups = [module.security.group_ids["slurm-compute"]], key_pair = var.ssh_key_name
    }
    slurm_cpu_04 = {
      name = "slurm-cpu-04", network_id = module.network.mgmt_network_id, subnet_id = module.network.mgmt_subnet_id, fixed_ip = var.node_fixed_ips["slurm_cpu_04"], flavor_name = var.compute_64c_flavor, image_id = var.image_id, security_groups = [module.security.group_ids["slurm-compute"]], key_pair = var.ssh_key_name
    }
    k8s_cp_01 = {
      name = "k8s-cp-01", network_id = module.network.k8s_network_id, subnet_id = module.network.k8s_subnet_id, fixed_ip = var.node_fixed_ips["k8s_cp_01"], flavor_name = var.k8s_control_plane_flavor, image_id = var.image_id, security_groups = [module.security.group_ids["k8s-control-plane"]], key_pair = var.ssh_key_name
    }
    k8s_cp_02 = {
      name = "k8s-cp-02", network_id = module.network.k8s_network_id, subnet_id = module.network.k8s_subnet_id, fixed_ip = var.node_fixed_ips["k8s_cp_02"], flavor_name = var.k8s_control_plane_flavor, image_id = var.image_id, security_groups = [module.security.group_ids["k8s-control-plane"]], key_pair = var.ssh_key_name
    }
    k8s_cp_03 = {
      name = "k8s-cp-03", network_id = module.network.k8s_network_id, subnet_id = module.network.k8s_subnet_id, fixed_ip = var.node_fixed_ips["k8s_cp_03"], flavor_name = var.k8s_control_plane_flavor, image_id = var.image_id, security_groups = [module.security.group_ids["k8s-control-plane"]], key_pair = var.ssh_key_name
    }
    k8s_worker_01 = {
      name = "k8s-worker-01", network_id = module.network.k8s_network_id, subnet_id = module.network.k8s_subnet_id, fixed_ip = var.node_fixed_ips["k8s_worker_01"], flavor_name = var.k8s_worker_flavor, image_id = var.image_id, security_groups = [module.security.group_ids["k8s-worker"]], key_pair = var.ssh_key_name
    }
    k8s_worker_02 = {
      name = "k8s-worker-02", network_id = module.network.k8s_network_id, subnet_id = module.network.k8s_subnet_id, fixed_ip = var.node_fixed_ips["k8s_worker_02"], flavor_name = var.k8s_worker_flavor, image_id = var.image_id, security_groups = [module.security.group_ids["k8s-worker"]], key_pair = var.ssh_key_name
    }
    k8s_worker_03 = {
      name = "k8s-worker-03", network_id = module.network.k8s_network_id, subnet_id = module.network.k8s_subnet_id, fixed_ip = var.node_fixed_ips["k8s_worker_03"], flavor_name = var.k8s_worker_flavor, image_id = var.image_id, security_groups = [module.security.group_ids["k8s-worker"]], key_pair = var.ssh_key_name
    }
  }
}

locals {
  jupyter_nodes = {
    for key, node in var.jupyter_workers :
    key => {
      name            = node.name
      network_id      = module.network.k8s_network_id
      subnet_id       = module.network.k8s_subnet_id
      fixed_ip        = node.fixed_ip
      flavor_name     = coalesce(try(node.flavor_name, null), var.k8s_worker_flavor)
      image_id        = var.image_id
      security_groups = [module.security.group_ids["k8s-worker"]]
      key_pair        = var.ssh_key_name
    }
  }
}

module "compute" {
  source = "../../modules/compute"
  nodes  = merge(local.nodes, local.jupyter_nodes)
}

# Optional Octavia example omitted from the public topology template.
# Use var.api_lb_address and private control-plane addresses from var.node_fixed_ips.

resource "openstack_networking_floatingip_v2" "edge" {
  pool = var.external_network_name
}

resource "openstack_networking_floatingip_associate_v2" "edge" {
  floating_ip = openstack_networking_floatingip_v2.edge.address
  port_id     = module.compute.port_ids["edge"]
}

resource "openstack_networking_router_route_v2" "wireguard" {
  router_id        = module.network.router_id
  destination_cidr = var.vpn_cidr
  next_hop         = var.node_fixed_ips["edge"]
}
