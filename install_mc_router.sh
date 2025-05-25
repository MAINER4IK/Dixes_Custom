#!/bin/bash

# Script to install, configure, and uninstall mc-router and frp on Ubuntu

set -e

# Default values
MC_ROUTER_VERSION="latest"
FRP_VERSION="0.60.0"
INSTALL_DIR="/usr/local/bin"
SERVICE_DIR="/etc/systemd/system"
CONFIG_DIR="/etc/mc-router"
FRP_CONFIG_DIR="/etc/frp"
MC_ROUTER_BINARY="mc-router"
FRP_BINARY="frps"
MC_ROUTER_SERVICE="mc-router.service"
FRP_SERVICE="frps.service"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}This script must be run as root${NC}"
        exit 1
    fi
}

# Function to install dependencies
install_dependencies() {
    echo "Installing dependencies..."
    apt-get update
    apt-get install -y curl tar docker.io
    systemctl enable docker
    systemctl start docker
}

# Function to download and install mc-router
install_mc_router() {
    echo "Installing mc-router..."
    if [[ "$MC_ROUTER_VERSION" == "latest" ]]; then
        # Fetch the latest release from Docker Hub (simplified, assuming binary download)
        echo "Fetching latest mc-router version..."
        docker pull itzg/mc-router
    else
        docker pull itzg/mc-router:$MC_ROUTER_VERSION
    fi

    # Ensure config directory exists
    mkdir -p "$CONFIG_DIR"

    # Create a basic routes config file
    cat > "$CONFIG_DIR/routes.json" << EOL
{
  "default-server": null,
  "mappings": {}
}
EOL

    # Create systemd service file for mc-router
    cat > "$SERVICE_DIR/$MC_ROUTER_SERVICE" << EOL
[Unit]
Description=mc-router service for Minecraft server routing
After=network.target docker.service
Requires=docker.service

[Service]
ExecStart=/usr/bin/docker run --rm \
    -v $CONFIG_DIR:/config \
    -p 25565:25565 \
    --name mc-router \
    itzg/mc-router \
    --routes-config=/config/routes.json \
    --routes-config-watch
ExecStop=/usr/bin/docker stop mc-router
Restart=always

[Install]
WantedBy=multi-user.target
EOL

    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable "$MC_ROUTER_SERVICE"
    systemctl start "$MC_ROUTER_SERVICE"
    echo -e "${GREEN}mc-router installed and started successfully${NC}"
}

# Function to install frp
install_frp() {
    echo "Installing frp (frps) version $FRP_VERSION..."
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            FRP_ARCH="amd64"
            ;;
        aarch64)
            FRP_ARCH="arm64"
            ;;
        arm*)
            FRP_ARCH="arm"
            ;;
        *)
            echo -e "${RED}Unsupported architecture: $ARCH${NC}"
            exit 1
            ;;
    esac

    # Download frp
    FRP_URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${FRP_ARCH}.tar.gz"
    curl -L "$FRP_URL" -o /tmp/frp.tar.gz
    tar -xzf /tmp/frp.tar.gz -C /tmp
    mv "/tmp/frp_${FRP_VERSION}_linux_${FRP_ARCH}/frps" "$INSTALL_DIR/$FRP_BINARY"
    rm -rf "/tmp/frp_${FRP_VERSION}_linux_${FRP_ARCH}" /tmp/frp.tar.gz

    # Ensure config directory exists
    mkdir -p "$FRP_CONFIG_DIR"

    # Create frps.ini
    cat > "$FRP_CONFIG_DIR/frps.ini" << EOL
[common]
bind_port = 7000
EOL

    # Create systemd service file for frps
    cat > "$SERVICE_DIR/$FRP_SERVICE" << EOL
[Unit]
Description=frp server (frps) for reverse proxy
After=network.target
Requires=network.target

[Service]
ExecStart=$INSTALL_DIR/$FRP_BINARY -c $FRP_CONFIG_DIR/frps.ini
Restart=always

[Install]
WantedBy=multi-user.target
EOL

    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable "$FRP_SERVICE"
    systemctl start "$FRP_SERVICE"
    echo -e "${GREEN}frp (frps) installed and started successfully${NC}"
}

# Function to uninstall mc-router
uninstall_mc_router() {
    echo "Uninstalling mc-router..."
    if systemctl is-active --quiet "$MC_ROUTER_SERVICE"; then
        systemctl stop "$MC_ROUTER_SERVICE"
    fi
    systemctl disable "$MC_ROUTER_SERVICE" 2>/dev/null || true
    rm -f "$SERVICE_DIR/$MC_ROUTER_SERVICE"
    rm -rf "$CONFIG_DIR"
    docker rm -f mc-router 2>/dev/null || true
    echo -e "${GREEN}mc-router uninstalled successfully${NC}"
}

# Function to uninstall frp
uninstall_frp() {
    echo "Uninstalling frp (frps)..."
    if systemctl is-active --quiet "$FRP_SERVICE"; then
        systemctl stop "$FRP_SERVICE"
    fi
    systemctl disable "$FRP_SERVICE" 2>/dev/null || true
    rm -f "$SERVICE_DIR/$FRP_SERVICE"
    rm -rf "$FRP_CONFIG_DIR"
    rm -f "$INSTALL_DIR/$FRP_BINARY"
    echo -e "${GREEN}frp (frps) uninstalled successfully${NC}"
}

# Main CLI logic
case "$1" in
    install)
        check_root
        install_dependencies
        install_mc_router
        install_frp
        echo -e "${GREEN}Installation complete!${NC}"
        echo "Edit $CONFIG_DIR/routes.json for mc-router mappings."
        echo "Edit $FRP_CONFIG_DIR/frps.ini for frp configuration."
        echo "For local servers, download frpc from https://github.com/fatedier/frp/releases and configure frpc.ini as per the guide."
        ;;
    uninstall)
        check_root
        uninstall_mc_router
        uninstall_frp
        echo -e "${GREEN}Uninstallation complete!${NC}"
        ;;
    *)
        echo "Usage: $0 {install|uninstall}"
        echo "  install: Installs mc-router and frps with systemd services"
        echo "  uninstall: Removes mc-router and frps along with their configurations"
        exit 1
        ;;
esac
