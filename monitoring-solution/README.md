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

   ```bash
   skaffold dev
   ```

3. **Access Grafana**:

   ```bash
   kubectl port-forward svc/grafana 3000:3000
   ```

   - Open [http://localhost:3000](http://localhost:3000) in your browser.
   - Login with username: `admin`, password: `admin`.

4. **Access MailHog**:

   ```bash
   kubectl port-forward svc/mailhog 8025:8025
   ```

   - Open [http://localhost:8025](http://localhost:8025) in your browser.

## Monitoring Multiple Endpoints

- **Add Endpoints**: Edit `k8s/base/vmagent-scrape-config.yaml` and add your endpoints under `static_configs`.
- **Apply Changes**: Since we're using Skaffold, changes will be automatically applied.

## Testing Alerts

- **Scale Down nginx**:

  ```bash
  kubectl scale deployment nginx --replicas=0
  ```

- **Check MailHog**: An alert email should appear in MailHog.

## Deploying to Production

- **Apply Manifests**:

  ```bash
  kubectl apply -k k8s/overlays/production
  ```

## Notes

- **Configurations**: All configurations are managed via ConfigMaps.
- **Reloading Configs**: Changes to ConfigMaps are automatically reloaded thanks to the `config-reloader` sidecars.
- **Persistent Storage**: For production use, consider adding PersistentVolumeClaims.
