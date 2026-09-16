# =============================================================================
# Module: proxmox-vm — outputs
# Purpose: Expose key attributes of the created VM so calling environments can
#          reference them (e.g. for DNS registration, monitoring, or scripting).
# =============================================================================

# The numeric VM ID assigned by Proxmox — useful for Proxmox API calls or CLI.
output "vm_id" {
  value = proxmox_virtual_environment_vm.vm.vm_id
}

# The VM display name as set in Proxmox — handy for logging and inventory.
output "vm_name" {
  value = proxmox_virtual_environment_vm.vm.name
}
