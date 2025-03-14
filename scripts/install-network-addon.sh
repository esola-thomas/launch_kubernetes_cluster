#!/bin/bash

set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Check if script is run as root
check_root

# Check if pod network CIDR is provided
POD_NETWORK_CIDR="${1:-192.168.0.0/16}"
echo "Installing network addon with Pod Network CIDR: ${POD_NETWORK_CIDR}"

# Load custom configurations if exists
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "${ROOT_DIR}/config/custom-values.env" ]; then
    source "${ROOT_DIR}/config/custom-values.env"
fi

# Set default values if not defined in custom-values.env
: "${NETWORK_ADDON:="calico"}"
: "${CALICO_VERSION:="v3.27.0"}"
: "${FLANNEL_VERSION:="v0.24.0"}"

# Install network addon
case "${NETWORK_ADDON}" in
    "calico")
        echo "Installing Calico network addon..."
        
        # Check if custom configuration exists
        if [ -f "${ROOT_DIR}/network-addons/calico.yaml" ]; then
            echo "Using custom Calico configuration from ${ROOT_DIR}/network-addons/calico.yaml"
            CALICO_CONFIG="${ROOT_DIR}/network-addons/calico.yaml"
            
            # Replace pod network CIDR in config file if needed
            sed -i "s|192.168.0.0/16|${POD_NETWORK_CIDR}|g" "${CALICO_CONFIG}"
        else
            echo "Downloading Calico manifest..."
            CALICO_CONFIG="/tmp/calico.yaml"
            curl -L https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml -o ${CALICO_CONFIG}
            
            # Replace pod network CIDR in config file if needed
            sed -i "s|192.168.0.0/16|${POD_NETWORK_CIDR}|g" "${CALICO_CONFIG}"
        fi
        
        # Apply Calico configuration
        kubectl apply -f ${CALICO_CONFIG}
        ;;
        
    "flannel")
        echo "Installing Flannel network addon..."
        
        # Check if custom configuration exists
        if [ -f "${ROOT_DIR}/network-addons/flannel.yaml" ]; then
            echo "Using custom Flannel configuration from ${ROOT_DIR}/network-addons/flannel.yaml"
            FLANNEL_CONFIG="${ROOT_DIR}/network-addons/flannel.yaml"
            
            # Replace pod network CIDR in config file if needed
            sed -i "s|\"Network\": \"10.244.0.0/16\"|\"Network\": \"${POD_NETWORK_CIDR}\"|g" "${FLANNEL_CONFIG}"
        else
            echo "Downloading Flannel manifest..."
            FLANNEL_CONFIG="/tmp/flannel.yaml"
            curl -L https://raw.githubusercontent.com/flannel-io/flannel/${FLANNEL_VERSION}/Documentation/kube-flannel.yml -o ${FLANNEL_CONFIG}
            
            # Replace pod network CIDR in config file if needed
            sed -i "s|\"Network\": \"10.244.0.0/16\"|\"Network\": \"${POD_NETWORK_CIDR}\"|g" "${FLANNEL_CONFIG}"
        fi
        
        # Apply Flannel configuration
        kubectl apply -f ${FLANNEL_CONFIG}
        ;;
        
    "custom")
        echo "Installing custom network addon from ${ROOT_DIR}/network-addons/custom.yaml"
        if [ -f "${ROOT_DIR}/network-addons/custom.yaml" ]; then
            kubectl apply -f "${ROOT_DIR}/network-addons/custom.yaml"
        else
            echo "Error: Custom network addon configuration not found at ${ROOT_DIR}/network-addons/custom.yaml"
            exit 1
        fi
        ;;
        
    *)
        echo "Error: Unsupported network addon: ${NETWORK_ADDON}"
        echo "Supported network addons: calico, flannel, custom"
        exit 1
        ;;
esac

# Wait for network addon to be ready
echo "Waiting for network addon pods to be ready..."
kubectl wait --for=condition=ready --timeout=300s pods -l k8s-app=calico-node -n kube-system || true
kubectl wait --for=condition=ready --timeout=300s pods -l app=flannel -n kube-system || true

echo "Network addon installation completed."