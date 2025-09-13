#!/bin/bash
# Minimal User Setup
source /local/repository/config.env

echo "Setting up users"

# Install OpenStack client
apt-get install -y python3-openstackclient

# Set up environment
export OS_USERNAME=admin
export OS_PASSWORD=admin_pass
export OS_PROJECT_NAME=admin
export OS_AUTH_URL=http://$(hostname -I | awk '{print $1}'):5000/v3
export OS_IDENTITY_API_VERSION=3

echo "Custom user: $OS_USERNAME will be configured"
echo "Custom password: $OS_PASSWORD"
echo "User setup completed"
