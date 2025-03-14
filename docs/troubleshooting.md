# Kubernetes Deployment Troubleshooting Guide

This guide provides solutions for common issues you might encounter when deploying and operating your Kubernetes cluster.

## Table of Contents

1. [Installation Problems](#installation-problems)
2. [Network Issues](#network-issues)
3. [Control Plane Issues](#control-plane-issues)
4. [Worker Node Issues](#worker-node-issues)
5. [Container Runtime Issues](#container-runtime-issues)
6. [DNS Issues](#dns-issues)
7. [Certificate Issues](#certificate-issues)
8. [Common Error Messages](#common-error-messages)

## Installation Problems

### Failed Prerequisites Check

**Symptoms:**
- Installation fails during the prerequisites check
- Error messages about missing packages or system requirements

**Solutions:**
1. Check system requirements:
   ```bash
   grep -c ^processor /proc/cpuinfo   # Should be >= 2 for control plane
   grep MemTotal /proc/meminfo        # Should be >= 2GB
   ```
2. Verify required ports are open:
   ```bash
   nc -v <IP> <PORT>  # Check if port is accessible
   ```
3. Run the prerequisites script again with more verbosity:
   ```bash
   bash -x ./scripts/install-prerequisites.sh
   ```

### Package Installation Failures

**Symptoms:**
- APT/DNF/YUM errors during installation
- Repository errors or GPG key issues

**Solutions:**
1. Check internet connectivity:
   ```bash
   ping -c 4 google.com
   ```
2. Verify repository configurations:
   ```bash
   cat /etc/apt/sources.list.d/kubernetes.list   # For Debian/Ubuntu
   cat /etc/yum.repos.d/kubernetes.repo          # For RHEL/CentOS
   ```
3. Try manually updating the package lists:
   ```bash
   apt-get update   # Debian/Ubuntu
   dnf check-update # RHEL/CentOS
   ```

## Network Issues

### Pod Network Issues

**Symptoms:**
- Pods stuck in `ContainerCreating` or `Pending` state
- Nodes not ready with network plugin not ready errors
- Pods cannot communicate between nodes

**Solutions:**
1. Verify network addon is running:
   ```bash
   kubectl get pods -n kube-system | grep -E 'calico|flannel'
   ```
2. Check pod network CIDR configuration:
   ```bash
   kubectl describe node | grep PodCIDR
   kubectl describe cm -n kube-system kubeadm-config
   ```
3. Check for CIDR conflicts with your existing network
4. Verify network policies are not blocking traffic
5. Try reinstalling the network addon:
   ```bash
   ./scripts/install-network-addon.sh <POD_NETWORK_CIDR>
   ```

### Service Connectivity Issues

**Symptoms:**
- Services not accessible
- `kube-proxy` pods not running
- CoreDNS not resolving service names

**Solutions:**
1. Check kube-proxy status:
   ```bash
   kubectl get pods -n kube-system | grep kube-proxy
   kubectl logs -n kube-system kube-proxy-xxxxx
   ```
2. Verify services have endpoints:
   ```bash
   kubectl get endpoints <service-name>
   ```
3. Check iptables rules to ensure traffic is being properly routed:
   ```bash
   iptables-save | grep <service-cluster-ip>
   ```
4. Restart kube-proxy pods if needed:
   ```bash
   kubectl rollout restart daemonset kube-proxy -n kube-system
   ```

## Control Plane Issues

### API Server Issues

**Symptoms:**
- `kubectl` commands fail with connection refused
- API server pod not running
- Error logs in API server

**Solutions:**
1. Check API server status:
   ```bash
   kubectl get pods -n kube-system | grep kube-apiserver
   ```
2. Inspect API server logs:
   ```bash
   kubectl logs -n kube-system kube-apiserver-$(hostname)
   # or
   journalctl -u kubelet | grep apiserver
   ```
3. Verify API server static pod manifest:
   ```bash
   cat /etc/kubernetes/manifests/kube-apiserver.yaml
   ```
4. Check certificates are valid:
   ```bash
   openssl x509 -in /etc/kubernetes/pki/apiserver.crt -text -noout
   ```

### etcd Issues

**Symptoms:**
- API server cannot connect to etcd
- etcd pod not running
- Data inconsistency or corruption

**Solutions:**
1. Check etcd status:
   ```bash
   kubectl get pods -n kube-system | grep etcd
   ```
2. Verify etcd health:
   ```bash
   ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
     --cacert=/etc/kubernetes/pki/etcd/ca.crt \
     --cert=/etc/kubernetes/pki/etcd/server.crt \
     --key=/etc/kubernetes/pki/etcd/server.key \
     endpoint health
   ```
3. Backup etcd data before attempting repairs:
   ```bash
   ./utils/backup-cluster.sh
   ```
4. Check etcd logs:
   ```bash
   kubectl logs -n kube-system etcd-$(hostname)
   ```

## Worker Node Issues

### Node Not Joining the Cluster

**Symptoms:**
- `kubeadm join` command fails
- Node status shows `NotReady`
- Kubelet not running on worker node

**Solutions:**
1. Verify token is valid:
   ```bash
   # On control-plane node
   kubeadm token list
   # Create new token if needed
   kubeadm token create --print-join-command
   ```
2. Check kubelet status on worker node:
   ```bash
   systemctl status kubelet
   journalctl -u kubelet
   ```
3. Verify network connectivity to control plane on port 6443:
   ```bash
   nc -v <control-plane-ip> 6443
   ```
4. Reset node and try joining again:
   ```bash
   ./utils/reset-node.sh
   ./setup-worker.sh <control-plane-ip> <token> <hash>
   ```

### Kubelet Issues

**Symptoms:**
- Node shows `NotReady` status
- Kubelet service not starting
- Errors in kubelet logs

**Solutions:**
1. Check kubelet service status:
   ```bash
   systemctl status kubelet
   ```
2. View kubelet logs:
   ```bash
   journalctl -u kubelet | tail -100
   ```
3. Verify kubelet configuration:
   ```bash
   cat /var/lib/kubelet/config.yaml
   ```
4. Restart kubelet:
   ```bash
   systemctl restart kubelet
   ```
5. Check node status in the cluster:
   ```bash
   kubectl get nodes
   kubectl describe node <node-name>
   ```

## Container Runtime Issues

### Containerd Issues

**Symptoms:**
- Kubelet errors about connecting to containerd
- Container images not pulling
- Pods stuck in ContainerCreating state

**Solutions:**
1. Check containerd status:
   ```bash
   systemctl status containerd
   ```
2. Verify containerd configuration:
   ```bash
   cat /etc/containerd/config.toml | grep SystemdCgroup
   ```
3. Check containerd logs:
   ```bash
   journalctl -u containerd
   ```
4. Restart containerd:
   ```bash
   systemctl restart containerd
   systemctl restart kubelet
   ```

### Docker Issues (if using cri-dockerd)

**Symptoms:**
- Kubelet errors connecting to Docker or cri-dockerd
- Container runtime not responding

**Solutions:**
1. Check Docker and cri-dockerd status:
   ```bash
   systemctl status docker
   systemctl status cri-docker
   ```
2. Verify cri-dockerd socket:
   ```bash
   ls -la /var/run/cri-dockerd.sock
   ```
3. Check Docker daemon configuration:
   ```bash
   cat /etc/docker/daemon.json
   ```
4. Restart services:
   ```bash
   systemctl restart docker
   systemctl restart cri-docker.socket
   systemctl restart cri-docker.service
   systemctl restart kubelet
   ```

## DNS Issues

### CoreDNS Issues

**Symptoms:**
- Pod domain names not resolving
- CoreDNS pods not running
- Service discovery not working

**Solutions:**
1. Check CoreDNS pod status:
   ```bash
   kubectl get pods -n kube-system -l k8s-app=kube-dns
   ```
2. View CoreDNS logs:
   ```bash
   kubectl logs -n kube-system -l k8s-app=kube-dns
   ```
3. Verify CoreDNS service:
   ```bash
   kubectl get svc -n kube-system kube-dns
   ```
4. Test DNS resolution from a pod:
   ```bash
   kubectl run -it --rm debug --image=busybox -- nslookup kubernetes.default
   ```
5. Restart CoreDNS pods if needed:
   ```bash
   kubectl rollout restart deployment coredns -n kube-system
   ```

## Certificate Issues

**Symptoms:**
- API server certificate errors
- Kubelet certificate errors
- Certificate expirations

**Solutions:**
1. Check certificate expiration:
   ```bash
   kubeadm certs check-expiration
   ```
2. Renew certificates if needed:
   ```bash
   kubeadm certs renew all
   ```
3. Verify certificate permissions:
   ```bash
   ls -la /etc/kubernetes/pki/
   ```
4. Check certificate subject and issuer:
   ```bash
   openssl x509 -in /etc/kubernetes/pki/apiserver.crt -text -noout | grep Subject
   ```

## Common Error Messages

### "The connection to the server localhost:8080 was refused"

**Cause:** kubectl is not properly configured with the cluster kubeconfig file.

**Solution:**
```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### "Error from server: etcdserver: request timed out"

**Cause:** etcd performance issues or etcd endpoint unreachable.

**Solution:**
- Check etcd health as described in the etcd section above
- Consider increasing etcd resources if overloaded
- Check network connectivity between API server and etcd

### "Error validating data: unknown object type schema.GroupVersionKind"

**Cause:** Version skew between client tools and server.

**Solution:**
- Ensure kubectl version matches or is compatible with server version:
  ```bash
  kubectl version --short
  ```

### "cni plugin not initialized"

**Cause:** Network plugin not correctly installed or configured.

**Solution:**
- Reinstall the network addon:
  ```bash
  kubectl delete -f network-addon.yaml  # Delete the current network addon
  kubectl apply -f network-addon.yaml   # Apply it again
  ```

## Additional Diagnostic Steps

If the above solutions do not resolve your issue, try these general diagnostic steps:

1. Run the cluster health check script:
   ```bash
   ./utils/check-cluster-health.sh
   ```

2. Inspect all system components:
   ```bash
   kubectl get componentstatuses
   ```

3. Check events for clues:
   ```bash
   kubectl get events --sort-by=.metadata.creationTimestamp
   ```

4. Check all pods in the kube-system namespace:
   ```bash
   kubectl get pods -n kube-system
   ```

5. Verify node status and capacity:
   ```bash
   kubectl describe nodes
   ```

For more detailed debugging and assistance, consider joining the Kubernetes community channels:
- Slack: [kubernetes.slack.com](https://kubernetes.slack.com)
- Forum: [discuss.kubernetes.io](https://discuss.kubernetes.io)
- GitHub Issues: [github.com/kubernetes/kubeadm/issues](https://github.com/kubernetes/kubeadm/issues)