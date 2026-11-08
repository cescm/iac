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
│   ├── versions.tf           ← pinned provider version + S3 remote backend (N5)
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
| **State** | Terraform's record of what it *thinks* is real | Remote S3-compatible backend (SeaweedFS on LXC 200) |
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

Two independent credential sets are required. Both are supplied through **environment variables or local (untracked) files only** — never committed.

### 5.1 Proxmox VE API token

```bash
export PROXMOX_VE_API_TOKEN='opentofu@pve!tofu=<token-secret-uuid>'
export PROXMOX_VE_USERNAME="opentofu@pve"
```

- **Token format is `USER@REALM!TOKENID=SECRET`.** All three parts are mandatory — the realm (`@pve`), the `!tokenid`, and `=secret`. Supplying only the secret UUID, or omitting the realm/tokenid, returns `401 Unauthorized`.
- **Where to get it:** Proxmox UI → **Datacenter → Permissions → API Tokens** → *Add*. The secret is shown **once** at creation. The token's user needs the `PVEVMAdmin` role on `/vms` (e.g. user `opentofu@pve`).
- **Bash gotcha:** in an interactive shell an unquoted `!` triggers **history expansion** and silently corrupts the value (`bash: !tokenid=…: event not found`). Always quote with **single quotes**.

### 5.2 SeaweedFS S3 (remote state) credentials

```bash
export AWS_ACCESS_KEY_ID="<key>"
export AWS_SECRET_ACCESS_KEY="<secret>"
```

- **Where they come from:** the SeaweedFS server config on the container (`CT 200`, `192.168.8.101`) at `/etc/weed/s3.json`, identity `terraform`. Copy them from there into the process environment.
- **Never commit these values.** They are not in any tracked file — the variable *names* are documented, the values are not.

> The Proxmox **endpoint** is *not* an environment variable here. It is a required input set in `terraform.tfvars` (`proxmox_endpoint`) and consumed by `provider.tf` (`endpoint = var.proxmox_endpoint`). See Section 15 for the S3 backend and Section 16 for CI.

---

## 6. The Full Lifecycle

### 6.1 `tofu init`

Downloads the provider plugin (bpg/proxmox 0.111.1) and initializes the working directory. Run once per environment, or after adding/removing providers. With the remote backend (N5), also ensure `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` are set — `tofu init` will connect to the S3 endpoint.

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
- **`windows11-lab` (102)**: boots the Windows 11 installer from `ide2` first (`boot_order = [ide2, scsi0]`) because the empty disk is not bootable yet. See Section 17 for the full Windows lifecycle.

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

VM IDs are declared per VM in the `locals.virtual_machines` map in `environments/homelab/main.tf`: `omarchy-lab` is **100**, `ubuntu-lab` is **101**, and `windows11-lab` is **102**. They align with the Proxmox convention of using low numbers for manually/importantly managed VMs. Every VM carries its own explicit `vm_id` in its map entry.

---

## 11. Evolution Roadmap

| Level | Name | What changes |
|-------|------|-------------|
| **1** ← current | Manual install | VM created via IaC, but OS installed interactively from ISO |
| **2** | Cloud-init (cidata) | **Dropped** — evaluated and deliberately not planned (roadmap item N2); installs stay manual |
| **3** | CI/CD pipeline | Push to `main` triggers automated plan + apply (GitHub Actions, GitLab CI) |
| **4** | Modular fleets | Multiple modules (VMs, VLANs, DNS, storage) orchestrated as a stack |

This roadmap is forward-looking; the repo today already exercises Level 1 plus the **multi-VM `for_each` pattern (N4)** — two VMs from one `locals` map, one module call (see Section 2). **N5 (remote state)** is also complete: state now lives in an S3-compatible backend (SeaweedFS) instead of a local file.

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

### S3 remote backend errors (`Error configuring S3 backend`, `Access Denied`)

The backend is the S3-compatible SeaweedFS endpoint on CT 200 (`192.168.8.101:9000`). Credentials come from environment variables only:

```bash
export AWS_ACCESS_KEY_ID="<your-key>"
export AWS_SECRET_ACCESS_KEY="<your-secret>"
```

**Never commit these values.** Re-initialize after changing credentials or the endpoint:

```bash
cd environments/homelab
tofu init -reconfigure                  # re-point / re-auth the existing backend
# tofu init -migrate-state -force-copy  # only for the FIRST migration from local state
```

If the credential variables are missing, the AWS SDK does **not** fail fast — it tries the EC2 metadata service (IMDS, `169.254.169.254`) and the resulting error is slow and misleading. If `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` are empty, the backend error is almost certainly this. See Section 15 for the full backend config.

---

## 13. Files

