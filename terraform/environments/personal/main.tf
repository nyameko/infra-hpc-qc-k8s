module "network" {
  source = "../../modules/network"
  name_prefix        = var.name_prefix
  external_network_id = var.external_network_id
  mgmt_cidr           = "10.50.0.0/24"
  mgmt_pool_start     = "10.50.0.50"
  mgmt_pool_end       = "10.50.0.240"
  k8s_cidr            = "10.51.0.0/24"
  k8s_pool_start      = "10.51.0.50"
  k8s_pool_end        = "10.51.0.99"
  dns_nameservers     = var.dns_nameservers
  edge_admin_ip       = "10.50.0.10"
  wireguard_cidr      = "10.60.0.0/24"
}

module "security" {
  source = "../../modules/security"
  name_prefix       = var.name_prefix
  k8s_cidr          = "10.51.0.0/24"
  bootstrap_ssh_cidr = var.bootstrap_ssh_cidr
  internal_cidrs    = ["10.50.0.0/24", "10.51.0.0/24", "10.60.0.0/24"]
}

module "compute" {
  source = "../../modules/compute"
  name_prefix              = var.name_prefix
  external_network_name   = var.external_network_name
  image_id                = var.image_id
  key_pair_name           = var.key_pair_name
  edge_flavor             = var.edge_flavor
  control_plane_flavor    = var.control_plane_flavor
  worker_flavor           = var.worker_flavor
  mgmt_network_id         = module.network.mgmt_network_id
  mgmt_subnet_id           = module.network.mgmt_subnet_id
  k8s_network_id          = module.network.k8s_network_id
  k8s_subnet_id            = module.network.k8s_subnet_id
  edge_sg_id               = module.security.edge_sg_id
  control_plane_sg_id      = module.security.control_plane_sg_id
  worker_sg_id             = module.security.worker_sg_id
  edge_ip                  = "10.50.0.10"
  edge_cloud_init          = file("${path.module}/cloud-init-edge.yaml")
  node_cloud_init_template = "${path.module}/cloud-init-node.yaml"
}

module "octavia" {
  source = "../../modules/octavia"
  name_prefix       = var.name_prefix
  k8s_subnet_id     = module.network.k8s_subnet_id
  control_plane_ips = module.compute.control_plane_ips
  vip_address       = "10.51.0.100"
}
