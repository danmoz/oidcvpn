# Use official Debian as base
FROM debian:bullseye-slim

# Install dependencies
RUN apt-get update && \
    apt-get install -y openvpn wget build-essential gcc g++ git libcurl4-openssl-dev libssl-dev libjansson-dev ca-certificates awscli easy-rsa && \
    rm -rf /var/lib/apt/lists/*

# Install Go 1.25+
ENV GO_VERSION=1.25.0
RUN wget https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz && \
    rm go${GO_VERSION}.linux-amd64.tar.gz
ENV PATH="/usr/local/go/bin:$PATH"

# Build and install openvpn-auth-oauth2 plugin
RUN git clone --depth 1 https://github.com/jkroepke/openvpn-auth-oauth2.git /opt/openvpn-auth-oauth2 && \
    cd /opt/openvpn-auth-oauth2 && \
    go build -buildmode=plugin -o openvpn-auth-oauth2.so && \
    mkdir -p /usr/lib/openvpn/plugins/ && \
    cp openvpn-auth-oauth2.so /usr/lib/openvpn/plugins/

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh

# Copy init script
COPY init.sh /init.sh

# Grant execute permissions to scripts and symlink easyrsa
RUN chmod +x /init.sh /entrypoint.sh && \
    ln -s /usr/share/easy-rsa/easyrsa /usr/local/bin/easyrsa

# Create OpenVPN config directory
RUN mkdir -p /etc/openvpn

# Expose OpenVPN port
EXPOSE 1194/udp

# Entrypoint
ENTRYPOINT ["/entrypoint.sh"]
