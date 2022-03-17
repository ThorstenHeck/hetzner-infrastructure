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

  source "source.hcloud.debian-base" {
  }

  provisioner "ansible" {
    ansible_env_vars = ["ANSIBLE_ROLES_PATH=/home/hetzner/ansible/roles"]
    inventory_directory = "/home/hetzner/ansible/environments/hetzner"
    playbook_file = "${var.playbook_file_init}"
    use_proxy = false
  }

  post-processor "manifest" {
    output = "manifest.json"
    strip_path = true
      custom_data = {
        Source_Name = "${source.name}"
        Playbook_File = "${var.playbook_file_init}"
        Build_At = "${local.time}"
    }
  }  
}