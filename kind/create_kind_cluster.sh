#!/bin/bash

# create_kind_cluster.sh - Script to create a kind cluster with Docker Hub mirror

# Exit immediately if a command exits with a non-zero status
set -e

# Function to check if kind is installed
function check_kind_installed {
    if ! command -v kind &> /dev/null
    then
        echo "kind could not be found. Please install kind before running this script."
        exit 1
    fi
}

# Check prerequisites
check_kind_installed

# Check if kind cluster already exists
if kind get clusters | grep -q "^kind$"; then
    echo "Kind cluster 'kind' already exists. Skipping creation."
else
    # Create kind cluster
    echo "Creating kind cluster..."
    kind create cluster --config kind/kind-config.yaml
    echo "Kind cluster created successfully."
fi
