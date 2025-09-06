#!/bin/sh

##
## Setup a OpenStack node to run the openvswitch ML2 plugin.
##

set -x

# Gotta know the rules!
if [ $EUID -ne 0 ] ; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

# Grab our libs
. "`dirname $0`/setup-lib.sh"

if [ -f $OURDIR/setup-network-plugin-openvswitch-done ]; then
    exit 0
fi

logtstart "network-plugin-openvswitch"

if [ -f $SETTINGS ]; then
    . $SETTINGS
fi
if [ -f $LOCALSETTINGS ]; then
    . $LOCALSETTINGS
fi

# Configure kernel networking parameters
cat <<EOF >> /etc/sysctl.conf
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
EOF

sysctl -p

# Install base packages
maybe_install_packages neutron-plugin-ml2 conntrack neutron-openvswitch-agent openvswitch-switch

# Only the controller node runs neutron-server and needs the DB
if [ "$HOSTNAME" = "$CONTROLLER" ]; then
    # Configure neutron.conf for controller
    crudini --set /etc/neutron/neutron.conf DEFAULT core_plugin ml2
    crudini --set /etc/neutron/neutron.conf DEFAULT service_plugins router,metering,qos
    crudini --set /etc/neutron/neutron.conf DEFAULT auth_strategy keystone
    crudini --set /etc/neutron/neutron.conf DEFAULT transport_url $RABBIT_URL
    crudini --set /etc/neutron/neutron.conf DEFAULT notify_nova_on_port_status_changes true
    crudini --set /etc/neutron/neutron.conf DEFAULT notify_nova_on_port_data_changes true

    # Configure database
    crudini --set /etc/neutron/neutron.conf database connection \
        "${DBDSTRING}://neutron:${NEUTRON_DBPASS}@${CONTROLLER}/neutron"
    
    # Configure keystone authentication
    crudini --set /etc/neutron/neutron.conf keystone_authtoken www_authenticate_uri http://${CONTROLLER}:5000
    crudini --set /etc/neutron/neutron.conf keystone_authtoken auth_url http://${CONTROLLER}:5000
    crudini --set /etc/neutron/neutron.conf keystone_authtoken memcached_servers ${CONTROLLER}:11211
    crudini --set /etc/neutron/neutron.conf keystone_authtoken auth_type password
    crudini --set /etc/neutron/neutron.conf keystone_authtoken project_domain_name default
    crudini --set /etc/neutron/neutron.conf keystone_authtoken user_domain_name default
    crudini --set /etc/neutron/neutron.conf keystone_authtoken project_name service
    crudini --set /etc/neutron/neutron.conf keystone_authtoken username neutron
    crudini --set /etc/neutron/neutron.conf keystone_authtoken password ${NEUTRON_PASS}

    # Configure nova notifications
    crudini --set /etc/neutron/neutron.conf nova auth_url http://${CONTROLLER}:5000
    crudini --set /etc/neutron/neutron.conf nova auth_type password
    crudini --set /etc/neutron/neutron.conf nova project_domain_name default
    crudini --set /etc/neutron/neutron.conf nova user_domain_name default
    crudini --set /etc/neutron/neutron.conf nova region_name ${REGION}
    crudini --set /etc/neutron/neutron.conf nova project_name service
    crudini --set /etc/neutron/neutron.conf nova username nova
    crudini --set /etc/neutron/neutron.conf nova password ${NOVA_PASS}
fi

# Configure ML2 plugin
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 type_drivers flat,vlan,vxlan
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 tenant_network_types vxlan
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 mechanism_drivers openvswitch
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 extension_drivers port_security,qos
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup enable_security_group true
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup enable_ipset true

# Configure ML2 network segment ranges
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_flat flat_networks external
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_vlan network_vlan_ranges external:1:4094
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_vxlan vni_ranges 1:16777215

# Configure Open vSwitch agent
crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs bridge_mappings external:br-ex
crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs local_ip $MGMTIP
crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini agent tunnel_types vxlan
# Note: enable_tunneling is deprecated, tunneling is enabled automatically when tunnel_types is set
crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini securitygroup enable_security_group true
crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini securitygroup firewall_driver openvswitch

# Configure layer 3 agent
crudini --set /etc/neutron/l3_agent.ini DEFAULT interface_driver openvswitch

