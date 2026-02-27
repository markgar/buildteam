#!/bin/bash
set -e

# --- Docker daemon ---
# If the host Docker socket is mounted, use it directly.
# Otherwise start our own daemon (DinD) — needed in ACI where there's no host socket.
if [ -S /var/run/docker.sock ]; then
    echo "✓ Using host Docker socket"
else
    echo "Starting dockerd (DinD)..."
    dockerd &
    DOCKERD_PID=$!
    for i in $(seq 1 30); do
        if docker info &>/dev/null; then
            echo "✓ dockerd ready"
            break
        fi
        sleep 1
    done
fi

# --- Key Vault: fetch GitHub token ---
# --- Managed identity login ---
# When BUILDTEAM_UAMI_CLIENT_ID is set, az login targets that specific user-assigned
# managed identity. Without it, az login --identity uses the system-assigned identity
# (which doesn't exist on ACI with UAMI-only). Call this early so Key Vault and blob
# operations both use it.
#   BUILDTEAM_UAMI_CLIENT_ID  - client ID of the user-assigned managed identity
if [ -n "${BUILDTEAM_UAMI_CLIENT_ID:-}" ] || [ -n "${BUILDTEAM_KEYVAULT:-}" ] || [ -n "${BUILDTEAM_BLOB_ACCOUNT:-}" ]; then
    az account show -o none 2>/dev/null || {
        if [ -n "${BUILDTEAM_UAMI_CLIENT_ID:-}" ]; then
            echo "Logging in with managed identity (client ID: ${BUILDTEAM_UAMI_CLIENT_ID})..."
            az login --identity --username "$BUILDTEAM_UAMI_CLIENT_ID" --allow-no-subscriptions -o none 2>/dev/null || {
                echo "✗ az login --identity failed"
                exit 1
            }
        else
            echo "Logging in with managed identity..."
            az login --identity --allow-no-subscriptions -o none 2>/dev/null || {
                echo "✗ az login --identity failed"
                exit 1
            }
        fi
        echo "✓ Logged in with managed identity"
    }
fi

# --- Key Vault: fetch GitHub token ---
# When BUILDTEAM_KEYVAULT is set, retrieve the GitHub PAT from Key Vault using
# managed identity. This is more secure than passing GITHUB_TOKEN as an env var
# (which is visible in the Azure portal and ARM API).
#   BUILDTEAM_KEYVAULT        - Key Vault name
#   BUILDTEAM_KEYVAULT_SECRET - secret name (default: "github-token")
if [ -n "${BUILDTEAM_KEYVAULT:-}" ]; then
    KV_SECRET="${BUILDTEAM_KEYVAULT_SECRET:-github-token}"
    echo "Fetching GitHub token from Key Vault: ${BUILDTEAM_KEYVAULT}/${KV_SECRET}"

    GITHUB_TOKEN=$(az keyvault secret show \
        --vault-name "$BUILDTEAM_KEYVAULT" \
        --name "$KV_SECRET" \
        --query value -o tsv 2>/dev/null) || {
        echo "✗ Failed to read secret '${KV_SECRET}' from Key Vault '${BUILDTEAM_KEYVAULT}'"
        exit 1
    }
    export GITHUB_TOKEN
    echo "✓ GitHub token loaded from Key Vault"
fi

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

# --- Blob storage: download spec ---
# When BUILDTEAM_BLOB_ACCOUNT is set, download the spec from blob storage using
# managed identity (az login is not needed on ACI — IMDS provides the token).
# Required env vars:
#   BUILDTEAM_BLOB_ACCOUNT     - storage account name
#   BUILDTEAM_BLOB_CONTAINER   - blob container name (default: "specs")
#   BUILDTEAM_BLOB_SPEC        - blob name for the spec file (default: "spec.md")
#   BUILDTEAM_SPEC_DEST        - local path to write the spec (default: "/workspace/data/spec.md")
#   BUILDTEAM_LOGS_DIR         - local logs directory to sync (default: auto-detected by buildteam)
#   BUILDTEAM_BLOB_LOGS_CONTAINER - blob container for logs (default: same as BUILDTEAM_BLOB_CONTAINER)
SYNC_PID=""
if [ -n "${BUILDTEAM_BLOB_ACCOUNT:-}" ]; then
    BLOB_CONTAINER="${BUILDTEAM_BLOB_CONTAINER:-specs}"
    BLOB_SPEC="${BUILDTEAM_BLOB_SPEC:-spec.md}"
    SPEC_DEST="${BUILDTEAM_SPEC_DEST:-/workspace/data/spec.md}"
    BLOB_LOGS_CONTAINER="${BUILDTEAM_BLOB_LOGS_CONTAINER:-$BLOB_CONTAINER}"

    # Download spec
    mkdir -p "$(dirname "$SPEC_DEST")"
    echo "Downloading spec: ${BUILDTEAM_BLOB_ACCOUNT}/${BLOB_CONTAINER}/${BLOB_SPEC} → ${SPEC_DEST}"
    if az storage blob download \
        --account-name "$BUILDTEAM_BLOB_ACCOUNT" \
        --container-name "$BLOB_CONTAINER" \
        --name "$BLOB_SPEC" \
        --file "$SPEC_DEST" \
        --auth-mode login \
        --no-progress -o none 2>/dev/null; then
        echo "✓ Spec downloaded"
    else
        echo "✗ Failed to download spec from blob"
        exit 1
    fi

    # Background log sync — uploads logs/ to blob every 60 seconds
    LOGS_DIR="${BUILDTEAM_LOGS_DIR:-/workspace/data/logs}"
    mkdir -p "$LOGS_DIR"
    (
        while true; do
            sleep 60
            az storage blob upload-batch \
                --account-name "$BUILDTEAM_BLOB_ACCOUNT" \
                --destination "$BLOB_LOGS_CONTAINER" \
                --destination-path "logs/" \
                --source "$LOGS_DIR" \
                --auth-mode login \
                --overwrite \
                --no-progress -o none 2>/dev/null || true
        done
    ) &
    SYNC_PID=$!
    echo "✓ Background log sync started (PID $SYNC_PID, every 60s → ${BUILDTEAM_BLOB_ACCOUNT}/${BLOB_LOGS_CONTAINER}/logs/)"
fi

# --- Run buildteam ---
buildteam "$@"
EXIT_CODE=$?

# --- Final log sync ---
if [ -n "$SYNC_PID" ]; then
    kill "$SYNC_PID" 2>/dev/null || true
    wait "$SYNC_PID" 2>/dev/null || true
    echo "Final log sync..."
    az storage blob upload-batch \
        --account-name "$BUILDTEAM_BLOB_ACCOUNT" \
        --destination "${BLOB_LOGS_CONTAINER}" \
        --destination-path "logs/" \
        --source "${LOGS_DIR}" \
        --auth-mode login \
        --overwrite \
        --no-progress -o none 2>/dev/null || true
    echo "✓ Final log sync complete"
fi

exit $EXIT_CODE
