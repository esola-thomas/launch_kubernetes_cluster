#!/bin/bash

set -e

# Print header
echo "====================================================="
echo "Kubernetes Control Plane Node Setup"
echo "====================================================="

# Source common functions and configurations
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/scripts/common.sh"

# Check if script is run as root
check_root

# Load custom configurations if exists
if [ -f "${SCRIPT_DIR}/config/custom-values.env" ]; then
    source "${SCRIPT_DIR}/config/custom-values.env"
fi

# Set default values if not defined in custom-values.env
: "${POD_NETWORK_CIDR:="192.168.0.0/16"}"
: "${SERVICE_CIDR:="10.96.0.0/12"}"
: "${KUBERNETES_VERSION:="stable-1"}"
: "${CONTROL_PLANE_ENDPOINT:=$(hostname -I | awk '{print $1}')}"
: "${NODE_NAME:=$(hostname -s)}"
: "${DISABLE_SWAP:="true"}"
: "${CONTAINER_RUNTIME:="containerd"}"
: "${CONTAINER_RUNTIME_INSTALL_METHOD:="package"}"
: "${INSTALL_PREREQUISITES:="true"}"

# Display configuration
echo "Configuration:"
echo "- Control Plane Endpoint: ${CONTROL_PLANE_ENDPOINT}"
echo "- Pod Network CIDR: ${POD_NETWORK_CIDR}"
echo "- Service CIDR: ${SERVICE_CIDR}"
echo "- Kubernetes Version: ${KUBERNETES_VERSION}"
echo "- Container Runtime: ${CONTAINER_RUNTIME}"
echo "- Container Runtime Install Method: ${CONTAINER_RUNTIME_INSTALL_METHOD}"
echo "- Node Name: ${NODE_NAME}"
echo ""

# Execute the installation steps
if [ "${INSTALL_PREREQUISITES}" = "true" ]; then
    echo "Step 1: Installing prerequisites..."
    rm -rf /tmp/cri-dockerd  # Clean up existing directory
    bash "${SCRIPT_DIR}/scripts/install-prerequisites.sh"
    echo "Prerequisites installed successfully."
fi

echo "Step 2: Installing container runtime (${CONTAINER_RUNTIME}) using ${CONTAINER_RUNTIME_INSTALL_METHOD} method..."
bash "${SCRIPT_DIR}/scripts/install-container-runtime.sh" "${CONTAINER_RUNTIME}" "${CONTAINER_RUNTIME_INSTALL_METHOD}"
echo "Container runtime installed successfully."

echo "Step 3: Installing Kubernetes components..."
bash "${SCRIPT_DIR}/scripts/install-kubernetes.sh" "${KUBERNETES_VERSION}"
echo "Kubernetes components installed successfully."

echo "Step 4: Initializing Kubernetes control plane..."
bash "${SCRIPT_DIR}/scripts/init-control-plane.sh" \
    "${CONTROL_PLANE_ENDPOINT}" \
    "${POD_NETWORK_CIDR}" \
    "${SERVICE_CIDR}" \
    "${NODE_NAME}"
echo "Control plane initialized successfully."

echo "Step 5: Installing network add-on..."
bash "${SCRIPT_DIR}/scripts/install-network-addon.sh" "${POD_NETWORK_CIDR}"
echo "Network add-on installed successfully."

echo "====================================================="
echo "Kubernetes control plane setup completed successfully!"
echo "====================================================="

# Display join command for worker nodes
KUBEADM_TOKEN=$(kubeadm token create)
DISCOVERY_TOKEN_CA_CERT_HASH=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | \
                              openssl rsa -pubin -outform der 2>/dev/null | \
                              openssl dgst -sha256 -hex | sed 's/^.* //')

echo ""
echo "To add worker nodes to this cluster, run the following on each worker node:"
echo ""
echo "  ./setup-worker.sh ${CONTROL_PLANE_ENDPOINT} ${KUBEADM_TOKEN} ${DISCOVERY_TOKEN_CA_CERT_HASH}"
echo ""
echo "Or run the kubeadm command directly:"
echo ""
echo "  kubeadm join ${CONTROL_PLANE_ENDPOINT}:6443 --token ${KUBEADM_TOKEN} \\"
echo "    --discovery-token-ca-cert-hash sha256:${DISCOVERY_TOKEN_CA_CERT_HASH}"
echo ""

exit 0