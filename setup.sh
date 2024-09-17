#!/bin/bash

# setup.sh - Script to set up the monitoring solution project

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

# Create nginx deployment and service
echo "Creating nginx.yaml..."
cat <<EOF > k8s/base/nginx.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: observability
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: nginx:stable
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx
  namespace: observability
spec:
  selector:
    app: nginx
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
EOF

# Create Blackbox Exporter deployment and service
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
          volumeMounts:
            - name: config
              mountPath: /etc/blackbox_exporter
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

# Create VictoriaMetrics deployment and service
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
EOF

# Create VMAgent deployment
echo "Creating vmagent deployment..."
cat <<EOF > k8s/base/vmagent.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vmagent
  namespace: observability
spec:
  replicas: 1
  selector:
    matchLabels:
      app: vmagent
  template:
    metadata:
      labels:
        app: vmagent
    spec:
      containers:
        - name: vmagent
          image: victoriametrics/vmagent:latest
          args:
            - '--promscrape.config=/etc/vmagent/vmagent.yaml'
            - '--remoteWrite.url=http://victoria-metrics:8428/api/v1/write'
            - '--httpListenAddr=:8429'
          volumeMounts:
            - name: config
              mountPath: /etc/vmagent
        - name: config-reloader
          image: jimmidyson/configmap-reload:v0.5.0
          args:
            - --volume-dir=/etc/vmagent
            - --webhook-url=http://localhost:8429/-/reload
          volumeMounts:
            - name: config
              mountPath: /etc/vmagent
      volumes:
        - name: config
          configMap:
            name: vmagent-scrape-config
            items:
              - key: vmagent.yaml
                path: vmagent.yaml
EOF

# Create ConfigMap for VMAgent scrape configurations
echo "Creating vmagent-scrape-config.yaml..."
cat <<EOF > k8s/base/vmagent-scrape-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: vmagent-scrape-config
  namespace: observability
data:
  vmagent.yaml: |
    global:
      scrape_interval: 15s
    scrape_configs:
      - job_name: 'blackbox'
        metrics_path: /probe
        params:
          module: [http_2xx]
        static_configs:
          - targets:
              - http://nginx.observability.svc.cluster.local
              # Add more endpoints here
              # - http://example.com
        relabel_configs:
          - source_labels: [__address__]
            target_label: __param_target
          - target_label: __address__
            replacement: blackbox-exporter.observability.svc.cluster.local:9115
          - source_labels: [__param_target]
            target_label: instance
EOF

# Create VMalert deployment
echo "Creating vmalert deployment..."
cat <<EOF > k8s/base/vmalert.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vmalert
  namespace: observability
spec:
  replicas: 1
  selector:
    matchLabels:
      app: vmalert
  template:
    metadata:
      labels:
        app: vmalert
    spec:
      containers:
        - name: vmalert
          image: victoriametrics/vmalert:latest
          args:
            - '--rule=/etc/vmalert/rules.yaml'
            - '--datasource.url=http://victoria-metrics.observability.svc.cluster.local:8428'
            - '--notifier.url=http://alertmanager.observability.svc.cluster.local:9093/'
            - '--httpListenAddr=:8880'
          volumeMounts:
            - name: config
              mountPath: /etc/vmalert
        - name: config-reloader
          image: jimmidyson/configmap-reload:v0.5.0
          args:
            - --volume-dir=/etc/vmalert
            - --webhook-url=http://localhost:8880/-/reload
          volumeMounts:
            - name: config
              mountPath: /etc/vmalert
      volumes:
        - name: config
          configMap:
            name: vmalert-rules
            items:
              - key: rules.yaml
                path: rules.yaml
EOF

# Create ConfigMap for VMalert alerting rules
echo "Creating vmalert-rules-config.yaml..."
cat <<EOF > k8s/base/vmalert-rules-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: vmalert-rules
  namespace: observability
data:
  rules.yaml: |
    groups:
      - name: availability-rules
        rules:
          - alert: EndpointDown
            expr: probe_success == 0
            for: 1m
            labels:
              severity: critical
            annotations:
              summary: "Endpoint {{ \$labels.instance }} is down"
              description: "The endpoint {{ \$labels.instance }} has been down for more than 1 minute."
EOF