# Configure DHCP agent
crudini --set /etc/neutron/dhcp_agent.ini DEFAULT interface_driver openvswitch
crudini --set /etc/neutron/dhcp_agent.ini DEFAULT dhcp_driver neutron.agent.linux.dhcp.Dnsmasq
crudini --set /etc/neutron/dhcp_agent.ini DEFAULT enable_isolated_metadata true

# Configure metadata agent
crudini --set /etc/neutron/metadata_agent.ini DEFAULT nova_metadata_host $CONTROLLER
crudini --set /etc/neutron/metadata_agent.ini DEFAULT metadata_proxy_shared_secret $METADATA_SECRET

# Set up OVS bridges
service_restart openvswitch-switch
service_enable openvswitch-switch

# Create the bridge interface
ovs-vsctl --may-exist add-br br-ex
ovs-vsctl --may-exist add-port br-ex $EXTERNAL_NETWORK_INTERFACE
ip addr flush dev $EXTERNAL_NETWORK_INTERFACE
ip addr add $MGMTIP/24 dev br-ex
ip link set br-ex up

crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 \
    type_drivers ${network_types}
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 \
    tenant_network_types ${network_types}
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 \
    mechanism_drivers openvswitch
extdrivers="port_security"
if [ $OSVERSION -ge $OSNEWTON ]; then
    extdrivers="${extdrivers},dns"
fi
if [ -n "$extdrivers" ]; then
    crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 \
        extension_drivers $extdrivers
fi
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_flat \
    flat_networks ${flat_networks}
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_gre \
    tunnel_id_ranges 1:1000
cat <<EOF >>/etc/neutron/plugins/ml2/ml2_conf.ini
[ml2_type_vlan]
${network_vlan_ranges}
EOF
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_vxlan \
    vni_ranges 3000:4000
#crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_vxlan \
#    vxlan_group 224.0.0.1
crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini securitygroup \
    enable_security_group True
crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini securitygroup \
    enable_ipset True
if [ -n "$fwdriver" ]; then
    crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini securitygroup \
	firewall_driver $fwdriver
fi
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup \
    enable_security_group True
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup \
    enable_ipset True
if [ -n "$fwdriver" ]; then
    crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup \
	firewall_driver $fwdriver
fi
cat <<EOF >> /etc/neutron/plugins/ml2/ml2_conf.ini
[ovs]
${gre_local_ip}
${enable_tunneling}
${bridge_mappings}

[agent]
${tunnel_types}
EOF

if [ $OSVERSION -ge $OSMITAKA ]; then
    # In Mitaka, these seem to need to be specifically in the agent file.
    # Must be a change in neutron-server init script.
    # Just slap these in.
    cat <<EOF >> /etc/neutron/plugins/ml2/openvswitch_agent.ini
[ovs]
${gre_local_ip}
${enable_tunneling}
${bridge_mappings}

[agent]
${tunnel_types}
EOF
fi

#
# Ok, also put our FQDN into the hosts file so that local applications can
# resolve that pair even if the network happens to be down.  This happens,
# for instance, because of our anti-ARP spoofing "patch" to the openvswitch
# agent (the agent remove_all_flow()s on a switch periodically and inserts a
# default normal forwarding rule, plus anything it needs --- our patch adds some
# anti-ARP spoofing rules after remove_all but BEFORE the default normal rule
# gets added back (this is just the nature of the existing code in Juno and Kilo
# (the situation is easier to patch more nicely on the master branch, but we
# don't have Liberty yet)) --- and because it adds the rules via command line
# using sudo, and sudo tries to lookup the hostname --- this can cause a hang.)
# Argh, what a pain.  For the rest of this hack, see setup-ovs-node.sh, and
# setup-networkmanager.sh and setup-compute-network.sh where we patch the 
# neutron openvswitch agent.
#
echo "$MYIP    $NFQDN $PFQDN" >> /etc/hosts

#
# Patch the neutron openvswitch agent to try to stop inadvertent spoofing on
# the public emulab/cloudlab control net, sigh.
#
if [ $OSVERSION -le $OSLIBERTY ]; then
    patch -d / -p0 < $DIRNAME/etc/neutron-${OSCODENAME}-openvswitch-remove-all-flows-except-system-flows.patch
