provider "vault" {
    
}

locals {
 default_3y_in_sec   = 94608000
 default_1y_in_sec   = 31536000
 default_1hr_in_sec = 3600
}

resource "vault_mount" "hetzner_v1_ica2_v1" {
  path                      = "hetzner/v1/ica2/v1"
  type                      = "pki"
  description               = "PKI engine hosting intermediate CA2 v1 for hetzner"
  default_lease_ttl_seconds = local.default_1hr_in_sec
  max_lease_ttl_seconds     = local.default_1y_in_sec
}

resource "vault_pki_secret_backend_intermediate_cert_request" "hetzner_v1_ica2_v1" {
  depends_on   = [vault_mount.hetzner_v1_ica2_v1]
  backend      = vault_mount.hetzner_v1_ica2_v1.path
  type         = "internal"
  common_name  = "Intermediate CA2 v1 "
  key_type     = "rsa"
  key_bits     = "2048"
  ou           = "hetzner"
  organization = "hetzner"
  country      = "DE"
  locality     = "Berlin"
  province     = "Germany"
}

resource "vault_pki_secret_backend_root_sign_intermediate" "hetzner_v1_sign_ica2_v1_by_ica1_v1" {
  backend              = var.VAULT_ICA1_PATH
  csr                  = vault_pki_secret_backend_intermediate_cert_request.hetzner_v1_ica2_v1.csr
  common_name          = "Intermediate CA2 v1.1"
  exclude_cn_from_sans = true
  ou                   = "hetzner"
  organization         = "hetzner"
  country              = "DE"
  locality             = "Berlin"
  province             = "Germany"
  max_path_length      = 1
  ttl                  = local.default_1y_in_sec
}

resource "vault_pki_secret_backend_intermediate_set_signed" "hetzner_v1_ica2_v1_signed_cert" {
  depends_on  = [vault_pki_secret_backend_root_sign_intermediate.hetzner_v1_sign_ica2_v1_by_ica1_v1]
  backend     = vault_mount.hetzner_v1_ica2_v1.path
  certificate = format("%s\n%s", vault_pki_secret_backend_root_sign_intermediate.hetzner_v1_sign_ica2_v1_by_ica1_v1.certificate, file("/home/hetzner/ca/root/ca/intermediate/certs/ca-chain.cert.pem"))
}

variable "VAULT_ICA1_PATH" {
  type = string
}

locals {
  vault_ica2_path = vault_mount.hetzner_v1_ica2_v1.path
}

output "vault_ica2_path" {
  value = "${local.vault_ica2_path}"
}