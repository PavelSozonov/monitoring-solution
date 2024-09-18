# Monitoring Solution

This project sets up a scalable monitoring solution for HTTP endpoints using Kubernetes, VictoriaMetrics, Grafana, and more.

## Components

- **nginx**: A demo web service.
- **nginx2**: An additional demo web service.
- **Blackbox Exporter**: Probes HTTP endpoints.
- **VMAgent**: Scrapes metrics and sends them to VictoriaMetrics.
- **VMAlert**: Evaluates alerting rules and sends alerts to Alertmanager.
- **VictoriaMetrics**: Time-series database for metrics.
- **Grafana**: Visualization of metrics.
- **Alertmanager**: Handles alerts.
- **MailHog**: Mock SMTP server for testing alerts (data is not persisted).

## Prerequisites

- **Kind**: Local Kubernetes cluster.
- **Skaffold**: For local development.
- **Kubectl**: To interact with the cluster.
- **Docker**: For building images.

## Setting Up the Kind Cluster

Navigate to the `kind` directory and run the `create_kind_cluster.sh` script to create a kind cluster configured with the Docker Hub mirror `https://dockerhub.timeweb.cloud`.

```bash
cd kind
./create_kind_cluster.sh
cd ..
```

## Deleting the Kind Cluster

To delete the kind cluster, run the `delete_kind_cluster.sh` script:

```bash
cd kind
./delete_kind_cluster.sh
cd ..
```

## Deploying the Monitoring Solution

Deploy the monitoring solution using Skaffold:

```bash
skaffold dev
```

## Accessing the Applications

1. **Access Grafana**:

   ```bash
   kubectl port-forward svc/grafana -n observability 3000:3000
   ```

   - Open [http://localhost:3000](http://localhost:3000) in your browser.
   - Login with username: `admin`, password: `admin`.

2. **Access MailHog**:

   ```bash
   kubectl port-forward svc/mailhog -n observability 8025:8025
   ```

   - Open [http://localhost:8025](http://localhost:8025) in your browser.

3. **Access Nginx2** (Optional):

   ```bash
   kubectl port-forward svc/nginx2 -n observability 8081:80
   ```

   - Open [http://localhost:8081](http://localhost:8081) in your browser.

## Monitoring Multiple Endpoints

- **Add Endpoints**: Edit `k8s/base/vmagent-scrape-config.yaml` and add your endpoints under `static_configs`.
- **Apply Changes**: Changes will be automatically applied due to the `config-reloader`.

## Testing Alerts

- **Scale Down nginx2**:

  ```bash
  kubectl scale deployment nginx2 -n observability --replicas=0
  ```

- **Check MailHog**: An alert email should appear in MailHog.

## Deploying to Production

- **Apply Manifests**:

  ```bash
  kubectl apply -k k8s/overlays/production
  ```

## Notes

- **Namespace**: All resources are deployed in the `observability` namespace.
- **Configurations**: All configurations are managed via ConfigMaps.
- **Reloading Configs**: Changes to ConfigMaps are automatically reloaded thanks to the `config-reloader` sidecars.
- **Timezone Configuration**: All components are configured to operate in the Moscow timezone (`Europe/Moscow`).
- **Persistent Storage**:
  - VictoriaMetrics uses a PersistentVolumeClaim limited to 5 GB.
  - **MailHog data is not persisted**; emails will not survive pod restarts.
- **Security Considerations**:
  - **TLS in Alertmanager**: Currently, TLS is disabled for SMTP to work with MailHog. Ensure TLS is enabled in production environments.
  - **Admin Password**: The default Grafana admin password is set to `admin`. Change this in production for security.

