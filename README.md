# SurrealDB Terraform Deployment

[![Terraform Registry](https://img.shields.io/badge/Terraform%20Registry-844FBA?logo=terraform&logoColor=white)](https://registry.terraform.io/modules/dvanmali/surrealdb/google)

A Google Kubernetes Engine Terraform deployment served on a HTTPS endpoint.

**Configuration Options:**
- Single cluster or multi cluster
- Traditional GKE or GKE Autopilot per cluster
- Internal and/or External Load Balancing
- IAP member security rules

# GCP Setup

The following instructions are required for all [example](#examples) terraform deployments:

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

# Examples

Each example is configured for a different type of setup.

- [Basic Deployment](./examples/basic/) - A one-replica Autopilot setup
- [Production Deployment](./examples/prod-auto/) - Minimum production Autopilot setup
- [Kind Local Deployment](./examples/kind/) - Local kind (non-terraform) cluster deployment 

Follow the specific example's instructions at this point. In general, terraform could be applied using the following basic commands.

1. Initialize your terraform state.
```bash
terraform init
```

2. Apply with your configurations.
```bash
terraform apply -var-file prod.tfvars
```

## Clean up

Clean up is simple with Terraform. If deletion_protection is true, remember to set to false by first applying those terraform changes then proceeding with the following command.

```bash
$ terraform destroy
```

**NOTE** The VPC and Public DNS Zone are not removed as part of the terraform destruction, delete them manually.

# Configuration

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

The private GKE control plane supports two access methods: DNS access (default) and via a VM connected in the VPC, such as through Cloud VPN or Interconnect.

The DNS is the new recommended approach as the control plane is still private and access is controlled through IAM policies (eg `container.clusters.connect`).

```bash
gcloud container clusters list
# export CLUSTER=surrealdb-* listed (associated to location)
gcloud container clusters get-credentials $CLUSTER \
	--location $LOCATION \
	--dns-endpoint
kubectl get ns
```

IP endpoint access is disabled by default. Set `enable_ip_access = true` to enable it.

To use an Identity-Aware Proxy (IAP) tunnel instead, set `enable_jump_host = true`, then connect to the jump host and proxy kubectl and helm traffic through it. The jump host is a spot virtual machine in the same region and is disabled by default:

```hcl
enable_jump_host = true
```

1. Deploy Tinyproxy on the jump host:

```bash
gcloud compute instances list
# export INSTANCE=surrealdb-* listed (associated to region)
gcloud compute ssh $INSTANCE --tunnel-through-iap
sudo apt install tinyproxy
sudo vi /etc/tinyproxy/tinyproxy.conf
# Add localhost to the Allow section, then save and exit.
sudo service tinyproxy restart
exit
```

2. Get cluster credentials:

```bash
gcloud container clusters list
# export CLUSTER=surrealdb-* listed (associated to location)
gcloud container clusters get-credentials $CLUSTER \
	--location $LOCATION
```

3. Start the local tunnel:

```bash
gcloud compute ssh $INSTANCE --tunnel-through-iap \
	--ssh-flag="-4 -L8888:localhost:8888 -N -q"
```

4. In a new terminal, configure kubectl and Helm to use the proxy:

```bash
alias k="HTTPS_PROXY=localhost:8888 kubectl"
alias h="HTTPS_PROXY=localhost:8888 helm"
k get ns
```

## Authors
[Dylan Vanmali](https://github.com/dvanmali)

## Contributing
See [Contribution Guidelines](./CONTRIBUTING.md)

## License
[Apache 2.0](./LICENSE)

## Closing

This setup took many hours of development, so if you found this following repository helpful or if you used this in your deployment, please feel free to donate or give a star :star:

<a href="https://ko-fi.com/dvanmali" target="_blank">
  <img src="https://img.shields.io/badge/Ko--fi-FF5E5B?logo=ko-fi&logoColor=white" alt="Support me on Ko-fi" height="35" />
</a>

Thanks! :heart: :heart: :heart: