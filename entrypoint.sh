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

# Configure rclone for S3 (using environment variables)
export RCLONE_CONFIG_S3_TYPE=s3
export RCLONE_CONFIG_S3_PROVIDER=AWS
export RCLONE_CONFIG_S3_ENV_AUTH=true
export RCLONE_CONFIG_S3_NO_CHECK_BUCKET=true

# Sync the S3 bucket URI to /etc/openvpn using rclone
rclone sync "s3:${OIDCVPN_S3_URI#s3://}" /etc/openvpn || { echo "Failed to sync S3 bucket URI to /etc/openvpn"; exit 1; }

# Start OpenVPN
exec openvpn --config /etc/openvpn/server.conf