| File | Purpose |
|------|---------|
| `environments/homelab/main.tf` | `locals.virtual_machines` map (one entry per VM) + single module call with `for_each` |
| `environments/homelab/provider.tf` | Proxmox provider configuration (endpoint, TLS) |
| `environments/homelab/variables.tf` | Environment-level input variable declarations |
| `environments/homelab/versions.tf` | OpenTofu version + exact provider pin + S3 remote backend config (SeaweedFS) |
| `environments/homelab/terraform.tfvars` | Non-secret variable values (endpoint URL). **Untracked** — ignored by `.gitignore` (`*.tfvars`); supply locally, or via `-var` / `TF_VAR_`. |
| `modules/proxmox-vm/main.tf` | VM resource definition (the reusable module) |
| `modules/proxmox-vm/variables.tf` | Module input variable declarations |
| `modules/proxmox-vm/outputs.tf` | Values exported by the module (vm_id, vm_name) |
| `modules/proxmox-vm/versions.tf` | Provider source declaration (no version pin) |
| `.forgejo/workflows/tofu.yml` | CI: `plan` on PR, `apply` on merge to `main` (see Section 16) |
| `docs/` | Postmortems and the CI runbook |
| `.gitignore` | Excludes state, caches, and all `*.tfvars` (including `terraform.tfvars`) |

---

## 14. Deploying a Single Machine (`-target`) vs. One Folder Per Machine

All machines in this environment come from **one** declaration:

```hcl
# environments/homelab/main.tf
module "vm" {
  source   = "../../modules/proxmox-vm"
  for_each = local.virtual_machines   # 🔑 the whole farm in one map
  ...
}
```

Because the module uses `for_each`, every machine is a **module instance** named `module.vm["<name>"]` — so "just one machine" is a **`-target`**, not a new directory:

```bash
# plan + apply ONE machine only (e.g. omarchy) — the rest of the map is untouched
tofu plan  -target='module.vm["omarchy"]'
tofu apply -target='module.vm["omarchy"]'

# both machines, straight from the map — the normal full run
tofu apply
```

Current machine names (keys of `local.virtual_machines`): **`omarchy`**, **`ubuntu`**.

### Why `-target` and not a folder per machine?

Both are legit; this repo deliberately uses `-target` **for now**. The honest tradeoff:

| | `-target` on the map (current) | One folder per machine |
|---|---|---|
| Where machines live | inside `for_each` map in one `main.tf` | `environments/homelab/<machine>/` each with own `main.tf` |
| State/backend | **one** state (same SeaweedFS key `homelab/terraform.tfstate`) | **N** state keys (one per machine dir) |
| Deploy one | `tofu apply -target='module.vm["…"]'` | `cd <machine> && tofu apply` |
| CI matrix | single job (loop `-target` per VM) | **native** matrix — one job per dir, parallel |
| Cross-machine refs | easy (same state graph) | needs `terraform_remote_state` data sources |
| Boilerplate | minimal (one provider/backend) | repeated per dir (provider, backend, versions) |

**Decision (recorded):** stay on the single map + `-target` **until either** (a) a machine's lifecycle drifts far from the rest (e.g. a k3s worker that rebuils weekly while `ubuntu` stays evergreen), **or** (b) you want parallel per-machine CI jobs. The moment the README's own history shows "rebuilt one VM without touching the others" more than once, do **not** keep stacking `-target` — split that machine into `environments/homelab/<machine>/` with its own backend key + a matrix job in CI. That split is a one-afternoon refactor, fully documented here, so it's a *planned* evolution, not a surprise.

---

## 15. Remote State — SeaweedFS S3 Backend (N5)

State is stored in an S3-compatible SeaweedFS endpoint — not on the Proxmox host and not in a local file.

| Setting | Value |
|---------|-------|
| Bucket | `homelab-tfstate` |
| Key | `homelab/terraform.tfstate` |
| Endpoint | `http://192.168.8.101:9000` (CT 200, static IP) |
| Region | `us-east-1` (placeholder; not validated) |
| Path style | `use_path_style = true` |
| Validation | `skip_region_validation`, `skip_credentials_validation`, `skip_requesting_account_id` all `true` |
| Credentials | `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` env vars (Section 5.2) |

The config lives in `environments/homelab/versions.tf` (the `backend "s3"` block). The endpoint is a **static string** — Tofu cannot interpolate the backend — so the SeaweedFS container must keep a stable IP (`192.168.8.101`; see the 2026-09-18 postmortem).

Verify (expect a clean/no-op plan when nothing changed):

```bash
export AWS_ACCESS_KEY_ID="<key>"; export AWS_SECRET_ACCESS_KEY="<secret>"
cd environments/homelab
tofu init -reconfigure
tofu plan
```

Local `terraform.tfstate*` files are leftovers from the migration and are gitignored; the remote key above is the source of truth.

---

## 16. CI/CD — Forgejo Actions

- **Workflow:** `.forgejo/workflows/tofu.yml` — `plan` on every pull request, `apply` on push to `main`.
- **Repository:** `forgejo.caprichosdelucia.com/cescm/iac`.
- **Secrets are repo-level**, at `cescm/iac → Settings → Actions → Secrets` (not organization-level). Create exactly these four:

