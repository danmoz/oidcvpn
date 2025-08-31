#!/bin/bash
set -e

# If the first argument is /init.sh, just run it and exit
if [[ "$1" == "/init.sh" ]]; then
  exec /init.sh
fi

# Clean up any leftover temp directories from init.sh
rm -rf /tmp/openvpn-init-*

# Check required env var for S3 bucket URI
if [ -z "$OIDCVPN_S3_URI" ]; then
  echo "OIDCVPN_S3_URI environment variable not set; no configuration downloaded."
  exit 1
fi

# Sync the S3 bucket URI to /etc/openvpn
aws s3 sync "$OIDCVPN_S3_URI" /etc/openvpn || { echo "Failed to sync S3 bucket URI to /etc/openvpn"; exit 1; }

# Start OpenVPN
exec openvpn --config /etc/openvpn/server.conf
