#!/bin/bash

# setup.sh - Script to set up the monitoring solution project

# Exit immediately if a command exits with a non-zero status
set -e

# Create the directory structure
echo "Creating directory structure..."
mkdir -p monitoring-solution/k8s/base
mkdir -p monitoring-solution/k8s/overlays/local
mkdir -p monitoring-solution/k8s/overlays/production

cd monitoring-solution

# Create nginx deployment and service
echo "Creating nginx.yaml..."
cat <<EOF > k8s/base/nginx.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
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
spec:
  selector:
    app: blackbox-exporter
  ports:
    - port: 9115
      targetPort: 9115
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: blackbox-exporter
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
spec:
  selector:
    app: victoria-metrics
  ports:
    - port: 8428
      targetPort: 8428
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: victoria-metrics
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
echo "Creating vmagent deployment in victoria-metrics.yaml..."
cat <<EOF >> k8s/base/victoria-metrics.yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vmagent
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
            - '--rule=/etc/vmagent/rules.yaml'
            - '--notifier.url=http://alertmanager:9093/'
            - '--httpListenAddr=:8429'
          volumeMounts:
            - name: config
              mountPath: /etc/vmagent
            - name: rules
              mountPath: /etc/vmagent/rules.yaml
              subPath: rules.yaml
        - name: config-reloader
          image: jimmidyson/configmap-reload:v0.5.0
          args:
            - --volume-dir=/etc/vmagent
            - --webhook-url=http://localhost:8429/-/reload
          volumeMounts:
            - name: config
              mountPath: /etc/vmagent
            - name: rules
              mountPath: /etc/vmagent
      volumes:
        - name: config
          configMap:
            name: vmagent-scrape-config
            items:
              - key: vmagent.yaml
                path: vmagent.yaml
        - name: rules
          configMap:
            name: vmagent-rules
            items:
              - key: rules.yaml
                path: rules.yaml
EOF

# Create ConfigMap for VMAgent scrape configurations
echo "Creating vmagent-scrape-config.yaml..."
cat <<EOF > k8s/base/vmagent-scrape-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: vmagent-scrape-config
data:
  vmagent.yaml: |
    global:
      scrape_interval: 15s
      evaluation_interval: 15s
    scrape_configs:
      - job_name: 'blackbox'
        metrics_path: /probe
        params:
          module: [http_2xx]
        static_configs:
          - targets:
              - http://nginx:80
              # Add more endpoints here
              # - http://example.com
        relabel_configs:
          - source_labels: [__address__]
            target_label: __param_target
          - target_label: __address__
            replacement: blackbox-exporter:9115
          - source_labels: [__param_target]
            target_label: instance
EOF

# Create ConfigMap for VMAgent alerting rules
echo "Creating vmagent-rules-config.yaml..."
cat <<EOF > k8s/base/vmagent-rules-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: vmagent-rules
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
spec:
  selector:
    app: grafana
  ports:
    - port: 3000
      targetPort: 3000
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
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
  labels:
    grafana_datasource: "1"
data:
  datasource.yaml: |
    apiVersion: 1
    datasources:
      - name: VictoriaMetrics
        type: prometheus
        access: proxy
        url: http://victoria-metrics:8428
        isDefault: true
EOF

# Create ConfigMap for Grafana dashboards
echo "Creating grafana-dashboard-configmap.yaml..."
cat <<EOF > k8s/base/grafana-dashboard-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboards
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
spec:
  selector:
    app: alertmanager
  ports:
    - port: 9093
      targetPort: 9093
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: alertmanager
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
data:
  config.yml: |
    global:
      smtp_smarthost: 'mailhog:1025'
      smtp_from: 'alertmanager@example.com'
    route:
      receiver: 'email-alert'
    receivers:
      - name: 'email-alert'
        email_configs:
          - to: 'user@example.com'
            # Uncomment and set your real email configurations here
            # smtp_smarthost: 'smtp.example.com:587'
            # smtp_from: 'alertmanager@example.com'
            # auth_username: 'your-username'
            # auth_password: 'your-password'
EOF

# Create MailHog deployment and service
echo "Creating mailhog.yaml..."
cat <<EOF > k8s/base/mailhog.yaml
apiVersion: v1
kind: Service
metadata:
  name: mailhog
spec:
  selector:
    app: mailhog
  ports:
    - port: 8025
      targetPort: 8025
    - port: 1025
      targetPort: 1025
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mailhog
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
  - nginx.yaml
  - blackbox-exporter.yaml
  - blackbox-exporter-configmap.yaml
  - victoria-metrics.yaml
  - vmagent-scrape-config.yaml
  - vmagent-rules-config.yaml
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
EOF

# Create kustomization.yaml in overlays/production
echo "Creating kustomization.yaml in overlays/production..."
cat <<EOF > k8s/overlays/production/kustomization.yaml
resources:
  - ../../base
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
- **VictoriaMetrics**: Time-series database for metrics.
- **Grafana**: Visualization of metrics.
- **Alertmanager**: Handles alerts.
- **MailHog**: Mock SMTP server for testing alerts.

## Prerequisites

- **Kind**: Local Kubernetes cluster.
- **Skaffold**: For local development.
- **Kubectl**: To interact with the cluster.
- **Docker**: For building images.

## Running Locally

1. **Start the kind cluster** (if not already running).
2. **Run Skaffold**:

   \`\`\`bash
   skaffold dev
   \`\`\`

3. **Access Grafana**:

   \`\`\`bash
   kubectl port-forward svc/grafana 3000:3000
   \`\`\`

   - Open [http://localhost:3000](http://localhost:3000) in your browser.
   - Login with username: \`admin\`, password: \`admin\`.

4. **Access MailHog**:

   \`\`\`bash
   kubectl port-forward svc/mailhog 8025:8025
   \`\`\`

   - Open [http://localhost:8025](http://localhost:8025) in your browser.

## Monitoring Multiple Endpoints

- **Add Endpoints**: Edit \`k8s/base/vmagent-scrape-config.yaml\` and add your endpoints under \`static_configs\`.
- **Apply Changes**: Since we're using Skaffold, changes will be automatically applied.

## Testing Alerts

- **Scale Down nginx**:

  \`\`\`bash
  kubectl scale deployment nginx --replicas=0
  \`\`\`

- **Check MailHog**: An alert email should appear in MailHog.

## Deploying to Production

- **Apply Manifests**:

  \`\`\`bash
  kubectl apply -k k8s/overlays/production
  \`\`\`

## Notes

- **Configurations**: All configurations are managed via ConfigMaps.
- **Reloading Configs**: Changes to ConfigMaps are automatically reloaded thanks to the \`config-reloader\` sidecars.
- **Persistent Storage**: For production use, consider adding PersistentVolumeClaims.

EOF

echo "Setup complete!"
