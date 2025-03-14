#!/bin/bash

set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Check if script is run as root
check_root

# Check required arguments
if [ $# -lt 3 ]; then
    echo "Error: Missing required arguments"
    echo "Usage: $0 <control-plane-endpoint> <pod-network-cidr> <service-cidr> [node-name]"
    exit 1
fi

CONTROL_PLANE_ENDPOINT=$1
POD_NETWORK_CIDR=$2
SERVICE_CIDR=$3
NODE_NAME=${4:-$(hostname -s)}

echo "Initializing Kubernetes control plane..."
echo "- Control Plane Endpoint: ${CONTROL_PLANE_ENDPOINT}"
echo "- Pod Network CIDR: ${POD_NETWORK_CIDR}"
echo "- Service CIDR: ${SERVICE_CIDR}"
echo "- Node Name: ${NODE_NAME}"

# Create kubeadm config file
KUBEADM_CONFIG_PATH="/tmp/kubeadm-config.yaml"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -f "${ROOT_DIR}/config/kubeadm-config.yaml" ]; then
    echo "Using custom kubeadm config template from ${ROOT_DIR}/config/kubeadm-config.yaml"
    cp "${ROOT_DIR}/config/kubeadm-config.yaml" "${KUBEADM_CONFIG_PATH}"
    
    # Replace placeholders in the config file
    sed -i "s|__CONTROL_PLANE_ENDPOINT__|${CONTROL_PLANE_ENDPOINT}|g" "${KUBEADM_CONFIG_PATH}"
    sed -i "s|__POD_NETWORK_CIDR__|${POD_NETWORK_CIDR}|g" "${KUBEADM_CONFIG_PATH}"
    sed -i "s|__SERVICE_CIDR__|${SERVICE_CIDR}|g" "${KUBEADM_CONFIG_PATH}"
    sed -i "s|__NODE_NAME__|${NODE_NAME}|g" "${KUBEADM_CONFIG_PATH}"
else
    echo "Creating default kubeadm config file"
    cat > "${KUBEADM_CONFIG_PATH}" << EOF
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
nodeRegistration:
  name: ${NODE_NAME}
  criSocket: unix:///run/containerd/containerd.sock
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
networking:
  podSubnet: ${POD_NETWORK_CIDR}
  serviceSubnet: ${SERVICE_CIDR}
kubernetesVersion: v1.29.0
controlPlaneEndpoint: ${CONTROL_PLANE_ENDPOINT}:6443
EOF
fi

# Initialize the control plane
echo "Running kubeadm init with the following config:"
cat "${KUBEADM_CONFIG_PATH}"
echo ""

kubeadm init --config=${KUBEADM_CONFIG_PATH} --upload-certs

# Configure kubectl for the current user
echo "Configuring kubectl for the current user..."
mkdir -p $HOME/.kube
cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

# Make kubectl work for root as well
export KUBECONFIG=/etc/kubernetes/admin.conf
echo "export KUBECONFIG=/etc/kubernetes/admin.conf" >> /root/.bashrc

# Create directory for non-root user if specified
if [ ! -z "${SUDO_USER}" ]; then
    USER_HOME=$(getent passwd ${SUDO_USER} | cut -d: -f6)
    mkdir -p ${USER_HOME}/.kube
    cp -f /etc/kubernetes/admin.conf ${USER_HOME}/.kube/config
    chown -R ${SUDO_USER}:$(id -g -n ${SUDO_USER}) ${USER_HOME}/.kube
fi

echo "Kubernetes control plane initialized successfully!"