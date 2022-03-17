resource "hcloud_server_network" "server_network" {
  server_id  = data.hcloud_server.server.id
  network_id = data.hcloud_network.network.id
  ip         = var.IP
}

data "hcloud_network" "network" {
  name = var.NETWORK_NAME
}

data "hcloud_server" "server" {
  name = var.SERVER_NAME
}