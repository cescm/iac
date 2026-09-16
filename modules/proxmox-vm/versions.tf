# =============================================================================
# Module: proxmox-vm — provider source declaration
# Purpose: Declares the *source* of the proxmox provider so OpenTofu/Terraform
#          downloads the correct binary. The version is NOT pinned here — that
#          responsibility belongs to the environment layer (versions.tf) which
#          can freeze a specific version per deployment.
# =============================================================================

terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}