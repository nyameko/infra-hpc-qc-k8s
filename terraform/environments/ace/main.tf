module "ace" {
  source = "../../modules/federated_gpu_site"

  name_prefix           = "ace"
  external_network_name = var.external_network_name

  private_cidr       = var.private_cidr
  private_gateway_ip = var.private_gateway_ip
  private_pool_start = var.private_pool_start
  private_pool_end   = var.private_pool_end
  dns_nameservers    = var.dns_nameservers

  edge_fixed_ip            = var.edge_fixed_ip
  gpu_fixed_ip             = var.gpu_fixed_ip
  edge_floating_ip_address = var.edge_floating_ip_address

  edge_image_id    = var.edge_image_id
  gpu_image_id     = var.gpu_image_id
  edge_flavor_name = var.edge_flavor_name
  gpu_flavor_name  = var.gpu_flavor_name
  key_pair         = var.key_pair

  bootstrap_ssh_cidrs     = var.bootstrap_ssh_cidrs
  wireguard_ingress_cidrs = var.wireguard_ingress_cidrs
  remote_routed_cidrs     = var.remote_routed_cidrs
  wireguard_port          = var.wireguard_port

  model_volume_size_gb = var.model_volume_size_gb
  model_volume_type    = var.model_volume_type
}
