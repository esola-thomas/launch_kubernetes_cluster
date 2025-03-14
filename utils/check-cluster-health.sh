#!/bin/bash

# Check the health of a Kubernetes cluster

# Print header
echo "====================================================="
echo "Kubernetes Cluster Health Check"
echo "====================================================="

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl command not found"
    echo "This script must be run on a machine with kubectl configured"
    exit 1
fi

# Check if we can access the cluster
echo "Checking API server connectivity..."
if ! kubectl get nodes &> /dev/null; then
    echo "Error: Cannot connect to Kubernetes API server"
    echo "Please ensure your kubectl is properly configured"
    exit 1
fi

# Check node status
echo -e "\n>> Node Status:"
kubectl get nodes -o wide

# Check for unhealthy nodes
UNHEALTHY_NODES=$(kubectl get nodes | grep -v "Ready" | grep -v "NAME" | wc -l)
if [ $UNHEALTHY_NODES -gt 0 ]; then
    echo -e "\nWarning: $UNHEALTHY_NODES node(s) are not in Ready state!"
    kubectl get nodes | grep -v "Ready" | grep -v "NAME"
fi

# Check pod status across all namespaces
echo -e "\n>> Pod Status Across All Namespaces:"
kubectl get pods --all-namespaces -o wide

# Check for unhealthy pods
UNHEALTHY_PODS=$(kubectl get pods --all-namespaces | grep -v "Running\|Completed" | grep -v "NAMESPACE" | wc -l)
if [ $UNHEALTHY_PODS -gt 0 ]; then
    echo -e "\nWarning: $UNHEALTHY_PODS pod(s) are not in Running or Completed state!"
    kubectl get pods --all-namespaces | grep -v "Running\|Completed" | grep -v "NAMESPACE"
fi

# Check component status
echo -e "\n>> Control Plane Component Status:"
kubectl get componentstatuses

# Check system services
echo -e "\n>> System Pods Status:"
kubectl get pods -n kube-system

# Check etcd health if possible
echo -e "\n>> Etcd Health Status:"
if kubectl -n kube-system get pods | grep -q "etcd"; then
    ETCD_POD=$(kubectl -n kube-system get pods | grep etcd | awk '{print $1}')
    kubectl -n kube-system exec $ETCD_POD -- etcdctl --endpoints https://127.0.0.1:2379 \
      --cacert /etc/kubernetes/pki/etcd/ca.crt \
      --cert /etc/kubernetes/pki/etcd/server.crt \
      --key /etc/kubernetes/pki/etcd/server.key \
      endpoint health || echo "Couldn't check etcd health directly"
fi

# Check DNS service
echo -e "\n>> DNS Service Health:"
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl get svc -n kube-system -l k8s-app=kube-dns

echo -e "\n>> Checking CoreDNS functionality with a test pod:"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: dns-test
  namespace: default
spec:
  containers:
  - name: dns-test
    image: busybox:1.28
    command:
      - sleep
      - "3600"
    imagePullPolicy: IfNotPresent
  restartPolicy: Always
EOF

echo "Waiting for DNS test pod to be ready..."
kubectl wait --for=condition=Ready pod/dns-test --timeout=60s || echo "Timeout waiting for dns-test pod"

echo -e "\n>> Testing DNS resolution inside the pod:"
kubectl exec -it dns-test -- nslookup kubernetes.default || echo "DNS resolution test failed"

# Clean up the test pod
kubectl delete pod dns-test

# Check networking
echo -e "\n>> Network Plugin Status:"
kubectl get pods -n kube-system -l k8s-app=calico-node 2>/dev/null || \
kubectl get pods -n kube-system -l app=flannel 2>/dev/null || \
echo "No standard network plugin pods found"

# Output overall health assessment
echo -e "\n====================================================="
echo "Overall Cluster Health Assessment:"

if [ $UNHEALTHY_NODES -eq 0 ] && [ $UNHEALTHY_PODS -eq 0 ]; then
    echo "✅ Cluster appears to be healthy!"
else
    echo "⚠️  Cluster has some issues that need attention!"
    echo "  - $UNHEALTHY_NODES unhealthy node(s)"
    echo "  - $UNHEALTHY_PODS unhealthy pod(s)"
fi
echo "====================================================="