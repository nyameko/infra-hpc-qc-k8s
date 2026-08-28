variable "nodes" {
  type = map(object({
    name            = string
    network_id      = string
    subnet_id       = string
    fixed_ip        = string
    flavor_name     = string
    image_id        = string
    security_groups = list(string)
    key_pair        = string
    user_data       = optional(string)
  }))
}
