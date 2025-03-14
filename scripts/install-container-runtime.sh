#!/bin/bash

set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Check if script is run as root
check_root

# Check if container runtime type is provided
if [ $# -lt 1 ]; then
    echo "Error: Container runtime type is required"
    echo "Usage: $0 <container-runtime-type> [installation-method]"
    echo "Supported types: containerd, docker"
    echo "Installation methods for containerd: package (default), binary"
    exit 1
fi

CONTAINER_RUNTIME="$1"
INSTALL_METHOD="${2:-package}"
echo "Installing container runtime: ${CONTAINER_RUNTIME}"

# Detect OS
detect_os

# Install containerd
install_containerd() {
    echo "Installing containerd..."
    local install_method="${1:-package}"
    
    if [[ "${install_method}" == "binary" ]]; then
        echo "Installing containerd from official binaries..."
        
        # Define versions and architectures
        CONTAINERD_VERSION="1.7.13"
        RUNC_VERSION="1.1.12"
        CNI_PLUGINS_VERSION="1.4.0"
        ARCH=$(uname -m)
        
        case "${ARCH}" in
            x86_64) ARCH="amd64" ;;
            aarch64) ARCH="arm64" ;;
            *)
                echo "Unsupported architecture: ${ARCH}"
                echo "Only amd64 (x86_64) and arm64 (aarch64) are supported"
                exit 1
                ;;
        esac
        
        # Step 1: Install containerd
        echo "Downloading containerd v${CONTAINERD_VERSION}..."
        TMP_DIR=$(mktemp -d)
        curl -L https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-${ARCH}.tar.gz -o ${TMP_DIR}/containerd.tar.gz
        
        echo "Extracting containerd to /usr/local..."
        tar Cxzf /usr/local ${TMP_DIR}/containerd.tar.gz
        
        # Setup containerd systemd service
        echo "Setting up containerd systemd service..."
        curl -L https://raw.githubusercontent.com/containerd/containerd/main/containerd.service -o /usr/local/lib/systemd/system/containerd.service
        mkdir -p /usr/local/lib/systemd/system
        curl -L https://raw.githubusercontent.com/containerd/containerd/main/containerd.service -o /usr/local/lib/systemd/system/containerd.service
        
        # Step 2: Install runc
        echo "Downloading runc v${RUNC_VERSION}..."
        curl -L https://github.com/opencontainers/runc/releases/download/v${RUNC_VERSION}/runc.${ARCH} -o ${TMP_DIR}/runc
        
        echo "Installing runc to /usr/local/sbin/runc..."
        install -m 755 ${TMP_DIR}/runc /usr/local/sbin/runc
        
        # Step 3: Install CNI plugins
        echo "Downloading CNI plugins v${CNI_PLUGINS_VERSION}..."
        mkdir -p /opt/cni/bin
        curl -L https://github.com/containernetworking/plugins/releases/download/v${CNI_PLUGINS_VERSION}/cni-plugins-linux-${ARCH}-v${CNI_PLUGINS_VERSION}.tgz -o ${TMP_DIR}/cni-plugins.tgz
        
        echo "Extracting CNI plugins to /opt/cni/bin..."
        tar Cxzf /opt/cni/bin ${TMP_DIR}/cni-plugins.tgz
        
        # Clean up temporary directory
        rm -rf ${TMP_DIR}
        
        # Configure containerd
        mkdir -p /etc/containerd
        containerd config default | tee /etc/containerd/config.toml > /dev/null
        sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
        
        # Enable and start containerd service
        systemctl daemon-reload
        systemctl enable --now containerd
        
        echo "Containerd binary installation completed successfully"
        
    elif [[ "${install_method}" == "package" ]]; then
        echo "Installing containerd from package repositories..."
        
        if [[ "${OS}" == "ubuntu" || "${OS}" == "debian" ]]; then
            # Install prerequisites
            apt-get update
            apt-get install -y ca-certificates curl gnupg

            # Set up Docker's apt repository
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/${OS}/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.asc
            chmod a+r /etc/apt/keyrings/docker.asc

            # Add the repository to Apt sources
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${OS} \
                $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
                tee /etc/apt/sources.list.d/docker.list > /dev/null

            # Update apt and install containerd
            apt-get update
            apt-get install -y containerd.io
            
        elif [[ "${OS}" == "rhel" || "${OS}" == "centos" || "${OS}" == "fedora" ]]; then
            # Install containerd from Docker's yum repository
            dnf -y install yum-utils
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            dnf -y install containerd.io
        fi
        
        # Configure containerd to use systemd as cgroup driver
        mkdir -p /etc/containerd
        containerd config default | tee /etc/containerd/config.toml > /dev/null
        sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
        
        # Restart containerd
        systemctl restart containerd
        systemctl enable containerd
        
        echo "Containerd package installation completed successfully"
    else
        echo "Error: Unsupported installation method: ${install_method}"
        echo "Supported methods: binary, package"
        exit 1
    fi
}

