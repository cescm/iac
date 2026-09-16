# =============================================================================
# Environment: homelab — Proxmox provider configuration
# Purpose: Configures the bpg/proxmox provider to talk to a single Proxmox VE
#          API endpoint. Authentication (API token + username) is supplied via
#          environment variables PROXMOX_VE_API_TOKEN and PROXMOX_VE_USERNAME —
#          never committed to source control.
# =============================================================================

provider "proxmox" {
  endpoint = var.proxmox_endpoint
  # Proxmox VE uses a self-signed TLS certificate by default — insecure = true
  # disables certificate verification. In production, use a proper CA cert and
  # set this to false.
  insecure = var.proxmox_insecure
}
