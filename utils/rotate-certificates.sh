#!/bin/bash

# This script rotates Kubernetes certificates to ensure security compliance
# Run this every 6-12 months as part of your security maintenance

set -e

# Print header
echo "====================================================="
echo "Kubernetes Certificate Rotation"
echo "====================================================="

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root"
    echo "Please run with sudo or as the root user"
    exit 1
fi

# Check if node is a control plane node
if [ ! -d "/etc/kubernetes/manifests" ] || [ ! -f "/etc/kubernetes/admin.conf" ]; then
    echo "Error: This script must be run on a control plane node"
    exit 1
fi

# Create backup directory
BACKUP_DIR="/etc/kubernetes/pki-backup-$(date +%Y%m%d-%H%M%S)"
echo "Creating backup of current certificates in ${BACKUP_DIR}"
mkdir -p ${BACKUP_DIR}
cp -r /etc/kubernetes/pki ${BACKUP_DIR}/
cp /etc/kubernetes/*.conf ${BACKUP_DIR}/

# Check certificate expiration dates before rotation
echo "Current certificate expiration dates:"
kubeadm certs check-expiration

# Prompt for confirmation
read -p "Do you want to proceed with certificate rotation? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Certificate rotation cancelled."
    exit 0
fi

# Rotate all certificates
echo "Rotating Kubernetes certificates..."
kubeadm certs renew all

# Restart control plane components
echo "Restarting control plane components..."
for component in /etc/kubernetes/manifests/kube-*.yaml; do
    echo "Temporarily moving ${component} to force restart"
    mv ${component} ${component}.tmp
done

sleep 5

for component in /etc/kubernetes/manifests/*.tmp; do
    target=${component%.tmp}
    echo "Restoring ${target}"
    mv ${component} ${target}
done

echo "Waiting for API server to become responsive..."
timeout=60
counter=0
while ! curl -sk https://localhost:6443/healthz >/dev/null 2>&1; do
    if [ $counter -ge $timeout ]; then
        echo "Timeout waiting for kube-apiserver to become responsive"
        break
    fi
    echo -n "."
    sleep 1
    ((counter++))
done

echo ""

# Copy new admin.conf to user's kube config
if [ ! -z "${SUDO_USER}" ]; then
    USER_HOME=$(getent passwd ${SUDO_USER} | cut -d: -f6)
    if [ -d "${USER_HOME}/.kube" ]; then
        echo "Updating ${USER_HOME}/.kube/config with new certificates"
        mkdir -p ${USER_HOME}/.kube
        cp -f /etc/kubernetes/admin.conf ${USER_HOME}/.kube/config
        chown -R ${SUDO_USER}:$(id -g -n ${SUDO_USER}) ${USER_HOME}/.kube
    fi
fi

# Update the local root user's kubeconfig
echo "Updating root user's kubeconfig with new certificates"
mkdir -p /root/.kube
cp -f /etc/kubernetes/admin.conf /root/.kube/config

# Check certificate expiration dates after rotation
echo "New certificate expiration dates:"
kubeadm certs check-expiration

echo "====================================================="
echo "Certificate rotation completed successfully!"
echo "Certificates have been backed up to: ${BACKUP_DIR}"
echo "====================================================="
echo "Note: You may need to distribute the new certificates"
echo "to users who access the cluster with client certificates."
echo "====================================================="

exit 0