# SurrealDB Terraform Deployment

The deployment deploys all of following components: an internal cross-regional load balancer for enabling internal access for clients, a Google-Managed SSL certificate for secure connectivity, a jump-host VM to access the GKE control plane for each cluster using Google’s IAP, and NAT for cluster internet connectivity.

# Deployment Instructions

## DNS

We must create the Public DNS separately (not part of our Terraform) for the following reasons:

- Provides us time to add our NS records to our domain name records before carrying out any certificate DNS authorizations
- Prevents us from having a hanging subdomain DNS attack if we accidently leave this record on our domain server and we perform a Terraform destroy command.

```bash
$ export DOMAIN="db.example.com" # Replace with your domain
$ gcloud dns managed-zones create surrealdb \
	--description="Public DNS zone for generating DNS certificates" \
	--dns-name=$DOMAIN \
	--visibility="public" \
	--dnssec-state="off"
```

Add the generated NS records for that subdomain to your domain server (where your domains are hosted). The host name for the record must be the full path name to the name server. For example, the above example it will be "db.example.com".

```bash
$ gcloud dns managed-zones describe surrealdb --format json | jq ".nameServers[]"
```

## VPC

If you don’t already have a VPC set up, run the following to create a VPC. Feel free to create the VPC in IPv4 auto mode or IPv6 custom mode, both work with this setup. We recommend the IPv6 for future extensibility.

```bash
# IPv4 only auto-mode
$ gcloud compute networks create VPC_NAME --subnet-mode=auto
# OR IPv4 and IPv6 dual-stack custom-mode
$ gcloud compute networks create VPC_NAME --subnet-mode=custom --enable-ula-internal-ipv6
```

## Basic Setup

See [examples](./examples/) for example configurations. The following follows the [basic setup](./examples/basic/).

1. Copy the [main.tf](./examples/basic/main.tf) to your own `main.tf` file. Remember, to replace the local values with your own variable values. Specifically, replace "\<PROJECT_ID\>", "\<VPC_NAME\>" and "\<REGION\>".

2. Plan the deployment to check for errors in setup before applying. The deployment deploys all of following components: an internal cross-regional load balancer for enabling internal access for clients, a Google-Managed SSL certificate for secure connectivity, a jump-host VM to access the GKE control plane for each cluster using Google’s IAP, and NAT for cluster internet connectivity.
```bash
$ terraform plan
```

3. When satisfied, apply the values.
```bash
$ terraform apply
```

## Deploy SurrealDB

1. For all the SurrealDB jump host instances, deploy tiny proxy
```bash
$ gcloud compute instances list
# INSTANCE = one of the compute instances listed
$ gcloud compute ssh INSTANCE --tunnel-through-iap
$ sudo apt install tinyproxy
$ sudo vi /etc/tinyproxy/tinyproxy.conf
# Add localhost to the Allow section using ‘i’ and ‘:wq’ to exit
$ sudo service tinyproxy restart
$ exit
```

2. Get cluster credentials
```bash
$ gcloud container clusters list
$ gcloud container clusters get-credentials CLUSTER \
  --location LOCATION
```

3. Connect to the server in the background.
```bash
$ gcloud compute ssh $INSTANCE \
  --tunnel-through-iap \
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

## Deploy TiDB

1. Install CRDS
```bash
$ k create -f https://raw.githubusercontent.com/pingcap/tidb-operator/v1.5.1/manifests/crd.yaml
```

2. Install TiDB Operator Helm chart:
```bash
$ h repo add pingcap https://charts.pingcap.org
$ h repo update
$ h install \
	-n tidb-operator \
	--create-namespace \
	tidb-operator \
	pingcap/tidb-operator \
	--version v1.5.1
```

3. Verify that the Pods are running
```bash
$ k get pods -n tidb-operator
NAME                          READY   STATUS    RESTARTS   AGE
tidb-controller-manager-xxx   1/1     Running   0          3m30s
tidb-scheduler-xxx            2/2     Running   0          3m30s
```

## Create TiDB Cluster

Now that we have the TiDB Operator running, it's time to define a TiDB Cluster and let the Operator do the rest.

1. Copy [tikv-cluster.yaml](./examples/basic/k8s/tikv-cluster.yaml) locally.

2. Create the TiDB Cluster
```bash
$ k create ns surreal-cluster
$ k apply -f tikv-cluster.yaml -n surreal-cluster
```

3. Check the cluster status and wait until it's ready (ie READY=`true`)
```bash
$ k get tidbcluster -n surreal-cluster
NAME             READY   PD                  STORAGE   READY   DESIRE   
sdb-datastore    True    pingcap/pd:v7.1.1   10Gi      3       3        

TIKV                  STORAGE   READY   DESIRE   
pingcap/tikv:v7.1.1   10Gi      3       3        

TIDB                  READY   DESIRE   AGE
pingcap/tidb:v7.1.1           0        9m
```

## Deploy SurrealDB

Now that we have a TiDB cluster running, we can deploy SurrealDB using the official Helm chart
The deploy will use the latest SurrealDB Docker image and make it accessible on internet

1. Get the TIKV PD service url to ensure the service is running.
```bash
$ k get svc/sdb-datastore-pd -n surreal-cluster
NAME               TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
sdb-datastore-pd   ClusterIP   x.x.x.x        <none>        2379/TCP   10m
```

2. Copy [values-surreal.yaml](./examples/basic/k8s/values-surreal.yaml) locally.

3. Upload the installation
```bash
$ h repo add surrealdb https://helm.surrealdb.com
$ h repo update
$ h install -f values-surreal.yaml surrealdb surrealdb/surrealdb -n surreal-cluster
```

## Change Default Admin

It is recommended to change the root user of the deployment.

1. Exit the previously-opened jump host connection.

2. Open a connection to the frontend to connect to the admin portal in the VPC. Note these flags are different because routes are dynamic instead of targeting the localhost.
```bash
$ gcloud compute ssh INSTANCE \
    --tunnel-through-iap \
    --project=rev-env-01 \
    --zone=us-central1-c \
    --ssh-flag="-ND 8888"
```

3. In another terminal, run the following to open a browser in the VPC network then visit surrealist.app to perform admin tasks. Feel free to modify the application with your computer’s application. If you followed the instructions, the root authentication is ‘root’ for both the username and password. The url domain is the https://DNS_NAME.

```bash
$ “/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
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

### Cross-Regional Load Balancer

A private DNS "geo-routes" to the nearest available frontend. Then, the cross regional load balancer forwards traffic to a SurrealDB service in that region.

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