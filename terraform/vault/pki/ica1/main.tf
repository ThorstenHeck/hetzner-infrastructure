provider "vault" {
    
}

locals {
 default_3y_in_sec   = 94608000
 default_1y_in_sec   = 31536000
 default_1hr_in_sec = 3600
}

resource "vault_mount" "hetzner_v1_ica1_v1" {
  path                      = "hetzner/v1/ica1/v1"
  type                      = "pki"
  description               = "PKI engine hosting intermediate CA1 v1 for hetzner"
  default_lease_ttl_seconds = local.default_1hr_in_sec
  max_lease_ttl_seconds     = local.default_3y_in_sec
}

resource "vault_pki_secret_backend_intermediate_cert_request" "hetzner_v1_ica1_v1" {
  depends_on   = [vault_mount.hetzner_v1_ica1_v1]
  backend      = vault_mount.hetzner_v1_ica1_v1.path
  type         = "internal"
  common_name  = "Intermediate CA1 v1 "
  key_type     = "rsa"
  key_bits     = "4096"
  ou           = "hetzner"
  organization = "hetzner"
  country      = "DE"
  locality     = "Berlin"
  province     = "Germany"
}

locals {
  vault_ica1_path = vault_mount.hetzner_v1_ica1_v1.path
}

output "vault_ica1_path" {
  value = "${local.vault_ica1_path}"
}