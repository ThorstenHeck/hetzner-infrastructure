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

VAULT_ICA1_PATH=$(terraform output -json | jq .vault_ica1_path.value | tr -d '"')
export TF_VAR_VAULT_ICA1_PATH=$VAULT_ICA1_PATH

terraform destroy -auto-approve

cd $HOME/terraform/vault/pki/ica_csr

terraform destroy -auto-approve

cd $HOME/terraform/vault/pki/ica2

VAULT_ICA2_PATH=$(terraform output -json | jq .vault_ica2_path.value | tr -d '"')
export TF_VAR_VAULT_ICA2_PATH=$VAULT_ICA2_PATH

terraform destroy -auto-approve

cd $HOME/terraform/vault/pki/cert

terraform destroy -auto-approve

rm -rf $HOME/ca