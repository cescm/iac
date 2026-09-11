variable "proxmox_endpoint" {
  type = string
}

variable "proxmox_insecure" {
  type    = bool
  default = true
}

variable "proxmox_node" {
  type = string
}

variable "vm_id" {
  type    = number
  default = 100
}

variable "vm_name" {
  type    = string
  default = "omarchy-lab"
}

variable "vm_storage" {
  type    = string
  default = "local-lvm"
}

variable "bridge" {
  type    = string
  default = "vmbr0"
}

variable "omarchy_iso" {
  type    = string
  default = "local:iso/omarchy.iso"
}
