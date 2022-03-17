#!/bin/bash

while getopts "spc" opt; do
  case $opt in
    s) SKIP_SSH="true"
    ;;
    p) SKIP_PACKER="true"
    ;;
    c) SKIP_CA="true"
    ;;
    \?) echo "Invalid option -$OPTARG" >&2
    ;;
  esac
done

echo "Setup Hetzner Environment"

python3 $HOME/build/hetzner_login.py -cg

if [ -f "$HOME/build/apitoken.env" ]
then
source $HOME/build/apitoken.env
rm $HOME/build/apitoken.env
fi
if [[ -z "${HCLOUD_TOKEN}" ]]
then
  echo "HCLOUD_TOKEN not found - please export it as an environment variable"
  exit 1
else
  echo "check if Token is valid"
  INVALID_TOKEN=$(curl -s -H "Authorization: Bearer $HCLOUD_TOKEN" 'https://api.hetzner.cloud/v1/actions' | jq .error)
fi

if [[ $INVALID_TOKEN = "null" ]]
then
  echo "Valid Token"
else
  echo "Invalid Token - please check your API Token"
  exit 1
fi

if [[ -z "${OPNSENSE_USER_PASSWORD}" ]]
then
  echo "OPNSENSE_USER_PASSWORD not found - please export it as an environment variable"
  exit 1  
fi

if [[ -z "${OPNSENSE_ROOT_PASSWORD}" ]]
then
  echo "OPNSENSE_ROOT_PASSWORD not found - please export it as an environment variable"
  exit 1  
fi

if [[ -z "${OPNSENSE_USER}" ]]
then
  echo "OPNSENSE_USER not found - please export it as an environment variable"
  exit 1  
fi

mkdir -p $HOME/.ssh

if [ "$SKIP_SSH" = true ]
then
echo 'Skip SSH-Key creation!'
if [ -f "$HOME/.ssh/$OPNSENSE_USER" ]
then
OPNSENSE_SSH_PUB_RAW=$(cat $HOME/.ssh/$OPNSENSE_USER.pub)
OPNSENSE_SSH_PUB=$(cat $HOME/.ssh/$OPNSENSE_USER.pub | base64 -w 0)
OPNSENSE_SSH_PRIV=$(realpath "$HOME/.ssh/$OPNSENSE_USER")
else
echo "no valid SSH-Key found - please move your matching SSH-Key to: " $HOME/.ssh/$OPNSENSE_USER
exit 1
fi
else
echo "Create SSH-Key Pair"
ssh-keygen -t ed25519 -f $HOME/.ssh/$OPNSENSE_USER -C $OPNSENSE_USER -q -N ''
SSH_PUB=$(cat $HOME/.ssh/$OPNSENSE_USER.pub)

cat <<EOF > $HOME/data.json
{"labels":{},"name":"$OPNSENSE_USER","public_key":"$SSH_PUB"}
EOF
DATA=$HOME/data.json

SSH_LIST=$(curl -s -H "Authorization: Bearer $HCLOUD_TOKEN" 'https://api.hetzner.cloud/v1/ssh_keys' | jq .meta.pagination.total_entries)
if [ "$SSH_LIST" -eq "0" ]
then
curl -s -X POST -H "Authorization: Bearer $HCLOUD_TOKEN" -H "Content-Type: application/json" -d @$DATA 'https://api.hetzner.cloud/v1/ssh_keys' >  /dev/null 2>& 1
else
SSH_KEY_ID=$(curl -s -H "Authorization: Bearer $HCLOUD_TOKEN" 'https://api.hetzner.cloud/v1/ssh_keys' | jq --arg USER $OPNSENSE_USER '.[][] | select(.name==$USER) | .id')
    if [ -z "$SSH_KEY_ID" ]
    then
    curl -s -X POST -H "Authorization: Bearer $HCLOUD_TOKEN" -H "Content-Type: application/json" -d @$DATA 'https://api.hetzner.cloud/v1/ssh_keys' >  /dev/null 2>& 1
    else
    curl -s -X DELETE -H "Authorization: Bearer $HCLOUD_TOKEN" -H "Content-Type: application/json" 'https://api.hetzner.cloud/v1/ssh_keys/'$SSH_KEY_ID >  /dev/null 2>& 1
    curl -s -X POST -H "Authorization: Bearer $HCLOUD_TOKEN" -H "Content-Type: application/json" -d @$DATA 'https://api.hetzner.cloud/v1/ssh_keys' >  /dev/null 2>& 1
    fi
