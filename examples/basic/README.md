# Basic

A basic setup of SurrealDB which contains the minimum resources to set up a SurrealDB cluster behind an Internal Cross-Regional Load Balancer. To ensure the example works without error, ensure you have Project Owner IAM permissions.

Encryption at rest is disabled by default so the bundled Kind workflow works without Google Cloud KMS. For a GKE deployment, enable `encryption_at_rest` for the cluster in Terraform, apply Terraform, and follow the chart commands in the main [deployment guide](../../README.md#encryption-at-rest).