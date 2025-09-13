#!/bin/bash

# OpenStack Storage Configuration (Cinder + Manila)
NODE_TYPE=${1:-controller}
source /local/repository/config.env

echo "Configuring storage for $NODE_TYPE node..."

NODE_IP=$(hostname -I | awk '{print $1}')

if [ "$NODE_TYPE" = "controller" ]; then
    # Configure Cinder API
    cat > /etc/cinder/cinder.conf << EOF
[DEFAULT]
transport_url = rabbit://openstack:rabbit_pass@$NODE_IP:5672/
auth_strategy = keystone  
my_ip = $NODE_IP
enabled_backends = lvm

[database]
connection = mysql+pymysql://cinder:cinder_pass@$NODE_IP/cinder

[keystone_authtoken]
www_authenticate_uri = http://$NODE_IP:5000
auth_url = http://$NODE_IP:5000
memcached_servers = $NODE_IP:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = cinder
password = cinder_pass

[oslo_concurrency]
lock_path = /var/lib/cinder/tmp

[lvm]
volume_driver = cinder.volume.drivers.lvm.LVMVolumeDriver
volume_group = cinder-volumes
target_protocol = iscsi
target_helper = tgtadm
EOF

    # Populate Cinder database
    su -s /bin/sh -c "cinder-manage db sync" cinder

elif [ "$NODE_TYPE" = "storage" ] || [ "$NODE_TYPE" = "controller" ]; then
    # Set up LVM for Cinder
    pvcreate /opt/openstack/cinder-volumes.img
    vgcreate cinder-volumes /opt/openstack/cinder-volumes.img
    
    # Configure Cinder volume service
    cat > /etc/cinder/cinder.conf << EOF
[DEFAULT]
transport_url = rabbit://openstack:rabbit_pass@$NODE_IP:5672/
auth_strategy = keystone
my_ip = $NODE_IP
enabled_backends = lvm
glance_api_servers = http://$NODE_IP:9292

[database]
connection = mysql+pymysql://cinder:cinder_pass@$NODE_IP/cinder

[keystone_authtoken]  
www_authenticate_uri = http://$NODE_IP:5000
auth_url = http://$NODE_IP:5000
memcached_servers = $NODE_IP:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = cinder
password = cinder_pass

[lvm]
volume_driver = cinder.volume.drivers.lvm.LVMVolumeDriver
volume_group = cinder-volumes
target_protocol = iscsi
target_helper = tgtadm

[oslo_concurrency]
lock_path = /var/lib/cinder/tmp
EOF

fi

# Configure Manila (if enabled)
if [ "$ENABLE_MANILA" = "True" ]; then
    if [ "$NODE_TYPE" = "controller" ]; then
        cat > /etc/manila/manila.conf << EOF
[DEFAULT]
transport_url = rabbit://openstack:rabbit_pass@$NODE_IP:5672/
default_share_type = default_share_type
share_name_template = share-%s
rootwrap_config = /etc/manila/rootwrap.conf
api_paste_config = /etc/manila/api-paste.ini
auth_strategy = keystone
my_ip = $NODE_IP
enabled_share_backends = generic
enabled_share_protocols = NFS,CIFS

[database]
connection = mysql+pymysql://manila:manila_pass@$NODE_IP/manila

[keystone_authtoken]
www_authenticate_uri = http://$NODE_IP:5000
auth_url = http://$NODE_IP:5000
memcached_servers = $NODE_IP:11211  
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = manila
password = manila_pass

[oslo_concurrency]
lock_path = /var/lib/manila/tmp

[generic]
share_backend_name = GENERIC
share_driver = manila.share.drivers.generic.GenericShareDriver
driver_handles_share_servers = True
service_instance_flavor_id = 100
service_image_name = manila-service-image
service_instance_user = manila
service_instance_password = manila
interface_driver = manila.network.linux.interface.OVSInterfaceDriver
connect_share_server_to_tenant_network = True
EOF

        # Populate Manila database
        su -s /bin/sh -c "manila-manage db sync" manila
        
        # Create Manila service image (simplified)
        # In production, you'd want to build a proper service image
        echo "Manila database synchronized"
    fi
fi

echo "Storage configuration completed for $NODE_TYPE"
