#!/bin/bash

OPNSENSE_SSH_PUB_RAW=$(cat $HOME/.ssh/$OPNSENSE_USER.pub)
OPNSENSE_SSH_PUB=$(cat $HOME/.ssh/$OPNSENSE_USER.pub | base64 -w 0)
OPNSENSE_SSH_PRIV=$(realpath "$HOME/.ssh/$OPNSENSE_USER")

OPNSENSE_ROOT_HASH=$(htpasswd -bnBC 10 "" $OPNSENSE_ROOT_PASSWORD | tr -d ':\n')
OPNSENSE_USER_HASH=$(htpasswd -bnBC 10 "" $OPNSENSE_USER_PASSWORD | tr -d ':\n')
VPN_USER_HASH=$(htpasswd -bnBC 10 "" $VPN_USER_PASSWORD | tr -d ':\n')

#########################################
### Terraform - create infrastructure ###
#########################################

cat <<EOF > $HOME/terraform.env
export TF_VAR_HCLOUD_TOKEN=$HCLOUD_TOKEN
export TF_VAR_SSH_PRIVATE_KEY_FILE=$OPNSENSE_SSH_PRIV
export TF_VAR_SSH_KEY_NAME=$OPNSENSE_USER
export TF_VAR_OPNSENSE_USER_PASSWORD=$OPNSENSE_USER_PASSWORD
export TF_VAR_NETWORK_NAME=$NETWORK_NAME
export TF_VAR_IP_RANGE=$IP_RANGE
export TF_VAR_SUB_IP_RANGE=$SUB_IP_RANGE
EOF
source  $HOME/terraform.env

bash $HOME/build/ca.sh

VPN_CA=$(cat $HOME/ca/root/ca/certs/ca.cert.pem | base64 -w 0)
VPN_CA_KEY=$(cat $HOME/ca/root/ca/private/ca.key.pem | base64 -w 0)
VPN_CLIENT=$(cat $HOME/ca/root/ca/certs/openvpn_client.cert.pem | base64 -w 0)
VPN_CLIENT_KEY=$(cat $HOME/ca/root/ca/private/client.key.pem | base64 -w 0)
VPN_SERVER=$(cat $HOME/ca/root/ca/certs/openvpn_server.cert.pem | base64 -w 0)
VPN_SERVER_KEY=$(cat $HOME/ca/root/ca/private/server.key.pem | base64 -w 0)
VPN_CA_RAW=$(cat $HOME/ca/root/ca/certs/ca.cert.pem)
VPN_CLIENT_RAW=$(cat $HOME/ca/root/ca/certs/openvpn_client.cert.pem)
VPN_CLIENT_KEY_RAW=$(cat $HOME/ca/root/ca/private/client.key.pem)

VPN_STATIC_KEY_RAW=$(cat static.key)
VPN_STATIC_KEY=$(cat static.key | base64 -w 0)

export VPN_CA=$VPN_CA
export VPN_CA_KEY=$VPN_CA_KEY
export VPN_CLIENT=$VPN_CLIENT
export VPN_CLIENT_KEY=$VPN_CLIENT_KEY
export VPN_SERVER=$VPN_SERVER
export VPN_SERVER_KEY=$VPN_SERVER_KEY
export VPN_CA_RAW=$VPN_CA_RAW
export VPN_CLIENT_RAW=$VPN_CLIENT_RAW
export VPN_CLIENT_KEY_RAW=$VPN_CLIENT_KEY_RAW
export VPN_STATIC_KEY_RAW=$VPN_STATIC_KEY_RAW
export VPN_STATIC_KEY=$VPN_STATIC_KEY
export OPNSENSE_SSH_PUB=$OPNSENSE_SSH_PUB
export OPNSENSE_SSH_PUB_RAW=$OPNSENSE_SSH_PUB_RAW
export OPNSENSE_ROOT_HASH=$OPNSENSE_ROOT_HASH
export OPNSENSE_USER_HASH=$OPNSENSE_USER_HASH
export VPN_USER_HASH=$VPN_USER_HASH

