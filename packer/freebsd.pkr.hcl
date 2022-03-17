packer {
  required_plugins {
    hcloud = {
      version = ">= 1.2.0"
      source = "github.com/ThorstenHeck/hcloud"
    }
  }
}

variable "hcloud_token" {
  type    = string
  default = "${env("HCLOUD_TOKEN")}"
}

variable "ssh_key" {
  type    = string
  default = "${env("OPNSENSE_USER")}"
}

variable "ssh_private_key_file" {
  type    = string
  default = "${env("OPNSENSE_SSH_PRIV")}"
}

variable "ssh_keypair_name" {
  type    = string
  default = "${env("OPNSENSE_USER")}"
}

variable "playbook_file_init" {
  type    = string
  default = "/home/hetzner/ansible/playbooks/initial_setup.yml"
}


locals {
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")
  time      = timestamp()
}

source "hcloud" "freebsd" {
  rescue      = "freebsd64"
  image       = "debian-11"
  location    = "nbg1"
  server_name = "packer-freebsd"
  server_type = "cx11"
  snapshot_labels = {
    name = "freebsd"
  }
  snapshot_name = "freebsd-${local.timestamp}"
  ssh_username  = "root"
  token         = "${var.hcloud_token}"
  ssh_private_key_file = "${var.ssh_private_key_file}"
  ssh_keypair_name = "${var.ssh_keypair_name}"
}

source "hcloud" "opnsense" {
  image_filter {
    most_recent   = true
    with_selector = ["name==freebsd"]
  }
  location    = "nbg1"
  server_name = "packer-opnsense"
  server_type = "cx11"
  snapshot_labels = {
    name = "opnsense"
  }
  snapshot_name = "opnsense-${local.timestamp}"
  ssh_username  = "root"
  token         = "${var.hcloud_token}"
  ssh_private_key_file = "${var.ssh_private_key_file}"
  ssh_keypair_name = "${var.ssh_keypair_name}"
}

source "hcloud" "debian-base" {
  image       = "debian-11"
  location    = "nbg1"
  server_name = "packer-debian-base"
  server_type = "cx11"
  snapshot_labels = {
    name = "debian-base"
  }
  snapshot_name = "debian-base-${local.timestamp}"
  ssh_username  = "root"
  token         = "${var.hcloud_token}"
  ssh_private_key_file = "${var.ssh_private_key_file}"
  ssh_keypair_name = "${var.ssh_keypair_name}"
}

build {

  source "source.hcloud.freebsd" {
  }

  provisioner "file" {
    source = "./packer/freebsd/bsdinstall.script"
    destination = "/tmp/bsdinstall.script"
  }

  provisioner "shell" {
    environment_vars = [
    ]
    inline = [
      "bsdinstall -D install.log script /tmp/bsdinstall.script"
    ]
  }  

}

build {

  source "source.hcloud.opnsense" {
  }

  provisioner "file" {
    source = "./packer/opnsense/config.xml"
    destination = "config.xml"
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; env {{ .Vars }} {{ .Path }}"
    inline = [
      "env ASSUME_ALWAYS_YES=YES pkg install ca_root_nss",
      "fetch https://raw.githubusercontent.com/opnsense/update/master/src/bootstrap/opnsense-bootstrap.sh.in",
      "sed -i \"\" \"s/reboot/#reboot/g\" opnsense-bootstrap.sh.in",
      "mkdir -p /usr/local/etc/",
      "cp config.xml /usr/local/etc/config.xml",
      "sh ./opnsense-bootstrap.sh.in -r 22.1 -y",
    ]
  }

}

build {

  source "source.hcloud.debian-base" {
  }

  provisioner "ansible" {
    ansible_env_vars = ["ANSIBLE_ROLES_PATH=/home/hetzner/ansible/roles"]
    inventory_directory = "/home/hetzner/ansible/environments/hetzner"
    playbook_file = "${var.playbook_file_init}"
    use_proxy = false
  }
}