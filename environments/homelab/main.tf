# =============================================================================
# Environment: homelab — main resource definitions
# Purpose: Instantiates the proxmox-vm module with concrete values that match
#          the real Proxmox infrastructure. This is the bridge between the
#          abstract module and the physical homelab.
# =============================================================================
#
# This file declares the machines this lab runs: the "what" (which VMs), the
# "where" (node, storage, bridge), and the "how big" (cores, RAM, disk). Each
# VM definition below is handed to the shared proxmox-vm module, which knows
# how to build one generic Proxmox VM.

# -----------------------------------------------------------------------------
# Multi-VM pattern (N4): each key in local.virtual_machines is exactly one VM.
# The module is called once with for_each = local.virtual_machines, so adding a
# new VM means adding a single map entry here — the module stays untouched.
# -----------------------------------------------------------------------------
locals {
  virtual_machines = {
    # omarchy — first lab VM (VM 100). The install ISO was removed after
    # installation, so the iso key is intentionally absent (see below).
    omarchy = {
      vm_id       = 100
      name        = "omarchy-lab"
      description = "Omarchy workstation"
      tags        = ["opentofu", "omarchy", "lab"]
      cpu_cores   = 4
      memory      = 8192
      disk_size   = 30
      # iso intentionally omitted: the install media was removed from VM 100
      # after installation (documented post-install step). The module only
      # attaches a cdrom when iso is set.
    }

    # ubuntu — second lab VM (VM 101). Install media is still attached (ide2)
    # so the installer can run on its first boot; the iso key drives that.
    ubuntu = {
      vm_id       = 101
      name        = "ubuntu-lab"
      description = "Ubuntu workstation"
      tags        = ["opentofu", "ubuntu", "lab"]
      cpu_cores   = 4
      memory      = 8192
      disk_size   = 20
      iso         = "HDD01:iso/ubuntu-26.04.1-desktop-amd64.iso"
    }

    # windows11 — third lab VM (VM 102). Windows 11 requires UEFI (OVMF), a
    # virtual TPM 2.0, and the "win11" guest type. Ballooning is capped at
    # 2048 MiB so the host can reclaim RAM when the guest idles. VGA is "std"
    # because Windows has no virtio-gpu driver during Setup — with "virtio"
    # the installer screen would stay black.
    windows11 = {
      vm_id       = 102
      name        = "windows11-lab"
      description = "Windows 11 workstation"
      tags        = ["opentofu", "windows", "lab"]
      cpu_cores   = 4
      memory      = 4096
      memory_min  = 2048
      disk_size   = 40
      os_type     = "win11"
      tpm_enabled = true
      vga_type    = "std"
      iso         = "HDD01:iso/Win11-Pro-Lite.iso"
      # Boot the installer CD first; the empty disk is not bootable yet.
      boot_order = ["ide2", "scsi0"]
      # The virtio-win driver ISO cannot be a second cdrom (provider limit).
      # Attach it after apply, before first boot:
      #   qm set 102 -ide0 HDD01:iso/virtio-win.iso,media=cdrom
    }
  }
}

# One module instance per entry in local.virtual_machines; each.value pulls
# that VM's sizing/identity values into the shared, environment-agnostic module.
module "vm" {
  for_each    = local.virtual_machines
  source      = "../../modules/proxmox-vm" #where the template is
  name        = each.value.name
  description = each.value.description
  tags        = each.value.tags
  vm_id       = each.value.vm_id
  node_name   = "trastero01"
  cpu_cores   = each.value.cpu_cores
  memory      = each.value.memory
  memory_min  = try(each.value.memory_min, null)
  disk_size   = each.value.disk_size
  # Windows-specific overrides; Linux entries fall back to the module defaults.
  os_type     = try(each.value.os_type, "l26")
  tpm_enabled = try(each.value.tpm_enabled, false)
  vga_type    = try(each.value.vga_type, "virtio")
  boot_order  = try(each.value.boot_order, ["scsi0", "ide2"])
  # try(each.value.iso, null): entries WITHOUT an iso key (e.g. omarchy)
  # evaluate to null, so the module's dynamic "cdrom" block does not render.
  # This keeps the pattern safe for VMs that have no install media attached.
  iso     = try(each.value.iso, null)
  storage = "local-lvm"
  bridge  = "vmbr0"
  started = true
}