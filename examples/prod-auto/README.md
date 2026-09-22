# Autopilot Production

A 1-cluster production-grade Autopilot Google Kubernetes Engine deployment. The setup includes HA distributed storage, encryption at REST, and TLS in transit.

To ensure this example works without error, ensure you have the Project Owner IAM permission.

**What you'll build**
- Single cluster
- GKE Autopilot
- External Load Balancer with HTTPS endpoint (Google-managed SSL certificate)
- NAT for cluster internet connectivity
- Encryption at Rest Storage (with master-key KMS)

# Deploy

The deployment instructions are the same as the instructions as [Basic](../basic/README.md#terraform-setup) except use the value files referenced locally instead. Also, all recommended steps should be required, specifically encryption at REST, encryption in transit, and backups.

The differences between basic and production autopilot are:
- High availability with minimum replica set of 3 for each pd-group, tikv-group, and surrealdb.
- Horizontal scaling of SurrealDB. by default and optional vertical pod scaling with `enable_vertical_scaling = true`. Note that scaling for TiKV and PD is performed using resources (vertical scaling) and replicas (horizontal scaling) in which kubernetes and the tidb-operator will handle the scaling operations.
- Enabled Prometheus metrics to Google Monitoring.
 
The replica counts and resource values in the production charts are minimum recommendations for an HA deployment. For larger databases, increase the CPU and memory under `resources` and increase the data volume sizes under `volumes` in the `pd-group` and `tikv-group` charts to match the expected workload and storage requirements.

### Enable managed Prometheus

The production cluster enables GKE Managed Service for Prometheus in `main.tf` and the cluster Helm values render a `PodMonitoring` resource. The monitoring Kubernetes ServiceAccount is bound to the Terraform-created Google service account through Workload Identity.

After applying Terraform, get the generated Google service account email:

```bash
terraform output monitoring_service_account_email
```

Replace the `<PROJECT_ID>` placeholder in `values.cluster.yaml` with the matching email before installing the cluster chart. Managed collection still requires the `PodMonitoring` and `Rules` CRDs supplied by GKE Managed Service for Prometheus.

Set `surrealdb_service_account_email` in `main.tf` to the Google service account annotated on the SurrealDB pods. Terraform grants that account access to the two metrics secrets for the GKE Secret Manager CSI driver.

The cluster chart can install the SurrealDB, PD, TiKV, [node exporter](https://github.com/prometheus/node_exporter), and [blackbox exporter](https://github.com/prometheus/blackbox_exporter). PD and TiKV rules are enabled by default when rules are enabled; node exporter and blackbox rules are disabled by default because they require those exporters and targets. SurrealDB rules are enabled in this example and use the metric families described in the [SurrealDB metrics reference](https://surrealdb.com/docs/manage/observability/metrics.md). Set `monitoring.rules.enabled: false` to install managed collection without alert rules.

SurrealDB's full metrics surface requires authenticated viewer-scoped root credentials. Create a separate metrics user after the initial deployment, then add its password as a Google Secret Manager secret version. The username is configured directly in `values.cluster.yaml`. Terraform creates the password secret container and grants the SurrealDB workload service account access; it does not store the password:

```sql
DEFINE USER metrics ON ROOT PASSWORD '<METRICS_PASSWORD>' ROLES VIEWER;
```

```bash
printf '<METRICS_PASSWORD>' | gcloud secrets versions add surrealdb-metrics-password \
  --data-file=- --project <PROJECT_ID>
```

The cluster chart renders a `SecretProviderClass` using the GKE Secret Manager CSI driver. The production SurrealDB values mount that provider, which materializes the namespace-local Secret required by `PodMonitoring`. The chart then scrapes `/metrics` over HTTPS (when TLS is enabled) with the `surrealdb-metrics` credentials. Install the SurrealDB release with `SURREAL_METRICS_ENABLED=true`, then verify collection and rules:

```bash
k get podmonitoring,rules -n surreal-cluster
k describe podmonitoring surrealdb -n surreal-cluster
k get secret surrealdb-metrics -n surreal-cluster
```

The metrics user password must not be committed to values files, Terraform state, or shell scripts. The complete alert set includes process, HTTP, query, transaction, and distributed-cluster signals.

### Enable scaling

The production example leaves horizontal scaling enabled with `disable_horizontal_scaling = false` and enables vertical scaling with `enable_vertical_scaling = true` in `examples/prod-auto/main.tf`. Set `disable_horizontal_scaling = true` to disable the GKE horizontal pod autoscaling addon. Horizontal scaling keeps three SurrealDB pods running and scales up to nine based on CPU utilization; vertical scaling adjusts pod resources through GKE Autopilot.

Apply the Terraform change, then install SurrealDB with the production values:

```bash
terraform apply
h upgrade --install -f ./charts/surrealdb/values.yaml surrealdb surrealdb/surrealdb -n surreal-cluster
```

Verify both scaling mechanisms:

```bash
k get hpa -n surreal-cluster
k describe cluster surrealdb-<REGION>-1
```

## Install cert-manager

The cluster chart creates a self-signed CA and component certificates through cert-manager. Cert-manager is trusted within the namespace, not externally where the load balancer has a Google-managed SSL certificate.

Install [cert-manager with HA](https://cert-manager.io/docs/installation/best-practice/#high-availability) before installing the TiDB Operator or the cluster chart:

```bash
h repo add jetstack https://charts.jetstack.io
h repo update
h upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true \
  --set global.leaderElection.namespace=cert-manager \
  --set replicaCount=2 \
  --set webhook.replicaCount=3 \
  --set cainjector.replicaCount=2
```

## Authors
[Dylan Vanmali](https://github.com/dvanmali)

## Contributing
See [Contribution Guidelines](../../CONTRIBUTING.md)

## License
[Apache 2.0](../../LICENSE)

## Closing

This setup took many hours of development, so if you found this following repository helpful or if you used this in your deployment, please feel free to donate or give a star :star:

<a href="https://ko-fi.com/dvanmali" target="_blank">
  <img src="https://img.shields.io/badge/Ko--fi-FF5E5B?logo=ko-fi&logoColor=white" alt="Support me on Ko-fi" height="35" />
</a>

Thanks! :heart: :heart: :heart: