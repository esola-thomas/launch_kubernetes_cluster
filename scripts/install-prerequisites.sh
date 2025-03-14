#!/bin/bash

set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Check if script is run as root
check_root

# Detect OS
detect_os

echo "Installing prerequisites for Kubernetes..."

# Configure system settings
configure_system

# Update package lists
echo "Updating package lists..."
if [[ "${OS}" == "ubuntu" || "${OS}" == "debian" ]]; then
    if [[ "$(lsb_release -rs)" == "24.04" ]]; then
        # Add Docker's official GPG key:
        sudo apt-get update;
        sudo apt-get install ca-certificates curl;
        sudo install -m 0755 -d /etc/apt/keyrings;
        sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc;
        sudo chmod a+r /etc/apt/keyrings/docker.asc

        # Add the repository to Apt sources:
        echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null;
        sudo apt-get update;
    else
        echo "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    fi
    apt-get update
elif [[ "${OS}" == "rhel" || "${OS}" == "centos" || "${OS}" == "fedora" ]]; then
    dnf check-update || true
fi

# Install required packages
echo "Installing required packages..."
if [[ "${OS}" == "ubuntu" || "${OS}" == "debian" ]]; then
    sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo apt-get install -y ca-certificates curl gnupg lsb-release apt-transport-https git
elif [[ "${OS}" == "rhel" || "${OS}" == "centos" || "${OS}" == "fedora" ]]; then
    dnf install -y ca-certificates curl gnupg git
fi

# Check and configure firewall if needed
if command_exists ufw; then
    echo "Configuring UFW firewall rules for Kubernetes..."
    ufw allow 6443/tcp  # Kubernetes API server
    ufw allow 2379:2380/tcp  # etcd server client API
    ufw allow 10250/tcp  # Kubelet API
    ufw allow 10251/tcp  # kube-scheduler
    ufw allow 10252/tcp  # kube-controller-manager
    ufw allow 8285/udp  # Flannel overlay network - udp
    ufw allow 8472/udp  # Flannel overlay network - vxlan
    ufw allow 179/tcp  # Calico networking (BGP)
fi

if command_exists firewalld; then
    echo "Configuring firewalld rules for Kubernetes..."
    firewall-cmd --permanent --add-port=6443/tcp  # Kubernetes API server
    firewall-cmd --permanent --add-port=2379-2380/tcp  # etcd server client API
    firewall-cmd --permanent --add-port=10250/tcp  # Kubelet API
    firewall-cmd --permanent --add-port=10251/tcp  # kube-scheduler
    firewall-cmd --permanent --add-port=10252/tcp  # kube-controller-manager
    firewall-cmd --permanent --add-port=8285/udp  # Flannel overlay network - udp
    firewall-cmd --permanent --add-port=8472/udp  # Flannel overlay network - vxlan
    firewall-cmd --permanent --add-port=179/tcp  # Calico networking (BGP)
    firewall-cmd --reload
fi

# Verify MAC address and product_uuid are unique
MAC_ADDRESS=$(ip link | grep -A 1 "eth0" | grep link/ether | awk '{print $2}')
PRODUCT_UUID=$(sudo cat /sys/class/dmi/id/product_uuid)

echo "MAC Address: ${MAC_ADDRESS}"
echo "Product UUID: ${PRODUCT_UUID}"
echo "Note: Please ensure these are unique across all nodes in your cluster."

echo "Prerequisites installation completed."