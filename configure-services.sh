#!/bin/bash

# OpenStack Service Configuration Script
NODE_TYPE=${1:-controller}
source /local/repository/config.env

echo "Configuring OpenStack services for $NODE_TYPE node..."

# Database setup (controller only)
if [ "$NODE_TYPE" = "controller" ]; then
    # Install and configure MySQL
    apt-get install -y mysql-server python3-pymysql
    
    # Configure MySQL
    cat > /etc/mysql/mysql.conf.d/99-openstack.cnf << EOF
[mysqld]
bind-address = 0.0.0.0
default-storage-engine = innodb
innodb_file_per_table = on
max_connections = 4096
collation-server = utf8_general_ci
character-set-server = utf8
EOF

    systemctl restart mysql
    
    # Create databases
    mysql -u root << EOF
CREATE DATABASE keystone;
CREATE DATABASE glance;  
CREATE DATABASE nova_api;
CREATE DATABASE nova;
CREATE DATABASE nova_cell0;
CREATE DATABASE neutron;
CREATE DATABASE cinder;
$([ "$ENABLE_MANILA" = "True" ] && echo "CREATE DATABASE manila;")

GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY 'keystone_pass';
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY 'keystone_pass';
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY 'glance_pass';
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY 'glance_pass';
GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY 'nova_pass';
GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY 'nova_pass';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY 'nova_pass';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY 'nova_pass';
GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' IDENTIFIED BY 'nova_pass';
GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' IDENTIFIED BY 'nova_pass';
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY 'neutron_pass';
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY 'neutron_pass';
GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'localhost' IDENTIFIED BY 'cinder_pass';
GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'%' IDENTIFIED BY 'cinder_pass';
$([ "$ENABLE_MANILA" = "True" ] && echo "GRANT ALL PRIVILEGES ON manila.* TO 'manila'@'localhost' IDENTIFIED BY 'manila_pass';")
$([ "$ENABLE_MANILA" = "True" ] && echo "GRANT ALL PRIVILEGES ON manila.* TO 'manila'@'%' IDENTIFIED BY 'manila_pass';")

FLUSH PRIVILEGES;
EOF

    # Configure RabbitMQ
    apt-get install -y rabbitmq-server
    rabbitmqctl add_user openstack rabbit_pass
    rabbitmqctl set_permissions openstack ".*" ".*" ".*"
    
    # Configure Memcached
    apt-get install -y memcached python3-memcache
    sed -i 's/-l 127.0.0.1/-l 0.0.0.0/g' /etc/memcached.conf
    systemctl restart memcached
fi

# Get controller IP for multi-node setup
CONTROLLER_IP=$(hostname -I | awk '{print $1}')

# Configure Keystone (controller only)
if [ "$NODE_TYPE" = "controller" ]; then
    cat > /etc/keystone/keystone.conf << EOF
[DEFAULT]
transport_url = rabbit://openstack:rabbit_pass@$CONTROLLER_IP:5672/

[database]
connection = mysql+pymysql://keystone:keystone_pass@$CONTROLLER_IP/keystone

[cache]
enabled = true
backend = oslo_cache.memcache_pool
memcache_servers = $CONTROLLER_IP:11211

[token]
provider = fernet
EOF

    # Populate Keystone database
    su -s /bin/sh -c "keystone-manage db_sync" keystone
    keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
    keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
    
    # Bootstrap Keystone
    keystone-manage bootstrap --bootstrap-password admin_pass \
        --bootstrap-admin-url http://$CONTROLLER_IP:5000/v3/ \
        --bootstrap-internal-url http://$CONTROLLER_IP:5000/v3/ \
        --bootstrap-public-url http://$CONTROLLER_IP:5000/v3/ \
        --bootstrap-region-id RegionOne
fi

echo "Service configuration completed for $NODE_TYPE"
