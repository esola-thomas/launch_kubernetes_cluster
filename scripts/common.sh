#!/bin/bash

# Common functions used by both control plane and worker node scripts

# Check if script is run as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Error: This script must be run as root"
        echo "Please run with sudo or as the root user"
        exit 1
    fi
}

# Check system requirements
check_system_requirements() {
    # Check CPU
    CPU_CORES=$(grep -c ^processor /proc/cpuinfo)
    if [[ "$1" == "control-plane" && ${CPU_CORES} -lt 2 ]]; then
        echo "Warning: Control plane node should have at least 2 CPU cores (found ${CPU_CORES})"
        echo "The installation will continue, but performance may be degraded"
    fi

    # Check RAM
    TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_MEM_GB=$((TOTAL_MEM_KB / 1024 / 1024))
    if [[ ${TOTAL_MEM_GB} -lt 2 ]]; then
        echo "Warning: Node should have at least 2GB RAM (found ${TOTAL_MEM_GB}GB)"
        echo "The installation will continue, but performance may be degraded"
    fi

    # Check disk space
    ROOT_DISK_FREE_GB=$(df -BG / | tail -n 1 | awk '{print $4}' | sed 's/G//')
    if [[ ${ROOT_DISK_FREE_GB} -lt 10 ]]; then
        echo "Warning: Node should have at least 10GB free disk space (found ${ROOT_DISK_FREE_GB}GB)"
        echo "The installation will continue, but you may run out of disk space"
    fi
}

# Configure system settings
configure_system() {
    # Disable swap if requested
    if [ "${DISABLE_SWAP}" = "true" ]; then
        echo "Disabling swap..."
        swapoff -a
        sed -i '/swap/d' /etc/fstab
    fi

    # Load overlay and br_netfilter modules
    echo "Loading required kernel modules..."
    mkdir -p /etc/modules-load.d
    cat > /etc/modules-load.d/k8s.conf << EOF
overlay
br_netfilter
EOF
    
    modprobe overlay
    modprobe br_netfilter

    # Configure sysctl parameters for Kubernetes
    echo "Configuring kernel parameters for Kubernetes..."
    cat > /etc/sysctl.d/k8s.conf << EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
    
    sysctl --system
}

# Function to detect the OS and distribution
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=${ID}
        OS_VERSION=${VERSION_ID}
        OS_NAME=${NAME}
        echo "Detected OS: ${OS_NAME} ${OS_VERSION}"
    else
        echo "Error: Unable to detect operating system"
        echo "This script requires a Debian-based or Red Hat-based distribution"
        exit 1
    fi
}

# Error handling function
handle_error() {
    echo "Error: An error occurred during execution at line: $1"
    echo "Please check the logs above for more information"
    exit 1
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to add Kubernetes apt repository key safely
add_apt_key_safe() {
    local key_url="$1"
    local key_path="$2"
    
    mkdir -p "$(dirname "$key_path")"
    curl -fsSL "$key_url" | gpg --dearmor -o "$key_path"
    chmod 644 "$key_path"
}

# Set up error handling
trap 'handle_error $LINENO' ERR