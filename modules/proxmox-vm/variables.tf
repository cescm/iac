# =============================================================================
# Module: proxmox-vm — input variables
# Purpose: Defines every knob this module exposes. Required variables have no
#          default and MUST be supplied by the calling environment. Optional
#          variables carry sensible lab defaults that can be overridden.
# =============================================================================

variable "name" {
  type = string
}

variable "description" {
  type    = string
  default = ""
}

variable "tags" {
  type    = list(string)
  default = ["opentofu"]
}

# Proxmox cluster node name — must match `pve` node hostname exactly.
variable "node_name" {
  type = string
}

# Numeric VM ID — must be unique within the Proxmox node.
variable "vm_id" {
  type = number
}

variable "cpu_cores" {
  type    = number
  default = 2
}

# Dedicated RAM in MiB (4096 = 4 GB).
variable "memory" {
  type    = number
  default = 4096
}

# Minimum RAM in MiB when memory ballooning is active (the "floating" memory).
# Set to a value below var.memory to let the hypervisor reclaim unused guest
# RAM; null disables ballooning (guest keeps all dedicated memory).
variable "memory_min" {
  type    = number
  default = null
}

# Disk size in GB — thin-provisioned on supported storage backends.
variable "disk_size" {
  type    = number
  default = 40
}

# Proxmox storage target for the VM disk and EFI disk (e.g. "local-lvm", "HDD01").
variable "storage" {
  type    = string
  default = "local-lvm"
}

# Linux bridge name for the VM's network adapter.
variable "bridge" {
  type    = string
  default = "vmbr0"
}

# Guest OS family reported to Proxmox. Controls virtio driver selection and
# paravirtualisation hints: "l26" for Linux 2.6+, "win11" for Windows 11.
variable "os_type" {
  type    = string
  default = "l26"
}

# Enable a virtual TPM 2.0 state disk (required by Windows 11).
variable "tpm_enabled" {
  type    = bool
  default = false
}

# TPM specification version — "v2.0" is required by Windows 11.
variable "tpm_version" {
  type    = string
  default = "v2.0"
}

# NOTE: the legacy proxmox_virtual_environment_vm resource allows only ONE
# cdrom block, so a second ISO (e.g. virtio-win for Windows) cannot be declared
# here. Attach it out-of-band before first boot (see README section 17).

# VGA adapter type. "virtio" for Linux guests; Windows has no virtio-gpu driver
# during Setup, so use "std" to keep the installer display visible.
variable "vga_type" {
  type    = string
  default = "virtio"
}

# Boot device order. The first entry is tried first; Proxmox falls through to
# the next device when the current one is not bootable.
variable "boot_order" {
  type    = list(string)
  default = ["scsi0", "ide2"]
}

# ISO file_id in Proxmox datastore format (e.g. "HDD01:iso/omarchy-4.0.3.iso").
# Default null: cdrom block is declared but empty — no ISO attached, VM boots
# from disk only. Set this to attach an install ISO.
variable "iso" {
  type    = string
  default = null
}

# Enable QEMU guest agent. Disabled by default because the guest OS may not
# have qemu-guest-agent installed yet — Proxmox will time out on operations
# if the agent is expected but absent.
variable "qemu_agent" {
  type    = bool
  default = false
}

# Whether to start the VM immediately after creation.
variable "started" {
  type    = bool
  default = true
}

# Whether the VM auto-starts when the Proxmox node boots. false = manual
# start only, appropriate for lab VMs that may need post-install work.
variable "on_boot" {
  type    = bool
  default = false
}
