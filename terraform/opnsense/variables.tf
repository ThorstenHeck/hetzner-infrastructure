variable "IMAGE" {
  type    = string
  default = "opnsense"
}

variable "HCLOUD_TOKEN" {
  type = string
}

variable "OPNSENSE_USER_PASSWORD" {
  type = string
}

variable "SSH_KEY_NAME" {
  type = string
}

variable "SSH_PRIVATE_KEY_FILE" {
  type    = string
}