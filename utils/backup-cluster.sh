#!/bin/bash

# Backup Kubernetes cluster essential data

set -e

# Print header
echo "====================================================="
echo "Kubernetes Cluster Backup"
echo "====================================================="

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root"
    echo "Please run with sudo or as the root user"
    exit 1
fi

# Set backup directory path
BACKUP_DIR=${1:-"/var/backups/kubernetes/$(date +%Y-%m-%d-%H%M%S)"}

# Create backup directory if it doesn't exist
mkdir -p ${BACKUP_DIR}
echo "Backup will be stored in: ${BACKUP_DIR}"

# Function to backup etcd
backup_etcd() {
    echo "Backing up etcd database..."
    
    # Check if we're on a control plane node with etcd
    if [ ! -d "/etc/kubernetes/pki/etcd" ]; then
        echo "Warning: This doesn't appear to be a control plane node with etcd."
        echo "Skipping etcd backup."
        return
    fi
    
    # Create etcd backup directory
    mkdir -p ${BACKUP_DIR}/etcd
    
    # Use etcdctl to create a snapshot
    ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
        --cacert=/etc/kubernetes/pki/etcd/ca.crt \
        --cert=/etc/kubernetes/pki/etcd/server.crt \
        --key=/etc/kubernetes/pki/etcd/server.key \
        snapshot save ${BACKUP_DIR}/etcd/snapshot.db
    
    # Check if backup was successful
    if [ $? -eq 0 ]; then
        echo "etcd backup completed successfully: ${BACKUP_DIR}/etcd/snapshot.db"
        
        # Verify the snapshot
        ETCDCTL_API=3 etcdctl --write-out=table snapshot status ${BACKUP_DIR}/etcd/snapshot.db
    else
        echo "Error: etcd backup failed"
    fi
}

# Function to backup Kubernetes configuration files
backup_kube_config() {
    echo "Backing up Kubernetes configuration files..."
    
    # Backup directory for Kubernetes configs
    mkdir -p ${BACKUP_DIR}/kubernetes/pki
    
    # Backup certificates and keys
    if [ -d "/etc/kubernetes/pki" ]; then
        cp -r /etc/kubernetes/pki ${BACKUP_DIR}/kubernetes/
        echo "PKI certificates backup completed"
    else
        echo "PKI directory not found, skipping certificate backup"
    fi
    
    # Backup kubeconfig files
    if [ -d "/etc/kubernetes" ]; then
        cp /etc/kubernetes/*.conf ${BACKUP_DIR}/kubernetes/ 2>/dev/null || echo "No kubeconfig files found"
        echo "Kubeconfig files backup completed"
    fi
}

# Function to backup important manifests
backup_manifests() {
    echo "Backing up Kubernetes static pod manifests..."
    
    if [ -d "/etc/kubernetes/manifests" ]; then
        mkdir -p ${BACKUP_DIR}/kubernetes/manifests
        cp -r /etc/kubernetes/manifests ${BACKUP_DIR}/kubernetes/
        echo "Static pod manifests backup completed"
    else
        echo "No static pod manifests found"
    fi
    
    # Backup all resources as YAML manifests
    if command -v kubectl &>/dev/null && kubectl get nodes &>/dev/null; then
        echo "Backing up cluster resources as YAML manifests..."
        mkdir -p ${BACKUP_DIR}/resources
        
        # List of resource types to backup
        RESOURCES=(
            "nodes"
            "namespaces"
            "deployments.apps"
            "statefulsets.apps"
            "daemonsets.apps"
            "services"
            "ingresses.networking.k8s.io"
            "configmaps"
            "secrets"
            "persistentvolumes"
            "persistentvolumeclaims"
            "storageclasses.storage.k8s.io"
            "roles.rbac.authorization.k8s.io"
            "rolebindings.rbac.authorization.k8s.io"
            "clusterroles.rbac.authorization.k8s.io"
            "clusterrolebindings.rbac.authorization.k8s.io"
        )
        
        # Backup each resource type across all namespaces
        for RESOURCE in "${RESOURCES[@]}"; do
            RESOURCE_NAME=$(echo $RESOURCE | cut -d. -f1)
            mkdir -p ${BACKUP_DIR}/resources/${RESOURCE_NAME}
            echo "Backing up ${RESOURCE}..."
            kubectl get ${RESOURCE} --all-namespaces -o yaml > ${BACKUP_DIR}/resources/${RESOURCE_NAME}/all.yaml
        done
        
        echo "Cluster resources backup completed"
    else
        echo "kubectl not available or not configured, skipping cluster resources backup"
    fi
}

# Function to create a metadata file with cluster information
create_metadata() {
    echo "Creating backup metadata..."
    
    METADATA_FILE="${BACKUP_DIR}/backup-metadata.txt"
    
    echo "Kubernetes Cluster Backup" > ${METADATA_FILE}
    echo "===========================" >> ${METADATA_FILE}
    echo "Backup Date: $(date)" >> ${METADATA_FILE}
    echo "Hostname: $(hostname)" >> ${METADATA_FILE}
    echo "" >> ${METADATA_FILE}
    
    if command -v kubectl &>/dev/null; then
        echo "Cluster Information:" >> ${METADATA_FILE}
        echo "------------------" >> ${METADATA_FILE}
        kubectl version >> ${METADATA_FILE} 2>&1
        echo "" >> ${METADATA_FILE}
        
        echo "Nodes:" >> ${METADATA_FILE}
        echo "------" >> ${METADATA_FILE}
        kubectl get nodes -o wide >> ${METADATA_FILE} 2>&1
    fi
    
    echo "" >> ${METADATA_FILE}
    echo "Backup Contents:" >> ${METADATA_FILE}
    echo "---------------" >> ${METADATA_FILE}
    find ${BACKUP_DIR} -type f | sort >> ${METADATA_FILE}
    
    echo "Backup metadata created: ${METADATA_FILE}"
}

# Create archive of the backup
create_archive() {
    echo "Creating compressed archive of the backup..."
    
    ARCHIVE_NAME="kubernetes-backup-$(date +%Y-%m-%d-%H%M%S).tar.gz"
    ARCHIVE_PATH="/var/backups/${ARCHIVE_NAME}"
    
    tar -czf ${ARCHIVE_PATH} -C $(dirname ${BACKUP_DIR}) $(basename ${BACKUP_DIR})
    
    echo "Backup archive created: ${ARCHIVE_PATH}"
    echo "You may want to copy this file to a secure off-node location."
}

# Execute backup functions
backup_etcd
backup_kube_config
backup_manifests
create_metadata
create_archive

echo "====================================================="
echo "Kubernetes cluster backup completed!"
echo "Backup location: ${BACKUP_DIR}"
echo "Archive: /var/backups/kubernetes-backup-$(date +%Y-%m-%d-%H%M%S).tar.gz"
echo "====================================================="
echo "IMPORTANT: Store this backup in a secure location."
echo "====================================================="