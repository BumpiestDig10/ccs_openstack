#!/bin/bash

# Custom User Authentication Setup
source /local/repository/config.env

echo "Setting up custom user authentication..."

# Source admin credentials
export OS_USERNAME=admin
export OS_PASSWORD=admin_pass  
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://$(hostname -I | awk '{print $1}'):5000/v3
export OS_IDENTITY_API_VERSION=3

# Wait for Keystone to be ready
sleep 30

# Create custom user project
openstack project create --domain default --description "Custom User Project" $OS_USERNAME-project

# Create custom user
openstack user create --domain default --password $OS_PASSWORD $OS_USERNAME

# Add user to project with member role  
openstack role add --project $OS_USERNAME-project --user $OS_USERNAME member

# Create service project for OpenStack services
openstack project create --domain default --description "Service Project" service

# Create required roles
openstack role create user

# Set up quotas for the custom user project
PROJECT_ID=$(openstack project show $OS_USERNAME-project -c id -f value)

# Nova quotas
openstack quota set --instances 20 --cores 40 --ram 81920 $PROJECT_ID

# Cinder quotas  
openstack quota set --volumes 50 --gigabytes 1000 --snapshots 20 $PROJECT_ID

# Neutron quotas
openstack quota set --networks 10 --subnets 10 --ports 100 --routers 5 $PROJECT_ID

# Create default security group for SSH and ping
openstack security group create --project $PROJECT_ID default-access
openstack security group rule create --protocol tcp --dst-port 22 --remote-ip 0.0.0.0/0 default-access
openstack security group rule create --protocol icmp --remote-ip 0.0.0.0/0 default-access

echo "Custom user $OS_USERNAME created with password $OS_PASSWORD"
echo "Project: $OS_USERNAME-project"
echo "Default security group 'default-access' created with SSH and ping access"
