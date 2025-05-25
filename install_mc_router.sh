#!/bin/bash

# Minecraft mc-router and frp installation/uninstallation script for Ubuntu with systemd

# Default variables
MC_ROUTER_IMAGE="itzg/mc-router:latest"
FRP_VERSION="0.60.0"
FRP_PORT="7000"
INSTALL_DIR="/opt/mc-router-frp"
COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"
ENV_FILE="$INSTALL_DIR/.env"
SYSTEMD_SERVICE="/etc/systemd/system/mc-router-frp.service"

# Function to check if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Function to resolve containerd conflicts
resolve_containerd_conflict() {
    echo "Checking for containerd conflicts..."
    if dpkg -l | grep -q containerd; then
        echo "Removing conflicting containerd package..."
        sudo apt-get remove --purge -y containerd
        sudo apt-get autoremove -y
    fi
}

# Function to check and install Docker
check_docker() {
    if ! command_exists docker; then
        echo "Docker not found. Installing Docker..."
        sudo apt-get update
        resolve_containerd_conflict
        sudo apt-get install -y docker.io
        if [ $? -ne 0 ]; then
            echo "Failed to install Docker. Trying to fix dependencies..."
            sudo apt-get install -f
            sudo apt-get install -y docker.io
        fi
        sudo systemctl enable docker
        sudo systemctl start docker
        sudo usermod -aG docker "$USER"
        echo "Docker installed. You may need to log out and log back in for Docker permissions."
    fi
}

# Function to check and install Docker Compose
check_docker_compose() {
    if ! command_exists docker-compose; then
        echo "Docker Compose not found. Installing Docker Compose..."
        sudo apt-get update
        sudo apt-get install -y docker-compose
        if [ $? -ne 0 ]; then
            echo "Failed to install Docker Compose. Trying to fix dependencies..."
            sudo apt-get install -f
            sudo apt-get install -y docker-compose
        fi
        echo "Docker Compose installed."
    fi
}

# Function to install mc-router and frp
install_mc_router_frp() {
    echo "Installing mc-router and frp..."

    # Check prerequisites
    check_docker
    check_docker_compose

    # Create installation directory
    sudo mkdir -p "$INSTALL_DIR"

    # Create .env file
    echo "Creating .env file at $ENV_FILE..."
    sudo bash -c "cat > $ENV_FILE" << EOL
MC_ROUTER_IMAGE=$MC_ROUTER_IMAGE
FRP_VERSION=$FRP_VERSION
FRP_PORT=$FRP_PORT
ROUTER_MAPPING=example.com=frp:25566,sub.example.com=frp:25567
EOL

    # Create docker-compose.yml
    echo "Creating docker-compose.yml at $COMPOSE_FILE..."
    sudo bash -c "cat > $COMPOSE_FILE" << EOL
version: "3.8"

services:
  frps:
    image: snowdreamtech/frps:\${FRP_VERSION}
    ports:
      - "\${FRP_PORT}:\${FRP_PORT}"
    volumes:
      - $INSTALL_DIR/frps.ini:/etc/frp/frps.ini
    restart: unless-stopped
  router:
    image: \${MC_ROUTER_IMAGE}
    depends_on:
      - frps
    ports:
      - "25565:25565"
    environment:
      MAPPING: \${ROUTER_MAPPING}
    restart: unless-stopped
EOL

    # Create frps.ini
    echo "Creating frps.ini at $INSTALL_DIR/frps.ini..."
    sudo bash -c "cat > $INSTALL_DIR/frps.ini" << EOL
[common]
bind_port = $FRP_PORT
# Optional: Uncomment and set a token for security
# token = your_secure_token
EOL

    # Create systemd service
    echo "Creating systemd service at $SYSTEMD_SERVICE..."
    sudo bash -c "cat > $SYSTEMD_SERVICE" << EOL
[Unit]
Description=Minecraft mc-router and frp service
After=docker.service
Requires=docker.service

[Service]
Type=simple
ExecStart=/usr/bin/docker-compose -f $COMPOSE_FILE up
ExecStop=/usr/bin/docker-compose -f $COMPOSE_FILE down
Restart=always
WorkingDirectory=$INSTALL_DIR

[Install]
WantedBy=multi-user.target
EOL

    # Set permissions
    sudo chown -R "$USER:$USER" "$INSTALL_DIR"
    sudo chmod 600 "$ENV_FILE"
    sudo chmod 644 "$INSTALL_DIR/frps.ini"
    sudo chmod 644 "$COMPOSE_FILE"
    sudo chmod 644 "$SYSTEMD_SERVICE"

    # Reload systemd and start service
    echo "Starting mc-router and frp services..."
    sudo systemctl daemon-reload
    sudo systemctl enable mc-router-frp.service
    sudo systemctl start mc-router-frp.service

    # Verify service status
    if sudo systemctl is-active --quiet mc-router-frp.service; then
        echo "Installation complete!"
        echo "mc-router is exposed on port 25565."
        echo "frps is exposed on port $FRP_PORT."
        echo "Edit $ENV_FILE to customize ROUTER_MAPPING for your domains."
        echo "Edit $INSTALL_DIR/frps.ini to configure frp settings (e.g., add a token)."
        echo "Manage the service with: sudo systemctl {start|stop|restart|status} mc-router-frp.service"
    else
        echo "Error: Service failed to start. Check logs with:"
        echo "sudo systemctl status mc-router-frp.service"
        echo "docker-compose -f $COMPOSE_FILE logs"
        exit 1
    fi
}

# Function to uninstall mc-router and frp
uninstall_mc_router_frp() {
    echo "Uninstalling mc-router and frp..."

    # Stop and disable systemd service
    if [ -f "$SYSTEMD_SERVICE" ]; then
        echo "Stopping and disabling systemd service..."
        sudo systemctl stop mc-router-frp.service
        sudo systemctl disable mc-router-frp.service
        sudo rm -f "$SYSTEMD_SERVICE"
        sudo systemctl daemon-reload
    fi

    # Stop and remove Docker Compose services
    if [ -f "$COMPOSE_FILE" ]; then
        echo "Stopping and removing Docker Compose services..."
        docker-compose -f "$COMPOSE_FILE" down
    fi

    # Remove installation directory
    if [ -d "$INSTALL_DIR" ]; then
        echo "Removing installation directory $INSTALL_DIR..."
        sudo rm -rf "$INSTALL_DIR"
    fi

    echo "Uninstallation complete!"
}

# CLI interface
case "$1" in
    install)
        install_mc_router_frp
        ;;
    uninstall)
        uninstall_mc_router_frp
        ;;
    *)
        echo "Usage: $0 {install|uninstall}"
        echo "  install: Installs mc-router and frps with systemd services"
        echo "  uninstall: Removes mc-router and frps along with their configurations"
        exit 1
        ;;
esac

exit 0
