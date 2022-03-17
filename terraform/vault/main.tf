resource "hcloud_server" "vault" {
  name        = "vault"
  server_type = "cx11"
  image       = data.hcloud_image.image.id
  location    = "nbg1"
  ssh_keys    = [data.hcloud_ssh_key.ssh-key.name]
  user_data     = templatefile("${path.module}/user-data.sh", {
    ip = var.IP
    hostname = "${var.HOSTNAME}.${var.DOMAIN}"
  })
  keep_disk   = true
  labels      = {
    "vault" = ""
  }
  network {
      network_id = data.hcloud_network.network.id
      ip = var.IP
  }
}

data "hcloud_network" "network" {
  name = var.NETWORK_NAME
}

data "hcloud_ssh_key" "ssh-key" {
  name = "${var.SSH_KEY_NAME}"
}

data "hcloud_image" "image" {
  with_selector = "name=${var.IMAGE}"
  most_recent = true
}

provider "hcloud" {
  token = var.HCLOUD_TOKEN
}

locals {
  public_ip = join("", hcloud_server.vault.*.ipv4_address)
}
output "WAN_Interface_Public" {
  value = "${local.public_ip}"
}