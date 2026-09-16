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
