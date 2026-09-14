# SurrealDB Terraform Deployment

A multi-node SurrealDB Kubernetes deployment on Google Kubernetes Engine served on a HTTPS endpoint.

**Configuration Options:**
- Single cluster or multi cluster
- Traditional GKE or GKE Autopilot per cluster
- Internal and/or External Load Balancing
- IAP member security rules

**Key Components:**
- Internal cross-regional load balancer for enabling internal access for clients
- Google-Managed SSL certificate for secure connectivity
- Jump-host VM to access the GKE control plane for each cluster using Google’s IAP
- NAT for cluster internet connectivity.

# Deployment Instructions

## DNS

We must create the Public DNS separately (not part of our Terraform) for the following reasons:

- Provides us time to add our NS records to our domain name records before carrying out any certificate DNS authorizations
- Prevents us from having a hanging subdomain DNS attack if we accidently leave this record on our domain server and we perform a Terraform destroy command.

```bash
$ export DOMAIN="db.example.com" # Replace with your domain
$ gcloud dns managed-zones create surrealdb \
	--description="Public DNS for $DOMAIN" \
	--dns-name=$DOMAIN \
	--visibility="public"
```

Add the generated NS records for that subdomain to your domain server (where your domains are hosted). The host name for the record must be the full path name to the name server. For example, the above example it will be "db.example.com".

```bash
$ gcloud dns managed-zones describe surrealdb --format json | jq ".nameServers[]"
```

## VPC

If you don’t already have a VPC set up, run the following to create a VPC. Feel free to create the VPC in IPv4 auto mode or IPv6 custom mode, both work with this setup. We recommend the IPv6 for future extensibility.

```bash
# IPv4 only auto-mode
$ gcloud compute networks create $VPC_NAME --subnet-mode=auto
# OR IPv4 and IPv6 dual-stack custom-mode (recommended)
$ gcloud compute networks create $VPC_NAME --subnet-mode=custom --enable-ula-internal-ipv6
```

## IAM

(recommended) If you wish to setup a default service account for the cluster instead of using the default compute class, please create a new service account within IAM with the following minimum roles. Add this email to every gke_cluster configuration under cluster_service_account_email. Note that this email is immutable once the cluster is created.

- Kubernetes Engine Default Node Service Account
- Monitoring Viewer
- Workload Identity User

## Basic Setup

See [examples](./examples/) for example configurations. The following follows the [basic setup](./examples/basic/).

### Prerequisites

- Helm v4
- Kubectl

1. Copy the [main.tf](./examples/basic/main.tf) to your own `main.tf` file. Remember, to replace the local values with your own variable values. Specifically, replace "\<PROJECT_ID\>", "\<VPC_NAME\>" and "\<REGION\>".

2. Initialize the provider plugins, format the configuration, and validate it locally.
```bash
$ terraform init
$ terraform fmt -check -recursive
$ terraform validate
```

3. Plan the deployment to check for setup errors before applying. Save the reviewed plan so the apply operation uses exactly those changes. The deployment includes an internal cross-regional load balancer for client access, a Google-managed SSL certificate, an IAP jump-host VM for each GKE cluster, and NAT for cluster internet connectivity.
```bash
$ terraform plan -out=tfplan
```

4. When satisfied, apply the reviewed plan.
```bash
$ terraform apply tfplan
```

### Encryption at Rest

Encryption at rest is opt-in and recommended in cloud deployments. Add `encryption_at_rest` to each entry in `gke_clusters` before applying:

```hcl
gke_clusters = {
  "<REGION>-1" = {
    # ...other cluster settings...
    encryption_at_rest = {
      enabled = true
    }
  }
}
```

Terraform creates a symmetric Google Cloud KMS key and a dedicated Google service account per cluster. It also grants Workload Identity access to two Kubernetes service accounts: `gke-pd-<cluster_name>` and `gke-tikv-<cluster_name>`. The KMS key location must cover the cluster region.

After applying Terraform, select the cluster outputs and create the two annotated Kubernetes service accounts:

