# homelab environment

Concrete OpenTofu values for THIS homelab (three VMs) plus the SeaweedFS remote-state backend. General concepts, the full lifecycle, and troubleshooting live in the [root README](../../README.md) — this file is only the operator quickstart for this directory.

## Quick path

1. Export credentials (details in [root README §5](../../README.md#5-authentication)):

   ```bash
   export PROXMOX_VE_API_TOKEN='opentofu@pve!tofu=<secret>'
   export PROXMOX_VE_USERNAME="opentofu@pve"
   export AWS_ACCESS_KEY_ID="<key>"
   export AWS_SECRET_ACCESS_KEY="<secret>"
   ```

   Token format is `USER@REALM!TOKENID=SECRET` — all three parts are required.

2. `proxmox_endpoint` is read from the local, **untracked** `terraform.tfvars`; or pass it inline:

   ```bash
   tofu plan -var="proxmox_endpoint=https://192.168.8.2:8006/"
   ```

3. Initialize and plan:

   ```bash
   tofu init -reconfigure   # remote S3 backend @ 192.168.8.101:9000
   tofu plan
   ```

## What this environment manages

| VM | Map key | VM ID | Notes |
|----|---------|-------|-------|
| `omarchy-lab` | `omarchy` | 100 | No ISO (install media removed post-install) |
| `ubuntu-lab` | `ubuntu` | 101 | Install ISO attached on `ide2` |
| `windows11-lab` | `windows11` | 102 | Windows 11: TPM 2.0, `win11`, VGA `std`, installer on `ide2` |

Windows 11 note: the guest needs the `virtio-win` driver ISO to see the VirtIO disk during Setup. It is already at `HDD01:iso/virtio-win-0.1.302.iso`; attach it after apply (provider allows only one `cdrom`): `qm set 102 -ide0 HDD01:iso/virtio-win-0.1.302.iso,media=cdrom`. Full lifecycle (drivers, post-install cleanup, boot order): [root README §17](../../README.md#17-windows-11-guest-windows11-lab-vm-102).

All VMs come from one `locals.virtual_machines` map plus a single `for_each` module call in `main.tf`. Deploy one machine with `tofu apply -target='module.vm["omarchy"]'` (see root README §14).

## Remote state

S3-compatible SeaweedFS at `http://192.168.8.101:9000`, bucket `homelab-tfstate`, key `homelab/terraform.tfstate`, path-style, region `us-east-1`. Full configuration and verification: root README §15.

## Files

| File | Purpose |
|------|---------|
| `main.tf` | `locals.virtual_machines` map + `for_each` module call |
| `provider.tf` | Proxmox provider (endpoint from `var.proxmox_endpoint`) |
| `variables.tf` | `proxmox_endpoint`, `proxmox_insecure` |
| `versions.tf` | Version pins + `backend "s3"` |
| `terraform.tfvars` | Non-secret endpoint value — **untracked** (`.gitignore`: `*.tfvars`) |
