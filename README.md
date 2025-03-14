# On-Premises Kubernetes Deployment

This repository contains everything you need to set up a Kubernetes cluster on bare-metal servers running Ubuntu. It's designed to streamline the process of installing and configuring Kubernetes components for both control plane nodes and worker nodes.

## Prerequisites

- Servers with Ubuntu (fresh installation)
- Minimum 2 GB RAM per machine (4+ GB recommended for control plane)
- Minimum 2 CPUs for control plane nodes
- Full network connectivity between all machines
- Unique hostname, MAC address, and product_uuid for each node
- Required ports opened as per Kubernetes networking requirements
- Internet access for package downloads (during installation)

## Quick Start

### Control Plane Setup

1. Clone this repository on your designated control plane node:
   ```bash
   git clone https://github.com/your-username/kubernetes-deploy.git
   cd kubernetes-deploy
   ```

2. (Optional) Customize the configuration:
   ```bash
   # Edit the configuration file with your preferred settings
   vi config/custom-values.env
   ```

3. Run the control plane setup script:
   ```bash
   sudo ./setup-control-plane.sh
   ```

4. After successful installation, the script will output a join command for worker nodes. Save this command for the next step.

### Worker Node Setup

1. Clone this repository on each worker node:
   ```bash
   git clone https://github.com/your-username/kubernetes-deploy.git
   cd kubernetes-deploy
   ```

2. Run the worker setup script with the join information from the control plane setup:
   ```bash
   sudo ./setup-worker.sh [CONTROL_PLANE_IP] [TOKEN] [HASH]
   ```

3. Verify the node has joined the cluster (run on control plane node):
   ```bash
   kubectl get nodes
   ```

## Post-Installation

### Testing Your Cluster

Run the test deployment script to verify your cluster is working correctly:

```bash
sudo ./utils/test-deployment.sh
```

This will deploy a simple nginx application and verify that it's accessible within the cluster.

### Checking Cluster Health

To check the health of your cluster:

```bash
sudo ./utils/check-cluster-health.sh
```

### After System Reboot

If your server reboots, ensure all Kubernetes services are running properly:

```bash
sudo ./utils/ensure-system-ready.sh
```

### Security Maintenance

To rotate cluster certificates (recommended every 6-12 months):

```bash
sudo ./utils/rotate-certificates.sh
```

## Features

- Automatic installation of container runtime (containerd)
- Pre-configured kubeadm for control plane initialization
- Calico network plugin for pod networking
- Parameterizable deployment through configuration files
- Helper utilities for maintenance and troubleshooting

## Configuration Options

You can modify the deployment parameters in the `config/custom-values.env` file:

| Parameter | Description | Default |
|-----------|-------------|---------|
| POD_NETWORK_CIDR | CIDR range for pod IPs | 192.168.0.0/16 |
| SERVICE_CIDR | CIDR range for service IPs | 10.96.0.0/12 |
| KUBERNETES_VERSION | Kubernetes version to install | stable-1 |
| CONTROL_PLANE_ENDPOINT | Control plane endpoint IP | auto-detected |
| NODE_NAME | Node name | hostname |
| CONTAINER_RUNTIME | Container runtime to use (containerd/docker) | containerd |
| NETWORK_ADDON | Network plugin (calico/flannel/custom) | calico |

## Scaling Your Cluster

To add more worker nodes or scale to a multi-master cluster, see the [scaling guide](docs/scaling.md).

## Troubleshooting

For common issues and solutions, see the [troubleshooting guide](docs/troubleshooting.md).

## Directory Structure

- `scripts/`: Core installation scripts
- `config/`: Configuration templates and files
- `network-addons/`: Network plugin manifests
- `utils/`: Utility scripts for maintenance and troubleshooting
- `docs/`: Documentation