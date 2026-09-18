# CI runbook — Forgejo Actions (OpenTofu homelab)

- Workflow: .forgejo/workflows/tofu.yml  (plan-on-PR, apply-on-merge)
- Secrets: repo-level, never in git
- Remote state: SeaweedFS S3 @ 192.168.8.101:9000 (static IP)
