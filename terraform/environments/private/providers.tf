variable "openstack_cloud" { type = string }
variable "openstack_region" { type = string }

provider "openstack" {
  cloud  = var.openstack_cloud
  region = var.openstack_region
}
