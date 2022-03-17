resource "hcloud_network" "network" {
  name     = var.NETWORK_NAME
  ip_range = var.IP_RANGE
}

resource "hcloud_network_subnet" "subnet" {
  network_id   = hcloud_network.network.id
  type         = "cloud"
  network_zone = "eu-central"
  ip_range = var.SUB_IP_RANGE
}