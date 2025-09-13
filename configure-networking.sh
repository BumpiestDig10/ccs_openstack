#!/bin/bash

# OpenStack Networking Configuration
NODE_TYPE=${1:-controller}
source /local/repository/config.env

echo "Configuring networking for $NODE_TYPE with $TENANT_NETWORK_TYPE tenant networks..."

# Get node IP
NODE_IP=$(hostname -I | awk '{print $1}')

if [ "$NODE_TYPE" = "controller" ]; then
    # Configure Neutron server
    cat > /etc/neutron/neutron.conf << EOF
[DEFAULT]
core_plugin = ml2
service_plugins = router
allow_overlapping_ips = true
transport_url = rabbit://openstack:rabbit_pass@$NODE_IP:5672/
auth_strategy = keystone
notify_nova_on_port_status_changes = true
notify_nova_on_port_data_changes = true

[database]
connection = mysql+pymysql://neutron:neutron_pass@$NODE_IP/neutron

[keystone_authtoken]
www_authenticate_uri = http://$NODE_IP:5000
auth_url = http://$NODE_IP:5000
memcached_servers = $NODE_IP:11211
auth_type = password
project_domain_name = default
user_domain_name = default  
project_name = service
username = neutron
password = neutron_pass

[nova]
auth_url = http://$NODE_IP:5000
auth_type = password
project_domain_name = default
user_domain_name = default
region_name = RegionOne
project_name = service
username = nova
password = nova_pass

[oslo_concurrency]
lock_path = /var/lib/neutron/tmp
EOF

    # Configure ML2 plugin
    cat > /etc/neutron/plugins/ml2/ml2_conf.ini << EOF
[ml2]
type_drivers = flat,vlan,vxlan
tenant_network_types = $TENANT_NETWORK_TYPE
mechanism_drivers = openvswitch,l2population
extension_drivers = port_security

[ml2_type_flat]
flat_networks = provider

[ml2_type_vlan]
network_vlan_ranges = provider

[ml2_type_vxlan]
vni_ranges = 1:1000
EOF

fi

# Configure OVS agent (all nodes)
cat > /etc/neutron/plugins/ml2/openvswitch_agent.ini << EOF  
[ovs]
bridge_mappings = provider:br-provider
local_ip = $NODE_IP

[agent]
tunnel_types = vxlan
l2_population = true
arp_responder = true

[securitygroup]  
enable_security_group = true
firewall_driver = openvswitch
EOF

# Configure bridges
ovs-vsctl add-br br-provider
ovs-vsctl add-br br-int

# Configure L3 agent (controller only)
if [ "$NODE_TYPE" = "controller" ]; then
    cat > /etc/neutron/l3_agent.ini << EOF
[DEFAULT]
interface_driver = openvswitch
external_network_bridge =
EOF

    cat > /etc/neutron/dhcp_agent.ini << EOF
[DEFAULT]
interface_driver = openvswitch
dhcp_driver = neutron.agent.linux.dhcp.Dnsmasq
enable_isolated_metadata = true
EOF
fi

# Populate Neutron database (controller only)
if [ "$NODE_TYPE" = "controller" ]; then
    su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf \
        --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron
fi

echo "Networking configuration completed for $NODE_TYPE"
