#!/bin/bash
# 01-install-openstack.sh
# This script installs a full OpenStack environment using DevStack.
# It is executed on the 'controller' node.

# --- Preamble ---
set -ex # Exit on error, print commands
LOG_FILE="/tmp/install-openstack.log"
exec > >(tee -a ${LOG_FILE}) 2>&1

echo "Starting OpenStack Installation via DevStack..."

# sudo su

# --- System Preparation ---
# Update package lists and install git.
apt-get update
apt-get install -y git

# --- DevStack Setup ---
# Clone the DevStack repository.
git clone https://opendev.org/openstack/devstack /opt/devstack

# Create a non-root user 'stack' for DevStack to run as.
/opt/devstack/tools/create-stack-user.sh

os_password=${1:-"chocolateFrog!"}

# Create the local.conf file. This is the primary configuration file for DevStack.
# It specifies which services to enable, sets passwords, and configures networking.
cat <<EOF > /opt/devstack/local.conf
[[local|localrc]]
# --- Passwords ---
ADMIN_PASSWORD=$os_password
DATABASE_PASSWORD=\$ADMIN_PASSWORD
RABBIT_PASSWORD=\$ADMIN_PASSWORD
SERVICE_PASSWORD=\$ADMIN_PASSWORD
HEAT_STACK_DOMAIN_ADMIN_PASSWORD=\$ADMIN_PASSWORD

# --- Networking ---
# Use the primary IP of this node. Assumes eno1 is the experiment interface.
HOST_IP=$(ip -4 addr show $(ip route | awk '/default/ {print $5}') | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
FLOATING_RANGE=192.168.100.0/24
PUBLIC_NETWORK_GATEWAY=192.168.100.1

# --- Enabled Services ---
# Enable the core services required for a functional cloud.
enable_service key mysql tempest
enable_service g-api g-reg n-api n-crt n-obj n-cpu n-cond n-sch n-novnc n-cauth
enable_service neutron_api neutron-dhcp-agent neutron-l3-agent neutron-metadata-agent openvswitch-agent
enable_service horizon
enable_service cinder c-api c-vol c-sch
enable_service heat h-api h-api-cfn h-api-cw h-eng

enable_plugin heat https://opendev.org/openstack/heat
# enable_plugin manila https://opendev.org/openstack/manila # (uncomment if you want the Manila service)
# enable_plugin manila-ui https://opendev.org/openstack/manila-ui   # (uncomment if you want the Manila dashboard)
enable_plugin magnum https://opendev.org/openstack/magnum
enable_plugin magnum-ui https://opendev.org/openstack/magnum-ui

# --- Service Configuration ---

# Might need to add an Image for Heat to use. Uncomment if needed.
# https://docs.openstack.org/heat/latest/getting_started/on_devstack.html#
# IMAGE_URL_SITE="https://download.fedoraproject.org"
# IMAGE_URL_PATH="/pub/fedora/linux/releases/37/Cloud/x86_64/images/"
# IMAGE_URL_FILE="Fedora-Cloud-Base-37-1.7.x86_64.qcow2"
# IMAGE_URLS+=","$IMAGE_URL_SITE$IMAGE_URL_PATH$IMAGE_URL_FILE

# Use the 'generic' driver for Manila, which uses a service VM.
# This is the simplest backend for a test environment.
# MANILA_ENABLED_BACKEND_NAMES=generic  # (uncomment if you want the Manila service)
# MANILA_GENERIC_SERVICE_INSTANCE_FLAVOR_ID=100 # (uncomment if you want the Manila service)

# Specify the driver for Magnum to use for creating Kubernetes clusters.
MAGNUM_K8S_TEMPLATE_DEFAULT_DRIVER=k8s_fedora_atomic_magnum

# Disable services not needed for this profile to speed up deployment.
disable_service swift s-proxy s-object s-container s-account

# Log file location
LOGFILE=/opt/stack/logs/stack.sh.log
EOF

# Transfer ownership of the devstack directory to the 'stack' user.
chown -R stack:stack /opt/devstack

# sudo su - stack

# --- Run DevStack ---
# Execute the main installation script as the 'stack' user.
# This process will take a significant amount of time (20-40 minutes).
# /opt/devstack/stack.sh

su stack -c "/opt/devstack/stack.sh"

echo "OpenStack Installation Complete."

exit