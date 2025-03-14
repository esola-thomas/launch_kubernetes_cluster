# Kubernetes Cluster Scaling Guide

This document provides instructions for scaling your Kubernetes cluster by adding more nodes or upgrading the control plane to high availability.

## Table of Contents

1. [Adding Worker Nodes](#adding-worker-nodes)
2. [Upgrading to Multi-Master High Availability](#upgrading-to-multi-master-high-availability)
3. [Resource Scaling Considerations](#resource-scaling-considerations)
4. [Monitoring Cluster Capacity](#monitoring-cluster-capacity)

## Adding Worker Nodes

### Prerequisites for New Worker Nodes

- Ubuntu server (fresh installation)
- Minimum 2GB RAM, 2 CPUs recommended
- Network connectivity to existing cluster nodes
- Unique hostname, MAC address, and product_uuid

### Joining a New Worker Node

1. On your control plane node, generate a new join token if your previous one has expired:
   ```bash
   sudo kubeadm token create --print-join-command
   ```

2. On the new worker node:
   ```bash
   # Clone the repository
   git clone https://github.com/your-username/kubernetes-deploy.git
   cd kubernetes-deploy
   
   # Run the worker setup script with the token from step 1
   sudo ./setup-worker.sh <control-plane-ip> <token> <discovery-token-ca-cert-hash>
   ```

3. Verify the new node has joined the cluster:
   ```bash
   kubectl get nodes
   ```

### Labeling Worker Nodes

To organize your nodes by role or capabilities:

```bash
# Label nodes by purpose
kubectl label nodes <node-name> node-role.kubernetes.io/worker=worker
kubectl label nodes <node-name> workload-type=production

# Label nodes by hardware capabilities
kubectl label nodes <node-name> disk=ssd
kubectl label nodes <node-name> cpu=high-performance
```

## Upgrading to Multi-Master High Availability

### Prerequisites for HA Control Plane

- At least three machines for control plane nodes
- Load balancer (HAProxy, Nginx, or cloud provider load balancer)
- Shared endpoint (IP or DNS) for the load balancer

### Setting Up the Load Balancer

1. Install and configure your load balancer to balance traffic to your control plane nodes on port 6443.

2. Example HAProxy configuration:
   ```
   frontend kubernetes-frontend
     bind *:6443
     mode tcp
     option tcplog
     default_backend kubernetes-backend

   backend kubernetes-backend
     mode tcp
     option tcp-check
     balance roundrobin
     server control-plane-1 <control-plane-1-ip>:6443 check fall 3 rise 2
     server control-plane-2 <control-plane-2-ip>:6443 check fall 3 rise 2
     server control-plane-3 <control-plane-3-ip>:6443 check fall 3 rise 2
   ```

### Setting Up Additional Control Plane Nodes

1. On the first control plane node, generate the join command for a new control plane node:
   ```bash
   sudo kubeadm init phase upload-certs --upload-certs
   ```
   Note the certificate key that is output.

2. Create a control plane join command:
   ```bash
   sudo kubeadm token create --print-join-command
   ```

3. On the new control plane node:
   ```bash
   # Clone the repository
   git clone https://github.com/your-username/kubernetes-deploy.git
   cd kubernetes-deploy
   
   # Create a custom values file
   cp config/custom-values.env config/my-custom-values.env
   
   # Edit the custom values
   # Set CONTROL_PLANE_ENDPOINT to the load balancer address
   vi config/my-custom-values.env
   ```

4. Join the new control plane node:
   ```bash
   sudo ./scripts/install-prerequisites.sh
   sudo ./scripts/install-container-runtime.sh containerd
   sudo ./scripts/install-kubernetes.sh
   
   # Use the join command from step 2 and add --control-plane --certificate-key flags
   sudo kubeadm join <load-balancer-ip>:6443 --token <token> \
     --discovery-token-ca-cert-hash sha256:<hash> \
     --control-plane --certificate-key <certificate-key>
   ```

5. Set up kubeconfig on the new control plane node:
   ```bash
   mkdir -p $HOME/.kube
   sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
   sudo chown $(id -u):$(id -g) $HOME/.kube/config
   ```

6. Verify the control plane is working:
   ```bash
   kubectl get nodes
   ```

## Resource Scaling Considerations

### Node Capacity Planning

- **Worker Nodes**: Size based on workload requirements. General recommendations:
  - Small workloads: 2-4 vCPUs, 4-8GB RAM
  - Medium workloads: 4-8 vCPUs, 8-16GB RAM
  - Large workloads: 8+ vCPUs, 16+ GB RAM

- **Control Plane Nodes**:
  - Up to 5 nodes: 2 vCPUs, 4GB RAM
  - Up to 50 nodes: 4 vCPUs, 8GB RAM
  - Up to 100 nodes: 8 vCPUs, 16GB RAM
  - Above 100 nodes: 16+ vCPUs, 32+ GB RAM

### Resource Quotas

To limit resource consumption by namespace:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ResourceQuota
metadata:
  name: compute-resources
  namespace: my-namespace
spec:
  hard:
    pods: "10"
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.cpu: "8"
    limits.memory: 16Gi
EOF
```

### Horizontal Pod Autoscaling

To automatically scale your deployments based on CPU/memory usage:

```bash
kubectl autoscale deployment <deployment-name> --cpu-percent=80 --min=3 --max=10
```

## Monitoring Cluster Capacity

### Installing Metrics Server

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### Monitoring Commands

```bash
# Check node resource usage
kubectl top nodes

# Check pod resource usage
kubectl top pods --all-namespaces

# Get detailed node descriptions
kubectl describe nodes | grep -A 5 "Allocated resources"
```

### Setting Up Prometheus and Grafana for Advanced Monitoring

Consider installing Prometheus and Grafana for comprehensive monitoring:

```bash
# Add Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install Prometheus stack
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace
```

## Next Steps

After scaling your cluster, consider:

1. Implementing proper backup and disaster recovery
2. Setting up a GitOps workflow for deploying applications
3. Implementing proper network security policies
4. Setting up cluster autoscaling for cloud environments