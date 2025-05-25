#!/bin/bash

# Minecraft mc-router and frp installation/removal script for Ubuntu

# Default variables
MC_ROUTER_IMAGE="itzg/mc-router:latest"
FRP_VERSION="0.60.0"
FRP_PORT="7000"
COMPOSE_FILE="/tmp/docker-compose.yml"
INSTALL_DIR="/opt/mc-router-frp"
ENV_FILE="$INSTALL_DIR/.env"

# Function to check if Docker is installed
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo "Docker not found. Installing Docker..."
        sudo apt-get update
        sudo apt-get install -y docker.io
        sudo systemctl enable docker
        sudo systemctl start docker
        sudo usermod -aG docker $USER
        echo "Docker installed. You may need to log out and log back in for Docker permissions to take effect."
    fi
}

# Function to check if Docker Compose is installed
check_docker_compose() {
    if ! command -v docker-compose &> /dev/null; then
        echo "Docker Compose not found. Installing Docker Compose..."
        sudo apt-get update
        sudo apt-get install -y docker-compose
        echo "Docker Compose installed."
    fi
}

# Function to install mc-router and frp
install_mc_router_frp() {
    echo "Installing mc-router and frp..."

    # Create installation directory
    sudo mkdir -p $INSTALL_DIR

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
EOL

    # Ensure permissions
    sudo chown -R $USER:$USER $INSTALL_DIR
    sudo chmod 600 $ENV_FILE
    sudo chmod 644 $INSTALL_DIR/frps.ini
    sudo chmod 644 $COMPOSE_FILE

    # Start Docker Compose services
    echo "Starting mc-router and frp services..."
    docker-compose -f $COMPOSE_FILE up -d

    echo "Installation complete!"
    echo "mc-router is exposed on port 25565."
    echo "frps is exposed on port $FRP_PORT."
    echo "Edit $ENV_FILE to customize ROUTER_MAPPING for your domains."
    echo "Edit $INSTALL_DIR/frps.ini to configure frp settings."
}

# Function to remove mc-router and frp
remove_mc_router_frp() {
    echo "Removing mc-router and frp..."

    # Stop and remove Docker Compose services
    if [ -f $COMPOSE_FILE ]; then
        echo "Stopping and removing Docker Compose services..."
        docker-compose -f $COMPOSE_FILE down
    fi

    # Remove installation directory
    if [ -d $INSTALL_DIR ]; then
        echo "Removing installation directory $INSTALL_DIR..."
        sudo rm -rf $INSTALL_DIR
    fi

    # Remove docker-compose.yml
    if [ -f $COMPOSE_FILE ]; then
        echo "Removing docker-compose.yml..."
        sudo rm -f $COMPOSE_FILE
    fi

    echo "Removal complete!"
}

# CLI interface
case "$1" in
    install)
        check_docker
        check_docker_compose
        install_mc_router_frp
        ;;
    remove)
        remove_mc_router_frp
        ;;
    *)
        echo "Usage: $0 {install|remove}"
        echo "  install: Install mc-router and frp with Docker Compose"
        echo "  remove: Remove mc-router, frp, and associated files"
        exit 1
        ;;
esac

exit 0
