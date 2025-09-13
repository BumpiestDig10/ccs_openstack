#!/bin/bash
# Minimal Storage Configuration  
NODE_TYPE=${1:-controller}
source /local/repository/config.env

echo "Configuring storage for $NODE_TYPE"

if [ "$NODE_TYPE" = "controller" ] || [ "$NODE_TYPE" = "storage" ]; then
    # Install storage packages
    apt-get install -y lvm2

    # Create storage directory
    mkdir -p /opt/stack/data

    # Create a simple file for testing
    if [ ! -f "/opt/stack/data/cinder-volumes.img" ]; then
        dd if=/dev/zero of=/opt/stack/data/cinder-volumes.img bs=1M count=1024
    fi
fi

echo "Storage configured for $NODE_TYPE"
