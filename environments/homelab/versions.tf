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
}
