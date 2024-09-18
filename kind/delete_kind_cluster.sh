#!/bin/bash

# delete_kind_cluster.sh - Script to delete the kind cluster

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

# Check if kind cluster exists
if kind get clusters | grep -q "^kind$"; then
    echo "Deleting kind cluster..."
    kind delete cluster
    echo "Kind cluster deleted successfully."
else
    echo "Kind cluster 'kind' does not exist. Nothing to delete."
fi
