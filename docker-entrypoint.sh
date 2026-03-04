#!/bin/bash
set -e

# --- Docker daemon ---
# If the host Docker socket is mounted, use it directly.
# If dockerd is available, start DinD. Otherwise skip (ACI has no Docker).
if [ -S /var/run/docker.sock ]; then
    echo "✓ Using host Docker socket"
elif [ -n "${DOCKER_HOST:-}" ]; then
    echo "DOCKER_HOST is set ($DOCKER_HOST) — waiting for remote Docker daemon..."
    for i in $(seq 1 30); do
        if docker info &>/dev/null 2>&1; then
            echo "✓ Remote Docker daemon ready"
            break
        fi
        sleep 1
    done
    if ! docker info &>/dev/null 2>&1; then
        echo "⚠ Remote Docker daemon at $DOCKER_HOST not reachable after 30s — validator agent will be skipped"
    fi
elif command -v dockerd &>/dev/null; then
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
else
    echo "⚠ No Docker socket or daemon — validator agent will be skipped"
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
        if [ -n "${AZURE_FEDERATED_TOKEN_FILE:-}" ] && [ -n "${AZURE_CLIENT_ID:-}" ]; then
            # AKS workload identity — use federated token
            echo "Logging in with workload identity (client ID: ${AZURE_CLIENT_ID})..."
            az login --federated-token "$(cat "$AZURE_FEDERATED_TOKEN_FILE")" \
                --service-principal -u "$AZURE_CLIENT_ID" -t "${AZURE_TENANT_ID}" \
                --allow-no-subscriptions -o none || {
                echo "✗ az login --federated-token failed"
                exit 1
            }
        elif [ -n "${BUILDTEAM_UAMI_CLIENT_ID:-}" ]; then
            echo "Logging in with managed identity (client ID: ${BUILDTEAM_UAMI_CLIENT_ID})..."
            az login --identity --client-id "$BUILDTEAM_UAMI_CLIENT_ID" --allow-no-subscriptions -o none || {
                echo "✗ az login --identity failed"
                exit 1
            }
        else
            echo "Logging in with managed identity..."
            az login --identity --allow-no-subscriptions -o none || {
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
        --query value -o tsv) || {
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

# --- Run ID for log organization ---
# BUILDTEAM_RUN_ID identifies this run within the project's blob container.
# If not set, defaults to a UTC timestamp so manual runs get unique IDs.
BUILDTEAM_RUN_ID="${BUILDTEAM_RUN_ID:-$(date -u +%Y%m%d-%H%M%S)}"
export BUILDTEAM_RUN_ID
echo "✓ Run ID: ${BUILDTEAM_RUN_ID}"

# --- Logs directory ---
# Export BUILDTEAM_LOGS_DIR so buildteam writes logs where the sync reads from.
LOGS_DIR="${BUILDTEAM_LOGS_DIR:-/workspace/data/logs}"
mkdir -p "$LOGS_DIR"
export BUILDTEAM_LOGS_DIR="$LOGS_DIR"

# --- Blob storage: download spec ---
# When BUILDTEAM_BLOB_ACCOUNT is set, download the spec from blob storage using
# managed identity (az login is not needed on ACI — IMDS provides the token).
# Required env vars:
#   BUILDTEAM_BLOB_ACCOUNT     - storage account name
#   BUILDTEAM_BLOB_CONTAINER   - blob container name (default: "specs")
#   BUILDTEAM_BLOB_SPEC        - blob name for the spec file (default: "spec.md")
#   BUILDTEAM_SPEC_DEST        - local path to write the spec (default: "/workspace/data/spec.md")
#   BUILDTEAM_RUN_ID            - run folder within the container's logs/ prefix (set above, defaults to timestamp)
SYNC_PID=""
if [ -n "${BUILDTEAM_BLOB_ACCOUNT:-}" ]; then
    BLOB_CONTAINER="${BUILDTEAM_BLOB_CONTAINER:-specs}"
    BLOB_SPEC="${BUILDTEAM_BLOB_SPEC:-spec.md}"
    SPEC_DEST="${BUILDTEAM_SPEC_DEST:-/workspace/spec.md}"
    BLOB_LOGS_PREFIX="logs/${BUILDTEAM_RUN_ID}"

    # Download spec
    mkdir -p "$(dirname "$SPEC_DEST")"
    echo "Downloading spec: ${BUILDTEAM_BLOB_ACCOUNT}/${BLOB_CONTAINER}/${BLOB_SPEC} → ${SPEC_DEST}"
    if az storage blob download \
        --account-name "$BUILDTEAM_BLOB_ACCOUNT" \
        --container-name "$BLOB_CONTAINER" \
        --name "$BLOB_SPEC" \
        --file "$SPEC_DEST" \
        --auth-mode login \
        --no-progress -o none; then
        echo "✓ Spec downloaded"
    else
        echo "✗ Failed to download spec from blob (exit code: $?)"
        exit 1
    fi

    # Background log sync — uploads logs/ to blob every 60 seconds
    (
        while true; do
            sleep 60
            az storage blob upload-batch \
                --account-name "$BUILDTEAM_BLOB_ACCOUNT" \
                --destination "$BLOB_CONTAINER" \
                --destination-path "${BLOB_LOGS_PREFIX}/" \
                --source "$LOGS_DIR" \
                --auth-mode login \
                --overwrite \
                --no-progress -o none 2>/dev/null || true
        done
    ) &
    SYNC_PID=$!
    echo "✓ Background log sync started (PID $SYNC_PID, every 60s → ${BUILDTEAM_BLOB_ACCOUNT}/${BLOB_CONTAINER}/${BLOB_LOGS_PREFIX}/)"
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
        --destination "${BLOB_CONTAINER}" \
        --destination-path "${BLOB_LOGS_PREFIX}/" \
        --source "${LOGS_DIR}" \
        --auth-mode login \
        --overwrite \
        --no-progress -o none 2>/dev/null || true
    echo "✓ Final log sync complete"
fi

exit $EXIT_CODE
