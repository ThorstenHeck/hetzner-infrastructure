provider "vault" {
    
}

locals {
 default_3y_in_sec   = 94608000
 default_1y_in_sec   = 31536000
 default_1hr_in_sec = 3600
}

resource "vault_pki_secret_backend_intermediate_set_signed" "hetzner_v1_ica1_v1_signed_cert" {
  backend      = var.VAULT_ICA1_PATH
  certificate = file("/home/hetzner/ca/root/ca/intermediate/certs/ca-chain.cert.pem")
}

variable "VAULT_ICA1_PATH" {
  type = string
}