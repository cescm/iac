# =============================================================================
# Environment: homelab — main resource definitions
# Purpose: Instantiates the proxmox-vm module with concrete values that match
#          the real Proxmox infrastructure. This is the bridge between the
#          abstract module and the physical homelab.
# =============================================================================

module "omarchy" {

  source = "../../modules/proxmox-vm"

  name        = "omarchy-lab"
  description = "Omarchy workstation"
  tags        = ["opentofu", "omarchy", "lab"]

  # Real Proxmox node name — must match `pve` node hostname in your cluster.
  node_name = "trastero01"
  # VM ID 100: matches the existing manually-created VM in Proxmox so the
  # state can be imported without creating a duplicate.
  vm_id     = 100

  # 4 cores, 8 GB RAM — sized for an interactive desktop/workstation.
  cpu_cores = 4
  memory    = 8192

  # 30 GB thin-provisioned disk. The plan may show growth to 60 GB in a
  # future iteration — 30 GB matches the current real VM.
  disk_size = 30
  storage   = "local-lvm"

  bridge = "vmbr0"

  # iso intentionally omitted: the install media was removed from the VM
  # after installation (documented post-install step). The module only
  # attaches a cdrom when iso is set; the ISO itself still lives on HDD01.

  started = true
}
