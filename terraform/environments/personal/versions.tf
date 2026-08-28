terraform {
  required_version = ">= 1.9.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "3.4.0"
    }
  }
}

provider "openstack" {
  cloud  = var.openstack_cloud
  region = var.openstack_region
}
