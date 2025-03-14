#!/bin/bash

# This script ensures that all Kubernetes services are running correctly
# Run it after a system reboot or if services are in an inconsistent state

set -e

# Print header
echo "====================================================="
echo "Kubernetes System Readiness Check"
echo "====================================================="

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root"
    echo "Please run with sudo or as the root user"
    exit 1
fi

# Check if node is a control plane node or worker node
IS_CONTROL_PLANE=false
if [ -d "/etc/kubernetes/manifests" ] && [ -f "/etc/kubernetes/admin.conf" ]; then
    IS_CONTROL_PLANE=true
    echo "Detected node type: Control Plane"
else
    echo "Detected node type: Worker Node"
fi

# Function to check and restart services
check_and_restart_service() {
    local service_name="$1"
    
    echo "Checking $service_name service..."
    if systemctl is-active --quiet $service_name; then
        echo "✓ $service_name is running"
    else
        echo "! $service_name is not running. Attempting to start..."
        systemctl start $service_name
        
        # Wait a moment and check again
        sleep 2
        if systemctl is-active --quiet $service_name; then
            echo "✓ $service_name successfully started"
        else
            echo "✗ Failed to start $service_name. Checking logs:"
            journalctl -u $service_name --no-pager | tail -n 20
        fi
    fi
    
    # Ensure service is enabled on startup
    if ! systemctl is-enabled --quiet $service_name; then
        echo "Enabling $service_name to start on boot"
        systemctl enable $service_name
    fi
}

# Check container runtime
if systemctl list-unit-files | grep -q containerd; then
    CONTAINER_RUNTIME="containerd"
elif systemctl list-unit-files | grep -q docker; then
    CONTAINER_RUNTIME="docker"
else
    echo "Error: No supported container runtime found"
    exit 1
fi

echo "Container runtime detected: $CONTAINER_RUNTIME"

# Check and restart container runtime
check_and_restart_service $CONTAINER_RUNTIME

# If using Docker with cri-dockerd, check the CRI adapter
if [ "$CONTAINER_RUNTIME" == "docker" ]; then
    if systemctl list-unit-files | grep -q cri-docker; then
        check_and_restart_service cri-docker.socket
        check_and_restart_service cri-docker
    else
        echo "Warning: Docker detected but cri-dockerd not found. Kubernetes requires cri-dockerd to work with Docker."
    fi
fi

# Check kubelet service
check_and_restart_service kubelet

# For control plane nodes, check static pod manifests
if [ "$IS_CONTROL_PLANE" == "true" ]; then
    echo "Checking control plane components..."
    
    # List of static pod manifests to check
    MANIFESTS=(
        "/etc/kubernetes/manifests/kube-apiserver.yaml"
        "/etc/kubernetes/manifests/kube-controller-manager.yaml"
        "/etc/kubernetes/manifests/kube-scheduler.yaml"
        "/etc/kubernetes/manifests/etcd.yaml"
    )
    
    # Check if all expected manifests exist
    for MANIFEST in "${MANIFESTS[@]}"; do
        if [ -f "$MANIFEST" ]; then
            echo "✓ $(basename "$MANIFEST") manifest exists"
        else
            echo "✗ $(basename "$MANIFEST") manifest missing!"
        fi
    done
    
    # Restart kubelet to ensure static pods are running
    echo "Restarting kubelet to ensure all static pods are running..."
    systemctl restart kubelet
    
    # Wait for API server to become responsive
    echo "Waiting for kube-apiserver to become responsive..."
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
    
    if [ $counter -lt $timeout ]; then
        echo "✓ kube-apiserver is responsive"
        
        # Check if kubectl works
        if KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes &>/dev/null; then
            echo "✓ kubectl is working properly"
            
            # Check cluster status
            echo "Cluster nodes:"
            KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes
            
            echo "Critical pods:"
            KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pods -n kube-system
        else
            echo "✗ kubectl is not working properly"
        fi
    else
        echo "✗ kube-apiserver is not responsive"
    fi
fi

# Check networking
echo "Checking network connectivity..."

# Check if DNS resolution works
if host kubernetes.default.svc.cluster.local. &>/dev/null || nslookup kubernetes.default.svc.cluster.local. &>/dev/null; then
    echo "✓ DNS resolution is working"
else
    echo "✗ DNS resolution is not working"
fi

# Check common Kubernetes ports
if [ "$IS_CONTROL_PLANE" == "true" ]; then
    # Check API server port
    if netstat -tuln | grep -q ":6443 "; then
        echo "✓ kube-apiserver port (6443) is open"
    else
        echo "✗ kube-apiserver port (6443) is not open"
    fi
    
    # Check etcd port
    if netstat -tuln | grep -q ":2379 "; then
        echo "✓ etcd port (2379) is open"
    else
        echo "✗ etcd port (2379) is not open"
    fi
fi

# Check kubelet port
if netstat -tuln | grep -q ":10250 "; then
    echo "✓ kubelet port (10250) is open"
else
    echo "✗ kubelet port (10250) is not open"
fi

echo "====================================================="
echo "System readiness check completed."
echo "If any issues were detected, please refer to the"
echo "troubleshooting guide for resolution steps."
echo "====================================================="

exit 0