fi
OPNSENSE_SSH_PUB_RAW=$(cat $HOME/.ssh/$OPNSENSE_USER.pub)
OPNSENSE_SSH_PUB=$(cat $HOME/.ssh/$OPNSENSE_USER.pub | base64 -w 0)
OPNSENSE_SSH_PRIV=$(realpath "$HOME/.ssh/$OPNSENSE_USER")

rm $DATA
fi

########################################
### opnsense base auth configuration ###
########################################
OPNSENSE_ROOT_HASH=$(htpasswd -bnBC 10 "" $OPNSENSE_ROOT_PASSWORD | tr -d ':\n')
OPNSENSE_USER_HASH=$(htpasswd -bnBC 10 "" $OPNSENSE_USER_PASSWORD | tr -d ':\n')
VPN_USER_HASH=$(htpasswd -bnBC 10 "" $VPN_USER_PASSWORD | tr -d ':\n')

cp $HOME/build/config.template.xml packer/opnsense/config.xml

sed -i 's|OPNSENSE_USER\b|'"$OPNSENSE_USER"'|g' packer/opnsense/config.xml
sed -i 's|OPNSENSE_ROOT_HASH\b|'"$OPNSENSE_ROOT_HASH"'|g' packer/opnsense/config.xml
sed -i 's|OPNSENSE_USER_HASH\b|'"$OPNSENSE_USER_HASH"'|g' packer/opnsense/config.xml
sed -i 's|OPNSENSE_SSH_PUB\b|'"$OPNSENSE_SSH_PUB"'|g' packer/opnsense/config.xml

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
rm $HOME/terraform.env

################################################
### Create CA - Creat Client and Server Cert ###
################################################

if [ "$SKIP_CA" = true ]
then
echo 'Skip creation of root CA!'
else

bash $HOME/build/ca.sh -c

VPN_CA=$(cat $HOME/ca/root/ca/certs/ca.cert.pem | base64 -w 0)
VPN_CA_KEY=$(cat $HOME/ca/root/ca/private/ca.key.pem | base64 -w 0)
VPN_CLIENT=$(cat $HOME/ca/root/ca/certs/openvpn_client.cert.pem | base64 -w 0)
VPN_CLIENT_KEY=$(cat $HOME/ca/root/ca/private/client.key.pem | base64 -w 0)
VPN_SERVER=$(cat $HOME/ca/root/ca/certs/openvpn_server.cert.pem | base64 -w 0)
VPN_SERVER_KEY=$(cat $HOME/ca/root/ca/private/server.key.pem | base64 -w 0)
VPN_CA_RAW=$(cat $HOME/ca/root/ca/certs/ca.cert.pem)
VPN_CLIENT_RAW=$(cat $HOME/ca/root/ca/certs/openvpn_client.cert.pem)
VPN_CLIENT_KEY_RAW=$(cat $HOME/ca/root/ca/private/client.key.pem)

#########################################
### OpeenVPN - create openvpn file    ###
#########################################

openvpn --genkey secret static.key

VPN_STATIC_KEY_RAW=$(cat static.key)
VPN_STATIC_KEY=$(cat static.key | base64 -w 0)

fi
###########################################
### Ansible - configure opnsense server ###
###########################################

# export all further needed environment vars

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

eval $(ssh-agent -s) && ssh-add $HOME/.ssh/$OPNSENSE_USER

########################################
###   packer - create base images    ###
########################################

if [ "$SKIP_PACKER" = true ]
then
echo 'Skip Packer Image creation!'
else

packer init packer/freebsd.pkr.hcl
packer build -var ssh_keypair_name=$OPNSENSE_USER -var ssh_private_key_file=$OPNSENSE_SSH_PRIV -except=hcloud.opnsense packer/freebsd.pkr.hcl
packer build -var ssh_keypair_name=$OPNSENSE_USER -var ssh_private_key_file=$OPNSENSE_SSH_PRIV -only=hcloud.opnsense packer/freebsd.pkr.hcl
fi

# terraform - create server

terraform -chdir=terraform/opnsense init
terraform -chdir=terraform/opnsense apply -auto-approve
WAN_PUBLIC_IP=$(terraform output -state=terraform/opnsense/terraform.tfstate -json | jq .WAN_Interface_Public.value | tr -d '"')

# terraform - create network

terraform -chdir=terraform/create-network init
terraform -chdir=terraform/create-network apply -auto-approve

# add opnsense server to a network with static ip

terraform -chdir=terraform/join-network init
terraform -chdir=terraform/join-network apply -var IP=$OPNSENSE_LOCAL_IP -var NETWORK_NAME=$NETWORK_NAME -var SERVER_NAME=opnsense -auto-approve

