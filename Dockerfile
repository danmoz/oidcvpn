# Use official Debian as base
FROM debian:bullseye-slim

# Install dependencies
RUN apt-get update && \
    apt-get install -y openvpn wget ca-certificates easy-rsa && \
    rm -rf /var/lib/apt/lists/*

# Download and install rclone
RUN wget -O /tmp/rclone.deb https://downloads.rclone.org/rclone-current-linux-amd64.deb && \
    dpkg -i /tmp/rclone.deb && \
    rm /tmp/rclone.deb

# Download and install openvpn-auth-oauth2
RUN wget -O /tmp/openvpn-auth-oauth2.deb https://github.com/jkroepke/openvpn-auth-oauth2/releases/download/v1.25.2/openvpn-auth-oauth2_1.25.2_linux_amd64.deb && \
    dpkg -i /tmp/openvpn-auth-oauth2.deb && \
    rm /tmp/openvpn-auth-oauth2.deb

# Copy scripts
COPY entrypoint.sh /entrypoint.sh
COPY init.sh /init.sh

# Grant execute permissions to scripts and symlink easyrsa
RUN chmod +x /init.sh /entrypoint.sh && \
    ln -s /usr/share/easy-rsa/easyrsa /usr/local/bin/easyrsa && \
    mkdir -p /etc/openvpn

# Expose OpenVPN port
EXPOSE 1194/udp

# Entrypoint
ENTRYPOINT ["/entrypoint.sh"]
