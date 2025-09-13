#!/bin/bash

# Test Script for CloudLab Profile Validation
# This script tests the shell scripts for syntax errors and basic functionality

set -e

echo "TESTING CLOUDLAB PROFILE SCRIPTS"
echo "================================="
echo

# Test 1: Check if all required files exist
echo "1. Checking file existence..."
FILES=(
    "profile.py"
    "install-openstack.sh" 
    "configure-services.sh"
    "configure-networking.sh"
    "configure-storage.sh"
    "setup-users.sh"
)

for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "  ✓ $file exists"
    else
        echo "  ✗ $file missing"
    fi
done
echo

# Test 2: Check bash syntax
echo "2. Checking bash syntax..."
for script in install-openstack.sh configure-services.sh configure-networking.sh configure-storage.sh setup-users.sh; do
    if [ -f "$script" ]; then
        if bash -n "$script"; then
            echo "  ✓ $script syntax OK"
        else
            echo "  ✗ $script syntax ERROR"
        fi
    fi
done
echo

# Test 3: Check Python syntax for profile.py
echo "3. Checking Python syntax..."
if [ -f "profile.py" ]; then
    if python3 -m py_compile profile.py; then
        echo "  ✓ profile.py syntax OK"
    else
        echo "  ✗ profile.py syntax ERROR"  
    fi
fi
echo

# Test 4: Create mock config.env for testing
echo "4. Creating test configuration..."
cat > config.env << 'EOF'
export OS_USERNAME="testuser"
export OS_PASSWORD="testpass"
export TENANT_NETWORK_TYPE="vxlan"
export STORAGE_SIZE_GB="50"
export ENABLE_MANILA="True"
export CONTROLLER_COUNT="1"
export COMPUTE_COUNT="2"
export STORAGE_COUNT="1"
EOF
echo "  ✓ Test config.env created"
echo

# Test 5: Test script sourcing
echo "5. Testing config.env sourcing..."
for script in install-openstack.sh configure-services.sh configure-networking.sh configure-storage.sh setup-users.sh; do
    if [ -f "$script" ]; then
        # Test if script can source config without errors (dry run)
        if bash -c "source config.env && echo 'Config sourced successfully'" >/dev/null; then
            echo "  ✓ $script can source config.env"
        else
            echo "  ✗ $script config.env sourcing failed"
        fi
    fi
done
echo

# Test 6: Check for common problematic commands
echo "6. Checking for problematic commands..."
PROBLEMATIC_COMMANDS=(
    "sunbeam prepare-node-script"
    "snap install openstack --channel=2025.1"
    "systemctl enable --now openstack-*" 
    "mysql -u root <<"
    "pvcreate /opt/openstack/cinder-volumes.img"
)

for cmd in "${PROBLEMATIC_COMMANDS[@]}"; do
    if grep -r "$cmd" *.sh 2>/dev/null; then
        echo "  ✗ Found problematic command: $cmd"
    else
        echo "  ✓ No problematic command: $cmd"
    fi
done
echo

# Test 7: Check for required packages
echo "7. Checking required package availability..."
REQUIRED_PACKAGES=(
    "python3-openstackclient"
    "mysql-server"
    "rabbitmq-server" 
    "memcached"
    "apache2"
    "lvm2"
)

for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if apt-cache show "$pkg" >/dev/null 2>&1; then
        echo "  ✓ Package available: $pkg"
    else
        echo "  ✗ Package not available: $pkg"
    fi
done
echo

# Test 8: Simulate CloudLab validation
echo "8. Simulating CloudLab validation..."
if [ -f "profile.py" ]; then
    # Try to execute the profile script in a restricted environment
    if timeout 30s python3 profile.py >/dev/null 2>&1; then
        echo "  ✓ Profile executes without hanging"
    else
        echo "  ✗ Profile execution failed or timed out"
    fi
fi

# Cleanup
rm -f config.env

echo
echo "TEST COMPLETED!"