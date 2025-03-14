#!/bin/bash

# Deploy a simple test application to verify cluster functionality

set -e

# Print header
echo "====================================================="
echo "Kubernetes Test Deployment"
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

# Display cluster information
echo "Cluster information:"
kubectl cluster-info
echo ""

echo "Nodes in the cluster:"
kubectl get nodes -o wide
echo ""

# Create a test namespace
echo "Creating test namespace..."
kubectl create namespace test-deployment || true

# Deploy a simple nginx application
echo "Deploying test application (nginx)..."
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-test
  namespace: test-deployment
  labels:
    app: nginx-test
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx-test
  template:
    metadata:
      labels:
        app: nginx-test
    spec:
      containers:
      - name: nginx
        image: nginx:stable
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "128Mi"
            cpu: "200m"
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-test
  namespace: test-deployment
spec:
  selector:
    app: nginx-test
  ports:
  - port: 80
    targetPort: 80
EOF

echo "Waiting for deployment to be ready..."
kubectl -n test-deployment wait --for=condition=Available --timeout=60s deployment/nginx-test

echo "Deployment status:"
kubectl -n test-deployment get deployment nginx-test
echo ""

echo "Pods status:"
kubectl -n test-deployment get pods -l app=nginx-test
echo ""

echo "Service details:"
kubectl -n test-deployment get service nginx-test
echo ""

# Test the service
echo "Testing service connectivity..."
TEST_POD=$(kubectl -n test-deployment get pod -l app=nginx-test -o jsonpath="{.items[0].metadata.name}")
echo "Executing test from pod $TEST_POD:"
kubectl -n test-deployment exec $TEST_POD -- curl -s nginx-test | grep -o "<title>.*</title>" || echo "Connection test failed"

echo "====================================================="
echo "Test deployment completed."
echo "To clean up, run: kubectl delete namespace test-deployment"
echo "====================================================="

exit 0