# =============================================================================
# Environment: homelab — input variables
# Purpose: Declares variables consumed by provider.tf. These are environment-
#          specific settings (endpoint, TLS policy) that differ between homelab,
#          staging, and production. Values come from terraform.tfvars or CLI
#          flags — NOT from this file.
# =============================================================================

variable "proxmox_endpoint" {
  description = "Proxmox VE API endpoint (e.g. https://192.168.8.2:8006/)"
  type        = string
}

variable "proxmox_insecure" {
  description = "Skip TLS verification for the Proxmox API (self-signed cert)."
  type        = bool
  default     = true
}