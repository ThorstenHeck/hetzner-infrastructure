provider "vault" {
    
}

locals {
 default_3y_in_sec   = 94608000
 default_1y_in_sec   = 31536000
 default_1hr_in_sec = 3600
}

resource "vault_pki_secret_backend_role" "role" {
  backend            = var.VAULT_ICA2_PATH
  name               = "test-dot-com-subdomain"
  ttl                = local.default_1hr_in_sec
  allow_ip_sans      = true
  key_type           = "rsa"
  key_bits           = 2048
  key_usage          = [ "DigitalSignature"]
  allow_any_name     = false
  allow_localhost    = false
  allowed_domains    = ["test.com"]
  allow_bare_domains = false
  allow_subdomains   = true
  server_flag        = false
  client_flag        = true
  no_store           = true
  country            = ["DE"]
  locality           = ["Berlin"]
  province           = ["Germany"]
}

variable "VAULT_ICA2_PATH" {
  type = string
}