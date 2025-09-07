#!/bin/bash

# Check OpenStack Services Status
services=(
    "nova-api"
    "nova-compute"
    "neutron-server"
    "glance-api"
    "keystone"
    "cinder-api"
)

OURDIR=/root/setup
SETTINGS=$OURDIR/settings
LOCALSETTINGS=$OURDIR/settings.local

# Source OpenStack credentials if available
if [ -f "$OURDIR/admin-openrc.py" ]; then
    source "$OURDIR/admin-openrc.py"
fi

# Create log directories if they don't exist
log_dirs=(
    "/var/log/nova"
    "/var/log/neutron"
    "/var/log/glance"
    "/var/log/keystone"
    "/var/log/cinder"
    "/var/log/mysql"
)

echo "Creating log directories..."
for dir in "${log_dirs[@]}"; do
    if [ ! -d "$dir" ]; then
        sudo mkdir -p $dir
        sudo chmod 750 $dir
        service_name=$(basename $dir)
        sudo chown ${service_name}:${service_name} $dir
        echo "Created $dir"
    fi
done

# Check service status
echo "Checking OpenStack Services..."
for service in "${services[@]}"; do
    echo "=== $service ==="
    systemctl status $service || true
    echo "Log contents for $service:"
    sudo find /var/log -name "*${service}*" -type f -exec tail -n 50 {} \; || true
    echo "-------------------"
done

# Check database
echo "Checking MySQL status..."
systemctl status mysql || true
if [ -f "/var/log/mysql/error.log" ]; then
    echo "Recent MySQL errors:"
    tail -n 50 /var/log/mysql/error.log
fi

# Check system journal for errors
echo "Checking system journal for OpenStack errors..."
journalctl -u nova* -u neutron* -u glance* -u keystone* -u cinder* --since "10 minutes ago" | grep -i error

# Check if setup completed
echo "Checking setup completion status..."
ls -la $OURDIR/*-done 2>/dev/null || echo "No completion markers found"

echo "Done checking services."
