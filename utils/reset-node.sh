#!/bin/bash

# Reset a Kubernetes node to a clean state

set -e

# Print header
echo "====================================================="
echo "Kubernetes Node Reset"
echo "====================================================="

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root"
    echo "Please run with sudo or as the root user"
    exit 1
fi

# Ask for confirmation
echo "WARNING: This will completely reset this node, removing all Kubernetes components and configurations."
echo "This operation cannot be undone!"
read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    exit 0
fi

# Drain the node if it's part of a cluster and kubectl is available
if command -v kubectl &> /dev/null; then
    NODE_NAME=$(hostname -s)
    echo "Attempting to drain node ${NODE_NAME} from the cluster..."
    kubectl drain ${NODE_NAME} --delete-emptydir-data --force --ignore-daemonsets || true
    echo "Attempting to delete node ${NODE_NAME} from the cluster..."
    kubectl delete node ${NODE_NAME} || true
fi

# Run kubeadm reset
echo "Resetting kubeadm..."
kubeadm reset -f

# Stop and disable kubelet service
echo "Stopping kubelet service..."
systemctl stop kubelet || true
systemctl disable kubelet || true

# Remove Kubernetes packages
echo "Removing Kubernetes packages..."
if command -v apt &> /dev/null; then
    apt-get remove -y kubeadm kubectl kubelet kubernetes-cni || true
elif command -v dnf &> /dev/null; then
    dnf remove -y kubeadm kubectl kubelet kubernetes-cni || true
elif command -v yum &> /dev/null; then
    yum remove -y kubeadm kubectl kubelet kubernetes-cni || true
fi

# Clean up directories
echo "Cleaning up directories..."
rm -rf /etc/kubernetes/ /var/lib/kubelet/ /var/lib/etcd/ $HOME/.kube

# Clean up container runtime
echo "Cleaning up container runtime..."
systemctl stop containerd || true
systemctl disable containerd || true
rm -rf /var/lib/containerd/

# If Docker was used
if command -v docker &> /dev/null; then
    echo "Docker found, cleaning up Docker resources..."
    systemctl stop docker || true
    systemctl disable docker || true
    rm -rf /var/lib/docker/
    
    # Stop and remove cri-dockerd if present
    systemctl stop cri-docker.socket || true
    systemctl stop cri-docker.service || true
    systemctl disable cri-docker.socket || true
    systemctl disable cri-docker.service || true
fi

# Clean up network configurations
echo "Cleaning up network configurations..."
rm -rf /etc/cni/net.d/

# Clean up iptables rules
echo "Cleaning up iptables rules..."
iptables -F
iptables -t nat -F
iptables -t mangle -F
iptables -X

# Clean up ipvs
if command -v ipvsadm &> /dev/null; then
    echo "Cleaning up IPVS rules..."
    ipvsadm -C
fi

echo "====================================================="
echo "Node reset completed successfully!"
echo "This node can now be reinstalled as a new Kubernetes node."
echo "====================================================="