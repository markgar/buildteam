# Running in Docker

Run the full buildteam orchestrator (all agents) in a single container. Useful for CI, headless servers, or environments where you don't want to install prerequisites locally.

## Quick Start

```bash
# Build the image
cd buildteam
docker build -t buildteam:latest .

# Run a project
docker run --privileged \
  -e GITHUB_TOKEN=ghp_xxxxx \
  -e BUILDTEAM_LOGS_DIR=/workspace/data/logs \
  -v ~/my-project/data:/workspace/data \
  buildteam:latest \
  go --directory /workspace/my-app --model claude-sonnet-4.6 \
     --spec-file /workspace/data/spec.md --headless --builders 2
```

## What's in the Image

The image bundles all runtimes so it can build Python, .NET, and Node.js target projects out of the box:

| Component | Purpose |
|-----------|---------|
| Python 3.12 | Runs buildteam itself; builds Python target projects |
| .NET 10 SDK | Builder/tester compile and test .NET target projects |
| Node.js 22 LTS | Builder/tester compile and test JS/TS target projects |
| Docker CE (daemon + CLI + containerd) | Validator agent builds/runs target project containers (Docker-in-Docker) |
| Copilot CLI | Standalone binary — the LLM engine all agents invoke |
| GitHub CLI (gh) | Repo creation, issue management, auth |
| System deps (git, curl, iptables) | Git operations, downloads |

## Authentication

The container requires a `GITHUB_TOKEN` environment variable. The token is **never baked into the image** — it's injected at runtime by whoever runs `docker run`.

The Copilot CLI reads auth from env vars in this order: `COPILOT_GITHUB_TOKEN` > `GH_TOKEN` > `GITHUB_TOKEN`. Since `GITHUB_TOKEN` is always set, Copilot auth works automatically.

### Token options

**For local testing** — use your existing `gh` OAuth token:

```bash
export GITHUB_TOKEN=$(gh auth token)
docker run --privileged -e GITHUB_TOKEN=$GITHUB_TOKEN ...
```

This stays valid until you run `gh auth logout` or revoke it in GitHub Settings.

**For production/CI** — create a fine-grained PAT at https://github.com/settings/personal-access-tokens/new with these permissions:

- **Contents** (read/write) — git push/pull
- **Issues** (read/write) — bug/finding filing
- **Administration** (read/write) — repo creation during bootstrap
- **Copilot Requests** — required for Copilot CLI

Fine-grained PATs expire after 90 days max (GitHub policy). For longer-lived automation, consider a GitHub App installation token.

**For CI/CD:**

- **GitHub Actions**: `${{ secrets.GITHUB_TOKEN }}` or a custom PAT in repo secrets
- **Azure DevOps**: Pipeline variable (secret) or Key Vault task
- **Azure Container Instances**: Key Vault reference or secure environment variable

## Docker-in-Docker

The validator agent needs `docker compose` to build and test the target project inside the container. The image includes the full Docker CE daemon, which starts automatically via the entrypoint script.

**`--privileged` is required** for local Docker runs because the inner Docker daemon needs access to cgroups and network namespaces. On Azure Container Instances, no host socket exists — the embedded daemon handles everything.

## Volume Mounts

Mount a data directory for spec input and log output:

```bash
-v ~/my-project/data:/workspace/data
```

The data directory should contain:

```
data/
  spec.md       # Your project requirements (input)
  logs/         # Agent logs, events, checkpoints (output)
```

Set `BUILDTEAM_LOGS_DIR=/workspace/data/logs` so buildteam writes logs to the mounted volume instead of inside the container.

## Headless Mode

The `--headless` flag (or running inside a container, which is auto-detected) causes agents to spawn as background processes instead of opening terminal windows. All output goes to log files in the logs directory.

Monitor progress by tailing the logs:

```bash
# From the host
docker logs buildteam-calc 2>&1 | grep -v '^time='

# Or read agent logs from the mounted volume
tail -f ~/my-project/data/logs/builder.log
tail -f ~/my-project/data/logs/orchestrator.log
```

## JSONL Events

In container mode, key orchestration milestones are written as structured JSONL to `logs/events.jsonl` and stdout. Each line is a self-contained JSON object:

```json
{"ts": "2026-02-26T03:00:19Z", "agent": "orchestrator", "event": "agents_launched", "model": "claude-sonnet-4.6"}
{"ts": "2026-02-26T03:05:42Z", "agent": "builder", "event": "milestone_completed", "milestone": "milestone-01"}
```

External systems can tail this file or parse container stdout for monitoring.

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `GITHUB_TOKEN` | Yes | GitHub auth for gh CLI and Copilot CLI |
| `BUILDTEAM_LOGS_DIR` | Recommended | Override log directory (default: auto-detected from cwd) |
| `BUILDTEAM_HEADLESS` | Auto | Set to `1` to force headless mode (auto-detected in containers) |
| `COPILOT_MODEL` | Via CLI | Set by `--model` flag, not typically set manually |

## Example: Full Run

```bash
# 1. Build image
docker build -t buildteam:latest .

# 2. Prepare data directory
mkdir -p ~/my-project/data/logs
cp my-spec.md ~/my-project/data/spec.md

# 3. Run in background
docker run -d --privileged \
  -e GITHUB_TOKEN=$GITHUB_TOKEN \
  -e BUILDTEAM_LOGS_DIR=/workspace/data/logs \
  -v ~/my-project/data:/workspace/data \
  --name my-build \
  buildteam:latest \
  go --directory /workspace/my-app --model claude-sonnet-4.6 \
     --spec-file /workspace/data/spec.md --headless --builders 2

# 4. Monitor
docker logs -f my-build 2>&1 | grep -v '^time='

# 5. Check agent logs
tail -f ~/my-project/data/logs/builder.log
```
