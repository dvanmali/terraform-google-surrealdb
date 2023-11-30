# SurrealDB Terraform Deployment

The deployment deploys all of following components: an internal cross-regional load balancer for enabling internal access for clients, a Google-Managed SSL certificate for secure connectivity, a jump-host VM to access the GKE control plane for each cluster using Google’s IAP, and NAT for cluster internet connectivity.

## DNS

We must create the Public DNS separately (not part of our Terraform) for the following reasons:

- Provides us time to add our NS records to our domain name records before carrying out any certificate DNS authorizations
- Prevents us from having a hanging subdomain DNS attack if we accidently leave this record on our domain server and we perform a Terraform destroy command.

## Cross-Regional Load Balancer

A private DNS "geo-routes" to the nearest available frontend. Then, the cross regional load balancer forwards traffic to a SurrealDB service in that region.

## GKE

Multiple regional Google Autopilot clusters are to create a SurrealDB cluster expandable globally. The service must be attached to an annotation named 'surrealdb-neg' to be noticed by the NEG and the load balancer.

## Jump Host

The jump host enables secure Identity Aware Proxy (IAP) tunnel access to both the VPC and the GKE control plane to perform kubectl and helm actions for deployments.

## Authors
Dylan Vanmali

## License
[Apache 2.0](./LICENSE)