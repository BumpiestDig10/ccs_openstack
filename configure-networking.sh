#!/bin/bash
# Minimal Networking Configuration
NODE_TYPE=${1:-controller}
source /local/repository/config.env

echo "Configuring networking for $NODE_TYPE"
echo "Network type: $TENANT_NETWORK_TYPE"

if [ "$NODE_TYPE" = "controller" ]; then
    # Install networking packages
    apt-get install -y openvswitch-switch
    systemctl start openvswitch-switch
fi

echo "Networking configured for $NODE_TYPE"
