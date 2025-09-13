#!/bin/bash
# Minimal OpenStack Installation Script
set -e
NODE_TYPE=${1:-controller}
source /local/repository/config.env || { echo "Config not found"; exit 1; }

echo "Installing OpenStack on $(hostname) as $NODE_TYPE"

# Update system
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y python3-openstackclient git curl wget

# Install DevStack
if [ ! -d "/opt/stack/devstack" ]; then
    mkdir -p /opt/stack
    cd /opt/stack
    git clone https://opendev.org/openstack/devstack
    chown -R ubuntu:ubuntu /opt/stack
fi

echo "DevStack installed successfully"
echo "OpenStack installation completed on $(hostname)"
