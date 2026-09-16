# =============================================================================
# Environment: homelab — main resource definitions
# Purpose: Instantiates the proxmox-vm module with concrete values that match
#          the real Proxmox infrastructure. This is the bridge between the
#          abstract module and the physical homelab.
# =============================================================================

locals {
  virtual_machines = {
    omarchy = {
      vm_id = 100
      name = "omarchy-lab"
      description = "Omarchy workstation"
      tags = ["opentofu", "omarchy", "lab"]
      cpu_cores = 4
      memory = 8192
      disk_size = 30
      iso = "HDD01:iso/omarchy-4.0.3.iso"
    }

    ubuntu = {
      vm_id = 101
      name = "ubuntu-lab"
      description = "Ubuntu workstation"
      tags = ["opentofu", "ubuntu", "lab"]
      cpu_cores = 4
      memory = 8192
      disk_size = 20
      iso = "HDD01:iso/ubuntu-26.04.1-desktop-amd64.iso"
    }
  }
}

module "vm" {
  for_each = local.virtual_machines
  source = "../../modules/proxmox-vm" #where the template is
  name = each.value.name
  description = each.value.description
  tags = each.value.tags
  vm_id = each.value.vm_id
  node_name = "trastero01"
  cpu_cores = each.value.cpu_cores
  memory = each.value.memory
  disk_size = each.value.disk_size
  iso = each.value.iso
  storage = "local-lvm" 
  bridge = "vmbr0"
  started = true
}