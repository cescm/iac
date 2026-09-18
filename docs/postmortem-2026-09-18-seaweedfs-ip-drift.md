# Postmortem: SeaweedFS IP drift breaks the OpenTofu S3 remote-state backend

- **Date:** 2026-09-18
- **Severity:** High (S3 remote-state backend unreachable during tofu apply/plan)
- **Duration:** from the SeaweedFS LXC boot until the static-IP pin
- **Systems:** SeaweedFS (filer/S3), OpenTofu remote state (`backend "s3"`)

## Summary
The OpenTofu S3 remote-state backend pointed at SeaweedFS on `192.168.8.101:9000`
but the SeaweedFS LXC was configured with `ip=dhcp`, so its live address leaked from
the DHCP pool (drifted to `192.168.8.49`, and earlier `192.168.8.37`). The endpoint
string is static in `versions.tf` — tofus cannot interpolate the S3 backend — so when
the lease moved, the backend became unreachable.

## Root cause
- `net0` of the SeaweedFS LXC used `ip=dhcp` (named "minio", SeaweedFS runs `weed server`).
- DHCP leases are ephemeral; the address changed across boots, and the pinned endpoint
  did not follow.

## Fix (applied, live, static)
- Pinned the SeaweedFS LXC to a **static IP `192.168.8.101/24`** (gw `192.168.8.1`).
- Convention (user-chosen): **LXC containers receive static IPs starting at `192.168.8.101`
  and upward.**
- Updated the S3 backend endpoint in `versions.tf` to `http://192.168.8.101:9000`.

## Verification (live, not assumed)
- SeaweedFS ports LISTEN on `.101`: S3 `:9000`, master `:9333`, filer `:8888`.
- `tofu init -reconfigure` succeeded against `.101` (remote state reachable + auth OK).
- SeaweedFS stores the identity in its server config (e.g. `/etc/weed/s3.json`,
  identity `terraform`); the client supplies matching creds through **environment
  variables only** — `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`. Their values are
  never stored or committed here (names are documented; the values live server-side
  and in the tofu process environment).

## Impact
- While the lease drifted, any `tofu plan/apply` that read remote state failed with a
  backend reachability/auth error.
- No SeaweedFS data was lost; the server itself was healthy — only its address moved.

## Prevention (long-term)
- **Static IP for the SeaweedFS LXC** (done) — the endpoint string never depends on DHCP.
- **Convention documented**: LXC static IPs from `.101` upward.
- OpenTofu S3 backend stays static-string by design; anchor it to a pinned IP, never DHCP.
- Sync client env creds (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`) to any host that
  runs tofu; the endpoint host must be reachable from that host first.

## Lessons
- Never anchor a remote-state backend to a DHCP-assigned address.
- Verify backend reachability + auth (`tofu init -reconfigure`) as a gate after any
  networking/IP convention change.
- Distinguish "server is down" from "server moved" — the SeaweedFS service was fine; the
  *endpoint string* was stale. That distinction is what redirected this postmortem.
