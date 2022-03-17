variable "HOSTNAME" {
  type    = string
  default = "vault"
}

variable "DOMAIN" {
  type    = string
  default = "local"
}

variable "HCLOUD_TOKEN" {
  type = string
}

variable "SSH_KEY_NAME" {
  type = string
}

variable "IMAGE" {
  type    = string
  default = "debian-base"
}

variable "IP" {
  type    = string
}

variable "NETWORK_NAME" {
  type = string
}