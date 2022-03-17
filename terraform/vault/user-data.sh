#!/bin/sh

ufw allow in on ens10 from 10.1.0.2 to any port 8200 proto tcp

# Install python3 (pip3 included) and dependencies
apt-get update
apt-get -y upgrade
apt-get -y install \
    python3 \
    python3-dev \
    python3-pip \
    jq \
    curl \
    unzip \
  && rm -rf /var/cache/*

ln -s /usr/bin/pip3 /usr/bin/pip

apt install software-properties-common -y
curl -fsSL https://apt.releases.hashicorp.com/gpg | apt-key add -
apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main" && apt update

# Install terraform
# shellcheck disable=SC2006
# avoid using alpha versions of TF >= 1.0.9
export TF_VER=`curl -sL https://releases.hashicorp.com/terraform/index.json | jq -r '.versions[].builds[].url | select(.|contains("1.0.9")) | select(.|contains("linux_amd64"))' | sort -V | tail -1 | grep terraform | cut -d '_' -f 2`
wget  https://releases.hashicorp.com/terraform/$TF_VER/terraform\_$TF_VER\_linux_amd64.zip \
  && unzip terraform\_$TF_VER\_linux_amd64.zip \
  && mv terraform /usr/bin \
  && rm terraform\_$TF_VER\_linux_amd64.zip
terraform --version

# Vault CLI
#apt install vault
wget --quiet https://releases.hashicorp.com/vault/1.8.4/vault_1.8.4_linux_amd64.zip \
  && unzip vault_1.8.4_linux_amd64.zip -d /usr/bin/ \
  && rm vault_1.8.4_linux_amd64.zip

# Create Vault directories
mkdir -p /etc/vault.d/
mkdir -p /opt/vault/data
mkdir -p /opt/vault/data/core
# mkdir -p /opt/vault/plugins

# # Install 1password plugin
# wget --quiet https://github.com/1Password/vault-plugin-secrets-onepassword/releases/download/v1.0.0/vault-plugin-secrets-onepassword_1.0.0_linux_amd64.zip \
#   && unzip vault-plugin-secrets-onepassword_1.0.0_linux_amd64.zip -d /opt/vault/plugins/ \
#   && rm vault-plugin-secrets-onepassword_1.0.0_linux_amd64.zip /opt/vault/plugins/CHANGELOG.md  /opt/vault/plugins/LICENSE  /opt/vault/plugins/README.md

#TODO: Due to fact that Hetzner doesn't accept templates for cloud-init configs, we can't parametrize below licenses, find a solution!!!
cat << EOF > /etc/vault.d/vault.hcl

storage "file" {
  path = "/opt/vault/data"
}

# HTTPS
#listener "tcp" {
#  address     = "127.0.0.1:8200"
#  tls_cert_file = "/etc/vault.d/vault.crt"
#  tls_key_file  = "/etc/vault.d/vault.key"
#  tls_client_ca_file = "/etc/vault.d/ca.crt"
#  tls_require_and_verify_client_cert = "false"
#}

#HTTP
listener "tcp" {
  address     = "${ip}:8200"
  tls_disable = 1
}

cluster_addr = "https://${ip}:8201"
api_addr = "http://${ip}:8200"

disable_mlock = true
ui=true

plugin_directory = "/opt/vault/plugins"

EOF

cp /etc/vault.d/ca.crt /usr/local/share/ca-certificates/hashicorp.crt
update-ca-certificates

useradd --system  --home /etc/vault.d vault

chown -R vault:vault /etc/vault.d/
chown -R vault:vault /opt/vault/


#create vault service for systemd
touch /etc/systemd/system/vault.service

cat >/etc/systemd/system/vault.service <<'EOF'
[Unit]
Description="HashiCorp Vault - A tool for managing secrets"
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/vault.d/vault.hcl
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
User=vault
Group=vault
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
SecureBits=keep-caps
AmbientCapabilities=CAP_IPC_LOCK
Capabilities=CAP_IPC_LOCK+ep
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
NoNewPrivileges=yes
ExecStart=/usr/bin/vault server -config=/etc/vault.d/vault.hcl -address=http://${ip}:8200
ExecReload=/bin/kill --signal HUP $MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
StartLimitInterval=60
StartLimitIntervalSec=60
StartLimitBurst=3
LimitNOFILE=65536
LimitMEMLOCK=infinity
LogRateLimitIntervalSec=0
LogRateLimitBurst=0

[Install]
WantedBy=multi-user.target

EOF

systemctl enable vault

#systemctl start vault
systemctl start vault
chown -R vault:vault /opt/vault/

# switch to vault user to unseal and basic configuration
sudo -u vault bash

export VAULT_ADDR='http://${ip}:8200'

sleep 5

vault operator init > /etc/vault.d/tokens.init

unseal_token_1=$(awk 'NR==1{print $4}' /etc/vault.d/tokens.init)
unseal_token_2=$(awk 'NR==2{print $4}' /etc/vault.d/tokens.init)
unseal_token_3=$(awk 'NR==3{print $4}' /etc/vault.d/tokens.init)
root_token=$(awk 'NR==7{print $4}' /etc/vault.d/tokens.init)

vault operator unseal $unseal_token_1
vault operator unseal $unseal_token_2
vault operator unseal $unseal_token_3


# vault login $root_token

# # Register OP plugin
# vault write sys/plugins/catalog/secret/op-connect sha_256="$(shasum -a 256 /opt/vault/plugins/vault-plugin-secrets-onepassword_v1.0.0 | cut -d " " -f1)" command="vault-plugin-secrets-onepassword_v1.0.0"

# vault secrets enable --plugin-name='op-connect' --path="op" plugin

# cat >/etc/vault.d/root_token_input.json <<'EOF'
# {
#   "category": "password",
#   "title": "Vault_Root_Token",
#   "fields": [
#     {
#       "id": "password",
#       "label": "vault",
#       "purpose": "PASSWORD",
#       "type": "CONCEALED",
#       "value": ""
#     }
#   ]
# }
# EOF

# jq --arg token $root_token 'select(.fields[].value).fields[].value |= $token' /etc/vault.d/root_token_input.json > /etc/vault.d/root_token.json

# vault write op/vaults/pcqpnafo7kk6smdf2jsxhpewi4/items/ @/etc/vault.d/root_token.json