| Secret | Value / source |
|--------|----------------|
| `PROXMOX_VE_USERNAME` | `opentofu@pve` |
| `PROXMOX_VE_API_TOKEN` | full `USER@REALM!TOKENID=SECRET` (Section 5.1) |
| `AWS_ACCESS_KEY_ID` | SeaweedFS `terraform` identity (Section 5.2) |
| `AWS_SECRET_ACCESS_KEY` | SeaweedFS `terraform` identity (Section 5.2) |

> **Known gap (fix pending):** the current workflow injects `PM_API_TOKEN_ID` / `PM_API_TOKEN_SECRET` instead of `PROXMOX_VE_*`, does not provide the required `proxmox_endpoint` variable, and runs `tofu init -backend=false` before `plan`. Each of these breaks the job. See `docs/postmortem-2026-10-13-seaweedfs-tofu-green-plan.md` → *Open issues*; the four secret names above are the contract to converge on.

---

## 17. Windows 11 Guest (`windows11-lab`, VM 102)

Windows 11 needs hardware features a Linux guest does not, so the `proxmox-vm` module exposes them as optional inputs and the `windows11` map entry turns them on.

### Requested specification

| Setting | Value | Module input |
|---------|-------|--------------|
| Machine | `q35` | hardcoded |
| BIOS | OVMF (UEFI) | hardcoded (`bios = "ovmf"`) |
| TPM | 2.0 | `tpm_enabled = true`, `tpm_version = "v2.0"` |
| CPU type | `host` | hardcoded |
| vCPU | 4 (range 2–4) | `cpu_cores = 4` |
| RAM | 4096 MiB | `memory = 4096` |
| Ballooning minimum | 2048 MiB | `memory_min = 2048` |
| Disk | 40 GB (range 32–40) | `disk_size = 40` |
| Controller | VirtIO SCSI Single | hardcoded (`scsi_hardware = "virtio-scsi-single"`) |
| Discard | enabled | hardcoded (`discard = "on"`) |
| IO thread | enabled | hardcoded (`iothread = true`) |
| Network | VirtIO | hardcoded (`model = "virtio"`) |
| Guest OS type | `win11` | `os_type = "win11"` |
| VGA | `std` | `vga_type = "std"` |
| Install ISO | `HDD01:iso/Win11-Pro-Lite.iso` | `iso = ...` |
| Boot order | installer first | `boot_order = ["ide2", "scsi0"]` |

Why `vga_type = "std"`: Windows has no virtio-gpu driver during Setup. With the Linux default `virtio` the installer screen stays black. Switch back to `virtio` after the guest driver is installed (optional).

Why `os_type = "win11"`: tells Proxmox/QEMU the guest family so it applies the correct paravirtualisation profile. `l26` would work but is semantically wrong for Windows.

### VirtIO drivers are required to install

The disk controller is VirtIO SCSI (as requested), and Windows Setup ships **no VirtIO driver** (verified: `boot.wim` contains no `vioscsi`/`viostor`/`netkvm`). Without the `virtio-win` ISO the installer shows no disk.

**Provider limitation:** the legacy `proxmox_virtual_environment_vm` resource allows only **one** `cdrom` block (`MaxItems=1`), and `q35` only exposes `ide0`/`ide2`. So the driver ISO cannot be declared as a second CD-ROM in OpenTofu. The Windows installer ISO is the single declarative `cdrom`; the driver ISO is attached out-of-band:

1. The ISO is already downloaded on the Proxmox host at
   `/mnt/storage/isos/template/iso/virtio-win-0.1.302.iso` (= `HDD01:iso/virtio-win-0.1.302.iso`).
   Official source: `https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso`.
2. After `tofu apply`, attach it to the (stopped) VM before first boot:

   ```bash
   qm set 102 -ide0 HDD01:iso/virtio-win-0.1.302.iso,media=cdrom
   ```

3. Start the VM and run Setup.

> This one line is the only non-declarative step. If you later want it fully in OpenTofu, the alternatives are (a) slipstream the VirtIO drivers into `boot.wim`/`install.wim` of the Windows ISO, or (b) use a SATA disk instead of VirtIO (rejected — VirtIO SCSI was a requirement).

### Post-install steps (manual)

1. In Windows Setup, load the VirtIO **storage** driver from the `virtio-win` CD (`vioscsi`), then the **network** driver (`NetKVM`) after first boot.
2. Install `virtio-win-guest-tools.exe` from the same CD (installs the QEMU guest agent and remaining drivers).
3. Shut down the guest.
4. Detach the driver ISO (`qm set 102 -delete ide0`) and the installer (`iso` removed from the map entry), set `boot_order = ["scsi0"]`, then `tofu apply`. This mirrors the `omarchy-lab` post-install cleanup.
5. Optional: enable the guest agent (`qemu_agent = true`) once it is installed, and restore `vga_type = "virtio"`.

### Ansible

The `ansible` repo does **not** manage this guest. Its playbook targets Linux over SSH; a Windows guest needs WinRM and a separate Windows playbook. Until that exists, `windows11-lab` is provisioned by OpenTofu only and configured manually. See `ansible/README.md`.
