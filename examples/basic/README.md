# Basic

A basic one-replica setup on GKE Autopilot served on a HTTPS endpoint. The basic method is the fastest and cheapest way to get SurrealDB running with a TiKV backend. Cost for this setup is $74.40/month for cluster management fee (free with usage credits) + $80/month resource request (approximate).

Important note: this setup is meant to be cheap with minimal resources and is not meant to be run in production. To run in production, see the [Autopilot Production example](../prod-auto).

To ensure this example works without error, ensure you have the Project Owner IAM permission.

**What you'll build**
- Single cluster
- GKE Autopilot
- External Load Balancer with an HTTPS endpoint (Google-managed SSL certificate)
- NAT for cluster internet connectivity
- Encryption at Rest Storage (with master-key KMS)
- TLS encryption between TiDB components

### Prerequisites

- [Helm v4](https://helm.sh/docs/intro/install/)
- [Kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl)
- [cert-manager](https://cert-manager.io/docs/installation/)

# GCP Setup

This setup requires the [gcp setup](../../README.md#gcp-setup) before continuing.

## Terraform Setup

1. Copy the [main.tf](./main.tf) to your own `main.tf` file. Remember, to replace the local values with your own variable values. Specifically, replace "\<PROJECT_ID\>", "\<VPC_NAME\>" and "\<REGION\>".

2. Initialize the provider plugins, format the configuration, and validate it locally.
```bash
terraform init
terraform fmt -check -recursive
terraform validate
```

3. Plan the deployment to check for setup errors before applying. Save the reviewed plan so the apply operation uses exactly those changes.
```bash
terraform plan -out=basic.tfplan
```

4. When satisfied, apply the reviewed plan.
```bash
terraform apply basic.tfplan
```

## Access the Private GKE Control Plane

1. Add your cluster credentials

```bash
gcloud container clusters list
# export CLUSTER=surrealdb-* cluster and its location
# export LOCATION= location of the cluster
gcloud container clusters get-credentials $CLUSTER \
  --location $LOCATION \
  --dns-endpoint
```

2. Check connection to the cluster.

```bash
alias k="kubectl"
alias h="helm"
k get ns
```

## Encryption at Rest

Encryption at rest is opt-in by adding `encryption_at_rest` to each entry in `gke_clusters` before applying (see [main.tf](./main.tf))

Terraform creates a symmetric Google Cloud KMS key in the cluster's region and a dedicated Google service account per cluster. It also grants Workload Identity access to two Kubernetes service accounts: `gke-pd-<cluster_name>` and `gke-tikv-<cluster_name>`.

Create the two annotated Kubernetes service accounts (apply to every cluster):

```bash
# export REGION= location of the cluster
CLUSTER_NAME="$REGION-1"
KEY_NAME="${CLUSTER_NAME//-/_}"
KMS_KEY_ID=$(terraform output -json --state ../../terraform.tfstate encryption_at_rest_key_ids | jq -r --arg cluster "$KEY_NAME" '.[$cluster]')
PD_GCP_SERVICE_ACCOUNT=$(terraform output -json --state ../../terraform.tfstate encryption_at_rest_service_account_emails | jq -r --arg cluster "$KEY_NAME" '.[$cluster].pd')
TIKV_GCP_SERVICE_ACCOUNT=$(terraform output -json --state ../../terraform.tfstate encryption_at_rest_service_account_emails | jq -r --arg cluster "$KEY_NAME" '.[$cluster].tikv')
PD_SERVICE_ACCOUNT="gke-pd-${CLUSTER_NAME}"
TIKV_SERVICE_ACCOUNT="gke-tikv-${CLUSTER_NAME}"

k create namespace surreal-cluster --dry-run=client -o yaml | k apply -f -
k create serviceaccount "$PD_SERVICE_ACCOUNT" -n surreal-cluster --dry-run=client -o yaml | k apply -f -
k create serviceaccount "$TIKV_SERVICE_ACCOUNT" -n surreal-cluster --dry-run=client -o yaml | k apply -f -
k annotate serviceaccount "$PD_SERVICE_ACCOUNT" -n surreal-cluster \
  "iam.gke.io/gcp-service-account=$PD_GCP_SERVICE_ACCOUNT" --overwrite
k annotate serviceaccount "$TIKV_SERVICE_ACCOUNT" -n surreal-cluster \
  "iam.gke.io/gcp-service-account=$TIKV_GCP_SERVICE_ACCOUNT" --overwrite
```

The charts use `gcp_v2` and application default credentials from Workload Identity; no credential file is stored in the repository. The currently supported algorithms by both [TiKV](https://docs.pingcap.com/tidb/stable/encryption-at-rest/#tikv-encryption-at-rest) and [KMS](https://docs.cloud.google.com/kms/docs/reference/rest/v1/CryptoKeyVersionAlgorithm) are "AES128-CTR" and "AES_256_CTR". TiKV data keys rotate every seven days by default, while the KMS key rotates every 30 days. Existing data is not retroactively encrypted immediately, and data paths must remain stable after encryption is enabled.

To rotate the master key, configure the new and previous KMS keys in the TiKV and PD configuration and perform a rolling restart. Keep the previous key available until all existing data has been re-encrypted.

> [!IMPORTANT]
> PD does not yet have encryption. PD encryption is both considered experimental and unsupported via `gcp_v2`.

> [!WARNING]
> Terraform will create a KMS key ring for master-key encryption. It may take a day (ie `destroy_scheduled_duration`) to fully delete the key ring. If you wish to respin the terraform, we recommend changing the `key_ring_name` to avoid "conflicting name" issues unless the key ring is fully deleted.

## Install cert-manager

The cluster chart creates a self-signed CA and component certificates through cert-manager. Cert-manager is trusted within the namespace, not externally where the load balancer has a Google-Managed SSL certificate.

Install cert-manager with bare-minimum resources before installing the TiDB Operator or the cluster chart:

```bash
h repo add jetstack https://charts.jetstack.io
h repo update
h upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true \
  --set global.leaderElection.namespace=cert-manager \
  --set resources.requests.cpu=50m \
  --set resources.requests.memory=52Mi \
  --set webhook.resources.requests.cpu=50m \
  --set webhook.resources.requests.memory=52Mi \
  --set cainjector.resources.requests.cpu=50m \
  --set cainjector.resources.requests.memory=52Mi \
  --set startupapicheck.resources.requests.cpu=50m \
  --set startupapicheck.resources.requests.memory=52Mi
```

## Deploy TiDB Operator

1. Install CRDS
```bash
k apply -f https://github.com/pingcap/tidb-operator/releases/download/v2.0.0/tidb-operator.crds.yaml --server-side
```

2. Install the TiDB Operator from the GitHub release manifest instead of the Helm repo index:
```bash
k apply -f https://github.com/pingcap/tidb-operator/releases/download/v2.0.0/tidb-operator.yaml --server-side
```

3. Verify that the Pods are running (tip: add the `--watch` command to wait for changes.)
```bash
k get pods -n tidb-admin
```
```text
NAME                          READY   STATUS    RESTARTS   AGE
tidb-operator-xxx             1/1     Running   0          3m30s
```

## Create TiKV Cluster

Now that we have the TiDB Operator running, it's time to define a TiKV Cluster and let the Operator do the rest.

1. Install the cluster chart from the example directory.
```bash
h upgrade --install cluster ./charts/cluster -n surreal-cluster --create-namespace
```

The cluster chart enables mutual TLS by default and creates the CA, cluster client, and PD/TiKV certificates. Disable it with `--set tls.enabled=false` on the cluster, PD, and TiKV chart installs. When enabled, wait for the certificates to become ready before installing the component groups:

```bash
k get certificates -n surreal-cluster
```
```text
NAME                READY   SECRET                     AGE
pd-pd-cluster       True    pd-pd-cluster-secret       10s
sdb-tls-ca          True    sdb-tls-ca-secret          10s
sdb-web             True    sdb-web-secret             10s
surreal-tls         True    surreal-tls-secret         10s
tikv-tikv-cluster   True    tikv-tikv-cluster-secret   10s
```

2. Install the PD group chart.
```bash
h upgrade --install pd-group ./charts/pd-group -n surreal-cluster \
  --set-string serviceAccountName="$PD_SERVICE_ACCOUNT"
k get pdgroup -n surreal-cluster
```
```text
NAME   CLUSTER         DESIRED   READY   UPDATED   UPDATEREVISION     CURRENTREVISION    SYNCED   READY   AGE
pd     sdb-datastore   1         1       1         pd-pd-xxx          pd-pd-xxx          True     True    45s
```

3. Install the TiKV group chart.
```bash
h upgrade --install tikv-group ./charts/tikv-group -n surreal-cluster \
  --set encryption.enabled=true \
  --set-string serviceAccountName="$TIKV_SERVICE_ACCOUNT" \
  --set-string encryption.kms.keyID="$KMS_KEY_ID" \
  --set-string encryption.kms.region="$REGION"
k get tikvgroup -n surreal-cluster
```
```text
NAME   CLUSTER         DESIRED   READY   UPDATED   UPDATEREVISION     CURRENTREVISION    SYNCED   READY   AGE
tikv   sdb-datastore   1         1       1         tikv-tikv-xxx      tikv-tikv-xxx      True     True    68s
```

4. Check the cluster status and wait until it's ready (all ready and running).
```bash
k get pods -n surreal-cluster
```
```text
NAME              READY     STATUS    RESTARTS   AGE
pd-pd-xxx         1/1       Running   0          8m
tikv-tikv-xxx     1/1       Running   0          2m
```

## Deploy SurrealDB

Now that we have a TiDB cluster running, we can deploy SurrealDB using the Helm chart included in this repository under [charts/surrealdb](./charts/surrealdb). The chart is configured to connect to the TiKV PD service and exposes the SurrealDB service through the GKE NEG.

1. Copy the surrealdb values file locally. Replace the version and the placeholder in `cloud.google.com/neg` with your cluster name (for the example, replace "\<REGION\>") and the `iam.gke.io/gcp-service-account` with your workload identity service account (replace "\<PROJECT_ID\>").
```bash
cp ./charts/surrealdb/values.example.yaml values.local.yaml
```

2. Install the chart from the repository checkout.
```bash
h repo add surrealdb https://helm.surrealdb.com
h repo update
h upgrade --install -f values.local.yaml surrealdb surrealdb/surrealdb -n surreal-cluster
```

3. Check the deployment status to check everything is ready.
```bash
k get deployment -n surreal-cluster
```
```text
NAME        READY   UP-TO-DATE   AVAILABLE   AGE
surrealdb   1/1     1            1           9m29s
```

The values mount the `sdb-kvs-secret` certificate and set the `SURREAL_TIKV_TLS_CA_PATH`, `SURREAL_TIKV_TLS_CERT_PATH`, and `SURREAL_TIKV_TLS_KEY_PATH` variables so SurrealDB can connect securely to the TiKV-backed KVS. They also mount the `sdb-web-secret` certificate and set `SURREAL_WEB_CRT` and `SURREAL_WEB_KEY`, allowing the load balancers to use HTTPS to the SurrealDB NEG on port 443.

## Change Default Admin

It is recommended to change the root user of the deployment.

### DNS Endpoint

1. Connect using the Surreal CLI, don't save history.

```bash
surreal sql -u root -p root -e https://$DOMAIN
```

2. Run the following SurrealQL. Exit with CTRL+C.

```surrealql
DEFINE USER newadmin
  ON ROOT
  PASSWORD 'NEW_PASSWORD'
  ROLES OWNER;
REMOVE USER root ON ROOT;
```

### Jump Host

1. Exit the previously-opened jump host connection.

2. Open a connection to the frontend to connect to the admin portal in the VPC. Note these flags are different because routes are dynamic instead of targeting the localhost.
```bash
gcloud compute ssh $INSTANCE \
    --tunnel-through-iap \
    --ssh-flag="-ND 8888"
```

3. In another terminal, run the following to open a browser in the VPC network then visit surrealist.app to perform admin tasks. Feel free to modify the application with your computer’s application. If you followed the instructions, the root authentication is ‘root’ for both the username and password. The url domain is the https://DNS_NAME.

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    --user-data-dir="$HOME/chrome-proxy-profile" \
    --proxy-server="socks5://localhost:8888"
```

## Clean up

### Helm chart

Clean up of the Kubernetes environment can be quickly performed via helm.

```bash
h uninstall surrealdb -n surreal-cluster
h uninstall cluster -n surreal-cluster
h uninstall pd-group -n surreal-cluster
h uninstall tikv-group -n surreal-cluster
k delete deployment tidb-operator -n tidb-admin
h uninstall cert-manager -n cert-manager
```

### Terraform

Clean up is simple with Terraform. If deletion_protection is true, remember to set to false by first applying those terraform changes then proceeding with the following command.

```bash
terraform destroy
```

**NOTE** The VPC and Public DNS Zone are not removed as part of the terraform destruction, delete them manually.

## Authors
[Dylan Vanmali](https://github.com/dvanmali)

## Contributing
See [Contribution Guidelines](../../CONTRIBUTING.md)

## License
[Apache 2.0](../../LICENSE)

## Closing

This setup took many hours of development, so if you found this following repository helpful or if you used this in your deployment, please feel free to donate or give us star :star:

<a href="https://ko-fi.com/dvanmali" target="_blank">
  <img src="https://img.shields.io/badge/Ko--fi-FF5E5B?logo=ko-fi&logoColor=white" alt="Support me on Ko-fi" height="35" />
</a>

Thanks! :heart: :heart: :heart: