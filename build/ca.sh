#!/bin/bash

while getopts "cip" opt; do
  case $opt in
    c) CA="true"
    ;;
    i) ICA="true"
    ;;
    p) PREP_ICA="true"
    ;;
    \?) echo "Invalid option -$OPTARG" >&2
    ;;
  esac
done

if [ "$CA" = true ]
then
## create root ca
root_ca_dir=$HOME/ca/root/ca
mkdir -p $root_ca_dir
cd $root_ca_dir

mkdir certs crl newcerts csr private
touch index.txt
echo 1000 > serial

# get fresh config file
wget -O openssl.cnf https://jamielinux.com/docs/openssl-certificate-authority/_downloads/root-config.txt >  /dev/null 2>& 1

# adjust config file
sed -i "s|/root/ca|$root_ca_dir|g" openssl.cnf

sed -i "s|GB|DE|g" openssl.cnf
sed -i "s|England|Germany|g" openssl.cnf
sed -i "s|Alice Ltd|hetzner|g" openssl.cnf
sed -i "s|organizationalUnitName_default  =|organizationalUnitName_default  = hetzner|g" openssl.cnf
sed -i "s|emailAddress_default            =|emailAddress_default            = hetzner@hetzner.org|g" openssl.cnf
sed -i "s|localityName_default            =|localityName_default            = Berlin|g" openssl.cnf

sed -i "s|utf8only|default|g" openssl.cnf
sed -i "s|pathlen:0|pathlen:1|g" openssl.cnf

openssl genrsa -out private/ca.key.pem 4096 >  /dev/null 2>& 1

# create root certificate

openssl req -config openssl.cnf \
      -subj "/C=DE/ST=Germany/L=Berlin/O=hetzner/OU=hetzner/CN=hetzner.local/emailAddress=hetzner@hetzner.org" \
      -key private/ca.key.pem \
      -new -x509 -days 7300 -sha256 -extensions v3_ca \
      -out certs/ca.cert.pem  >  /dev/null 2>& 1

## create client and server certificate

### server cert
# create a key
openssl genrsa -out private/server.key.pem 2048  >  /dev/null 2>& 1

# create certificate signing request server
openssl req -config openssl.cnf \
      -subj "/C=DE/ST=Germany/L=Berlin/O=hetzner/OU=opnsense/CN=opnsense.root_server.local" \
      -key private/server.key.pem \
      -new -sha256 -out csr/server.csr.pem  >  /dev/null 2>& 1

# create server certificate
openssl ca -batch -config openssl.cnf \
      -extensions server_cert -days 375 -notext -md sha256 \
      -in csr/server.csr.pem \
      -out certs/openvpn_server.cert.pem  >  /dev/null 2>& 1

# client certificate
openssl genrsa -out private/client.key.pem 2048  >  /dev/null 2>& 1

# create certificate signing request client

openssl req -config openssl.cnf \
      -subj "/C=DE/ST=Germany/L=Berlin/O=hetzner/OU=opnsense/CN=opnsense.root_client.local" \
      -key private/client.key.pem \
      -new -sha256 -out csr/client.csr.pem  >  /dev/null 2>& 1

# create client certificate
openssl ca -batch -config openssl.cnf \
      -extensions usr_cert -days 375 -notext -md sha256 \
      -in csr/client.csr.pem \
      -out certs/openvpn_client.cert.pem  >  /dev/null 2>& 1
fi


if [ "$PREP_ICA" = true ]
then
# create intermediate cert 
intermediate_ca_dir=$HOME/ca/root/ca/intermediate
mkdir -p $intermediate_ca_dir/csr

cd $intermediate_ca_dir

mkdir certs crl newcerts private
touch index.txt
echo 1000 > serial

# get fresh config file
wget -O openssl.cnf https://jamielinux.com/docs/openssl-certificate-authority/_downloads/intermediate-config.txt >  /dev/null 2>& 1

# adjust config file
sed -i "s|/root/ca/intermediate|$intermediate_ca_dir|g" openssl.cnf
fi

if [ "$ICA" = true ]
then
root_ca_dir=$HOME/ca/root/ca
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
fi