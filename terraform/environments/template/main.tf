module "network" {
  source                = "../../modules/network"
  name_prefix           = "infra-hpc-qc-k8s"
  external_network_name = var.external_network_name
  mgmt_cidr             = "10.50.0.0/24"
  k8s_cidr              = "10.51.0.0/24"
  mgmt_gateway_ip       = "10.50.0.1"
  k8s_gateway_ip        = "10.51.0.1"
  mgmt_pool_start       = "10.50.0.50"
  mgmt_pool_end         = "10.50.0.240"
  k8s_pool_start        = "10.51.0.50"
  k8s_pool_end          = "10.51.0.99"
}

module "security" {
  source             = "../../modules/security"
  name_prefix        = "infra-hpc-qc-k8s"
  bootstrap_ssh_cidr = var.bootstrap_ssh_cidr
  vpn_cidr           = "10.60.0.0/24"
  mgmt_cidr          = "10.50.0.0/24"
  k8s_cidr           = "10.51.0.0/24"
}

locals {
  nodes = {
    edge = {
      name = "edge", network_id = module.network.mgmt_network_id, subnet_id = module.network.mgmt_subnet_id, fixed_ip = "10.50.0.10", flavor_name = var.edge_flavor, image_id = var.image_id, security_groups = [module.security.group_ids["edge"]], key_pair = var.ssh_key_name
    }
    hermes = {
      name = "hermes-orchestrator-01", network_id = module.network.mgmt_network_id, subnet_id = module.network.mgmt_subnet_id, fixed_ip = "10.50.0.11", flavor_name = var.hermes_flavor, image_id = var.image_id, security_groups = [module.security.group_ids["hermes-orchestrator"]], key_pair = var.ssh_key_name
    }
    slurm_controller = {
      name = "slurm-controller-01", network_id = module.network.mgmt_network_id, subnet_id = module.network.mgmt_subnet_id, fixed_ip = "10.50.0.12", flavor_name = var.slurm_controller_flavor, image_id = var.image_id, security_groups = [module.security.group_ids["slurm-controller"]], key_pair = var.ssh_key_name
    }
    login1 = {
      name = "login1", network_id = module.network.mgmt_network_id, subnet_id = module.network.mgmt_subnet_id, fixed_ip = "10.50.0.20", flavor_name = var.login_flavor, image_id = var.image_id, security_groups = [module.security.group_ids["slurm-login"]], key_pair = var.ssh_key_name
    }
    login2 = {
      name = "login2", network_id = module.network.mgmt_network_id, subnet_id = module.network.mgmt_subnet_id, fixed_ip = "10.50.0.21", flavor_name = var.login_flavor, image_id = var.image_id, security_groups = [module.security.group_ids["slurm-login"]], key_pair = var.ssh_key_name
    }
    slurm_cpu_01 = {
      name = "slurm-cpu-01", network_id = module.network.mgmt_network_id, subnet_id = module.network.mgmt_subnet_id, fixed_ip = "10.50.0.30", flavor_name = var.compute_32c_flavor, image_id = var.image_id, security_groups = [module.security.group_ids["slurm-compute"]], key_pair = var.ssh_key_name
    }
    slurm_cpu_02 = {
      name = "slurm-cpu-02", network_id = module.network.mgmt_network_id, subnet_id = module.network.mgmt_subnet_id, fixed_ip = "10.50.0.31", flavor_name = var.compute_32c_flavor, image_id = var.image_id, security_groups = [module.security.group_ids["slurm-compute"]], key_pair = var.ssh_key_name
    }
    k8s_cp_01 = {
      name = "k8s-cp-01", network_id = module.network.k8s_network_id, subnet_id = module.network.k8s_subnet_id, fixed_ip = "10.51.0.11", flavor_name = var.k8s_control_plane_flavor, image_id = var.image_id, security_groups = [module.security.group_ids["k8s-control-plane"]], key_pair = var.ssh_key_name
    }
    k8s_cp_02 = {
      name = "k8s-cp-02", network_id = module.network.k8s_network_id, subnet_id = module.network.k8s_subnet_id, fixed_ip = "10.51.0.12", flavor_name = var.k8s_control_plane_flavor, image_id = var.image_id, security_groups = [module.security.group_ids["k8s-control-plane"]], key_pair = var.ssh_key_name
    }
    k8s_cp_03 = {
      name = "k8s-cp-03", network_id = module.network.k8s_network_id, subnet_id = module.network.k8s_subnet_id, fixed_ip = "10.51.0.13", flavor_name = var.k8s_control_plane_flavor, image_id = var.image_id, security_groups = [module.security.group_ids["k8s-control-plane"]], key_pair = var.ssh_key_name
    }
    k8s_worker_01 = {
      name = "k8s-worker-01", network_id = module.network.k8s_network_id, subnet_id = module.network.k8s_subnet_id, fixed_ip = "10.51.0.21", flavor_name = var.k8s_worker_flavor, image_id = var.image_id, security_groups = [module.security.group_ids["k8s-worker"]], key_pair = var.ssh_key_name
    }
    k8s_worker_02 = {
      name = "k8s-worker-02", network_id = module.network.k8s_network_id, subnet_id = module.network.k8s_subnet_id, fixed_ip = "10.51.0.22", flavor_name = var.k8s_worker_flavor, image_id = var.image_id, security_groups = [module.security.group_ids["k8s-worker"]], key_pair = var.ssh_key_name
    }
    k8s_worker_03 = {
      name = "k8s-worker-03", network_id = module.network.k8s_network_id, subnet_id = module.network.k8s_subnet_id, fixed_ip = "10.51.0.23", flavor_name = var.k8s_worker_flavor, image_id = var.image_id, security_groups = [module.security.group_ids["k8s-worker"]], key_pair = var.ssh_key_name
    }
  }
}

module "compute" {
  source = "../../modules/compute"
  nodes  = local.nodes
}

module "octavia" {
  source        = "../../modules/octavia"
  name          = "infra-hpc-qc-k8s-api"
  vip_subnet_id = module.network.k8s_subnet_id
  vip_address   = "10.51.0.100"
  control_plane_ips = {
    cp01 = "10.51.0.11"
    cp02 = "10.51.0.12"
    cp03 = "10.51.0.13"
  }
}

resource "openstack_networking_floatingip_v2" "edge" {
  pool = var.external_network_name
}

resource "openstack_networking_floatingip_associate_v2" "edge" {
  floating_ip = openstack_networking_floatingip_v2.edge.address
  port_id     = module.compute.port_ids["edge"]
}

resource "openstack_networking_router_route_v2" "wireguard" {
  router_id        = module.network.router_id
  destination_cidr = "10.60.0.0/24"
  next_hop         = "10.50.0.10"
}