```bash
CLUSTER_NAME="<REGION>-1"
KMS_KEY_ID=$(terraform output -json encryption_at_rest_key_ids | jq -r --arg cluster "$CLUSTER_NAME" '.[$cluster]')
GCP_SERVICE_ACCOUNT=$(terraform output -json encryption_at_rest_service_account_emails | jq -r --arg cluster "$CLUSTER_NAME" '.[$cluster]')
PD_SERVICE_ACCOUNT="gke-pd-${CLUSTER_NAME}"
TIKV_SERVICE_ACCOUNT="gke-tikv-${CLUSTER_NAME}"

kubectl create namespace surreal-cluster --dry-run=client -o yaml | kubectl apply -f -
kubectl create serviceaccount "$PD_SERVICE_ACCOUNT" -n surreal-cluster --dry-run=client -o yaml | kubectl apply -f -
kubectl create serviceaccount "$TIKV_SERVICE_ACCOUNT" -n surreal-cluster --dry-run=client -o yaml | kubectl apply -f -
kubectl annotate serviceaccount "$PD_SERVICE_ACCOUNT" -n surreal-cluster \
  "iam.gke.io/gcp-service-account=$GCP_SERVICE_ACCOUNT" --overwrite
kubectl annotate serviceaccount "$TIKV_SERVICE_ACCOUNT" -n surreal-cluster \
  "iam.gke.io/gcp-service-account=$GCP_SERVICE_ACCOUNT" --overwrite

helm upgrade --install pd-group ./examples/basic/charts/pd-group -n surreal-cluster \
  --set encryption.enabled=true \
  --set-string serviceAccountName="$PD_SERVICE_ACCOUNT" \
  --set-string encryption.kms.keyID="$KMS_KEY_ID"

helm upgrade --install tikv-group ./examples/basic/charts/tikv-group -n surreal-cluster \
  --set encryption.enabled=true \
  --set-string serviceAccountName="$TIKV_SERVICE_ACCOUNT" \
  --set-string encryption.kms.keyID="$KMS_KEY_ID"
```

The charts use `gcp_v2` and application default credentials from Workload Identity; no credential file is stored in the repository. TiKV data keys rotate every seven days by default, while the KMS key rotates every 30 days. Existing data is not retroactively encrypted immediately, and data paths must remain stable after encryption is enabled.

To rotate the master key, configure the new and previous KMS keys in the TiKV and PD configuration and perform a rolling restart. Keep the previous key available until all existing data has been re-encrypted.

## Setup Jump Host

To reach our private GKE control plane, we install tiny proxy which proxies our aliased kubctl and helm commands.

1. For all the SurrealDB jump host instances, deploy tiny proxy
```bash
$ gcloud compute instances list
# $INSTANCE = one of the compute instances listed
$ gcloud compute ssh $INSTANCE --tunnel-through-iap
$ sudo apt install tinyproxy
$ sudo vi /etc/tinyproxy/tinyproxy.conf
# Add localhost to the Allow section using ‘i’ and ‘:wq’ to exit
$ sudo service tinyproxy restart
$ exit
```

2. Get cluster credentials
```bash
$ gcloud container clusters list
$ gcloud container clusters get-credentials $CLUSTER \
  --location $LOCATION
```

3. Connect to the server in the background.
```bash
$ gcloud compute ssh $INSTANCE --tunnel-through-iap \
  --ssh-flag="-4 -L8888:localhost:8888 -N -q"
```

4. Open a new terminal and set up the environment.
```bash
# Prevents us from retyping the proxy variable on each subsequent line
$ alias k="HTTPS_PROXY=localhost:8888 kubectl"
$ alias h="HTTPS_PROXY=localhost:8888 helm"
# Verify cluster instance is correctly setup
$ k get ns
NAME                       STATUS   AGE
default                    Active   9m
gke-gmp-system             Active   8m
gke-managed-filestorecsi   Active   8m
gmp-public                 Active   8m
kube-node-lease            Active   8m
kube-public                Active   8m
kube-system                Active   8m
```

## Deploy TiDB Operator

1. Install CRDS
```bash
$ k apply -f https://github.com/pingcap/tidb-operator/releases/download/v2.0.0/tidb-operator.crds.yaml --server-side
```

2. Install the TiDB Operator from the GitHub release manifest instead of the Helm repo index:
```bash
$ k apply -f https://github.com/pingcap/tidb-operator/releases/download/v2.0.0/tidb-operator.yaml --server-side
```

3. Verify that the Pods are running (tip: add the `--watch` command to wait for changes.)
```bash
$ k get pods -n tidb-admin
NAME                          READY   STATUS    RESTARTS   AGE
tidb-operator-xxx             1/1     Running   0          3m30s
```

## Create TiKV Cluster

Now that we have the TiDB Operator running, it's time to define a TiKV Cluster and let the Operator do the rest.

1. Install the cluster chart from the example directory.
```bash
$ cd examples/basic/charts
$ h upgrade --install cluster ./cluster -n surreal-cluster --create-namespace
```

2. Install the PD group chart.
```bash
$ h upgrade --install pd-group ./pd-group -n surreal-cluster
$ k get pdgroup -n surreal-cluster
NAME   CLUSTER         DESIRED   READY   UPDATED   UPDATEREVISION     CURRENTREVISION    SYNCED   READY   AGE
pd     sdb-datastore   1         1       1         pd-pd-xxx          pd-pd-xxx          True     True    45s
```

