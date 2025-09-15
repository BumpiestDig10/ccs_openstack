# profile.py: A geni-lib script to deploy a multi-node
# OpenStack + Kubernetes environment on CloudLab.

#!/usr/bin/env python

# Import the necessary geni-lib libraries.
# geni.portal is used for defining user-configurable parameters.
# geni.rspec.pg is for defining the resources in the ProtoGENI RSpec format.
import geni.portal as portal
import geni.rspec.pg as pg
import geni.rspec.emulab as emulab
import geni.rspec.igext as ig

# Create a portal context object.
# This is the main interface to the CloudLab portal environment.
pc = portal.Context()

# === Profile Parameters ===
# Define user-configurable parameters that will appear
# on the CloudLab instantiation page.

# Parameter for selecting the OS image.
# Note: You can find other images and their URNs at:
# https://www.cloudlab.us/images.php
pc.defineParameter(
    "osImage", "Operating System Image",
    portal.ParameterType.IMAGE,
    "urn:publicid:IDN+emulab.net+image+emulab-ops:UBUNTU24-64-STD",
    longDescription="OS image for all nodes. Ubuntu 24.04 is used here."
)

# Parameter for selecting the physical hardware type.
# An empty string lets CloudLab choose the best available type.
# Specifying a type (e.g., 'd430', 'm510') ensures hardware homogeneity.[11]
pc.defineParameter(
    "hwType", "Hardware Type",
    portal.ParameterType.NODETYPE,
    "d430", # Default to d430 nodes.
    longDescription="Specify a hardware type for all nodes. Clear Selection for any available type."
)

# Parameter for the number of compute nodes.
# The total number of nodes will be this value + 1 (for the controller).
pc.defineParameter(
    "computeNodeCount", "Number of Compute Nodes",
    portal.ParameterType.INTEGER,
    2,
    longDescription="The number of OpenStack compute nodes to provision. Total number of nodes will be n+1 (including controller node). Recommended: 2 or more. Try increasing this if Kubernetes Cluster creation fails due to insufficient resources."
)

# Parameters for OpenStack authentication.
# These will be used in the DevStack configuration.
# Default values are provided for convenience but should be changed.
pc.defineParameter(
    "os_username", "OpenStack Username", 
    portal.ParameterType.STRING, 
    "nevilleLongbottom",
    longDescription="Custom username for OpenStack authentication (required). Defaulting to 'nevilleLongbottom'."
)

pc.defineParameter(
    "os_password", "OpenStack Password",
    portal.ParameterType.STRING,
    "anythingOffTheTrolley?",
    longDescription="Custom password for OpenStack authentication (required). Defaulting to 'anythingOffTheTrolley?'."  # TODO Check if this affects dashboard credentials, my guess - it doesn't.
)

# Retrieve the bound parameters from the portal context.
params = pc.bindParameters()

# === Resource Specification ===
# Create a request object to start building the RSpec.
request = pc.makeRequestRSpec()

# Create a LAN object to connect all nodes.
lan = request.LAN("lan")

# --- Controller Node Definition ---
# This node will run all OpenStack control plane services and
# orchestrate the deployment.
controller = request.RawPC("controller")
controller.disk_image = params.osImage
if params.hwType:
    controller.hardware_type = params.hwType

# Add the controller node to the LAN.
iface_controller = controller.addInterface("if0")
lan.addInterface(iface_controller)

# Add post-boot execution services to the controller node.
# These commands are executed sequentially after the OS boots.
# The repository is cloned to /local/repository automatically.
controller.addService(pg.Execute(shell="sh", command="sudo chmod +x /local/repository/scripts/01-install-openstack.sh"))
controller.addService(pg.Execute(shell="sh", command="sudo -H /local/repository/scripts/01-install-openstack.sh {}".format(params.os_password)))
controller.addService(pg.Execute(shell="sh", command="sudo chmod +x /local/repository/scripts/02-configure-magnum.sh"))
controller.addService(pg.Execute(shell="sh", command="sudo -H /local/repository/scripts/02-configure-magnum.sh"))

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
    

