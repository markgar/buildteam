#!/bin/bash
set -e

# --- Start Docker daemon (DinD) ---
# The validator agent needs docker compose to build/test the target project.
# In ACI there's no host socket, so we run our own daemon.
dockerd &
DOCKERD_PID=$!

# Wait for daemon to be ready
for i in $(seq 1 30); do
    if docker info &>/dev/null; then
        echo "✓ dockerd ready"
        break
    fi
    sleep 1
done

# --- Authenticate gh CLI and copilot CLI ---
# gh uses GITHUB_TOKEN env var directly — no 'gh auth login' needed.
# copilot CLI checks COPILOT_GITHUB_TOKEN first, then GITHUB_TOKEN, then gh auth.
# Explicitly bridge the two so PAT-based auth works in headless environments (ACI).
if [ -n "$GITHUB_TOKEN" ]; then
    export COPILOT_GITHUB_TOKEN="${COPILOT_GITHUB_TOKEN:-$GITHUB_TOKEN}"
    # Verify the token works
    if gh api user --jq .login &>/dev/null; then
        echo "✓ gh authenticated as $(gh api user --jq .login)"
    else
        echo "✗ GITHUB_TOKEN is set but gh api call failed"
        exit 1
    fi
else
    echo "✗ GITHUB_TOKEN is not set"
    exit 1
fi

# Verify copilot CLI is available
if command -v copilot &>/dev/null; then
    echo "✓ copilot CLI $(copilot --version 2>/dev/null | head -1)"
else
    echo "✗ copilot CLI not found"
    exit 1
fi

# Show available runtimes (informational, not fatal if missing)
echo "✓ python $(python3 --version 2>/dev/null | awk '{print $2}')"
dotnet --version &>/dev/null && echo "✓ dotnet $(dotnet --version)" || echo "⚠ dotnet not available"
node --version &>/dev/null && echo "✓ node $(node --version)" || echo "⚠ node not available"

# --- Run buildteam ---
exec buildteam "$@"
