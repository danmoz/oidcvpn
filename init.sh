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

# Test AWS credentials and check for existing files in one operation
echo "Testing AWS credentials and checking for existing files..."

# Configure rclone for S3 (using environment variables)
export RCLONE_CONFIG_S3_TYPE=s3
export RCLONE_CONFIG_S3_PROVIDER=AWS
export RCLONE_CONFIG_S3_ENV_AUTH=true
export RCLONE_CONFIG_S3_NO_CHECK_BUCKET=true

# Capture stdout separately from stderr to avoid NOTICE messages being treated as files
S3_LISTING=$(rclone lsf "s3:${OIDCVPN_S3_URI#s3://}/" 2>/dev/null)
RCLONE_EXIT_CODE=$?

# Check if rclone command failed (credentials/permissions issue)
if [ $RCLONE_EXIT_CODE -ne 0 ]; then
  # Re-run with stderr to get error details
  S3_ERROR=$(rclone lsf "s3:${OIDCVPN_S3_URI#s3://}/" 2>&1 >/dev/null)
  if echo "$S3_ERROR" | grep -q "NoSuchBucket\|AccessDenied\|InvalidAccessKeyId\|SignatureDoesNotMatch"; then
    echo "Error: Failed to access S3 bucket"
    echo "Please check:"
    echo "  - AWS credentials are configured correctly"
    echo "  - The bucket exists and you have permissions"
    echo "  - The S3 URI format is correct (s3://bucket/path)"
    exit 1
  elif echo "$S3_ERROR" | grep -q "directory not found"; then
    # Directory doesn't exist - that's fine, we'll create it
    echo "S3 directory doesn't exist. Proceeding with initialization..."
  else
    echo "Error: Unexpected rclone error:"
    echo "$S3_ERROR"
    exit 1
  fi
elif [ -n "$S3_LISTING" ]; then
  # Directory exists and contains files (check only stdout content, not stderr notices)
  echo "Error: S3 directory $OIDCVPN_S3_URI already contains files:"
  echo "$S3_LISTING"
  echo ""
  echo "Please either:"
  echo "  - Delete existing files: rclone delete s3:${OIDCVPN_S3_URI#s3://}/"
  echo "  - Use a different S3 path"
  exit 1
else
  # Directory exists but is empty (or doesn't exist)
  echo "S3 directory is empty or doesn't exist. Proceeding with initialization..."
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

# Check for rclone
if ! command -v rclone >/dev/null 2>&1; then
  echo "rclone not found. Please install rclone to upload to S3."
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

# Generate default server.conf
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
auth-user-pass-verify /usr/bin/openvpn-auth-oauth2 via-env
script-security 2
EOF
fi

# Generate default oauth2.yaml
if [ ! -f "$TMPDIR/oauth2.yaml" ]; then
  cat <<EOF > "$TMPDIR/oauth2.yaml"
# openvpn-auth-oauth2 plugin YAML config template for Google OIDC
client_id: "YOUR_GOOGLE_CLIENT_ID"
client_secret: "YOUR_GOOGLE_CLIENT_SECRET"
issuer: "https://accounts.google.com"
redirect_uri: "https://vpn.example.com/callback"
extra_scopes: "openid email profile"
user_name_field: "email" # or "sub"
# See plugin docs for more options
EOF
fi

# Upload to S3
for f in ca.crt server.crt server.key dh.pem ta.key server.conf oauth2.yaml; do
  rclone copy "$TMPDIR/$f" "s3:${OIDCVPN_S3_URI#s3://}/" || { echo "Failed to upload $f to S3"; exit 1; }
  echo "Generated $f in $TMPDIR"
done

# Output summary
echo "Generated files in $TMPDIR:"
ls -l "$TMPDIR" | grep -E '(ca.crt|server.crt|server.key|dh.pem|ta.key|server.conf|oauth2.yaml)'

echo "Temporary directory $TMPDIR will be deleted."
