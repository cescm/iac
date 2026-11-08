# =============================================================================
# Module: proxmox-vm
# Purpose: Reusable module that provisions a single VM on a Proxmox VE node.
#          Called by environment layers (e.g. environments/homelab) that supply
#          concrete values for node, sizing, storage, and ISO. The module itself
#          is environment-agnostic — it defines *what* a VM looks like, not
#          *where* it lives.
# =============================================================================

resource "proxmox_virtual_environment_vm" "vm" {

  name        = var.name
  description = var.description
  tags        = var.tags

  node_name = var.node_name
  vm_id     = var.vm_id

  # --------------------------------------------------
  # System
  # --------------------------------------------------

  # q35: modern PC chipset emulation with PCIe support (required for UEFI/OVMF).
  machine = "q35"
  # OVMF: UEFI firmware — enables modern boot, Secure Boot-ready but not enforced here.
  bios = "ovmf"

  efi_disk {
    datastore_id = var.storage
    type         = "4m"
    # Secure Boot not needed for this lab — no shim/kernel signing required.
    pre_enrolled_keys = false
  }

  # l26 = Linux 2.6+ kernel type — tells Proxmox the guest OS family for
  # optimised virtio driver selection and paravirtualisation hints. Windows
  # guests use "win11" so QEMU applies the right paravirtualisation profile.
  operating_system {
    type = var.os_type
  }

  # Virtual TPM 2.0 state disk — required by Windows 11. Rendered only when
  # tpm_enabled is true; Linux guests leave it out entirely.
  dynamic "tpm_state" {
    for_each = var.tpm_enabled ? [1] : []
    content {
      datastore_id = var.storage
      version      = var.tpm_version
    }
  }

  # --------------------------------------------------
  # CPU
  # --------------------------------------------------

  cpu {
    cores   = var.cpu_cores
    sockets = 1
    # "host": passes through the physical CPU flags to the guest — best
    # performance for a lab where host and guest share the same architecture.
    type = "host"
  }

  # --------------------------------------------------
  # Memory
  # --------------------------------------------------

  memory {
    dedicated = var.memory
    # floating = minimum balloon memory. null disables ballooning entirely.
    floating = var.memory_min
  }

  # --------------------------------------------------
  # Disk
  # --------------------------------------------------

  # virtio-scsi-single: paravirtual SCSI controller — better throughput than
  # the emulated LSI Logic and required for discard (TRIM) support.
  scsi_hardware = "virtio-scsi-single"

  disk {
    datastore_id = var.storage
    interface    = "scsi0"

    size = var.disk_size
    # discard = "on": enables TRIM/DISCARD on the block device — keeps the
    # underlying thin-provisioned storage efficient as files are deleted.
    discard = "on"
    # iothread: dedicates a QEMU I/O thread to this disk — reduces latency
    # by preventing I/O from blocking the main VM vCPU thread.
    iothread = true
  }

  # --------------------------------------------------
  # Network
  # --------------------------------------------------

  network_device {
    bridge = var.bridge
    model  = "virtio"
  }

  # --------------------------------------------------
  # Install media
  # --------------------------------------------------

  # Install ISO attached as a cdrom on the IDE bus ONLY while var.iso is set
  # (Level 1 install media). Once the ISO has been removed from the VM
  # (documented post-install step), the cdrom block disappears from the config
  # — aligning desired state with the real VM instead of re-attaching media.
  dynamic "cdrom" {
    for_each = var.iso != null ? [1] : []
    content {
      file_id   = var.iso
      interface = "ide2"
    }
  }

  # Secondary install media — NOT supported: the provider allows only one
  # cdrom block. A virtio-win ISO must be attached out-of-band (README §17).

  # --------------------------------------------------
  # Display
  # --------------------------------------------------

  vga {
    type = var.vga_type
  }

  # --------------------------------------------------
  # Boot
  # --------------------------------------------------

  # Boot order: scsi0 first (disk — boots installed OS after install),
  # ide2 second (ISO cdrom — used during initial installation).
  boot_order = var.boot_order

  # QEMU guest agent disabled: Omarchy may not ship qemu-guest-agent on the
  # live ISO. Enabling it before the agent is installed causes Proxmox to
  # time out on every operation. Re-enable once the guest OS has the agent.
  agent {
    enabled = var.qemu_agent
  }

  started = var.started
  # on_boot = false intentionally: Level 1 lab VM should not auto-start on
  # Proxmox host reboot — it may need manual intervention after install.
  on_boot = var.on_boot
  # Gracefully shut down the guest before destroying the resource in Proxmox.
  stop_on_destroy = true

  lifecycle {
    # Safety net: prevents `tofu destroy` from deleting the VM accidentally.
    # To actually destroy, remove this block or use -target.
    prevent_destroy = true
  }
}