# Create Grafana deployment and service
echo "Creating grafana.yaml..."
cat <<EOF > k8s/base/grafana.yaml
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: observability
spec:
  selector:
    app: grafana
  ports:
    - port: 3000
      targetPort: 3000
      name: http
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: observability
spec:
  replicas: 1
  selector:
    matchLabels:
      app: grafana
  template:
    metadata:
      labels:
        app: grafana
    spec:
      containers:
        - name: grafana
          image: grafana/grafana:latest
          ports:
            - containerPort: 3000
          env:
            - name: GF_SECURITY_ADMIN_PASSWORD
              value: "admin"
          volumeMounts:
            - name: grafana-datasources
              mountPath: /etc/grafana/provisioning/datasources
            - name: grafana-dashboards
              mountPath: /var/lib/grafana/dashboards
            - name: grafana-dashboard-provisioning
              mountPath: /etc/grafana/provisioning/dashboards
      volumes:
        - name: grafana-datasources
          configMap:
            name: grafana-datasources
        - name: grafana-dashboards
          configMap:
            name: grafana-dashboards
        - name: grafana-dashboard-provisioning
          configMap:
            name: grafana-dashboard-provisioning
EOF

# Create ConfigMap for Grafana data sources
echo "Creating grafana-datasources.yaml..."
cat <<EOF > k8s/base/grafana-datasources.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasources
  namespace: observability
  labels:
    grafana_datasource: "1"
data:
  datasource.yaml: |
    apiVersion: 1
    datasources:
      - name: VictoriaMetrics
        type: prometheus
        access: proxy
        url: http://victoria-metrics.observability.svc.cluster.local:8428
        isDefault: true
EOF

# Create ConfigMap for Grafana dashboards
echo "Creating grafana-dashboard-configmap.yaml..."
cat <<EOF > k8s/base/grafana-dashboard-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboards
  namespace: observability
  labels:
    grafana_dashboard: "1"
data:
  nginx-availability.json: |
    {
      "id": null,
      "title": "HTTP Endpoint Availability",
      "uid": "endpoint-availability",
      "version": 1,
      "schemaVersion": 16,
      "panels": [
        {
          "type": "graph",
          "title": "Endpoint Availability",
          "targets": [
            {
              "expr": "probe_success{job=\"blackbox\"}",
              "legendFormat": "{{ instance }}",
              "refId": "A"
            }
          ]
        }
      ],
      "templating": {
        "list": [
          {
            "name": "instance",
            "type": "query",
            "datasource": "VictoriaMetrics",
            "query": "label_values(probe_success{job=\"blackbox\"}, instance)"
          }
        ]
      }
    }
EOF

# Create ConfigMap for Grafana dashboard provisioning
echo "Creating grafana-dashboard-provisioning.yaml..."
cat <<EOF > k8s/base/grafana-dashboard-provisioning.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-provisioning
  namespace: observability
data:
  dashboards.yaml: |
    apiVersion: 1
    providers:
      - name: 'default'
        orgId: 1
        folder: ''
        type: file
        disableDeletion: false
        updateIntervalSeconds: 10
        options:
          path: /var/lib/grafana/dashboards
EOF

# Create Alertmanager deployment and service
echo "Creating alertmanager.yaml..."
cat <<EOF > k8s/base/alertmanager.yaml
apiVersion: v1
kind: Service
metadata:
  name: alertmanager
  namespace: observability
spec:
  selector:
    app: alertmanager
  ports:
    - port: 9093
      targetPort: 9093
      name: http
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: alertmanager
  namespace: observability
spec:
  replicas: 1
  selector:
    matchLabels:
      app: alertmanager
  template:
    metadata:
      labels:
        app: alertmanager
    spec:
      containers:
        - name: alertmanager
          image: prom/alertmanager:latest
          args:
            - '--config.file=/etc/alertmanager/config.yml'
          volumeMounts:
            - name: config
              mountPath: /etc/alertmanager
      volumes:
        - name: config
          configMap:
            name: alertmanager-config
EOF

# Create ConfigMap for Alertmanager configuration
echo "Creating alertmanager-config.yaml..."
cat <<EOF > k8s/base/alertmanager-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: alertmanager-config
  namespace: observability
data:
  config.yml: |
    global:
      smtp_smarthost: 'mailhog.observability.svc.cluster.local:1025'
      smtp_from: 'alertmanager@example.com'
    route:
      receiver: 'email-alert'
    receivers:
      - name: 'email-alert'
        email_configs:
          - to: 'user@example.com'
EOF

# Create MailHog deployment and service
echo "Creating mailhog.yaml..."
cat <<EOF > k8s/base/mailhog.yaml
apiVersion: v1
kind: Service
metadata:
  name: mailhog
  namespace: observability
