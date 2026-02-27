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

# --- Authenticate gh CLI ---
# gh uses GITHUB_TOKEN env var directly — no 'gh auth login' needed.
if [ -n "$GITHUB_TOKEN" ]; then
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

# --- Run buildteam ---
exec buildteam "$@"