# === Instructions ===
# The 'instructions' text is displayed on the experiment page after the user
# has created an experiment using the profile. Markdown is supported.

instructions = """
### Basic Instructions

**PATIENCE IS KEY!** The OpenStack installation and configuration process is complex and can take 30-60 minutes to complete.
- While the experiment nodes are being provisioned, you can monitor the `logs` on the project page.
- When the nodes start booting, you can inspect their status either in `Topology View` or `List View`.
- Once a node is booted and it's 'Status' column shows 'ready', you can click on the settings gear icon on the right side of the experiment page to open a shell to the node. Here, you can monitor the installation progress by viewing log files or by inspecting running services.

Once the controller node's `Status` changes to `ready`, and profile configuration scripts finish configuring OpenStack (indicated by `Startup` column changing to `Finished`), you'll be able to visit and log in to [the OpenStack Dashboard](http://{host-controller}/dashboard).
Default dashboard credentials are:
1. `username`: admin , `password`: password
2. `username`: demo , `password`: password

> **OpenStack Login Credentials**
> Click on the `Bindings` tab on the experiment page to see the OpenStack login credentials you specified when instantiating the profile.

### Some commands to run on the controller node

Click on the settings gear icon on the right side of the experiment page to open a shell to the controller node.

#### Run every time you open a new shell
```bash
$ source /opt/devstack/openrc admin admin
```

#### Create Keypair and Deploy a Kubernetes Cluster
```bash
$ openstack keypair create mykey > ~/.ssh/mykey.pem   # Create a keypair for use with Kubernetes nodes.
$ chmod 600 ~/.ssh/mykey.pem  # Permissions for the private key.
$ openstack keypair list	# To Confirm the keypair was created.

$ openstack [option] --help
$ openstack coe cluster template list # This shows a list of custom K8s templates. Note the UUID of the required template.

$ openstack coe cluster create --cluster-template <UUID> --master-count 1 --node-count 2 --keypair mykey  my-first-k8s-cluster	# Creates a K8s deployement named 'my-first-k8s-cluster'. Replace <UUID> with the actual UUID as noted previously.
$ watch openstack coe cluster show my-first-k8s-cluster    # Monitor the cluster creation process. Press Ctrl+C to exit watch.

$ openstack stack list
```

### Resources
- [CloudLab Documentation](https://docs.cloudlab.us/)
- [OpenStack Documentation](https://docs.openstack.org/)
- [Kubernetes Documentation](https://kubernetes.io/docs/home/)
- [DevStack Documentation](https://docs.openstack.org/devstack/latest/)
- [Magnum Documentation](https://docs.openstack.org/magnum/latest/)
- [Keystone Documentation](https://docs.openstack.org/keystone/latest/)
- [Horizon Documentation](https://docs.openstack.org/horizon/latest/)
- [Nova Documentation](https://docs.openstack.org/nova/latest/)
- [Neutron Documentation](https://docs.openstack.org/neutron/latest/)
- [Glance Documentation](https://docs.openstack.org/glance/latest/)
- [Cinder Documentation](https://docs.openstack.org/cinder/latest/)
- [Heat Documentation](https://docs.openstack.org/heat/latest/)
- [Manila Documentation](https://docs.openstack.org/manila/latest/)
"""

# === Description ===
# Set the description to be displayed on the profile selection page.
description = """
Simple multi-node OpenStack + Kubernetes deployment using Ubuntu 24.04.
Kubernetes is deployed using OpenStack Magnum.
This profile provisions one controller node and a user-defined number of compute nodes.
Default Magnum scripts and settings are used for the deployment.
"""

# Set the instructions to be displayed on the experiment page.
tour = ig.Tour()
tour.Description = (ig.Tour.MARKDOWN, description)
tour.Instructions(ig.Tour.MARKDOWN,instructions)
request.addTour(tour)

# === Finalization ===
# Print the generated RSpec to the CloudLab portal, which will then use it
# to provision the experiment.
pc.printRequestRSpec(request)