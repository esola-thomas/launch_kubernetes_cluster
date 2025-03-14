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
    echo "Usage: $0 <container-runtime-type>"
    echo "Supported types: containerd, docker"
    exit 1
fi

CONTAINER_RUNTIME="$1"
echo "Installing container runtime: ${CONTAINER_RUNTIME}"

# Detect OS
detect_os

# Install containerd
install_containerd() {
    echo "Installing containerd..."
    
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
    
    echo "Containerd installed and configured successfully"
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
    
    # Clone and build cri-dockerd
    cd /tmp
    git clone https://github.com/Mirantis/cri-dockerd.git
    cd cri-dockerd
    
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
        install_containerd
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