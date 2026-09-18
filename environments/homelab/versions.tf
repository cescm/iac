# =============================================================================
# Environment: homelab — version constraints
# Purpose: Pins the minimum OpenTofu/Terraform version and the exact provider
#          version for this environment. Tight pinning (= 0.111.1) ensures
#          reproducible plans — every team member and CI run uses the same
#          provider binary. Bump intentionally after testing a new release.
# =============================================================================

terraform {
  # >= 1.6.0: first version with stable OpenTofu support and provider
  # forwarding — no reason to support anything older in a learning lab.
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      # Exact pin: avoids surprise breaking changes from minor/patch bumps.
      # The bpg/proxmox provider moves fast; pin until you can test upgrades.
      version = "= 0.111.1"
    }
  }

  # N5 — Remote state backend (SeaweedFS S3, LXC 200 minio/seaweedfs).
  # State no longer lives on the Proxmox host: it is stored in the
  # homelab-tfstate bucket on 192.168.8.101:9000. Credentials come from
  # AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY env vars — never commit them.
  backend "s3" {
    bucket                      = "homelab-tfstate"
    key                         = "homelab/terraform.tfstate"
    region                      = "us-east-1"
    endpoint                    = "http://192.168.8.101:9000"
    use_path_style              = true
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
  }
}
