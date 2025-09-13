#!/bin/bash
# Minimal Services Configuration
NODE_TYPE=${1:-controller}
source /local/repository/config.env

echo "Configuring services for $NODE_TYPE"

if [ "$NODE_TYPE" = "controller" ]; then
    # Install MySQL
    apt-get install -y mysql-server

    # Set root password
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'mysql_pass';"

    # Create basic database
    mysql -u root -pmysql_pass -e "CREATE DATABASE IF NOT EXISTS keystone;"

    # Install basic services
    apt-get install -y keystone apache2 rabbitmq-server

    # Start services
    systemctl start mysql
    systemctl start apache2
    systemctl start rabbitmq-server
fi

echo "Services configured for $NODE_TYPE"