spec:
  selector:
    app: mailhog
  ports:
    - name: http
      port: 8025
      targetPort: 8025
    - name: smtp
      port: 1025
      targetPort: 1025
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mailhog
  namespace: observability
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mailhog
  template:
    metadata:
      labels:
        app: mailhog
    spec:
      containers:
        - name: mailhog
          image: mailhog/mailhog:latest
          ports:
            - containerPort: 1025
            - containerPort: 8025
EOF

# Create kustomization.yaml in base
echo "Creating kustomization.yaml in base..."
cat <<EOF > k8s/base/kustomization.yaml
resources:
  - namespace.yaml
  - nginx.yaml
  - blackbox-exporter.yaml
  - blackbox-exporter-configmap.yaml
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

# Create kustomization.yaml in overlays/local
echo "Creating kustomization.yaml in overlays/local..."
cat <<EOF > k8s/overlays/local/kustomization.yaml
resources:
  - ../../base
namespace: observability
EOF

# Create kustomization.yaml in overlays/production
echo "Creating kustomization.yaml in overlays/production..."
cat <<EOF > k8s/overlays/production/kustomization.yaml
resources:
  - ../../base
namespace: observability
EOF

# Create skaffold.yaml
echo "Creating skaffold.yaml..."
cat <<EOF > skaffold.yaml
apiVersion: skaffold/v2beta26
kind: Config
deploy:
  kustomize:
    paths:
      - k8s/overlays/local
EOF

# Create README.md
echo "Creating README.md..."
cat <<EOF > README.md
# Monitoring Solution

This project sets up a scalable monitoring solution for HTTP endpoints using Kubernetes, VictoriaMetrics, Grafana, and more.

## Components

- **nginx**: A demo web service.
- **Blackbox Exporter**: Probes HTTP endpoints.
- **VMAgent**: Scrapes metrics and sends them to VictoriaMetrics.
- **VMAlert**: Evaluates alerting rules and sends alerts to Alertmanager.
- **VictoriaMetrics**: Time-series database for metrics.
- **Grafana**: Visualization of metrics.
- **Alertmanager**: Handles alerts.
- **MailHog**: Mock SMTP server for testing alerts.

## Prerequisites

- **Kind**: Local Kubernetes cluster.
- **Skaffold**: For local development.
- **Kubectl**: To interact with the cluster.
- **Docker**: For building images.

## Setting Up the Kind Cluster

Navigate to the \`kind\` directory and run the \`create_kind_cluster.sh\` script to create a kind cluster configured with the Docker Hub mirror \`https://dockerhub.timeweb.cloud\`.

\`\`\`bash
cd kind
./create_kind_cluster.sh
cd ..
\`\`\`

## Deleting the Kind Cluster

To delete the kind cluster, run the \`delete_kind_cluster.sh\` script:

\`\`\`bash
cd kind
./delete_kind_cluster.sh
cd ..
\`\`\`

## Deploying the Monitoring Solution

Deploy the monitoring solution using Skaffold:

\`\`\`bash
skaffold dev
\`\`\`

## Accessing the Applications

1. **Access Grafana**:

   \`\`\`bash
   kubectl port-forward svc/grafana -n observability 3000:3000
   \`\`\`

   - Open [http://localhost:3000](http://localhost:3000) in your browser.
   - Login with username: \`admin\`, password: \`admin\`.

2. **Access MailHog**:

   \`\`\`bash
   kubectl port-forward svc/mailhog -n observability 8025:8025
   \`\`\`

   - Open [http://localhost:8025](http://localhost:8025) in your browser.

## Monitoring Multiple Endpoints

- **Add Endpoints**: Edit \`k8s/base/vmagent-scrape-config.yaml\` and add your endpoints under \`static_configs\`.
- **Apply Changes**: Changes will be automatically applied due to the \`config-reloader\`.

## Testing Alerts

- **Scale Down nginx**:

  \`\`\`bash
  kubectl scale deployment nginx -n observability --replicas=0
  \`\`\`

- **Check MailHog**: An alert email should appear in MailHog.

## Deploying to Production

- **Apply Manifests**:

  \`\`\`bash
  kubectl apply -k k8s/overlays/production
  \`\`\`

## Notes

- **Namespace**: All resources are deployed in the \`observability\` namespace.
- **Configurations**: All configurations are managed via ConfigMaps.
- **Reloading Configs**: Changes to ConfigMaps are automatically reloaded thanks to the \`config-reloader\` sidecars.
- **Persistent Storage**: For production use, consider adding PersistentVolumeClaims.

EOF

echo "Setup complete!"