else
    patch -d / -p0 < $DIRNAME/etc/neutron-${OSCODENAME}-ovs-reserved-cookies.patch
fi

#
# https://git.openstack.org/cgit/openstack/neutron/commit/?id=51f6b2e1c9c2f5f5106b9ae8316e57750f09d7c9
#
if [ $OSVERSION -ge $OSLIBERTY -a $OSVERSION -lt $OSNEWTON ]; then
    patch -d / -p0 < $DIRNAME/etc/neutron-liberty-ovs-agent-segmentation-id-None.patch
fi

if [ $OSVERSION -ge $OSROCKY ]; then
    crudini --set /etc/neutron/neutron.conf oslo_concurrency \
	lock_path /var/lib/neutron/lock
    mkdir -p /var/lib/neutron/lock/
    chown neutron:neutron /var/lib/neutron/lock
fi

#
# Neutron depends on bridge module, but it doesn't autoload it.
#
modprobe bridge
echo bridge >> /etc/modules

if [ $OSVERSION -eq $OSUSSURI ]; then
    patch -d / -p0 < $DIRNAME/etc/oslo_service-ussuri-log-circular-import.patch
fi

service_restart openvswitch-switch
service_enable openvswitch-switch
service_restart nova-compute
# Restart the ovs-cleanup service to ensure it is using the patched code
# and thus will not delete our new cookie-based flows once we add them.
service_restart neutron-ovs-cleanup
service_enable neutron-ovs-cleanup
if [ $OSVERSION -lt $OSMITAKA ]; then
    service_restart neutron-plugin-openvswitch-agent
    service_enable neutron-plugin-openvswitch-agent
else
    service_restart neutron-openvswitch-agent
    service_enable neutron-openvswitch-agent
fi

if [ $OSVERSION -gt $OSLIBERTY ]; then
    # If we are using the reserved cookies patch, we have to figure out
    # what our cookie is, read it, and then edit all the anti-spoofing
    # flows to have our reserved cookie -- and then re-insert them all.
    # We don't know what our per-host reserved cookie is until the
    # patched ovs code creates one on the first startup after patch.
    echo "*** Re-adding OVS anti-spoofing flows with reserved cookie..."
    i=30
    while [ ! -f /var/lib/neutron/ovs-default-flows.reserved_cookie -a $i -gt 0 ]; do
	sleep 1
	i=`expr $i - 1`
    done
    # Restart services
if [ "$HOSTNAME" = "$CONTROLLER" ]; then
    service_restart neutron-server
    service_enable neutron-server
fi

service_restart neutron-openvswitch-agent
service_enable neutron-openvswitch-agent

if [ "$HOSTNAME" = "$CONTROLLER" ]; then
    service_restart neutron-l3-agent
    service_enable neutron-l3-agent
    service_restart neutron-dhcp-agent
    service_enable neutron-dhcp-agent
    service_restart neutron-metadata-agent
    service_enable neutron-metadata-agent
fi

# Add FQDN to hosts file for local resolution
echo "$MYIP    $NFQDN $PFQDN" >> /etc/hosts

# Ensure bridge module is loaded
modprobe bridge
echo bridge >> /etc/modules

touch $OURDIR/setup-network-plugin-openvswitch-done
logtend "network-plugin-openvswitch"
    # Let the agent settle again...
    sleep 16
    if [ -f /var/lib/neutron/ovs-default-flows.reserved_cookie -a -f /etc/neutron/ovs-default-flows/br-ex ]; then
	cookie=`cat /var/lib/neutron/ovs-default-flows.reserved_cookie`
	for fl in `cat /etc/neutron/ovs-default-flows/br-ex`; do
	    echo "cookie=$cookie,$fl" >> /etc/neutron/ovs-default-flows/br-ex.tmp
	    ovs-ofctl add-flow br-ex "cookie=$cookie,$fl"
	done
	mv /etc/neutron/ovs-default-flows/br-ex.tmp /etc/neutron/ovs-default-flows/br-ex
	echo "br-ex flows:"
	ovs-ofctl dump-flows br-ex
    fi
fi

touch $OURDIR/setup-network-plugin-openvswitch-done

logtend "network-plugin-openvswitch"

exit 0