3. Install the TiKV group chart.
```bash
$ h upgrade --install tikv-group ./tikv-group -n surreal-cluster
$ k get tikvgroup -n surreal-cluster
NAME   CLUSTER         DESIRED   READY   UPDATED   UPDATEREVISION     CURRENTREVISION    SYNCED   READY   AGE
tikv   sdb-datastore   1         1       1         tikv-tikv-xxx      tikv-tikv-xxx      True     True    68s
```

4. Check the cluster status and wait until it's ready (ie READY=`true`)
```bash
$ k get pods -n surreal-cluster
NAME              READY     STATUS    RESTARTS   AGE
pd-pd-xxx         1/1       Running   0          8m
tikv-tikv-xxx     1/1       Running   0          2m
```

## Deploy SurrealDB

Now that we have a TiDB cluster running, we can deploy SurrealDB using the Helm chart included in this repository under [examples/basic/charts/surrealdb](./examples/basic/charts/surrealdb). The chart is configured to connect to the TiKV PD service and exposes the SurrealDB service through the GKE NEG.

1. Get the TIKV PD service url to ensure the service is running. For example, the following interprets the url "tikv://pd-pd:2379":
```bash
$ k get svc/pd-pd -n surreal-cluster
NAME    TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)             AGE
pd-pd   ClusterIP   x.x.x.x        <none>        2379/TCP,2380/TCP   10m
```

2. Update the chart values to match your cluster and region. The example values file is [examples/basic/charts/surrealdb/values.yaml](./examples/basic/charts/surrealdb/values.yaml). Replace the placeholder in `cloud.google.com/neg` with your region or cluster-specific value (for the example, replace "\<REGION\>").

3. Install the chart from the repository checkout.
```bash
$ h repo add surrealdb https://helm.surrealdb.com
$ h repo update
$ h upgrade --install -f values.yaml surrealdb surrealdb/surrealdb -n surreal-cluster
```

4. Check the deployment status to check everything is ready.
```bash
$ k get deployment -n surreal-cluster
NAME        READY   UP-TO-DATE   AVAILABLE   AGE
surrealdb   1/1     1            1           9m29s
```

Notes when testing in a local [kind](https://kind.sigs.k8s.io/) cluster:

- Start a kind cluster using `kind create cluster --config examples/basic/kind-config.yaml` and delete with `kind delete cluster`
- Forward using `k port-forward svc/surrealdb 8000:8000 -n surreal-cluster`. Ensure the ports in [values.yaml](./examples/basic/charts/surrealdb/values.yaml) are 8000 instead of 8080.
- In a new shell, run `surreal sql -u root -p root -e http://localhost:8000`.

## Change Default Admin

It is recommended to change the root user of the deployment.

1. Exit the previously-opened jump host connection.

2. Open a connection to the frontend to connect to the admin portal in the VPC. Note these flags are different because routes are dynamic instead of targeting the localhost.
```bash
$ gcloud compute ssh $INSTANCE \
    --tunnel-through-iap \
    --ssh-flag="-ND 8888"
```

3. In another terminal, run the following to open a browser in the VPC network then visit surrealist.app to perform admin tasks. Feel free to modify the application with your computer’s application. If you followed the instructions, the root authentication is ‘root’ for both the username and password. The url domain is the https://DNS_NAME.

```bash
$ "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    --user-data-dir="$HOME/chrome-proxy-profile" \
    --proxy-server="socks5://localhost:8888"
```

## Clean up

Clean up is simple with Terraform. If deletion_protection is true, remember to set to false by first applying those terraform changes then proceeding with the following command.

```bash
$ terraform destroy
```

**NOTE** The VPC and Public DNS Zone are not removed as part of the terraform destruction, delete them manually.

# Definitions

### Internal Cross-Regional Load Balancer

A private DNS "geo-routes" to the nearest available frontend. Then, the cross-regional load balancer forwards traffic to a SurrealDB service in that region. "Internal" means the load balancer frontend endpoint is available on your VPC. To enable, set the following to true (default: true):

```ts
enable_internal_cross_regional_lb = true
```

### External Global Load Balancer

A global load balancer forwards internet traffic to the nearest available frontend from one of many Google's point of entry site. "External" means the frontend faces the internet and is available both the public internet and your private VPC through the public internet. To enable, set the following to true (default: false):

```ts
enable_external_global_lb = true
```

### GKE

Multiple regional Google Autopilot clusters are to create a SurrealDB cluster expandable globally. The service must be attached to an annotation named 'surrealdb-neg' to be noticed by the NEG and the load balancer.

### Jump Host

The jump host enables secure Identity Aware Proxy (IAP) tunnel access to both the VPC and the GKE control plane to perform kubectl and helm actions for deployments.

## Authors
[Dylan Vanmali](https://github.com/dvanmali)

## Contributing
See [Contribution Guidelines](./)

## License
[Apache 2.0](./LICENSE)

## Closing

This setup took many hours of development, so if you found this following repository helpful or if you used this in your deployment, please give us star :star:

Thanks! :heart: :heart: :heart: