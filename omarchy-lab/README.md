# Omarchy Lab

Provisions an [Omarchy](https://omarchy.org/) virtual machine on Proxmox using OpenTofu/Terraform. This is the first lab in a multi-phase DevOps portfolio.

## What it creates

A single VM on Proxmox with the following specs:

| Resource | Value |
|----------|-------|
| Machine type | q35 |
| BIOS | OVMF (UEFI) |
| CPU | 4 cores, host passthrough |
| RAM | 8 GB dedicated |
| Disk | 30 GB SCSI (discard, iothread) |
| Network | VirtIO on `vmbr0` |
| Boot order | `scsi0`, `ide2` (cdrom) |
| QEMU Guest Agent | Disabled |

## Prerequisites

1. **Proxmox VE** running on the target node (tested with Proxmox 9.x)
2. **Omarchy ISO** uploaded to the Proxmox datastore (default: `local:iso/omarchy.iso`)
3. **Proxmox API token** with sufficient privileges to create VMs
   - Recommended: create a dedicated user (e.g., `opentofu@pve`) with `PVEVMAdmin` role on `/vms`
   - Generate an API token under **Datacenter → Permissions → API Tokens**
4. **OpenTofu** (or Terraform) >= 1.6.0 installed on the machine running this configuration

## Authentication

Set the following environment variables before running OpenTofu/Terraform:

```bash
export PROXMOX_VE_ENDPOINT="https://192.168.8.2:8006/"
export PROXMOX_VE_API_TOKEN="opentofu@pve!tokenid=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export PROXMOX_VE_USERNAME="opentofu@pve"
```

> **Security note**: The API token value is not committed to this repository. Use environment variables or a secrets manager. The `.gitignore` excludes `*.tfvars` except `terraform.tfvars` (which contains no secrets).

## Usage

```bash
# Initialize the provider
tofu init

# Preview the plan
tofu plan

# Apply (creates the VM)
tofu apply
```

After the VM is created, Open the Proxmox console to complete the Omarchy installation interactively.

## Post-install: boot order fix

After the ISO installation completes, the VM will attempt to boot from the cdrom again (since `ide2` is still in the boot order). This is **expected behavior** at this stage (Level 1 — manual install).

To fix the boot order after installation:

1. Shut down the VM from the Proxmox console
2. In the Proxmox UI, go to **VM → Options → Boot Order**
3. Disable `ide2` or remove it from the boot sequence
4. Start the VM

A future iteration (Level 2+) will handle this automatically with cloud-init/cidata.

## Why `on_boot = false`

The VM has `on_boot = false` intentionally. At this stage (Level 1), the VM is manually installed and not yet production-ready. This prevents the VM from automatically starting on Proxmox host reboot, which is appropriate for a lab environment where the VM may need post-install configuration before it can boot reliably.

## Why `terraform` instead of `opentofu` in `versions.tf`

The `versions.tf` file uses the `terraform {}` block rather than an `opentofu {}` block. This is **intentional**:

- **HCL compatibility**: OpenTofu is fully compatible with Terraform's HCL syntax and the `terraform {}` block. There is no functional difference at runtime.
- **Provider ecosystem**: The `bpg/proxmox` provider (pinned at `0.111.1`) is published to the Terraform Registry and consumed identically by both tools.
- **Portability**: Using the `terraform {}` block means this configuration works out-of-the-box with both `terraform` and `tofu` commands. If you later switch to `opentofu`, just use `tofu init` — no code changes needed.
- **Documentation alignment**: Most Proxmox provider documentation and community examples use the `terraform {}` block, so this matches the reference material.

When switching to OpenTofu is needed (e.g., to use state encryption or other OpenTofu-specific features), the migration is a single command: `tofu init -migrate-state`.

## VM ID

The default `vm_id` is `100` (set in `terraform.tfvars`). This aligns with the Proxmox convention of using low numbers for manually/importantly managed VMs. The `variables.tf` default also matches at `100`.

## Files

| File | Purpose |
|------|---------|
| `versions.tf` | Provider version constraints |
| `provider.tf` | Proxmox provider configuration |
| `variables.tf` | Input variable declarations |
| `terraform.tfvars` | Variable values for this environment |
| `main.tf` | VM resource definition |
