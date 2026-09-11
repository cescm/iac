resource "proxmox_virtual_environment_vm" "omarchy" {

  name        = var.vm_name
  description = "Omarchy Lab - managed by OpenTofu"
  tags        = ["opentofu", "omarchy", "lab"]

  node_name = var.proxmox_node
  vm_id     = var.vm_id

  # --------------------------------------------------
  # System
  # --------------------------------------------------

  machine = "q35"
  bios    = "ovmf"

  efi_disk {
    datastore_id      = var.vm_storage
    type              = "4m"
    pre_enrolled_keys = false
  }

  operating_system {
    type = "l26"
  }

  # --------------------------------------------------
  # CPU
  # --------------------------------------------------

  cpu {
    cores   = 4
    sockets = 1
    type    = "host"
  }

  # --------------------------------------------------
  # Memory
  # --------------------------------------------------

  memory {
    dedicated = 8192
  }

  # --------------------------------------------------
  # Disk
  # --------------------------------------------------

  scsi_hardware = "virtio-scsi-single"

  disk {
    datastore_id = var.vm_storage
    interface    = "scsi0"

    size     = 30
    discard  = "on"
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
  # Omarchy ISO
  # --------------------------------------------------

  cdrom {
    file_id   = var.omarchy_iso
    interface = "ide2"
  }

  # --------------------------------------------------
  # Display
  # --------------------------------------------------

  vga {
    type = "virtio"
  }

  # --------------------------------------------------
  # Boot
  # --------------------------------------------------

  boot_order = [
    "scsi0",
    "ide2"
  ]

  # Omarchy may not have qemu-guest-agent available or configured at this stage.
  agent {
    enabled = false
  }

  started         = true
  on_boot         = false # Intentional: see README for rationale (Level 1 — manual install)
  stop_on_destroy = true

  lifecycle {
    prevent_destroy = true
  }
}
