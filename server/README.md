# OCI Free Tier Claude Server

Runbook for a 24/7 Claude Code box on Oracle Cloud Always Free.

**Goal: rebuild everything from this README alone in under 30 minutes.**

Free-tier instances can be reclaimed at any time. Treat the server as cattle, not a pet:

- Keep nothing that exists only on the server. Always `git push`; every credential is re-issuable.
- If it dies, rebuild it with this runbook instead of repairing it.

## Layout

```
[Mac / iPhone]
   │ tailscale ssh (no public ports)
   ▼
[OCI VM.Standard.A1.Flex — 2 OCPU / 12GB / Ubuntu 24.04 arm64]
   ├─ tailscaled ...... joins the tailnet outbound-only
   ├─ tmux.service .... persistent "main" session (systemd user unit)
   ├─ keepalive.timer . daily 2h CPU load (anti idle-reclaim)
   └─ Claude Code + gh
```

| File | Role |
| --- | --- |
| `cloud-init.yaml` | paste at instance creation; joins Tailscale, clones dotfiles |
| `install.zsh` | non-interactive apt install (reads `packages.txt`) |
| `bootstrap.zsh` | idempotent first-time setup; `--dry-run` prints the plan |
| `tmux.service`, `keepalive.{service,timer}` | systemd user units |
| `../test/server.bats` | static checks, including a secret scan of this directory |

Prerequisites (all free): OCI account (§1), Tailscale account with your Mac/iPhone already on the tailnet, GitHub access to this repo, Claude subscription.

## 1. Create the OCI account (once)

1. Sign up at <https://www.oracle.com/cloud/free/>.
2. **Home region: `ap-tokyo-1`. It cannot be changed later**, and A1 instances only launch in the home region.
3. Stay on the pure free tier. Do not upgrade to Pay As You Go.
4. Since 2026-06-15 the free A1 quota is **2 OCPU / 12GB**.

## 2. Create the instance

### 2.1 Tailscale auth key

Generate at <https://login.tailscale.com/admin/settings/keys>: **Reusable OFF / Expiration ≤ 90 days / Pre-approved ON**. Use it once, then discard it. Never write it into this repo.

### 2.2 Prepare cloud-init

Copy `cloud-init.yaml` and replace `{{TAILSCALE_AUTH_KEY}}` with the key, **outside the repo** (e.g. an unsaved editor buffer). Never save or commit the result.

### 2.3 Create in the OCI console

Compute → Instances → Create:

| Field | Value |
| --- | --- |
| Name | anything; it becomes the tailnet hostname |
| Image | Canonical Ubuntu 24.04 (aarch64 with the A1 shape) |
| Shape | VM.Standard.A1.Flex — 2 OCPU / 12GB |
| VCN / subnet | new public subnet is fine (ingress gets closed next) |
| SSH key | add one; only needed for serial-console rescue |
| Boot volume | 100GB |
| cloud-init | Advanced options → Management → paste the prepared content |

"Out of capacity" is a known free-tier issue: retry at another time of day (early morning works best).

### 2.4 Close all ingress

VCN → Default Security List → **delete every ingress rule**, including the default `0.0.0.0/0` TCP 22. Keep egress. Tailscale joins outbound-only, so nothing breaks.

### 2.5 Confirm

On the Mac: `tailscale status | grep <hostname>`. Visible = cloud-init done.

## 3. First-time setup

```sh
tailscale ssh ubuntu@<hostname>
zsh ~/dotfiles/server/bootstrap.zsh --dry-run   # plan only, no side effects
zsh ~/dotfiles/server/bootstrap.zsh
```

If `~/dotfiles` is missing: `git clone https://github.com/cmb-sy/dotfiles.git ~/dotfiles`.

Bootstrap is idempotent — on failure, fix the cause and re-run. Interactive parts:

- **Claude**: `claude` starts; run `/login`, open the URL in the Mac browser, paste the code back, then `/exit`. Bootstrap fails loudly if login is skipped.
- **gh**: choose HTTPS + "Login with a web browser".

Verify:

```sh
systemctl --user status tmux.service keepalive.timer   # both active
tmux attach -t main
claude --version
gh auth status
```

> `Failed to connect to bus`: run `export XDG_RUNTIME_DIR=/run/user/$(id -u)` and retry.
> Enabling symlinked units fails on old systemd: `for u in tmux.service keepalive.service keepalive.timer; do cp -f ~/dotfiles/server/$u ~/.config/systemd/user/$u; done && systemctl --user daemon-reload && systemctl --user enable --now tmux.service keepalive.timer`

If the rebuild took more than 30 minutes, add what blocked you to this README before closing.

## 4. Operations

- Connect: `tailscale ssh ubuntu@<hostname>` → `tmux attach -t main`. The session survives SSH disconnects.
- Watch `/usage` in Claude Code, especially the first 1–2 weeks.
- **One week in (required)**: instance metrics → CPU 95th percentile must be **> 20%** (switch the chart statistic from mean to **P95**). If lower, raise `--cpu-load` / `--timeout` in `keepalive.service`. This defeats OCI idle reclaim (7-day P95 below 20%).
- Backups: assign a **custom** weekly boot-volume backup policy with retention ≤ 4 (free tier keeps 5 total). Rebuild stays the primary recovery path.

## 5. Recovery

From the Mac: `tailscale status` / `tailscale ping <hostname>`. If offline, check the OCI console:

| Console state | Action |
| --- | --- |
| STOPPED | Start it; units come back on boot (re-run §3 verify) |
| Running but unreachable | serial console; if debugging takes > 30 min, rebuild instead |
| Terminated / missing | reclaimed — redo §2 (target: 30 min) |

Discipline that keeps recovery fast: push everything, keep all credentials re-issuable, and land every server change in `server/` in this repo before applying it.

## 6. Security

- No real OCIDs, IPs, or keys in this directory — placeholders only. `bats test/server.bats` scans every file here.
- Always use a fresh single-use Tailscale key; the substituted cloud-init is pasted, never saved.
- Keep ingress fully closed. If you ever need to expose something, prefer `tailscale serve`.
