#!/bin/bash

set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Check if script is run as root
check_root

# Check if Kubernetes version is provided
KUBERNETES_VERSION="${1:-stable-1}"
echo "Installing Kubernetes components (version: ${KUBERNETES_VERSION})..."

# Detect OS
detect_os

# Install kubeadm, kubelet, and kubectl
if [[ "${OS}" == "ubuntu" || "${OS}" == "debian" ]]; then
    echo "Installing Kubernetes components on Debian/Ubuntu..."
    
    # Install required packages
    apt-get update
    apt-get install -y apt-transport-https ca-certificates curl
    
    # Add Kubernetes apt repository
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
    
    apt-get update
    
    # If version is not specified as stable, install specific version
    if [[ "${KUBERNETES_VERSION}" == "stable"* ]]; then
        apt-get install -y kubelet kubeadm kubectl
    else
        apt-get install -y kubelet=${KUBERNETES_VERSION}-* kubeadm=${KUBERNETES_VERSION}-* kubectl=${KUBERNETES_VERSION}-*
    fi
    
    # Hold packages to prevent automatic upgrades
    apt-mark hold kubelet kubeadm kubectl
    
elif [[ "${OS}" == "rhel" || "${OS}" == "centos" || "${OS}" == "fedora" ]]; then
    echo "Installing Kubernetes components on RHEL/CentOS/Fedora..."
    
    # Add Kubernetes yum repository
    cat <<EOF | tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF
    
    # Set SELinux to permissive mode
    setenforce 0
    sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
    
    # Install required packages
    if [[ "${KUBERNETES_VERSION}" == "stable"* ]]; then
        dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
    else
        dnf install -y kubelet-${KUBERNETES_VERSION} kubeadm-${KUBERNETES_VERSION} kubectl-${KUBERNETES_VERSION} --disableexcludes=kubernetes
    fi
    
    # Enable kubelet service
    systemctl enable --now kubelet
fi

# Enable kubelet service
systemctl enable kubelet

echo "Kubernetes components installation completed."