cd $HOME

echo "set up vpn connection inside container"

cat <<EOF > $HOME/pass.txt
$VPN_USER
$VPN_USER_PASSWORD
EOF

#sudo openvpn --config vpn.opnvpn --auth-user-pass pass.txt --daemon

export OPNSENSE_LOCAL_IP=$OPNSENSE_LOCAL_IP
export VAULT_LOCAL_IP=$VAULT_LOCAL_IP

terraform -chdir=terraform/vault init

echo "build vault"
terraform -chdir=terraform/vault apply -var IP=$VAULT_LOCAL_IP -var NETWORK_NAME=$NETWORK_NAME -var SSH_KEY_NAME=$OPNSENSE_USER -auto-approve

# get root_token

while true
do
    if scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $OPNSENSE_SSH_PRIV $OPNSENSE_USER@$VAULT_LOCAL_IP:/etc/vault.d/tokens.init .
    then
        echo "transfer OK"
        break
    fi
    sleep 15
done

VAULT_TOKEN=$(awk 'NR==7{print $4}' tokens.init)
export TF_VAR_VAULT_TOKEN=$VAULT_TOKEN
export VAULT_TOKEN=$VAULT_TOKEN

export TF_VAR_VAULT_ADDR=http://$VAULT_LOCAL_IP:8200
export VAULT_ADDR=http://$VAULT_LOCAL_IP:8200

cd $HOME/terraform/vault/pki/ica1

terraform init
terraform apply -auto-approve

VAULT_ICA1_PATH=$(terraform output -json | jq .vault_ica1_path.value | tr -d '"')
export TF_VAR_VAULT_ICA1_PATH=$VAULT_ICA1_PATH

# create intermediate cert 
root_ca_dir=$HOME/ca/root/ca
intermediate_ca_dir=$HOME/ca/root/ca/intermediate
mkdir -p $intermediate_ca_dir/csr

# create csr of ica1
terraform show -json | jq '.values["root_module"]["resources"][].values.csr' -r | grep -v null > $HOME/ca/root/ca/intermediate/csr/hetzner_v1_ICA1_v1.csr

cd $intermediate_ca_dir

mkdir certs crl newcerts private
touch index.txt
echo 1000 > serial

# get fresh config file
wget -O openssl.cnf https://jamielinux.com/docs/openssl-certificate-authority/_downloads/intermediate-config.txt >  /dev/null 2>& 1

# adjust config file
sed -i "s|/root/ca/intermediate|$intermediate_ca_dir|g" openssl.cnf

cd $root_ca_dir

openssl ca -batch -config openssl.cnf -extensions v3_intermediate_ca \
      -days 3650 -notext -md sha256 \
      -in intermediate/csr/hetzner_v1_ICA1_v1.csr \
      -out intermediate/certs/Intermediate_CA1_v1.crt

openssl verify -CAfile certs/ca.cert.pem \
      intermediate/certs/Intermediate_CA1_v1.crt
# create the certificate chain file
cat intermediate/certs/Intermediate_CA1_v1.crt \
      certs/ca.cert.pem > intermediate/certs/ca-chain.cert.pem

cd $HOME/terraform/vault/pki/ica_csr

terraform init
terraform apply -auto-approve

# Verify ICA1 cert in Vault
curl -s $VAULT_ADDR/v1/hetzner/v1/ica1/v1/ca/pem | openssl crl2pkcs7 -nocrl -certfile  /dev/stdin  | openssl pkcs7 -print_certs -noout

# Verifiy ICA1 CA chhain in Vault
curl -s $VAULT_ADDR/v1/hetzner/v1/ica1/v1/ca_chain | openssl crl2pkcs7 -nocrl -certfile  /dev/stdin  | openssl pkcs7 -print_certs -noout

cd $HOME/terraform/vault/pki/ica2

terraform init
terraform apply -auto-approve

