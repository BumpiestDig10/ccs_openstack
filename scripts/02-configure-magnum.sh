#!/bin/bash
# 02-configure-magnum.sh
# This script configures OpenStack Magnum to be ready for Kubernetes cluster creation.
# It is executed on the 'controller' node after OpenStack is installed.

# --- Preamble ---
set -ex # Exit on error, print commands
LOG_FILE="/tmp/configure-magnum.log"
exec > >(tee -a ${LOG_FILE}) 2>&1

echo "Starting Magnum Configuration..."

# --- Source OpenStack Credentials ---
# The DevStack installation creates a file with the necessary environment
# variables to use the OpenStack command-line clients as the 'admin' user.[34]
source /opt/devstack/openrc admin admin

# Wait for services to be fully available.
sleep 30

# --- Create Magnum Cluster Template ---
# A Cluster Template defines the parameters for creating a Kubernetes cluster.[29]
# This allows for consistent cluster deployments.
echo "Creating Magnum Cluster Template for Kubernetes..."
openstack coe cluster template create k8s-default-template \
    --image Fedora-Atomic-27 \
    --keypair default \
    --external-network public \
    --dns-nameserver 8.8.8.8 \
    --master-flavor m1.small \
    --flavor m1.small \
    --docker-volume-size 5 \
    --network-driver flannel \
    --coe kubernetes

# --- Verification ---
# List the created cluster templates to confirm success.
echo "Verifying Cluster Template creation..."
openstack coe cluster template list

echo "Magnum Configuration Complete. The platform is ready to create Kubernetes clusters."