# Postmortem: SeaweedFS remote state, Proxmox token format, and a green OpenTofu plan

- **Date:** 2026-10-13
- **Severity:** High (remote-state backend and Proxmox provider auth failing → no trustworthy plan/apply)
- **Duration:** multi-session, ending with a green `tofu plan` on 2026-10-13
- **Systems:** OpenTofu (bpg/proxmox 0.111.1), SeaweedFS S3 (LXC 200), Proxmox VE API, Forgejo Actions (CI)

## Summary

The homelab OpenTofu configuration could not reliably reach its remote state or authenticate to Proxmox. Three independent drifts compounded: the S3 remote-state backend pointed at a SeaweedFS container whose address and service state had drifted, the Proxmox API token was supplied in the wrong format, and local/remote state bookkeeping had diverged. Each drift produced a similar "it just won't connect" symptom, so they had to be separated one at a time. The work ended with `tofu plan` **green** (0 to add, 2 to change, 0 to destroy) against the remote state and the first CI workflow pushed to Forgejo (PR #1). This document also records CI defects found while writing it (see *Open issues*).

## Impact

- While the drifts were live, any `tofu plan/apply` that read remote state failed, and any plan that queried Proxmox failed authentication — so no change could be trusted or applied.
- No data loss: SeaweedFS and Proxmox were healthy; only addresses, credentials, and bookkeeping were wrong.
- The two VMs (`omarchy-lab` VM 100, `ubuntu-lab` VM 101) remained as previously provisioned.

## Timeline (reconstructed from artifacts)

| When | Event |
|------|-------|
| 2026-09-16 | Remote S3 backend configured and state migrated. Local leftovers remain: `terraform.tfstate` (0 B), `terraform.tfstate.<ts>.backup`, `.terraform.lock.hcl`. |
| 2026-09-18 | SeaweedFS DHCP IP drift broke the S3 endpoint → LXC pinned to static `192.168.8.101/24` (see `postmortem-2026-09-18-seaweedfs-ip-drift.md`). |
| (later) | LXC 200 renamed in intent from "minio" to "seaweedfs"; the `weed` service was installed but **not enabled**, so the S3 API (`:9000`) was absent after a container restart. |
| (later) | Proxmox API token supplied in the wrong format → repeated `401 Unauthorized`. |
| 2026-10-13 | Correct token `opentofu@pve!tofu=<secret>` validated with `curl` → HTTP 200. |
| 2026-10-13 | `tofu plan` GREEN: 0 to add, 2 to change, 0 to destroy (exit 0). |
| 2026-10-13 | Pushed to Forgejo; PR #1 (`ci-first-plan` → `main`); CI workflow added. |

## Root causes

### 1. State/backend filename + credential-resolution (IMDS) drift
- Local state artifacts (`terraform.tfstate` at 0 bytes, timestamped `.backup` files, the lockfile) lived beside the configuration, while the authoritative copy is the remote S3 key `homelab/terraform.tfstate`. This local/remote "filename" drift makes it easy to inspect or reason about the wrong state.
- When `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` were absent, the AWS SDK did not fail fast — it fell through to the EC2 **Instance Metadata Service (IMDS, `169.254.169.254`)**. On a non-EC2 host that lookup stalls and surfaces as a slow, misleading backend error instead of "credentials not found".

### 2. Proxmox API token format confusion
- A PVE API token is **`USER@REALM!TOKENID=SECRET`**. The realm (`@pve`), the `!` separator, and the `=secret` are all required. Supplying only the secret UUID, or omitting the realm/tokenid, returns `401 Unauthorized`.
- In an interactive shell, an unquoted `!` triggers bash history expansion and silently corrupts the value (`bash: !tokenid=…: event not found`).

### 3. MinIO → SeaweedFS rename + `weed.service` not enabled
- LXC 200's legacy name was "minio" but it actually runs `weed server` (SeaweedFS). The service existed and could be started manually, but was **not enabled**, so after any container reboot the S3 endpoint was down — the backend became unreachable while the "server" looked installed.

### 4. Documentation/config drift (found while writing this postmortem)
- The CI workflow references credentials that do not match the provider/environment contract, and a required variable is not supplied. See *Open issues*.

## Fixes applied

| Fix | Detail |
|-----|--------|
| Static IP pin | SeaweedFS LXC pinned to `192.168.8.101/24`; backend endpoint `http://192.168.8.101:9000` (prior postmortem). |
| SeaweedFS service | `systemctl enable --now weed` on CT 200; hostname `seaweedfs`; S3 `:9000`, master `:9333`, filer `:8888` live. |
| Proxmox token | Use the full `USER@REALM!TOKENID=SECRET`; validated with `curl` → 200. Exported `PROXMOX_VE_API_TOKEN` + `PROXMOX_VE_USERNAME` (quoted). |
| S3 credentials | Read the `terraform` identity from CT 200 `/etc/weed/s3.json`; exported `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` into the process env only (never committed). |
| Remote-state re-init | `tofu init -reconfigure` against `192.168.8.101:9000`. |

## Verification (live, not assumed)

- **Proxmox:** `curl` with `Authorization: PVEAPIToken=opentofu@pve!tofu=<secret>` → **HTTP 200**.
- **OpenTofu:** `tofu plan` **exit 0** — *Plan: 0 to add, 2 to change, 0 to destroy*.
  - The 2 changes are computed/cosmetic: `ipv6_addresses` `[]` → *(known after apply)* and `started` `false` → `true`.
  - State lists `module.vm["omarchy"]` id `100` and `module.vm["ubuntu"]` id `101` (refreshed).
- **Forgejo:** push succeeded; the remote URL is credential-free, no `oauth2` helper in `.git/config`, no token persisted; PR #1 exists.
- **CT 200:** `systemctl is-enabled weed` → `enabled`; `is-active` → `active`.

## Open issues (CI is not yet trusted)

Found while writing this document. All three live in `.forgejo/workflows/tofu.yml`.

1. **Secret names do not match the provider contract.** The workflow injects `PM_API_TOKEN_ID` / `PM_API_TOKEN_SECRET`, but the bpg/proxmox provider reads `PROXMOX_VE_USERNAME` and `PROXMOX_VE_API_TOKEN`. Plan/apply would fail auth even if the secrets existed. Fix: create the four repo-level secrets (`PROXMOX_VE_USERNAME`, `PROXMOX_VE_API_TOKEN`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) and map `PROXMOX_VE_*` in the workflow.
2. **Required variable not supplied.** `proxmox_endpoint` has no default and `terraform.tfvars` is gitignored (untracked), so CI has no value → "No value for required variable". Fix: pass `TF_VAR_proxmox_endpoint` in the job environment, or track a non-secret tfvars via a `.gitignore` negation.
3. **Backend disabled at init.** `tofu init -backend=false` followed by `tofu plan` cannot read remote state. Fix: run `tofu init` (remote backend enabled) in jobs that need state.

## Lessons learned

- Absent credentials do not mean "no auth" — the AWS SDK falls through to IMDS and fails slowly and confusingly. Set credentials explicitly and fail fast.
- The PVE token format is exact: `USER@REALM!TOKENID=SECRET`. Quote exports to defeat `!` history expansion.
- A service that is *started* is not a service that is *enabled*; after a reboot the difference is an outage. Verify with `systemctl is-enabled`.
- Never anchor a remote-state backend to a DHCP address (recap of the 2026-09-18 lesson).
- Documentation must be validated against code: secret names and required variables are part of the interface. A CI workflow that has never run green is not "done".
- Separate "server is down" from "server moved" from "credentials are wrong" — three different questions with three different fixes.

## Next steps

1. Fix the three CI defects above and get PR #1's workflow green end-to-end.
2. Add the four Forgejo repo secrets at `cescm/iac → Settings → Actions → Secrets`.
3. Mirror this postmortem to Docmost (Homelab workspace) — see `docs/ci-runbook.md` and the `docmost-publish` skill.
4. Optional cleanup: remove local `terraform.tfstate*` leftovers (keep `.backup` until the remote state is confirmed stable) and trim `boot_order` for VM 100 (no cdrom) to `["scsi0"]`.
