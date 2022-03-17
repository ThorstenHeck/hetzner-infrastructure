resource "hcloud_server" "server" {
  name        = "opnsense"
  server_type = "cx11"
  image       = data.hcloud_image.image.id
  location    = "nbg1"
  ssh_keys    = [data.hcloud_ssh_key.ssh-key.name]
  keep_disk   = true
  labels      = {
    "opnsense" = ""
  }
  connection {
    type     = "ssh"
    user     = data.hcloud_ssh_key.ssh-key.name
    password = var.OPNSENSE_USER_PASSWORD
    host     = self.ipv4_address
    private_key = "${file(var.SSH_PRIVATE_KEY_FILE)}"
  }

  provisioner "remote-exec" {
    inline = [
      "echo ${var.OPNSENSE_USER_PASSWORD} | sudo -S reboot -r",
    ]
  }
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
  public_ip = join("", hcloud_server.server.*.ipv4_address)
}
output "WAN_Interface_Public" {
  value = "${local.public_ip}"
}