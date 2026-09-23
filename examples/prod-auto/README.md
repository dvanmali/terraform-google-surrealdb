# Autopilot Production

A 1-cluster production-grade Autopilot Google Kubernetes Engine deployment. The setup includes HA distributed storage, encryption at REST, and TLS in transit.

To ensure this example works without error, ensure you have the Project Owner IAM permission.

**What you'll build**
- Single cluster
- GKE Autopilot
- External Load Balancer with HTTPS endpoint (Google-managed SSL certificate)
- NAT for cluster internet connectivity
- Encryption at Rest Storage (with master-key KMS)
- Horizontal pod autoscaling

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

Terraform enables GKE Secret Sync for the cluster so the metrics credential can be synchronized from Google Secret Manager.

The cluster chart can install the SurrealDB, PD, TiKV, [node exporter](https://github.com/prometheus/node_exporter), and [blackbox exporter](https://github.com/prometheus/blackbox_exporter). PD and TiKV rules are enabled by default when rules are enabled; node exporter and blackbox rules are disabled by default because they require those exporters and targets. SurrealDB rules are enabled in this example and use the metric families described in the [SurrealDB metrics reference](https://surrealdb.com/docs/manage/observability/metrics.md). Set `monitoring.rules.enabled: false` to install managed collection without alert rules.

SurrealDB's full metrics surface requires authenticated viewer-scoped root credentials. Create a separate metrics user after the initial deployment, then add its password as a Google Secret Manager secret version. The username is configured directly in `values.cluster.yaml`. Terraform creates the password secret container and grants the SurrealDB workload service account access; it does not store the password:

```sql
DEFINE USER metrics ON ROOT PASSWORD '<METRICS_PASSWORD>' ROLES VIEWER;
```

```bash
printf '<METRICS_PASSWORD>' | gcloud secrets versions add surrealdb-metrics-password \
  --data-file=- --project <PROJECT_ID>
```

The cluster chart renders a `SecretSync` using GKE Secret Sync. The password source is Google Secret Manager; Secret Sync makes it available to the monitoring configuration as the `surrealdb-metrics` Kubernetes Secret without mounting anything into the SurrealDB pod. The chart then scrapes `/metrics` over HTTPS (when TLS is enabled) with the `surrealdb-metrics` credentials. Install the SurrealDB release with `SURREAL_METRICS_ENABLED=true`, then verify collection and rules:

```bash
k get podmonitoring,rules -n surreal-cluster
k describe podmonitoring surrealdb -n surreal-cluster
k get secretsync surrealdb-metrics -n surreal-cluster
```

The metrics user password must not be committed to values files, Terraform state, or shell scripts. The complete alert set includes process, HTTP, query, transaction, and distributed-cluster signals.

### Verify metrics

Use the following trace to verify the raw metrics endpoints and managed collection. These commands assume the namespace is `surreal-cluster`:

```bash
# export NS=surreal-cluster
kubectl get podmonitoring,rules -n "$NS"
kubectl describe podmonitoring sdb-datastore-pd -n "$NS"
kubectl describe podmonitoring sdb-datastore-tikv -n "$NS"
kubectl describe podmonitoring surrealdb -n "$NS"
kubectl get secretsync surrealdb-metrics -n "$NS"
```

#### PD metrics

PD and TiKV require mutual TLS, so query their endpoints from inside the workload pods using the mounted client certificates.

```bash
PD_POD=$(kubectl get pod -n "$NS" \
  -l 'pingcap.com/component=pd' \
  -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n "$NS" "$PD_POD" -- sh -c \
  'curl -sS --cacert /var/lib/pd-tls/ca.crt \
    --cert /var/lib/pd-tls/tls.crt \
    --key /var/lib/pd-tls/tls.key \
    https://127.0.0.1:2379/metrics' \
  | grep -E '^(pd_regions_status|pd_cluster_metadata|pd_tso_events|etcd_server_is_leader)' \
  | head -20
```

#### TiKV metrics

```bash
TIKV_POD=$(kubectl get pod -n "$NS" \
  -l 'pingcap.com/component=tikv' \
  -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n "$NS" "$TIKV_POD" -- sh -c \
  'curl -sS --cacert /var/lib/tikv-tls/ca.crt \
    --cert /var/lib/tikv-tls/tls.crt \
    --key /var/lib/tikv-tls/tls.key \
    https://127.0.0.1:20180/metrics' \
  | grep -E '^(tikv_|process_|go_)' \
  | head -30
```

#### SurrealDB metrics

To test the endpoint from inside the cluster, use the TiDB Operator pod which includes `curl`, with `-k` for a certificate:

```bash
OPERATOR_NS=tidb-admin
OPERATOR_POD=$(kubectl get pod -n "$OPERATOR_NS" \
  -l app.kubernetes.io/name=tidb-operator \
  -o jsonpath='{.items[0].metadata.name}')
METRICS_PASSWORD=$(gcloud secrets versions access latest \
  --secret=surrealdb-metrics-password)
kubectl exec -n "$OPERATOR_NS" "$OPERATOR_POD" -- \
  env METRICS_PASSWORD="$METRICS_PASSWORD" sh -c \
  'curl -sS -k -u "metrics:${METRICS_PASSWORD}" \
    -w "\\nHTTP_STATUS:%{http_code}\\n" \
    https://surrealdb.surreal-cluster.svc:443/metrics' \
  | grep -E '^(surrealdb_build_info|surrealdb_process_uptime_seconds|surrealdb_process_memory_bytes|surrealdb_process_cpu_percent|target_info|HTTP_STATUS:)'
```

The expected result is `HTTP_STATUS:200` and metrics including `surrealdb_build_info`. The in-cluster service address is `https://surrealdb.surreal-cluster.svc:443/metrics`.

#### Cloud Monitoring Metrics Explorer

PD v8.5.8 does not emit the older `pd_cluster_status` family. Verify managed collection with metric families that this version exposes:

```promql
pd_regions_status
pd_cluster_metadata
etcd_server_is_leader
tikv_engine_size_bytes
surrealdb_build_info
```

For a target summary, use:

```promql
count by (job) (up)
```

### Enable scaling

The production example leaves horizontal scaling enabled with `disable_horizontal_scaling = false` and enables vertical scaling with `enable_vertical_scaling = true` in `examples/prod-auto/main.tf`. Set `disable_horizontal_scaling = true` to disable the GKE horizontal pod autoscaling addon. Horizontal scaling keeps three SurrealDB pods running and scales up to nine based on CPU utilization; vertical scaling adjusts pod resources through GKE Autopilot.

Apply the Terraform change, then install SurrealDB with the production values:

```bash
terraform apply
h upgrade --install -f values.surrealdb.yaml surrealdb surrealdb/surrealdb -n surreal-cluster
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