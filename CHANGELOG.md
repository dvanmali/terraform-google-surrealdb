# Changelog

All notable changes to this project are documented here.

## [Unreleased]

### Changed

- Restricted health-check and backend firewall rules to each cluster's service account where one is configured.
- Consolidated each load balancer's backend service into a single resource aggregating all cluster NEGs, fixing name collisions and unreliable backend selection across multiple clusters.
- Derived firewall `source_ranges` for backend traffic from each cluster's `proxy_subnet_ip_cidr` instead of a hard-coded CIDR.
- Scoped each cluster's subnet name with its key to prevent collisions when multiple clusters share a region.
- Wired `max_rate_per_endpoint` through to both load balancer modules.
- Removed the unused `vpc_auto_create_subnetworks` reference.

## [1.2.3] - 2026-09-08

### Fixed

- Added missing variable wiring for the example and GKE cluster configuration.
- Expanded `.gitignore` coverage for generated Terraform and local files.
- Bumped default jump host operating system image to debian-trixie (v13).

## [1.2.2] - 2025-02-03

### Added

- Added a configurable daily GKE maintenance window, defaulting to midnight.

### Changed

- Updated the default jump host operating system image.

## [1.2.1] - 2025-01-07

### Added

- Added the `enable_backup` option for enabling the GKE Backup for GKE API on individual clusters.

### Changed

- Updated the default jump host operating system image.

## [1.2.0] - 2024-08-27

### Breaking Changes

- Enabling Autopilot on the cluster is no longer the default. To keep the previous behavior, set `enable_autopilot = true` on each created cluster.

### Changed

- Updated the Terraform version constraint in the basic example.
- Updated the default jump host operating system image.

## [1.1.1] - 2024-07-01

### Fixed

- Updated the default jump host operating system image to address an OpenSSH vulnerability notice.
- Updated the example documentation and configuration to match the new image.

## [1.1.0] - 2024-01-18

### Added

- Added an optional external global load balancer for internet-facing access.
- Added configuration for public and private DNS zones and load balancer enablement.

### Changed

- Refactored the internal cross-regional load balancer into a configurable module.

## [1.0.0] - 2023-12-08

### Added

- Initial release of the SurrealDB Google Cloud Terraform module.
- Added GKE Autopilot cluster deployment with NAT and IAP-accessible jump hosts.
- Added an internal cross-regional load balancer for private client access.
- Added service account configuration and a basic deployment example.
- Added documentation for DNS, VPC, IAM, TiDB, and SurrealDB setup.

[Unreleased]: https://github.com/dvanmali/terraform-google-surrealdb/compare/v1.2.3...HEAD
[1.2.3]: https://github.com/dvanmali/terraform-google-surrealdb/releases/tag/v1.2.3
[1.2.2]: https://github.com/dvanmali/terraform-google-surrealdb/releases/tag/v1.2.2
[1.2.1]: https://github.com/dvanmali/terraform-google-surrealdb/releases/tag/v1.2.1
[1.2.0]: https://github.com/dvanmali/terraform-google-surrealdb/releases/tag/v1.2.0
[1.1.1]: https://github.com/dvanmali/terraform-google-surrealdb/releases/tag/v1.1.1
[1.1.0]: https://github.com/dvanmali/terraform-google-surrealdb/releases/tag/v1.1.0
[1.0.0]: https://github.com/dvanmali/terraform-google-surrealdb/releases/tag/v1.0.0