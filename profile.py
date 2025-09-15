#!/usr/bin/env python
# profile.py: A geni-lib script to deploy a multi-node OpenStack + Kubernetes
# environment on CloudLab.

# Import the necessary geni-lib libraries.
# geni.portal is used for defining user-configurable parameters.
# geni.rspec.pg is for defining the resources in the ProtoGENI RSpec format.
import geni.portal as portal
import geni.rspec.pg as pg
import geni.rspec.emulab as emulab

# Create a portal context object. This is the main interface to the
# CloudLab portal environment.
pc = portal.Context()

# === Profile Parameters ===
# Define user-configurable parameters that will appear on the CloudLab
# instantiation page. This makes the profile flexible.

# Parameter for selecting the OS image.
# Note: As of the writing of this report, the official Ubuntu 24.04 image is
# still in development. The emulab-devel issue tracker indicates a beta
# image is available named 'UBUNTU24-64-BETA'.[33] We use its URN here.
# This should be updated to the stable URN when it is released.
pc.defineParameter(
    "osImage", "Operating System Image",
    portal.ParameterType.IMAGE,
    "urn:publicid:IDN+emulab.net+image+emulab-ops:UBUNTU24-64-STD",
    longDescription="OS image for all nodes. The default is Ubuntu 24.04."
)

# Parameter for selecting the physical hardware type.
# An empty string lets CloudLab choose the best available type.
# Specifying a type (e.g., 'd710', 'm510') ensures hardware homogeneity.[11]
pc.defineParameter(
    "hwType", "Hardware Type",
    portal.ParameterType.NODETYPE,
    "d430",
    longDescription="Specify a hardware type for all nodes. Leave empty for any available type."
)

# Parameter for the number of compute nodes.
# The total number of nodes will be this value + 1 (for the controller).
pc.defineParameter(
    "computeNodeCount", "Number of Compute Nodes",
    portal.ParameterType.INTEGER,
    2,
    longDescription="The number of OpenStack compute nodes to provision."
)

pc.defineParameter(
    "os_username", "OpenStack Username", 
    portal.ParameterType.STRING, 
    "user",
    longDescription="Custom username for OpenStack authentication (required)"
)

pc.defineParameter(
    "os_password", "OpenStack Password",
    portal.ParameterType.STRING,
    "password",
    longDescription="Custom password for OpenStack authentication (required)"
)

# Retrieve the bound parameters from the portal context.
params = pc.bindParameters()

# === Resource Specification ===
# Create a request object to start building the RSpec.
request = pc.makeRequestRSpec()

# Create a LAN object to connect all nodes.
lan = request.LAN("lan")

# --- Controller Node Definition ---
# This node will run all OpenStack control plane services and orchestrate
# the deployment.
controller = request.RawPC("controller")
controller.disk_image = params.osImage
if params.hwType:
    controller.hardware_type = params.hwType

# Add the controller node to the LAN.
iface_controller = controller.addInterface("if0")
lan.addInterface(iface_controller)

# Add post-boot execution services to the controller node.
# These commands are executed sequentially as root after the OS boots.
# The repository is cloned to /local/repository automatically.[9, 16]
controller.addService(pg.Execute(shell="bash", command="sudo /bin/bash /local/repository/scripts/01-install-openstack.sh"))
controller.addService(pg.Execute(shell="bash", command="sudo /bin/bash /local/repository/scripts/02-configure-magnum.sh"))

# --- Compute Nodes Definition ---
# These nodes will run the OpenStack Nova compute service and host the VMs.
for i in range(params.computeNodeCount):
    node_name = "compute-{}".format(i+1)
    node = request.RawPC(node_name)
    node.disk_image = params.osImage
    if params.hwType:
        node.hardware_type = params.hwType
    
    # Add the compute node to the LAN.
    iface_compute = node.addInterface("if0")
    lan.addInterface(iface_compute)

# === Finalization ===
# Print the generated RSpec to the CloudLab portal, which will then use it
# to provision the experiment.
pc.printRequestRSpec(request)