# Install Docker Engine and cri-dockerd
install_docker() {
    echo "Installing Docker Engine and cri-dockerd..."
    
    if [[ "${OS}" == "ubuntu" || "${OS}" == "debian" ]]; then
        # First, uninstall any conflicting packages
        for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
            apt-get remove -y $pkg || true
        done

        # Install prerequisites
        apt-get update
        apt-get install -y ca-certificates curl gnupg

        # Set up Docker's apt repository
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/${OS}/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.asc
        chmod a+r /etc/apt/keyrings/docker.asc

        # Add the repository to Apt sources
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${OS} \
            $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
            tee /etc/apt/sources.list.d/docker.list > /dev/null

        # Install Docker Engine and related packages
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        
    elif [[ "${OS}" == "rhel" || "${OS}" == "centos" || "${OS}" == "fedora" ]]; then
        # Install Docker Engine
        dnf -y install yum-utils
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi
    
    # Configure Docker to use systemd as cgroup driver
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF
    
    # Start and enable Docker
    systemctl restart docker
    systemctl enable docker
    
    # Install cri-dockerd
    echo "Installing cri-dockerd..."
    
    if ! command_exists git; then
        if [[ "${OS}" == "ubuntu" || "${OS}" == "debian" ]]; then
            apt-get install -y git
        elif [[ "${OS}" == "rhel" || "${OS}" == "centos" || "${OS}" == "fedora" ]]; then
            dnf -y install git
        fi
    fi
    
    # Install Go
    if ! command_exists go; then
        echo "Installing Go..."
        GO_VERSION="1.20.6"
        curl -L https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz -o /tmp/go.tar.gz
        rm -rf /usr/local/go && tar -C /usr/local -xzf /tmp/go.tar.gz
        export PATH=$PATH:/usr/local/go/bin
        echo "export PATH=\$PATH:/usr/local/go/bin" >> /etc/profile
    fi
    
    # Clone and build cri-dockerd only if directory doesn't exist
    cd /tmp
    if [ ! -d "/tmp/cri-dockerd" ]; then
        echo "Cloning cri-dockerd repository..."
        git clone https://github.com/Mirantis/cri-dockerd.git
    else
        echo "cri-dockerd repository already exists, skipping clone..."
    fi
    
    cd cri-dockerd
    
    # Fix invalid Go version in go.mod file if needed
    if grep -q "invalid go version" <<< "$(go mod tidy 2>&1)"; then
        echo "Fixing invalid Go version in go.mod file..."
        # Extract the problematic version and fix it
        GO_VERSION_LINE=$(grep -n "^go " go.mod | cut -d: -f1)
        if [ ! -z "$GO_VERSION_LINE" ]; then
            # Replace the line with a valid Go version format (1.21 instead of 1.21.x)
            sed -i "${GO_VERSION_LINE}s/go [0-9]\+\.[0-9]\+\.[0-9]\+/go 1.21/" go.mod
            echo "Fixed go.mod file with Go version 1.21"
        fi
    fi
    
    # Build and install cri-dockerd
    mkdir -p /usr/local/bin
    go build -o /usr/local/bin/cri-dockerd
    chmod +x /usr/local/bin/cri-dockerd
    
    # Install systemd units
    cat > /etc/systemd/system/cri-docker.service <<EOF
[Unit]
Description=CRI Interface for Docker Application Container Engine
Documentation=https://docs.mirantis.com
After=network-online.target firewalld.service docker.service
Wants=network-online.target

[Service]
Type=notify
ExecStart=/usr/local/bin/cri-dockerd --container-runtime-endpoint fd://
ExecReload=/bin/kill -s HUP \$MAINPID
TimeoutSec=0
RestartSec=2
Restart=always
StartLimitBurst=3
StartLimitInterval=60s
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity

[Install]
WantedBy=multi-user.target
EOF
    
    cat > /etc/systemd/system/cri-docker.socket <<EOF
[Unit]
Description=CRI Docker Socket for the API
PartOf=cri-docker.service

[Socket]
ListenStream=/var/run/cri-dockerd.sock
SocketMode=0660
SocketUser=root
SocketGroup=root

[Install]
WantedBy=sockets.target
EOF
    
    # Start and enable cri-dockerd
    systemctl daemon-reload
    systemctl enable cri-docker.service
    systemctl enable --now cri-docker.socket
    
    # Verify docker installation
    echo "Verifying Docker Engine installation..."
    if docker --version > /dev/null 2>&1; then
        echo "Docker Engine installed and configured successfully"
    else
        echo "Warning: Docker installation cannot be verified"
    fi
}

# Install the specified container runtime
case "${CONTAINER_RUNTIME}" in
    "containerd")
        install_containerd "${INSTALL_METHOD}"
        ;;
    "docker")
        install_docker
        ;;
    *)
        echo "Error: Unsupported container runtime type: ${CONTAINER_RUNTIME}"
        echo "Supported types: containerd, docker"
        exit 1
        ;;
esac

echo "Container runtime installation completed."