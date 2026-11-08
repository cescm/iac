# CI runbook — Forgejo Actions (OpenTofu homelab)

- Workflow: `.forgejo/workflows/tofu.yml` — plan-on-PR, apply-on-merge (push to `main`)
- Repo: `forgejo.caprichosdelucia.com/cescm/iac`
- Remote state: SeaweedFS S3 @ `http://192.168.8.101:9000` (CT 200, static IP), bucket `homelab-tfstate`

## Secrets (repo-level, never in git)

Set at `cescm/iac → Settings → Actions → Secrets`:

| Secret | Source |
|--------|--------|
| `PROXMOX_VE_USERNAME` | Proxmox token user (e.g. `opentofu@pve`) |
| `PROXMOX_VE_API_TOKEN` | full `USER@REALM!TOKENID=SECRET` |
| `AWS_ACCESS_KEY_ID` | CT 200 `/etc/weed/s3.json`, identity `terraform` |
| `AWS_SECRET_ACCESS_KEY` | CT 200 `/etc/weed/s3.json`, identity `terraform` |

## Known gaps (workflow not yet green)

The workflow currently references `PM_API_TOKEN_ID` / `PM_API_TOKEN_SECRET` instead of `PROXMOX_VE_*`, omits the required `proxmox_endpoint` variable, and runs `tofu init -backend=false` before `plan`. See `docs/postmortem-2026-10-13-seaweedfs-tofu-green-plan.md` (Open issues).
