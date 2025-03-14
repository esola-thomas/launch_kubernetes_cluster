#!/bin/bash

set -e

# Print header
echo "====================================================="
echo "Kubernetes Worker Node Setup"
echo "====================================================="

# Source common functions and configurations
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/scripts/common.sh"

# Check if script is run as root
check_root

# Check if required arguments are provided
if [ $# -lt 3 ]; then
    echo "Error: Missing required arguments"
    echo "Usage: $0 <control-plane-ip> <token> <discovery-token-ca-cert-hash>"
    echo "Example: $0 192.168.1.100 abcdef.1234567890abcdef 1234567890abcdef1234567890abcdef1234567890abcdef"
    exit 1
fi

CONTROL_PLANE_IP=$1
TOKEN=$2
DISCOVERY_TOKEN_CA_CERT_HASH=$3

# Load custom configurations if exists
if [ -f "${SCRIPT_DIR}/config/custom-values.env" ]; then
    source "${SCRIPT_DIR}/config/custom-values.env"
fi

# Set default values if not defined in custom-values.env
: "${KUBERNETES_VERSION:="stable-1"}"
: "${NODE_NAME:=$(hostname -s)}"
: "${DISABLE_SWAP:="true"}"
: "${CONTAINER_RUNTIME:="containerd"}"
: "${CONTAINER_RUNTIME_INSTALL_METHOD:="package"}"
: "${INSTALL_PREREQUISITES:="true"}"

# Determine CRI socket path based on container runtime
if [ "${CONTAINER_RUNTIME}" == "docker" ]; then
    CRI_SOCKET="unix:///var/run/cri-dockerd.sock"
    echo "Using Docker as container runtime with CRI socket: ${CRI_SOCKET}"
else
    CRI_SOCKET="unix:///run/containerd/containerd.sock"
    echo "Using Containerd as container runtime with CRI socket: ${CRI_SOCKET}"
fi

# Display configuration
echo "Configuration:"
echo "- Control Plane IP: ${CONTROL_PLANE_IP}"
echo "- Kubernetes Version: ${KUBERNETES_VERSION}"
echo "- Container Runtime: ${CONTAINER_RUNTIME}"
echo "- Container Runtime Install Method: ${CONTAINER_RUNTIME_INSTALL_METHOD}"
echo "- Node Name: ${NODE_NAME}"
echo "- CRI Socket: ${CRI_SOCKET}"
echo ""

# Execute the installation steps
if [ "${INSTALL_PREREQUISITES}" = "true" ]; then
    echo "Step 1: Installing prerequisites..."
    bash "${SCRIPT_DIR}/scripts/install-prerequisites.sh"
    echo "Prerequisites installed successfully."
fi

echo "Step 2: Installing container runtime (${CONTAINER_RUNTIME}) using ${CONTAINER_RUNTIME_INSTALL_METHOD} method..."
bash "${SCRIPT_DIR}/scripts/install-container-runtime.sh" "${CONTAINER_RUNTIME}" "${CONTAINER_RUNTIME_INSTALL_METHOD}"
echo "Container runtime installed successfully."

echo "Step 3: Installing Kubernetes components..."
bash "${SCRIPT_DIR}/scripts/install-kubernetes.sh" "${KUBERNETES_VERSION}"
echo "Kubernetes components installed successfully."

echo "Step 4: Joining the Kubernetes cluster..."
echo "Running: kubeadm join ${CONTROL_PLANE_IP}:6443 --token ${TOKEN} --discovery-token-ca-cert-hash sha256:${DISCOVERY_TOKEN_CA_CERT_HASH} --cri-socket ${CRI_SOCKET} --node-name ${NODE_NAME}"

kubeadm join ${CONTROL_PLANE_IP}:6443 \
    --token ${TOKEN} \
    --discovery-token-ca-cert-hash sha256:${DISCOVERY_TOKEN_CA_CERT_HASH} \
    --cri-socket ${CRI_SOCKET} \
    --node-name ${NODE_NAME}

echo "====================================================="
echo "Kubernetes worker node joined the cluster successfully!"
echo "====================================================="

exit 0