if [ "$SKIP_CA" = true ]
then
echo 'Skip creation of opnvpn File!'
else
cat <<EOF > $HOME/vpn.opnvpn
dev tun
persist-tun
persist-key
cipher AES-256-CBC
auth SHA512
client
resolv-retry infinite
reneg-sec 0
remote $WAN_PUBLIC_IP 1194 udp
lport 0
verify-x509-name "C=DE, ST=Germany, O=hetzner, OU=opnsense, CN=opnsense.root_server.local" subject
remote-cert-tls server
auth-user-pass
<ca>
$VPN_CA_RAW
</ca>
<cert>
$VPN_CLIENT_RAW
</cert>
<key>
$VPN_CLIENT_KEY_RAW
</key>
<tls-auth>
$VPN_STATIC_KEY_RAW
</tls-auth>
key-direction 1
EOF
fi
# change network name of hcloud.yml for dynamic inventory

sed -i "s|NETWORK_NAME|$NETWORK_NAME|g" $HOME/ansible/environments/hetzner/hcloud.yml

# create local inventory for opnsense to connect via public ip

cat <<EOF > $HOME/ansible/environments/hetzner/opnsense.inventory
[local]
localhost ansible_connection=local

[opnsense]
opnsense ansible_host=$WAN_PUBLIC_IP
EOF

cd $HOME/ansible

ansible-playbook -i environments/hetzner/opnsense.inventory playbooks/__opnsense.yml --tags fetch,ca,vpn,interfaces,user,general,filter,copy

ansible-playbook -i environments/hetzner/opnsense.inventory playbooks/__opnsense.yml --tags reload_no_wait

cd $HOME

export OPNSENSE_LOCAL_IP=$OPNSENSE_LOCAL_IP

echo "set up vpn connection inside container"

cat <<EOF > $HOME/pass.txt
$VPN_USER
$VPN_USER_PASSWORD
EOF

sudo openvpn --config vpn.opnvpn --auth-user-pass pass.txt --daemon

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

if [ "$SKIP_CA" = true ]
then
echo 'Skip creation of intermediate CA!'
else
# create intermediate cert 
bash $HOME/build/ca.sh -p

cd $HOME/terraform/vault/pki/ica1

terraform init
terraform apply -auto-approve

VAULT_ICA1_PATH=$(terraform output -json | jq .vault_ica1_path.value | tr -d '"')
export TF_VAR_VAULT_ICA1_PATH=$VAULT_ICA1_PATH

# create csr of ica1
terraform show -json | jq '.values["root_module"]["resources"][].values.csr' -r | grep -v null > $HOME/ca/root/ca/intermediate/csr/hetzner_v1_ICA1_v1.csr

cd $HOME

bash $HOME/build/ca.sh -i

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

# create client cert for 1.test.com
cd $HOME/terraform/vault/pki/cert

terraform init
terraform apply -auto-approve

vault write -format=json hetzner/v1/ica2/v1/issue/test-dot-com-subdomain \
   common_name=1.test.com | jq .data.certificate -r | openssl x509 -in /dev/stdin -text -noout

fi

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

###########################################
### Print useful information in the end ###
###########################################

if [ "$SKIP_SSH" != true ]
then
echo ""
echo ""
# SSH Key Generation output
echo "########## Privat Key File ##########"
echo ""
echo "$(cat $OPNSENSE_SSH_PRIV)"
echo ""
echo "########## Public Key File ##########"
echo ""
echo $OPNSENSE_SSH_PUB_RAW
echo ""
echo "######################################"
echo ""
echo "To copy the whole ssh Folder to your current directory, execute:"
echo ""
echo 'docker cp $(docker ps -aqf "name=hetzner-infra"):/home/hetzner/.ssh .'
fi

echo ""
echo ""
echo "To copy opnvpn from container to host execute this on your host system:"
echo ""
echo 'docker cp $(docker ps -aqf "name=hetzner-infra"):/home/hetzner/vpn.opnvpn .'
echo ""
echo ""
echo "For Ubuntu using NetworkManager - you can run this to add the VPN connection"
echo ""
echo 'nmcli connection import type openvpn file vpn.opnvpn'
echo 'nmcli connection modify vpn +vpn.data username='$VPN_USER
echo 'nmcli connection modify vpn ipv4.never-default true'
echo 'nmcli con up id vpn'

echo ""
echo "######################################"
echo ""
echo "If you succesfully connected to the VPN continue the script"

# read -rsn1 -p"Press any key to continue";echo


# ps aux
# sudo pkill -f "openvpn --config"