# Omarchy Lab — Infrastructure-as-Code for a Proxmox Homelab

Provisions an [Omarchy](https://omarchy.org/) virtual machine on Proxmox VE using OpenTofu (or Terraform). This is the first lab in a multi-phase DevOps portfolio.

---

## 1. Why Infrastructure-as-Code?

Infrastructure-as-Code (IaC) means describing your servers, networks, and services in text files that a computer can read, plan, and execute. Instead of clicking through a web UI to create a VM, you write a file that says *"I want a VM with 4 cores, 8 GB RAM, and this ISO"*, and a tool (OpenTofu/Terraform) makes it happen.

**Why bother?**

- **Reproducibility**: the same `.tf` files create the same VM every time — no "it worked on my machine" surprises.
- **Version control**: every change is a git commit, so you can see *who* changed *what* and *when*.
- **Idempotency**: running `tofu apply` twice does nothing the second time — the desired state is already matched.
- **Learning**: this homelab is a sandbox. Break things, destroy, rebuild — the code is the source of truth, not the running VM.

This project is the **Level 1** starting point: a single VM managed by IaC, with manual installation steps. Each subsequent level adds automation (CI/CD pipelines, multi-VM fleets).

---

## 2. Architecture: Environments + Modules

The repository is split into two layers:

```
omarchy-lab/
├── environments/homelab/     ← concrete values for THIS homelab
│   ├── main.tf               ← calls the module with real values
│   ├── provider.tf           ← Proxmox provider config
│   ├── variables.tf          ← environment-level inputs
│   ├── versions.tf           ← pinned provider version
│   └── terraform.tfvars      ← non-secret variable values
└── modules/proxmox-vm/       ← reusable, environment-agnostic module
    ├── main.tf               ← VM resource definition
    ├── variables.tf          ← every knob the module exposes
    ├── outputs.tf            ← values the module exports
    └── versions.tf           ← provider source (no version pin)
```

**Modules** define *what* a thing looks like: "a Proxmox VM has CPU, RAM, disk, network, and a boot order." They contain no hard-coded node names, IP addresses, or storage IDs.

**Environments** define *where* and *how big*: "on node `trastero01`, 4 cores, 8 GB, ISO at `HDD01:iso/...`". They call a module and fill in the blanks.

This separation means the same module could power a staging VM, a production VM, or a dozen VMs across a cluster — each environment just passes different values.

---

## 3. The Three Worlds

When you work with Terraform/OpenTofu, there are three distinct worlds:

| World | What it is | Where it lives |
|-------|-----------|----------------|
| **Configuration files** | Your desired state — the `.tf` files you edit | This repository |
| **State** | Terraform's record of what it *thinks* is real | `terraform.tfstate` (local file) |
| **Real infrastructure** | The actual VMs, disks, and networks in Proxmox | Your Proxmox cluster |

**Terraform manages the state, not the files.** When you run `tofu plan`, it:

1. Reads your `.tf` files (desired state).
2. Reads the state file (last-known real state).
3. Queries Proxmox (current real state).
4. Shows you the *diff* between desired and real.

If the state file is out of sync with reality (e.g. someone deleted the VM in the Proxmox UI), `tofu plan` will show a plan to *create* it again. The `.tf` files are the source of truth; the state file is Terraform's memory.

**Never edit `terraform.tfstate` by hand.** Use `tofu state` commands instead (see Section 5).

---

## 4. Prerequisites

1. **Proxmox VE** running on the target node (tested with Proxmox 9.x)
2. **Omarchy ISO** uploaded to the Proxmox datastore (`HDD01:iso/omarchy-4.0.3.iso`)
3. **Proxmox API token** with sufficient privileges to create VMs
   - Recommended: create a dedicated user (e.g. `opentofu@pve`) with `PVEVMAdmin` role on `/vms`
   - Generate an API token under **Datacenter → Permissions → API Tokens**
4. **OpenTofu** (or Terraform) >= 1.6.0 installed on the machine running this configuration

---

## 5. Authentication

Set the following environment variables **before** running OpenTofu/Terraform:

```bash
export PROXMOX_VE_ENDPOINT="https://192.168.8.2:8006/"
export PROXMOX_VE_API_TOKEN="opentofu@pve!tokenid=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export PROXMOX_VE_USERNAME="opentofu@pve"
```

> **Security note**: The API token value is never committed to this repository. The `.gitignore` excludes `*.tfvars` except `terraform.tfvars` (which contains only the non-secret endpoint URL).

> **Bash gotcha**: If you paste the export lines inside double quotes (`"..."`), the `!` character triggers **history expansion** in bash and the command silently expands to garbage. Always use single quotes (`'...'`) or run the exports in a non-interactive context.

---

## 6. The Full Lifecycle

### 6.1 `tofu init`

Downloads the provider plugin (bpg/proxmox 0.111.1) and initializes the working directory. Run once per environment, or after adding/removing providers.

```bash
cd environments/homelab
tofu init
```

### 6.2 `tofu plan`

Reads the `.tf` files, compares them to the state and the real Proxmox infrastructure, and shows you a preview of what will change. **Nothing is modified** — this is dry-run only.

```bash
tofu plan
```

### 6.3 `tofu apply`

Executes the plan from `tofu plan`. Asks for confirmation, then creates/modifies/destroys resources in Proxmox.

```bash
tofu apply
```

After the VM is created, open the **Proxmox console** to complete the Omarchy installation interactively (see Section 7).

### 6.4 State Management Commands

```bash
# List all resources Terraform knows about
tofu state list

# Show details of a specific resource
tofu state show module.omarchy.proxmox_virtual_environment_vm.vm

# Move a resource in state (used when refactoring — NOT what we did here)
tofu state mv <old_address> <new_address>
```

In this project, the VM resource was moved from the old flat address `proxmox_virtual_environment_vm.omarchy` to the current module address `module.omarchy.proxmox_virtual_environment_vm.vm` using `tofu state mv`.

---

## 7. Post-Install: No Boot Order Fix Needed

Historically, the Omarchy ISO booted once from the cdrom attached on `ide2`. After installation the ISO was removed from the VM (a documented post-install step), so nothing remains to boot from.

Today, **no cdrom is attached**:

- The module attaches the install media *only while `iso` is set*, via a dynamic block (`dynamic "cdrom" { for_each = var.iso != null ? [1] : [] }`).
- The environment leaves `iso` unset, so the cdrom block renders nothing and the VM has no optical drive at all.

The `boot_order` still lists `[scsi0, ide2]`, but `ide2` is vacant (no device). The VM boots from `scsi0` (the disk) first, so **no manual fix is needed anymore**. Optionally, trimming `boot_order` to `[scsi0]` is a cosmetic cleanup for a future change.

Note: unattended/cloud-init installs were **evaluated and deliberately not planned** — manual installation remains the approach (roadmap item N2 was dropped).

---

## 8. Why `on_boot = false`

The VM has `on_boot = false` intentionally. At this stage (Level 1), the VM is manually installed and not yet production-ready. This prevents the VM from automatically starting on Proxmox host reboot, which is appropriate for a lab environment where the VM may need post-install configuration before it can boot reliably.

---

## 9. Why `terraform {}` Instead of `opentofu {}`

The `versions.tf` file uses the `terraform {}` block rather than an `opentofu {}` block. This is **intentional**:

- **HCL compatibility**: OpenTofu is fully compatible with Terraform's HCL syntax and the `terraform {}` block. There is no functional difference at runtime.
- **Provider ecosystem**: The `bpg/proxmox` provider (pinned at `0.111.1`) is published to the Terraform Registry and consumed identically by both tools.
- **Portability**: Using the `terraform {}` block means this configuration works out-of-the-box with both `terraform` and `tofu` commands. If you later switch to `opentofu`, just use `tofu init` — no code changes needed.
- **Documentation alignment**: Most Proxmox provider documentation and community examples use the `terraform {}` block, so this matches the reference material.

When switching to OpenTofu is needed (e.g., to use state encryption or other OpenTofu-specific features), the migration is a single command: `tofu init -migrate-state`.

---

## 10. VM ID

The default `vm_id` is `100` (set in `terraform.tfvars`). This aligns with the Proxmox convention of using low numbers for manually/importantly managed VMs. The `variables.tf` default also matches at `100`.

---

## 11. Evolution Roadmap

| Level | Name | What changes |
|-------|------|-------------|
| **1** ← current | Manual install | VM created via IaC, but OS installed interactively from ISO |
| **2** | Cloud-init (cidata) | **Dropped** — evaluated and deliberately not planned (roadmap item N2); installs stay manual |
| **3** | CI/CD pipeline | Push to `main` triggers automated plan + apply (GitHub Actions, GitLab CI) |
| **4** | Modular fleets | Multiple modules (VMs, VLANs, DNS, storage) orchestrated as a stack |

---

## 12. Troubleshooting

### "Error: Missing required argument"

A required variable has no default and was not provided. Check that all variables without `default` in `variables.tf` are set in `terraform.tfvars` or passed via CLI.

### "Error: Failed to query available provider packages" / "provider registry"

Wrong provider source. The module's `versions.tf` must declare `source = "bpg/proxmox"` (not `hashicorp/proxmox`). The environment pins the exact version.

### "Error: Unauthorized / authentication failed"

- Verify `PROXMOX_VE_API_TOKEN` and `PROXMOX_VE_USERNAME` are set in the current shell.
- Check that the token hasn't expired or been revoked in Proxmox.
- Confirm the token user has the `PVEVMAdmin` role on `/vms`.

### "Error: certificate verify failed"

Set `insecure = true` in `terraform.tfvars` (already the default for this environment) or provide a CA certificate.

### State is out of sync (VM exists but plan wants to create it)

The state file doesn't know about the VM. Import it:

```bash
tofu import module.omarchy.proxmox_virtual_environment_vm.vm <node_name>/<vm_id>
# e.g. tofu import module.omarchy.proxmox_virtual_environment_vm.vm trastero01/100
```

### `terraform.tfvars` changes are not picked up

Run `tofu refresh` (or just `tofu plan`) — variables are re-read on every plan/apply.

---

## 13. Files

| File | Purpose |
|------|---------|
| `environments/homelab/main.tf` | Calls the module with concrete homelab values |
| `environments/homelab/provider.tf` | Proxmox provider configuration (endpoint, TLS) |
| `environments/homelab/variables.tf` | Environment-level input variable declarations |
| `environments/homelab/versions.tf` | OpenTofu version + exact provider pin |
| `environments/homelab/terraform.tfvars` | Non-secret variable values (endpoint URL) |
| `modules/proxmox-vm/main.tf` | VM resource definition (the reusable module) |
| `modules/proxmox-vm/variables.tf` | Module input variable declarations |
| `modules/proxmox-vm/outputs.tf` | Values exported by the module (vm_id, vm_name) |
| `modules/proxmox-vm/versions.tf` | Provider source declaration (no version pin) |
| `.gitignore` | Excludes state, caches, secrets; tracks `terraform.tfvars` |
