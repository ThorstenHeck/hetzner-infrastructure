## Opnsense Hetzner-infrastructure

## First steps

Get the environment variable example, edit it and source it:

    wget https://raw.githubusercontent.com/ThorstenHeck/hetzner-infrastructure/master/build/secret.env

Edit

    nano secret.env

Source

    source secret.env


Pull Container

    docker pull thorstenheck0/hetzner-opnsense:hetzner-infrastructure:latest

Run Container

    docker run -it --name hetzner-infrastructure \
    --device /dev/net/tun \
    --cap-add=NET_ADMIN \
    -e OPNSENSE_USER=$OPNSENSE_USER \
    -e OPNSENSE_USER_PASSWORD=$OPNSENSE_USER_PASSWORD \
    -e OPNSENSE_ROOT_PASSWORD=$OPNSENSE_ROOT_PASSWORD \
    -e PROJECT=$PROJECT \
    -e USERNAME=$HETZNER_USERNAME \
    -e PASSWORD=$PASSWORD \
    -e PERMISSIONS="Read & Write" \
    -e VPN_USER=$VPN_USER \
    -e VPN_GROUP=$VPN_GROUP \
    -e VPN_USER_PASSWORD=$VPN_USER_PASSWORD \
    -e NETWORK_NAME=$NETWORK_NAME \
    -e IP_RANGE=$IP_RANGE \
    -e SUB_IP_RANGE=$SUB_IP_RANGE \
    -e ROOT_PASSWORD=$ROOT_PASSWORD \
    -e VAULT_LOCAL_IP=$VAULT_LOCAL_IP \
    thorstenheck0/hetzner-infrastructure:latest bash

Inside the container execute:

    bash hetzner_setup.sh