VAULT_ICA2_PATH=$(terraform output -json | jq .vault_ica2_path.value | tr -d '"')
export TF_VAR_VAULT_ICA2_PATH=$VAULT_ICA2_PATH

# Verify ICA2 cert in Vault
curl -s $VAULT_ADDR/v1/hetzner/v1/ica2/v1/ca/pem | openssl crl2pkcs7 -nocrl -certfile  /dev/stdin  | openssl pkcs7 -print_certs -noout

# Verify ICA2 CA chain in Vault
curl -s $VAULT_ADDR/v1/hetzner/v1/ica2/v1/ca_chain | openssl crl2pkcs7 -nocrl -certfile  /dev/stdin  | openssl pkcs7 -print_certs -noout

# Run ICA2 x509 certificate constraint check
curl -s $VAULT_ADDR/v1/hetzner/v1/ica2/v1/ca/pem | openssl x509 -in /dev/stdin -noout -text | grep "X509v3 extensions"  -A 13

cd $HOME/terraform/vault/pki/cert

terraform init
terraform apply -auto-approve

vault write -format=json hetzner/v1/ica2/v1/issue/test-dot-com-subdomain \
   common_name=1.test.com | jq .data.certificate -r | openssl x509 -in /dev/stdin -text -noout

vault secrets enable -path=opnsense kv
vault secrets enable -path=terraform kv
vault secrets enable -path=vault kv

vault kv put opnsense/vpn VPN_CLIENT=$VPN_CLIENT VPN_vpn=$VPN_vpn VPN_vpn_KEY=$VPN_vpn_KEY VPN_CLIENT_KEY=$VPN_CLIENT_KEY VPN_SERVER=$VPN_SERVER VPN_SERVER_KEY=$VPN_SERVER_KEY VPN_vpn_RAW=$VPN_vpn_RAW VPN_CLIENT_RAW=$VPN_CLIENT_RAW VPN_CLIENT_KEY_RAW=$VPN_CLIENT_KEY_RAW VPN_STATIC_KEY_RAW=$VPN_STATIC_KEY_RAW VPN_STATIC_KEY=$VPN_STATIC_KEY
vault kv put opnsense/user VPN_USER=$VPN_USER VPN_USER_PASSWORD=$VPN_USER_PASSWORD OPNSENSE_USER=$OPNSENSE_USER VPN_USER_HASH=$VPN_USER_HASH OPNSENSE_USER_HASH=$OPNSENSE_USER_HASH OPNSENSE_ROOT_HASH=$OPNSENSE_ROOT_HASH
vault kv put opnsense/ssh OPNSENSE_SSH_PUB=$OPNSENSE_SSH_PUB OPNSENSE_SSH_PUB_RAW=$OPNSENSE_SSH_PUB_RAW
vault kv put opnsense/network WAN_PUBLIC_IP=$WAN_PUBLIC_IP OPNSENSE_LOCAL_IP=$OPNSENSE_LOCAL_IP

vault kv put terraform/general TF_VAR_HCLOUD_TOKEN=$HCLOUD_TOKEN TF_VAR_SSH_KEY_NAME=$OPNSENSE_USER
vault kv put terraform/ssh TF_VAR_SSH_PRIVATE_KEY_FILE=$OPNSENSE_SSH_PRIV TF_VAR_OPNSENSE_USER_PASSWORD=$OPNSENSE_USER_PASSWORD
vault kv put terraform/network TF_VAR_NETWORK_NAME=$NETWORK_NAME TF_VAR_IP_RANGE=$IP_RANGE TF_VAR_SUB_IP_RANGE=$SUB_IP_RANGE

vault kv put vault/auth VAULT_TOKEN=$VAULT_TOKEN
vault kv put vault/network VAULT_LOCAL_IP=$VAULT_LOCAL_IP TF_VAR_VAULT_ADDR=$VAULT_ADDR
vault kv put vault/pki TF_VAR_VAULT_ICA1_PATH=$VAULT_ICA1_PATH TF_VAR_VAULT_ICA2_PATH=$VAULT_ICA2_PATH