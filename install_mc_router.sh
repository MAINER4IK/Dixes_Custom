#!/bin/bash

# Script to install, configure, and uninstall mc-router and frp on Ubuntu
# for Minecraft server reverse proxy with dynamic port assignment

# Exit on error
set -e

# Server configuration
PUBLIC_IP="31.25.235.168"
DOMAIN="local.xneon.org"
FRP_PORT=7000
MIN_PORT=5000
MAX_PORT=6000
COMPOSE_FILE="/opt/mc-router/docker-compose.yml"
FRP_CONFIG_DIR="/opt/mc-router/frp"
FRP_TOKEN="your-secure-frp-token" # Replace with a secure token
MC_ROUTER_IMAGE="itzg/mc-router:latest"
FRP_VERSION="0.60.0"

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to generate a random port
generate_random_port() {
    shuf -i $MIN_PORT-$MAX_PORT -n 1
}

# Function to install dependencies (Docker and Docker Compose)
install_dependencies() {
    echo "Installing dependencies..."

    # Update package list
    sudo apt-get update

    # Install prerequisites
    sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common

    # Install Docker if not present
    if ! command_exists docker; then
        echo "Installing Docker..."
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io
        sudo systemctl enable docker
        sudo systemctl start docker
    else
        echo "Docker already installed."
    fi

    # Install Docker Compose if not present
    if ! command_exists docker-compose; then
        echo "Installing Docker Compose..."
        sudo curl -L "https://github.com/docker/compose/releases/download/v2.24.6/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
    else
        echo "Docker Compose already installed."
    fi
}

# Function to install mc-router and frp
install_mc_router() {
    echo "Setting up mc-router and frp..."

    # Create directories
    sudo mkdir -p /opt/mc-router
    sudo mkdir -p "$FRP_CONFIG_DIR"

    # Generate a random port for initial setup
    RANDOM_PORT=$(generate_random_port)

    # Create docker-compose.yml
    cat <<EOF | sudo tee "$COMPOSE_FILE" > /dev/null
version: "3.8"

services:
  frps:
    image: snowdreamtech/frps:${FRP_VERSION}
    container_name: frps
    ports:
      - "${FRP_PORT}:${FRP_PORT}"
      - "${MIN_PORT}-${MAX_PORT}:${MIN_PORT}-${MAX_PORT}"
    volumes:
      - ${FRP_CONFIG_DIR}/frps.ini:/etc/frp/frps.ini
    restart: unless-stopped

  router:
    image: ${MC_ROUTER_IMAGE}
    container_name: mc-router
    depends_on:
      - frps
    environment:
      MAPPING: "${DOMAIN}:${RANDOM_PORT}=frps:${RANDOM_PORT}"
      PORT: "25565"
      RECORD_LOGINS: "true"
    ports:
      - "25565:25565"
    restart: unless-stopped
EOF

    # Create frps.ini
    cat <<EOF | sudo tee "${FRP_CONFIG_DIR}/frps.ini" > /dev/null
[common]
bind_port = ${FRP_PORT}
token = ${FRP_TOKEN}
EOF

    # Start services
    sudo docker-compose -f "$COMPOSE_FILE" up -d

    # Generate frpc.ini for the user
    cat <<EOF > frpc.ini
[common]
server_addr = ${PUBLIC_IP}
server_port = ${FRP_PORT}
token = ${FRP_TOKEN}

[minecraft]
type = tcp
local_port = 25565
remote_port = ${RANDOM_PORT}
EOF

    echo "Installation complete!"
    echo "Your Minecraft server can be accessed at ${DOMAIN}:${RANDOM_PORT}"
    echo "Download frpc from https://github.com/fatedier/frp/releases and use the following frpc.ini on your local machine:"
    cat frpc.ini
    echo "Run 'frpc -c frpc.ini' on your local machine to connect your Minecraft server."
}

# Function to uninstall mc-router and frp
uninstall_mc_router() {
    echo "Uninstalling mc-router and frp..."

    # Stop and remove Docker Compose services
    if [ -f "$COMPOSE_FILE" ]; then
        sudo docker-compose -f "$COMPOSE_FILE" down
        sudo rm -rf /opt/mc-router
    fi

    # Optionally remove Docker and Docker Compose
    read -p "Do you want to remove Docker and Docker Compose as well? (y/N): " remove_docker
    if [[ "$remove_docker" =~ ^[Yy]$ ]]; then
        sudo apt-get purge -y docker-ce docker-ce-cli containerd.io
        sudo rm -rf /var/lib/docker
        sudo rm -f /usr/local/bin/docker-compose
        sudo apt-get autoremove -y
    fi

    echo "Uninstallation complete."
}

# Function to display usage
usage() {
    echo "Usage: $0 {install|uninstall}"
    echo "  install   - Install and configure mc-router and frp"
    echo "  uninstall - Remove mc-router, frp, and optionally Docker"
    exit 1
}

# Main script
case "$1" in
    install)
        install_dependencies
        install_mc_router
        ;;
    uninstall)
        uninstall_mc_router
        ;;
    *)
        usage
        ;;
esac
