#!/usr/bin/env python

"""
OpenStack Epoxy 2025.1 on Ubuntu 24.04 LTS - CloudLab Profile

This profile creates a modern OpenStack cloud with the following features:
- Ubuntu 24.04 LTS as the base operating system
- OpenStack Epoxy 2025.1 with latest features
- Custom user authentication (configurable username/password)
- Dynamic resource allocation with Nova
- Personal storage with Cinder
- Shared storage with Manila
- Horizon web dashboard
- VXLAN tenant networking (configurable)
- Multi-user support with project isolation
- SSH and ping access by default
- Configurable storage sizing

Instructions:
After your experiment starts, wait for all nodes to complete their startup scripts.
Then access the Horizon dashboard using the URL provided in the experiment status page.
Use your configured username and password to log in.
"""

import geni.portal as portal
import geni.rspec.pg as pg
import geni.rspec.emulab as emulab

# Create a portal context
pc = portal.Context()

# Create a Request object to start building the RSpec
request = pc.makeRequestRSpec()

# Profile parameters
pc.defineParameter("controller_count", "Number of Controller Nodes", 
                  portal.ParameterType.INTEGER, 1,
                  longDescription="Number of OpenStack controller nodes (1-3)")

pc.defineParameter("compute_count", "Number of Compute Nodes",
                  portal.ParameterType.INTEGER, 1, 
                  longDescription="Number of OpenStack compute nodes (1-10)")

pc.defineParameter("storage_count", "Number of Storage Nodes",
                  portal.ParameterType.INTEGER, 1,
                  longDescription="Number of dedicated storage nodes (1-5)")

pc.defineParameter("node_type", "Hardware Type",
                  portal.ParameterType.NODETYPE, "d430",
                  longDescription="Hardware type for all nodes")

pc.defineParameter("os_username", "OpenStack Username", 
                  portal.ParameterType.STRING, "user",
                  longDescription="Custom username for OpenStack authentication (required)")

pc.defineParameter("os_password", "OpenStack Password",
                  portal.ParameterType.STRING, "password",
                  longDescription="Custom password for OpenStack authentication (required)")

pc.defineParameter("tenant_network_type", "Tenant Network Type",
                  portal.ParameterType.STRING, "vxlan",
                  ["vxlan", "vlan", "flat"],
                  longDescription="Default tenant network type (VXLAN recommended)")

pc.defineParameter("storage_size_gb", "Storage Size per Node (GB)",
                  portal.ParameterType.INTEGER, 100,
                  longDescription="Storage size in GB per node (minimum 50GB)")

pc.defineParameter("enable_manila", "Enable Shared File Storage (Manila)",
                  portal.ParameterType.BOOLEAN, True,
                  longDescription="Enable Manila for shared file storage between users")

# Bind the parameters to local variables
params = pc.bindParameters()

# Validate parameters
if not params.os_username or not params.os_password:
    pc.reportError("Both OpenStack username and password are required")

if params.storage_size_gb < 50:
    pc.reportError("Storage size must be at least 50GB")

if params.controller_count < 1 or params.controller_count > 3:
    pc.reportError("Controller count must be between 1 and 3")

if params.compute_count < 1 or params.compute_count > 10:
    pc.reportError("Compute count must be between 1 and 10")

# Create the management network
mgmt_lan = request.LAN("management-lan")
mgmt_lan.best_effort = True

# Create the data network for VM traffic
data_lan = request.LAN("data-lan") 
data_lan.best_effort = True

# Create controller nodes
controllers = []
for i in range(params.controller_count):
    node_name = "controller-{}".format(i+1)
    node = request.RawPC(node_name)
    node.hardware_type = params.node_type
    node.disk_image = "urn:publicid:IDN+emulab.net+image+emulab-ops//UBUNTU24-64-STD"
    
    # Management interface
    mgmt_iface_name = "mgmt-{}".format(i)
    mgmt_iface = node.addInterface(mgmt_iface_name)
    mgmt_lan.addInterface(mgmt_iface)
    
    # Data interface  
    data_iface_name = "data-{}".format(i)
    data_iface = node.addInterface(data_iface_name)
    data_lan.addInterface(data_iface)
    
    # Add extra storage
    storage_name = "{}-storage".format(node_name)
    bs = node.Blockstore(storage_name, "/opt/openstack")
    bs.size = "{}GB".format(params.storage_size_gb)
    
    # Install scripts
    node.addService(pg.Execute(shell="bash", 
                              command="sudo bash /local/repository/install-openstack.sh controller"))
    
    controllers.append(node)

# Create compute nodes
computes = []
for i in range(params.compute_count):
    node_name = "compute-{}".format(i+1)
    node = request.RawPC(node_name)
    node.hardware_type = params.node_type
    node.disk_image = "urn:publicid:IDN+emulab.net+image+emulab-ops//UBUNTU24-64-STD"
    
    # Management interface
    mgmt_iface_name = "mgmt-{}".format(i)
    mgmt_iface = node.addInterface(mgmt_iface_name)
    mgmt_lan.addInterface(mgmt_iface)
    
    # Data interface
    data_iface_name = "data-{}".format(i)
    data_iface = node.addInterface(data_iface_name)
    data_lan.addInterface(data_iface)
    
    # Add storage for VMs
    storage_name = "{}-storage".format(node_name)
    bs = node.Blockstore(storage_name, "/var/lib/nova")
    bs.size = "{}GB".format(params.storage_size_gb * 2)  # Double size for VM storage
    
    # Install scripts
    node.addService(pg.Execute(shell="bash",
                              command="sudo bash /local/repository/install-openstack.sh compute"))
    
    computes.append(node)

# Create storage nodes if more than basic storage needed
if params.storage_count > 0:
    storage_nodes = []
    for i in range(params.storage_count):
        node_name = "storage-{}".format(i+1)
        node = request.RawPC(node_name)
        node.hardware_type = params.node_type  
        node.disk_image = "urn:publicid:IDN+emulab.net+image+emulab-ops//UBUNTU24-64-STD"
        
        # Management interface
        mgmt_iface_name = "mgmt-{}".format(i)
        mgmt_iface = node.addInterface(mgmt_iface_name)
        mgmt_lan.addInterface(mgmt_iface)
        
        # Multiple storage devices for Cinder and Manila
        for j in range(3):  # 3 storage devices per node
            storage_name = "{}-disk-{}".format(node_name, j+1)
            mount_point = "/dev/disk{}".format(j+1)
            bs = node.Blockstore(storage_name, mount_point)
            bs.size = "{}GB".format(params.storage_size_gb)
        
        # Install scripts
        node.addService(pg.Execute(shell="bash",
                                  command="sudo bash /local/repository/install-openstack.sh storage"))
        
        storage_nodes.append(node)

# Set up configuration parameters that will be available to scripts
config_command = """
cat > /local/repository/config.env << 'EOF'
export OS_USERNAME='{}'
export OS_PASSWORD='{}'
export TENANT_NETWORK_TYPE='{}'
export STORAGE_SIZE_GB='{}'
export ENABLE_MANILA='{}'
export CONTROLLER_COUNT='{}'
export COMPUTE_COUNT='{}'
export STORAGE_COUNT='{}'
EOF
""".format(
    params.os_username,
    params.os_password, 
    params.tenant_network_type,
    params.storage_size_gb,
    str(params.enable_manila),
    params.controller_count,
    params.compute_count,
    params.storage_count
)

# Add the configuration service to the first controller node
if controllers:
    controllers[0].addService(pg.Execute(shell="bash", command=config_command))

# Print the RSpec to the enclosing page
pc.printRequestRSpec(request)