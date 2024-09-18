#!/bin/bash

# setup.sh - Script to set up the monitoring solution project with VictoriaMetrics using a PVC limited to 5 GB

# Exit immediately if a command exits with a non-zero status
set -e

# Create the directory structure
echo "Creating directory structure..."
mkdir -p k8s/base
mkdir -p k8s/overlays/local
mkdir -p k8s/overlays/production
mkdir -p kind

# Create kind cluster configuration
echo "Creating kind cluster configuration..."
cat <<EOF > kind/kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
containerdConfigPatches:
  - |
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
      endpoint = ["https://dockerhub.timeweb.cloud"]
EOF

# Create script to create kind cluster
echo "Creating create_kind_cluster.sh script..."
cat <<'EOF' > kind/create_kind_cluster.sh
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
EOF

# Make the create_kind_cluster.sh script executable
chmod +x kind/create_kind_cluster.sh

# Create script to delete kind cluster
echo "Creating delete_kind_cluster.sh script..."
cat <<'EOF' > kind/delete_kind_cluster.sh
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
EOF

# Make the delete_kind_cluster.sh script executable
chmod +x kind/delete_kind_cluster.sh

# Create the observability namespace manifest
echo "Creating namespace.yaml..."
cat <<EOF > k8s/base/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: observability
EOF

# Function to create deployments with timezone configuration
create_deployment_with_timezone() {
    local name=$1
    local image=$2
    local port=$3
    local container_port=$4
    local env_vars=$5

    echo "Creating ${name}.yaml..."
    cat <<EOF > k8s/base/${name}.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${name}
  namespace: observability
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${name}
  template:
    metadata:
      labels:
        app: ${name}
    spec:
      containers:
        - name: ${name}
          image: ${image}
          ports:
            - containerPort: ${container_port}
          env:
            - name: TZ
              value: "Europe/Moscow"
            ${env_vars}
          volumeMounts:
            - name: tz-config
              mountPath: /etc/localtime
              readOnly: true
      volumes:
        - name: tz-config
          hostPath:
            path: /usr/share/zoneinfo/Europe/Moscow
            type: File
---
apiVersion: v1
kind: Service
metadata:
  name: ${name}
  namespace: observability
spec:
  selector:
    app: ${name}
  ports:
    - protocol: TCP
      port: ${port}
      targetPort: ${container_port}
EOF
}

# Create nginx deployment and service with timezone configuration
create_deployment_with_timezone "nginx" "nginx:stable" 80 80 ""

# Create nginx2 deployment and service with timezone configuration
create_deployment_with_timezone "nginx2" "nginx:stable" 80 80 ""

# Create Blackbox Exporter deployment and service with timezone configuration
echo "Creating blackbox-exporter.yaml..."
cat <<EOF > k8s/base/blackbox-exporter.yaml
apiVersion: v1
kind: Service
metadata:
  name: blackbox-exporter
  namespace: observability
spec:
  selector:
    app: blackbox-exporter
  ports:
    - port: 9115
      targetPort: 9115
      name: http
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: blackbox-exporter
  namespace: observability
spec:
  replicas: 1
  selector:
    matchLabels:
      app: blackbox-exporter
  template:
    metadata:
      labels:
        app: blackbox-exporter
    spec:
      containers:
        - name: blackbox-exporter
          image: prom/blackbox-exporter:latest
          args:
            - '--config.file=/etc/blackbox_exporter/config.yml'
          env:
            - name: TZ
              value: "Europe/Moscow"
          volumeMounts:
            - name: config
              mountPath: /etc/blackbox_exporter
            - name: tz-config
              mountPath: /etc/localtime
              readOnly: true
        - name: config-reloader
          image: jimmidyson/configmap-reload:v0.5.0
          args:
            - --volume-dir=/etc/blackbox_exporter
            - --webhook-url=http://localhost:9115/-/reload
          volumeMounts:
            - name: config
              mountPath: /etc/blackbox_exporter
      volumes:
        - name: config
          configMap:
            name: blackbox-exporter-config
            items:
              - key: config.yml
                path: config.yml
        - name: tz-config
          hostPath:
            path: /usr/share/zoneinfo/Europe/Moscow
            type: File
EOF

# Create ConfigMap for Blackbox Exporter
echo "Creating blackbox-exporter-configmap.yaml..."
cat <<EOF > k8s/base/blackbox-exporter-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: blackbox-exporter-config
  namespace: observability
data:
  config.yml: |
    modules:
      http_2xx:
        prober: http
        timeout: 5s
        http:
          valid_status_codes: [200]
          method: GET
EOF

# Create PVC for VictoriaMetrics
echo "Creating victoria-metrics-pvc.yaml..."
cat <<EOF > k8s/base/victoria-metrics-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: victoria-metrics-pvc
  namespace: observability
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi   # Request 5 GB of storage
EOF

# Create VictoriaMetrics deployment and service with timezone configuration and storage limit
echo "Creating victoria-metrics.yaml..."
cat <<EOF > k8s/base/victoria-metrics.yaml
apiVersion: v1
kind: Service
metadata:
  name: victoria-metrics
  namespace: observability
spec:
  selector:
    app: victoria-metrics
  ports:
    - port: 8428
      targetPort: 8428
      name: http
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: victoria-metrics
  namespace: observability
spec:
  replicas: 1
  selector:
    matchLabels:
      app: victoria-metrics
  template:
    metadata:
      labels:
        app: victoria-metrics
    spec:
      containers:
        - name: victoria-metrics
          image: victoriametrics/victoria-metrics:latest
          args:
            - '--selfScrapeInterval=0'
            - '--storageDataPath=/victoria-metrics-data'   # Specify storage path
            - '--retentionPeriod=30d'                      # Retain data for 30 days
          env:
            - name: TZ
              value: "Europe/Moscow"
          volumeMounts:
            - name: victoria-metrics-storage
              mountPath: /victoria-metrics-data           # Mount storage volume
            - name: tz-config
              mountPath: /etc/localtime
              readOnly: true
      volumes:
        - name: victoria-metrics-storage
          persistentVolumeClaim:
            claimName: victoria-metrics-pvc
        - name: tz-config
          hostPath:
            path: /usr/share/zoneinfo/Europe/Moscow
            type: File
EOF

# [Rest of the script remains unchanged]

# Create kustomization.yaml in base
echo "Creating kustomization.yaml in base..."
cat <<EOF > k8s/base/kustomization.yaml
resources:
  - namespace.yaml
  - nginx.yaml
  - nginx2.yaml
  - blackbox-exporter.yaml
  - blackbox-exporter-configmap.yaml
  - victoria-metrics-pvc.yaml     # Added PVC resource
  - victoria-metrics.yaml
  - vmagent.yaml
  - vmagent-scrape-config.yaml
  - vmalert.yaml
  - vmalert-rules-config.yaml
  - grafana.yaml
  - grafana-datasources.yaml
  - grafana-dashboard-configmap.yaml
  - grafana-dashboard-provisioning.yaml
  - alertmanager.yaml
  - alertmanager-config.yaml
  - mailhog.yaml
EOF

# [Rest of the script remains unchanged]

echo "Setup complete!"
