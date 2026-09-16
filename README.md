# Omarchy Lab — Infrastructure-as-Code for a Proxmox Homelab

Provisions virtual machines on Proxmox VE using OpenTofu (or Terraform). The homelab currently runs **two VMs** — `omarchy-lab` (VM 100) and `ubuntu-lab` (VM 101) — both created by the same reusable `proxmox-vm` module via a `for_each` map. This is the first lab in a multi-phase DevOps portfolio.

---

## 1. Why Infrastructure-as-Code?

Infrastructure-as-Code (IaC) means describing your servers, networks, and services in text files that a computer can read, plan, and execute. Instead of clicking through a web UI to create a VM, you write a file that says *"I want a VM with 4 cores, 8 GB RAM, and this ISO"*, and a tool (OpenTofu/Terraform) makes it happen.

**Why bother?**

- **Reproducibility**: the same `.tf` files create the same VM every time — no "it worked on my machine" surprises.
- **Version control**: every change is a git commit, so you can see *who* changed *what* and *when*.
- **Idempotency**: running `tofu apply` twice does nothing the second time — the desired state is already matched.
- **Learning**: this homelab is a sandbox. Break things, destroy, rebuild — the code is the source of truth, not the running VM.

This project started at the **Level 1** point: a single VM managed by IaC, with manual installation steps. The **N4 refactor** took it further — the module is now driven by `for_each` and provisions **two VMs** from one `locals` map. Each subsequent level adds automation (CI/CD pipelines, larger fleets).

---

## 2. Architecture: Environments + Modules

The repository is split into two layers:

```
omarchy-lab/
├── environments/homelab/     ← concrete values for THIS homelab
│   ├── main.tf               ← VM map + single module call (for_each)
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

**Multi-VM pattern (N4)**: `environments/homelab/main.tf` declares a `locals.virtual_machines` map — one entry per VM (VM 100 `omarchy-lab`, VM 101 `ubuntu-lab`). The module is called exactly once with `for_each = local.virtual_machines`, so adding a third VM is one more map entry. The module stays untouched.

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
2. **Install ISOs** uploaded to the Proxmox datastore as needed (e.g. `HDD01:iso/ubuntu-26.04.1-desktop-amd64.iso` for `ubuntu-lab`)
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

After each VM is created, open the **Proxmox console** to complete its installation interactively (see Section 7).

### 6.4 State Management Commands

```bash
# List all resources Terraform knows about
tofu state list

# Show details of a specific resource (for_each module address)
tofu state show 'module.vm["omarchy"].proxmox_virtual_environment_vm.vm'
tofu state show 'module.vm["ubuntu"].proxmox_virtual_environment_vm.vm'

# Move a resource in state (used when refactoring — NOT what we did here)
tofu state mv <old_address> <new_address>
```

In this project, the VM resource was moved from the old flat address `proxmox_virtual_environment_vm.omarchy` into the module using `tofu state mv`. After the N4 `for_each` refactor the module addresses are `module.vm["omarchy"].proxmox_virtual_environment_vm.vm` and `module.vm["ubuntu"].proxmox_virtual_environment_vm.vm`.

---

## 7. Post-Install: No Boot Order Fix Needed

Neither VM needs a boot-order fix after install:

- **`omarchy-lab` (100)**: its ISO booted once from the cdrom on `ide2`; after installation the media was removed (a documented post-install step), so no optical device remains.
- **`ubuntu-lab` (101)**: its install ISO is still attached on `ide2` (`HDD01:iso/ubuntu-26.04.1-desktop-amd64.iso`) so it can boot the installer on first start.

How the module decides:

- The module attaches install media *only while `iso` is set*, via a dynamic block (`dynamic "cdrom" { for_each = var.iso != null ? [1] : [] }`).
- The environment passes `iso = try(each.value.iso, null)`: entries without an `iso` key evaluate to `null`, so the cdrom block renders nothing. This is how `omarchy-lab` has no cdrom while `ubuntu-lab` does.

`boot_order` still lists `[scsi0, ide2]`; every VM boots from `scsi0` (the disk) first, so **no manual fix is needed**. For `omarchy-lab`, `ide2` is vacant; trimming its `boot_order` to `[scsi0]` is a cosmetic cleanup for a future change.

Note: unattended/cloud-init installs were **evaluated and deliberately not planned** — manual installation remains the approach (roadmap item N2 was dropped).

---

## 8. Why `on_boot = false`

Both VMs have `on_boot = false` intentionally (the module default). At this stage (Level 1), the VMs are manually installed and not yet production-ready. This prevents them from automatically starting on Proxmox host reboot, which is appropriate for a lab environment where a VM may need post-install configuration before it can boot reliably.

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

VM IDs are declared per VM in the `locals.virtual_machines` map in `environments/homelab/main.tf`: `omarchy-lab` is **100** and `ubuntu-lab` is **101**. They align with the Proxmox convention of using low numbers for manually/importantly managed VMs. Every VM carries its own explicit `vm_id` in its map entry.

---

## 11. Evolution Roadmap

| Level | Name | What changes |
|-------|------|-------------|
| **1** ← current | Manual install | VM created via IaC, but OS installed interactively from ISO |
| **2** | Cloud-init (cidata) | **Dropped** — evaluated and deliberately not planned (roadmap item N2); installs stay manual |
| **3** | CI/CD pipeline | Push to `main` triggers automated plan + apply (GitHub Actions, GitLab CI) |
| **4** | Modular fleets | Multiple modules (VMs, VLANs, DNS, storage) orchestrated as a stack |

This roadmap is forward-looking; the repo today already exercises Level 1 plus the **multi-VM `for_each` pattern (N4)** — two VMs from one `locals` map, one module call (see Section 2).

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

The state file doesn't know about the VM. Import it (note the `for_each` module address):

```bash
tofu import 'module.vm["omarchy"].proxmox_virtual_environment_vm.vm' trastero01/100
tofu import 'module.vm["ubuntu"].proxmox_virtual_environment_vm.vm'  trastero01/101
```

### The 'host_cdrom' block driver requires a file name (VM won't start after removing install media)

If install media is removed but Proxmox keeps an **empty** cdrom device, QEMU fails to start the VM with `The 'host_cdrom' block driver requires a file name`. Proxmox shows the leftover as `ide3: cdrom,media=cdrom` — an empty optical drive with no media.

Fix — delete the empty ide device, then start the VM:

```bash
# Proxmox API (authenticate with a PVEAPIToken)
curl -X PUT \
  -H "Authorization: PVEAPIToken=opentofu@pve!<token-id>=<secret>" \
  'https://192.168.8.2:8006/api2/json/nodes/<node>/qemu/<vmid>/config?delete=ide3'
```

Or remove it in the Proxmox UI (Hardware tab → the cdrom device → Remove), then start the VM.

Best practice: when you are done with install media, remove the cdrom device entirely — empty drives cause this start failure. In this repo the module never creates a cdrom unless `iso` is set, so the clean way to drop media is to remove the `iso` key from the VM's `locals` entry and apply.

### `terraform.tfvars` changes are not picked up

Run `tofu refresh` (or just `tofu plan`) — variables are re-read on every plan/apply.

---

## 13. Files

| File | Purpose |
|------|---------|
| `environments/homelab/main.tf` | `locals.virtual_machines` map (one entry per VM) + single module call with `for_each` |
| `environments/homelab/provider.tf` | Proxmox provider configuration (endpoint, TLS) |
| `environments/homelab/variables.tf` | Environment-level input variable declarations |
| `environments/homelab/versions.tf` | OpenTofu version + exact provider pin |
| `environments/homelab/terraform.tfvars` | Non-secret variable values (endpoint URL) |
| `modules/proxmox-vm/main.tf` | VM resource definition (the reusable module) |
| `modules/proxmox-vm/variables.tf` | Module input variable declarations |
| `modules/proxmox-vm/outputs.tf` | Values exported by the module (vm_id, vm_name) |
| `modules/proxmox-vm/versions.tf` | Provider source declaration (no version pin) |
| `.gitignore` | Excludes state, caches, secrets; tracks `terraform.tfvars` |
