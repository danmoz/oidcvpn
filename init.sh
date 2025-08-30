#!/bin/bash
set -e

# Run Easy-RSA in batch mode and set default Common Name for CA
export EASYRSA_BATCH=1
export EASYRSA_REQ_CN="OpenVPN-CA"

# Check required env var for S3 bucket URI
if [ -z "$OIDCVPN_S3_URI" ]; then
  echo "Error: OIDCVPN_S3_URI environment variable not set."
  exit 1
fi

# Create a dedicated temporary directory
TMPDIR=$(mktemp -d /tmp/openvpn-init-XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

# Easy-RSA location
EASYRSA_DIR="/usr/share/easy-rsa"
EASYRSA_PKI="$TMPDIR/pki"

# Check for Easy-RSA
if ! command -v easyrsa >/dev/null 2>&1; then
  echo "Easy-RSA not found. Please install Easy-RSA."
  exit 1
fi

# Check for AWS CLI
if ! command -v aws >/dev/null 2>&1; then
  echo "AWS CLI not found. Please install awscli to upload to S3."
  exit 1
fi

# Generate files in TMPDIR
cd "$TMPDIR"

# Initialize PKI
if [ ! -d "$EASYRSA_PKI" ]; then
  easyrsa init-pki
fi

# Build CA
if [ ! -f "$EASYRSA_PKI/ca.crt" ]; then
  easyrsa build-ca nopass
fi
cp "$EASYRSA_PKI/ca.crt" "$TMPDIR/ca.crt"

# Set Common Name for server cert
export EASYRSA_REQ_CN="server"

# Generate server key and cert
if [ ! -f "$EASYRSA_PKI/private/server.key" ]; then
  easyrsa gen-req server nopass
fi
if [ ! -f "$EASYRSA_PKI/issued/server.crt" ]; then
  easyrsa sign-req server server
fi
cp "$EASYRSA_PKI/issued/server.crt" "$TMPDIR/server.crt"
cp "$EASYRSA_PKI/private/server.key" "$TMPDIR/server.key"

# Generate DH params
if [ ! -f "$EASYRSA_PKI/dh.pem" ]; then
  easyrsa gen-dh
fi
cp "$EASYRSA_PKI/dh.pem" "$TMPDIR/dh.pem"

# Generate TLS auth key
test -f "$TMPDIR/ta.key" || openvpn --genkey --secret "$TMPDIR/ta.key"

# Generate default server.conf if missing
if [ ! -f "$TMPDIR/server.conf" ]; then
  cat <<EOF > "$TMPDIR/server.conf"
port 1194
proto udp
dev tun
user nobody
group nogroup
persist-key
persist-tun
keepalive 10 120
topology subnet
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt
ca /etc/openvpn/ca.crt
cert /etc/openvpn/server.crt
key /etc/openvpn/server.key
dh /etc/openvpn/dh.pem
tls-server
tls-auth /etc/openvpn/ta.key 0
cipher AES-256-GCM
auth SHA256
verb 3
EOF
fi

# Upload to S3
for f in ca.crt server.crt server.key dh.pem ta.key server.conf; do
  aws s3 cp "$TMPDIR/$f" "$OIDCVPN_S3_URI/$f" || { echo "Failed to upload $f to S3"; exit 1; }
  echo "Generated $f in $TMPDIR"
done

# Output summary
echo "Generated files in $TMPDIR:"
ls -l "$TMPDIR" | grep -E '(ca.crt|server.crt|server.key|dh.pem|ta.key|server.conf)'

echo "Temporary directory $TMPDIR will be deleted."
