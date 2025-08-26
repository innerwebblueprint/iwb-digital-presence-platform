#!/bin/bash

# Script to create a minimal environment file for n8n with only safe variables
# This runs during container startup to extract only the variables n8n needs

# Create directory if it doesn't exist
mkdir -p /var/setup

# Extract only the specific variable n8n needs from the main environment
if [ -f /var/setup/scripts/setup-env.sh ]; then
    # Source the main environment file to get variables
    source /var/setup/scripts/setup-env.sh
    
    # Create a minimal .env file with only the bucket name
    cat > /var/setup/.env <<EOF
# Minimal environment for n8n - only contains non-sensitive variables
IWB_STORJ_WPOPS_BUCKET=${IWB_STORJ_WPOPS_BUCKET}
EOF
    
    # Set restrictive permissions - only n8n can read
    chown n8n:n8n /var/setup/.env
    chmod 600 /var/setup/.env
    
    echo "Created minimal environment file for n8n with bucket name: ${IWB_STORJ_WPOPS_BUCKET}"
else
    echo "Warning: setup-env.sh not found, creating empty n8n environment"
    touch /var/setup/.env
    chown n8n:n8n /var/setup/.env
    chmod 600 /var/setup/.env
fi
