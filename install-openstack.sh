#!/bin/bash

# OpenStack Epoxy 2025.1 Installation Script for Ubuntu 24.04 LTS
# Usage: install-openstack.sh [controller|compute|storage]

set -e

NODE_TYPE=${1:-controller}
SCRIPT_DIR="/local/repository"
source $SCRIPT_DIR/config.env

# Logging
exec > >(tee -a /var/log/openstack-install.log) 2>&1
echo "Starting OpenStack installation on $(hostname) as $NODE_TYPE at $(date)"

# Update system
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y

# Install required packages
apt-get install -y python3-pip python3-dev git curl wget gnupg lsb-release

# Add OpenStack Epoxy repository
add-apt-repository cloud-archive:epoxy -y
apt-get update

# Install Sunbeam (modern OpenStack deployment tool)
snap install openstack --channel=2025.1/stable

# Prepare the node
sunbeam prepare-node-script | bash -x
newgrp snap_daemon

# Node-specific configuration
case $NODE_TYPE in
    "controller")
        echo "Configuring controller node..."
        # Install controller services
        apt-get install -y keystone glance nova-api nova-conductor nova-scheduler \
                          neutron-server neutron-plugin-ml2 neutron-l3-agent \
                          neutron-dhcp-agent neutron-metadata-agent \
                          cinder-api cinder-scheduler \
                          horizon apache2 libapache2-mod-wsgi-py3
        
        if [ "$ENABLE_MANILA" = "True" ]; then
            apt-get install -y manila-api manila-scheduler manila-share python3-manila
        fi
        
        # Configure services
        bash $SCRIPT_DIR/configure-services.sh controller
        ;;
        
    "compute")
        echo "Configuring compute node..."
        # Install compute services  
        apt-get install -y nova-compute neutron-plugin-ml2 neutron-openvswitch-agent
        
        # Configure services
        bash $SCRIPT_DIR/configure-services.sh compute
        ;;
        
    "storage") 
        echo "Configuring storage node..."
        # Install storage services
        apt-get install -y cinder-volume tgt
        
        if [ "$ENABLE_MANILA" = "True" ]; then
            apt-get install -y manila-share nfs-kernel-server
        fi
        
        # Configure services
        bash $SCRIPT_DIR/configure-services.sh storage
        ;;
esac

# Configure networking based on tenant network type
bash $SCRIPT_DIR/configure-networking.sh $NODE_TYPE

# Configure storage
bash $SCRIPT_DIR/configure-storage.sh $NODE_TYPE

# Set up custom user authentication
if [ "$NODE_TYPE" = "controller" ]; then
    bash $SCRIPT_DIR/setup-users.sh
fi

# Start services
systemctl daemon-reload
systemctl enable --now openstack-*
systemctl enable --now neutron-*
systemctl enable --now cinder-*

if [ "$ENABLE_MANILA" = "True" ]; then
    systemctl enable --now manila-*
fi

if [ "$NODE_TYPE" = "controller" ]; then
    systemctl enable --now apache2
fi

echo "OpenStack installation completed on $(hostname) at $(date)"
